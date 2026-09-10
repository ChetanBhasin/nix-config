import type { ExtensionAPI, ExtensionContext, ToolCallEvent } from "../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js";
import { WorkflowLedger, object, text, type Contract, type Receipt } from "./workflow-ledger.js";
import { canonicalRoots, contains, digest } from "./workflow-workspace.js";
import { WriterLeaseStore, mutationTargets, type Lease } from "./writer-lease.js";

export type WorkflowApi = ExtensionAPI;
export interface AutoControls { enabled: boolean; owner: boolean }
const STATUS = "cb-workflow";
const INSTRUCTIONS = "cb-workflow-context-v1";
const REMEDIATION = "cb-workflow-remediation-v1";
const string = { type: "string", minLength: 1, maxLength: 4000 };
const strings = { type: "array", items: string, maxItems: 32 };
const definitionSchema = {
  type: "object", additionalProperties: false,
  required: ["objective", "kind", "roots", "externalInputs", "requirements", "journeys"],
  properties: {
    objective: string, kind: { type: "string", enum: ["implementation", "inspection"] }, roots: strings, externalInputs: strings,
    requirements: { type: "array", maxItems: 64, items: { type: "object", additionalProperties: false, required: ["id", "mandatory", "expected"],
      properties: { id: string, mandatory: { type: "boolean" }, expected: string, artifactRequired: { type: "boolean" } } } },
    journeys: { type: "array", maxItems: 16, items: { type: "object", additionalProperties: false, required: ["id", "scenario", "interface", "tool", "input", "expected"],
      properties: { id: string, scenario: string, interface: string, tool: string, input: { type: "object" }, expected: string, artifactRequired: { type: "boolean" } } } },
  },
};

/** Instantiated in parent AND child controllers. Never activates tools or changes role allowlists. */
export function registerWorkflow(pi: WorkflowApi, controls: () => AutoControls, database?: string): void {
  const ledger = new WorkflowLedger((type, data) => pi.appendEntry(type, data));
  let store: WriterLeaseStore | undefined;
  let lease: Lease | undefined;
  let sessionId: string | undefined;
  let runtimeFault: string | undefined;
  let waitingUi = false;
  const mutations = new Set<string>();
  const finalized = new Set<string>();
  const starts = new Map<string, Omit<Receipt, "after" | "resultHash" | "isError">>();
  const permits = new Map<string, string[]>();
  const branch = (ctx: ExtensionContext) => ctx.sessionManager.getBranch();
  const storage = () => store ??= new WriterLeaseStore(database);
  const own = (ctx: ExtensionContext): Lease => {
    if (runtimeFault) throw new Error(runtimeFault);
    if (!lease || lease.owner.session !== ctx.sessionManager.getSessionId() || sessionId !== lease.owner.session) throw new Error("Claim writer_lease for this session first");
    return storage().check(lease.owner);
  };
  const drained = (): void => {
    if (mutations.size) throw new Error("Mutation batch has not drained; retry in the next turn");
  };
  const missingCapabilities = (): string[] => {
    const c = ledger.contract;
    if (!c) return [];
    const active = new Set(pi.getActiveTools());
    const required = new Set(["workflow_contract", ...c.journeys.map((journey) => journey.tool)]);
    if (c.kind === "implementation") required.add("writer_lease");
    return [...required].filter((tool) => !active.has(tool));
  };
  const report = (ctx: ExtensionContext, refresh = true): string => {
    const c = ledger.contract;
    const issues = c && !ledger.fault && refresh ? ledger.refresh(branch(ctx)) : [];
    const capabilityBlockers = c?.status !== "complete" ? missingCapabilities() : [];
    issues.push(...capabilityBlockers.map((tool) => `Required tool unavailable: ${tool}`));
    ctx.ui.setStatus(STATUS, ledger.fault || runtimeFault ? "WORKFLOW ERROR" : c ? `WORKFLOW ${c.status === "complete" ? "CHECKED" : (capabilityBlockers.length ? "CAPABILITY BLOCKED" : c.disposition.toUpperCase()) + "/UNACCEPTED"}` : undefined);
    const serialized = JSON.stringify({
      acceptance: ledger.fault || runtimeFault ? "unaccepted" : c?.status ?? "no active contract",
      fault: ledger.fault ?? runtimeFault, durability: ctx.sessionManager.getSessionFile() ? "Pi custom entries" : "ephemeral; not durable across process exit",
      input: ledger.input && { ...ledger.input, authorization: ledger.input.authorization && { action: ledger.input.authorization.action, revision: ledger.input.authorization.revision, scopeHash: digest(ledger.input.authorization.definition) } },
      objective: c && { id: c.id, objective: c.objective, revision: c.revision, kind: c.kind, roots: c.roots, externalInputs: c.externalInputs,
        requirements: c.requirements, journeys: c.journeys, evidence: c.evidence.map((e) => ({ target: e.target, toolCallId: e.receipt.toolCallId, artifact: e.artifact, workspaceRevision: e.receipt.after })),
        disposition: c.disposition, blockers: c.blockers, continuations: c.continuations, noProgress: c.noProgress },
      issues, writer: lease && { nonce: lease.owner.nonce, session: lease.owner.session, roots: lease.roots, inFlight: [...mutations] },
    });
    return Buffer.byteLength(serialized) <= 48000 ? serialized : Buffer.from(serialized).subarray(0, 48000).toString("utf8") + "\n[Status truncated; full ledger is in this session's Pi custom entries.]";
  };
  const output = (ctx: ExtensionContext, refresh = true) => ({ content: [{ type: "text" as const, text: report(ctx, refresh) }], details: {} });
  const restore = (ctx: ExtensionContext): void => {
    sessionId = ctx.sessionManager.getSessionId();
    ledger.restore(branch(ctx));
    report(ctx);
  };
  // Shutdown may run after Pi has changed the in-memory SessionManager ID.
  // Its private cleanup validates the captured owner/nonce; public release still checks current-session ownership.
  const release = (ctx?: ExtensionContext): void => {
    if (!lease) return;
    drained();
    storage().release(ctx ? own(ctx).owner : lease.owner);
    lease = undefined;
    permits.clear();
  };

  pi.registerCommand("workflow", {
    description: "Show active-branch workflow acceptance and writer status (not transport settlement)",
    handler: async (args, ctx) => {
      if (args.trim() && args.trim() !== "status") { ctx.ui.notify("Usage: /workflow [status]. Scope changes use genuine workflow-scope input; see auto-mode/README.md.", "warning"); return; }
      ctx.ui.notify(report(ctx), "info");
    },
  });
  pi.registerTool({
    name: "workflow_contract", label: "Workflow contract",
    description: "Branch-local acceptance ledger. Start implementation explicitly with objective, mandatory criteria and a planned real-interface journey. status exposes latest genuine inputId. confirm cheaply acknowledges unchanged scope. revise may add/strengthen obligations within unchanged roots/objective without more input; removals, weakening, changed scope or replacement of unfinished work require genuine workflow-scope {action:start|revise,revision,definition}. New genuine input after checked completion permits a new objective. evidence cites finalized non-error tool-call IDs and literal expected/observed output; source inspection and child reports alone never satisfy a journey. complete validates current sources, external inputs and required evidence, and THROWS on failure. disposition waiting/blocked suppresses Auto remediation; actionable resumes. Structural checking, not semantic proof.",
    promptSnippet: "Track explicit workflow criteria, executed journeys and checked completion",
    parameters: { type: "object", additionalProperties: false, required: ["action"], properties: {
      action: { type: "string", enum: ["status", "start", "revise", "confirm", "evidence", "complete", "disposition"] },
      inputId: string, revision: { type: "integer", minimum: 1 }, definition: definitionSchema,
      evidence: { type: "object", additionalProperties: false, required: ["target", "kind", "expected", "observed", "toolCallId"], properties: {
        target: string, kind: { type: "string", enum: ["requirement", "journey"] }, expected: string, observed: string, toolCallId: string, artifact: string,
      } },
      disposition: { type: "string", enum: ["actionable", "waiting", "blocked"] }, reasons: strings,
    } },
    async execute(_id, raw, signal, _update, ctx) {
      signal?.throwIfAborted();
      const args = object(raw);
      if (runtimeFault) throw new Error(runtimeFault);
      if (args.action !== "status" && args.action !== "confirm") drained();
      switch (args.action) {
        case "status": return output(ctx);
        case "start": ledger.start(args.definition, text(args.inputId, "input ID")); break;
        case "revise": ledger.revise(args.definition, Number(args.revision), text(args.inputId, "input ID")); break;
        case "confirm": ledger.confirm(Number(args.revision), text(args.inputId, "input ID")); return output(ctx, false);
        case "evidence": ledger.addEvidence(args.evidence, branch(ctx)); break;
        case "complete": ledger.complete(branch(ctx)); break;
        case "disposition": ledger.disposition(args.disposition as Contract["disposition"], args.reasons as string[]); break;
        default: throw new Error("Unknown workflow action");
      }
      return output(ctx);
    },
  });
  pi.registerTool({
    name: "writer_lease", label: "Cooperative writer lease",
    description: "Claim/release explicit absolute source roots for ONE session/process. Required for file/Hashline/AST mutations; read-only tools need no claim or workflow. All shell, LSP rename and unknown plugin effects also need permit with exact tool+input and affected roots. permit is one-use, scoped to this nonce and cannot authorize protected actions. Declare ALL possible mutations; no detached/background writers. Release by nonce in a later turn after the mutation batch drains. Not a sandbox; do not bypass with extension code or undeclared shell writes.",
    parameters: { type: "object", additionalProperties: false, required: ["action"], properties: {
      action: { type: "string", enum: ["status", "claim", "permit", "release"] }, roots: strings, nonce: string, tool: string, input: { type: "object" },
    } },
    async execute(_id, raw, signal, _update, ctx) {
      signal?.throwIfAborted();
      const args = object(raw);
      switch (args.action) {
        case "status": return output(ctx);
        case "claim":
          if (runtimeFault) throw new Error(runtimeFault);
          if (lease) throw new Error("Already holding a writer lease; release before changing roots");
          drained();
          lease = storage().claim(ctx.sessionManager.getSessionId(), args.roots as string[]);
          break;
        case "permit": {
          const held = own(ctx);
          if (args.nonce !== held.owner.nonce) throw new Error("Writer nonce mismatch");
          const roots = canonicalRoots(args.roots as string[]);
          if (roots.some((target) => !held.roots.some((root) => contains(root, target)))) throw new Error("Permit outside claimed roots");
          if (permits.size >= 8) throw new Error("At most eight pending exact mutation permits");
          permits.set(digest([text(args.tool, "tool"), object(args.input)]), roots);
          break;
        }
        case "release":
          if (args.nonce !== own(ctx).owner.nonce) throw new Error("Writer nonce mismatch");
          release(ctx);
          break;
        default: throw new Error("Unknown writer lease action");
      }
      return output(ctx);
    },
  });

  pi.on("session_start", (_event, ctx) => restore(ctx));
  pi.on("session_tree", (_event, ctx) => {
    try { release(ctx); } catch (error) { runtimeFault = `Writer retained on tree navigation: ${String(error)}`; }
    starts.clear(); finalized.clear(); permits.clear();
    restore(ctx);
  });
  const preventUndrainedSwitch = () => mutations.size ? { cancel: true } : undefined;
  pi.on("session_before_tree", preventUndrainedSwitch);
  pi.on("session_before_switch", preventUndrainedSwitch);
  pi.on("session_before_fork", preventUndrainedSwitch);
  pi.on("session_shutdown", (_event, ctx) => {
    try { release(); } catch (error) { ctx.ui.notify(`Writer lease NOT released (ownership/batch uncertain): ${String(error)}`, "warning"); }
    store?.close(); store = undefined;
    ctx.ui.setStatus(STATUS, undefined);
  });
  pi.on("input", (event, ctx) => {
    ledger.receiveInput(event.source, event.text, ctx.sessionManager.getLeafId(), controls().owner);
  });
  pi.on("ui_prompt_start", () => { waitingUi = true; });
  pi.on("ui_prompt_end", () => { waitingUi = false; });
  pi.on("context", (event, ctx) => {
    if (!ledger.contract && !ledger.fault && !pi.getActiveTools().includes("workflow_contract")) return;
    const messages = event.messages.filter((message) => !(message.role === "custom" &&
      (message.customType === INSTRUCTIONS || (message.customType === REMEDIATION && !controls().enabled))));
    messages.push({ role: "custom", customType: INSTRUCTIONS, display: false, timestamp: Date.now(),
      content: `Workflow policy: implementation objectives start explicitly with workflow_contract; pure discussion/read-only inspection needs none. Preserve every mandatory requirement. Complete only via the tool after actual finalized real-interface evidence. Writer ownership is independent of Auto Mode; claim/release before any mutation, exact permits for ALL shell/LSP rename/unknown effects. Never use a lease as protected-action permission. Use disposition waiting before delegated work; child reports are attestations, then verify artifacts and explicitly resume actionable. Transport settlement and already-streamed answers are not acceptance.\n${report(ctx)}` });
    return { messages };
  });
  pi.on("tool_call", (event, ctx) => {
    captureStart(event);
    const targets = mutationTargets(event.toolName, event.input, ctx.cwd);
    if (targets !== undefined) {
      if (ledger.fault) throw new Error(ledger.fault);
      const held = own(ctx);
      let affected: string[];
      if (targets === "permit") {
        const key = digest([event.toolName, event.input]);
        const permitted = permits.get(key);
        if (!permitted) throw new Error("Mutation-capable tool needs an exact writer_lease permit with declared affected roots (including shell commands)");
        affected = permitted;
        permits.delete(key);
      } else affected = targets;
      const contract = ledger.contract;
      if (contract && (contract.kind !== "implementation" || affected.some((target) => !contract.roots.some((root) => contains(root, target))))) {
        throw new Error("Mutation exceeds the active implementation contract; revise its explicit roots/scope first");
      }
      storage().reserve(held.owner, event.toolCallId, affected);
      mutations.add(event.toolCallId);
    }
    if (event.toolName === "subagent" && ledger.contract && !event.input.action &&
      (typeof event.input.agent === "string" || typeof event.input.workflowScript === "string")) {
      ledger.disposition("waiting", ["Delegated work launched; explicitly resume actionable after it returns and verify its evidence"]);
    }
  });
  function captureStart(event: ToolCallEvent): void {
    const c = ledger.contract;
    if (!c || event.toolName === "workflow_contract" || event.toolName === "writer_lease" || ledger.fault) return;
    ledger.begin(event.toolName, digest(event.input));
    try {
      starts.set(event.toolCallId, { version: 1, objectiveId: c.id, revision: c.revision, toolCallId: event.toolCallId,
        tool: event.toolName, inputHash: digest(event.input), before: ledger.stamp().revision });
    } catch { /* Missing/bounded inputs cannot produce an acceptance receipt. Status explains the input failure. */ }
  }
  pi.on("tool_execution_end", (event) => {
    if (mutations.has(event.toolCallId)) finalized.add(event.toolCallId);
    const start = starts.get(event.toolCallId);
    starts.delete(event.toolCallId);
    if (!start) return;
    try {
      ledger.record({ ...start, after: ledger.stamp().revision, resultHash: digest(event.result.content), isError: event.isError });
    } catch { /* No valid snapshot => no evidence receipt, never automatic acceptance. */ }
  });
  pi.on("turn_end", (_event, ctx) => {
    if (lease && finalized.size) {
      try {
        storage().drain(own(ctx).owner, [...finalized]);
        for (const id of finalized) mutations.delete(id);
        finalized.clear();
      } catch (error) { runtimeFault = `Writer drain failed closed: ${String(error)}`; }
    }
  });
  pi.on("user_bash", () => ({ result: {
    output: "Cooperative writer guard: !/!! shell has no guarded tool-batch finalization. Use read-only tools or a writer_lease-authorized bash tool call.",
    exitCode: 1, cancelled: false, truncated: false,
  } }));
  pi.on("agent_end", (event, ctx) => {
    const last = [...event.messages].reverse().find((message) => message.role === "assistant");
    const unavailable = missingCapabilities();
    const issues = ledger.continuation(branch(ctx), { ...controls(), aborted: ctx.signal?.aborted === true || last?.stopReason === "aborted",
      failed: !!runtimeFault || !last || !["stop", "toolUse"].includes(last.stopReason),
      pending: waitingUi || ctx.hasPendingMessages() || mutations.size > 0 || unavailable.length > 0 });
    if (issues) {
      const c = ledger.require();
      pi.sendMessage({ customType: REMEDIATION, display: true,
        content: `[workflow-remediation objective=${c.id} revision=${c.revision} attempt=${c.continuations}/3] Acceptance remains OPEN: ${issues.join("; ")}. Resolve only the existing contract, supply executed evidence and call complete, or record blocked/waiting. Do not restate or remove the original answer.` }, { deliverAs: "followUp", triggerTurn: true });
    }
    if (ledger.contract || ledger.fault || runtimeFault) {
      report(ctx);
      if (ledger.contract?.status !== "complete") {
        const warning = "Workflow remains UNACCEPTED. Already-streamed text is unchanged; settlement is not acceptance. /workflow shows evidence and blockers."
          + (unavailable.length ? ` Capability blocker: unavailable tools ${unavailable.join(", ")}; remediation budget preserved. Restore the intended tools through authorized configuration, not an expanded role allowlist.` : "");
        ctx.ui.notify(warning, "warning");
        if (!issues) pi.sendMessage({ customType: "cb-workflow-acceptance-v1", content: warning, display: true }, { triggerTurn: false });
      }
    }
  });
}
