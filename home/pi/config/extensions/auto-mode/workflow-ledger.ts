import { randomUUID } from "node:crypto";
import path from "node:path";
import { canonicalRoots, digest, fingerprint, type WorkspaceStamp } from "./workflow-workspace.js";

export const LEDGER_ENTRY = "cb-workflow-ledger-v1";
export const INPUT_ENTRY = "cb-workflow-input-v1";
export const RECEIPT_ENTRY = "cb-workflow-receipt-v1";
export interface BranchEntry { type: string; id?: string; customType?: string; data?: unknown; message?: unknown }
export interface Requirement { id: string; mandatory: boolean; expected: string; artifactRequired: boolean }
export interface Journey { id: string; scenario: string; interface: string; tool: string; input: Record<string, unknown>; expected: string; artifactRequired: boolean }
export interface Definition {
  objective: string;
  kind: "implementation" | "inspection";
  roots: string[];
  externalInputs: string[];
  requirements: Requirement[];
  journeys: Journey[];
}
export interface InputProvenance {
  version: 1;
  id: string;
  source: "interactive" | "rpc";
  authority: "user-input" | "delegated-input";
  textHash: string;
  beforeLeaf: string | null;
  authorization?: { action: "start" | "revise"; revision?: number; definition: Definition };
  invalidAuthorization?: string;
  precedingCompletion?: { id: string; revision: number };
}
export interface Receipt {
  version: 1;
  objectiveId: string;
  revision: number;
  toolCallId: string;
  tool: string;
  inputHash: string;
  resultHash: string;
  before: string;
  after: string;
  isError: boolean;
}
export interface Evidence {
  target: string;
  kind: "requirement" | "journey";
  expected: string;
  observed: string;
  receipt: Receipt;
  artifact?: string;
  artifactRevision?: string;
}
export interface Contract extends Definition {
  version: 1;
  id: string;
  revision: number;
  input: InputProvenance;
  confirmedInput: string;
  evidence: Evidence[];
  blockers: string[];
  disposition: "actionable" | "waiting" | "blocked";
  status: "open" | "complete";
  continuations: number;
  noProgress: number;
  progressFingerprint?: string;
}

export function text(value: unknown, label: string, max = 4000): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) throw new Error(`${label}: nonempty text up to ${max} characters required`);
  return value;
}
export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Object required");
  return value as Record<string, unknown>;
}
function list(value: unknown, max: number): unknown[] {
  if (!Array.isArray(value) || value.length > max) throw new Error(`Array required (maximum ${max})`);
  return value;
}
const NON_JOURNEY_TOOLS = new Set([
  "subagent", "subagent_wait", "subagent_supervisor", "workflow_contract", "writer_lease",
  "read", "read_symbol", "read_enclosing", "grep", "find", "ls", "symbol_search",
  "project_report", "module_report", "ast_grep_search", "ast_grep_outline", "ast_grep_dump",
  "lsp_navigation", "lsp_diagnostics", "lens_diagnostics", "pi_lens_activate_tools", "lens_diagnostic_mark",
  "write", "edit", "replace", "insert", "undo_last_change", "ast_grep_replace",
  "ctx_search", "ctx_expand", "ctx_memory", "ctx_note", "ctx_reduce", "todo", "ask_user_question",
  "view_image",
]);

export function definition(value: unknown): Definition {
  const data = object(value);
  if (!["implementation", "inspection"].includes(String(data.kind))) throw new Error("kind must be implementation or inspection");
  const requirements = list(data.requirements, 64).map((entry) => {
    const r = object(entry);
    if (typeof r.mandatory !== "boolean") throw new Error("Explicit mandatory status required");
    return { id: text(r.id, "requirement ID", 80), mandatory: r.mandatory, expected: text(r.expected, "expected observable outcome"), artifactRequired: r.artifactRequired === true };
  });
  if (!requirements.some((r) => r.mandatory)) throw new Error("At least one mandatory criterion required");
  const journeys = list(data.journeys, 16).map((entry) => {
    const j = object(entry);
    const tool = text(j.tool, "journey tool", 100);
    if (NON_JOURNEY_TOOLS.has(tool)) {
      throw new Error("Journey must invoke the real interface, not read files, edit source, or attest via a child/ledger");
    }
    const input = object(j.input);
    if (JSON.stringify(input).length > 16000) throw new Error("Journey arguments too large");
    return { id: text(j.id, "journey ID", 80), scenario: text(j.scenario, "user scenario"), interface: text(j.interface, "real interface"), tool, input, expected: text(j.expected, "journey outcome"), artifactRequired: j.artifactRequired === true };
  });
  const ids = [...requirements, ...journeys].map((r) => r.id);
  if (new Set(ids).size !== ids.length) throw new Error("Requirement and journey IDs must be unique");
  if (data.kind === "implementation" && journeys.length === 0) throw new Error("Implementation needs a real-interface journey");
  const externalInputs = list(data.externalInputs, 32).map((v) => {
    const filename = text(v, "external input");
    if (!path.isAbsolute(filename)) throw new Error("External inputs must be absolute file/directory paths");
    return path.resolve(filename);
  }).sort();
  return {
    objective: text(data.objective, "objective"), kind: data.kind as Definition["kind"],
    roots: canonicalRoots(data.roots as string[]), externalInputs, requirements, journeys,
  };
}
function scope(contract: Definition): Definition {
  const { objective, kind, roots, externalInputs, requirements, journeys } = contract;
  return { objective, kind, roots, externalInputs, requirements, journeys };
}
/** Strengthening within the authorized scope needs no new user decision. */
function strengthens(current: Definition, next: Definition): boolean {
  if (current.objective !== next.objective || current.kind !== next.kind || digest(current.roots) !== digest(next.roots)) return false;
  if (!current.externalInputs.every((input) => next.externalInputs.includes(input))) return false;
  const requirementsPreserved = current.requirements.every((before) => {
    const after = next.requirements.find((requirement) => requirement.id === before.id);
    return after !== undefined && before.expected === after.expected
      && (!before.mandatory || after.mandatory) && (!before.artifactRequired || after.artifactRequired);
  });
  const journeysPreserved = current.journeys.every((before) => {
    const after = next.journeys.find((journey) => journey.id === before.id);
    return after !== undefined && digest({ ...after, artifactRequired: before.artifactRequired }) === digest(before)
      && (!before.artifactRequired || after.artifactRequired);
  });
  return requirementsPreserved && journeysPreserved;
}

function resultOnBranch(branch: BranchEntry[], receipt: Receipt): { output: string; hash: string } | undefined {
  let latestCall: string | undefined;
  let result: { output: string; hash: string } | undefined;
  for (const entry of branch) {
    if (entry.type !== "message" || !entry.message) continue;
    const message = object(entry.message);
    if (message.role === "assistant" && Array.isArray(message.content)) {
      for (const content of message.content) {
        const part = object(content);
        if (part.type === "toolCall" && part.name === receipt.tool && digest(part.arguments) === receipt.inputHash) latestCall = String(part.id);
      }
    }
    if (message.role === "toolResult" && message.toolCallId === receipt.toolCallId && message.toolName === receipt.tool && latestCall === receipt.toolCallId) {
      if (message.isError !== false) return undefined;
      result = { output: outputText(message.content), hash: digest(message.content) };
    }
  }
  return latestCall === receipt.toolCallId ? result : undefined;
}
export function outputText(content: unknown): string {
  if (!Array.isArray(content)) return "";
  return content.map((part) => part?.type === "text" ? String(part.text) : "").join("\n");
}

/** Branch-local structural acceptance. Literal output checks are not semantic proof. */
export class WorkflowLedger {
  contract?: Contract;
  input?: InputProvenance;
  receipts = new Map<string, Receipt>();
  fault?: string;
  constructor(private append: (type: string, data: unknown) => void) {}
  restore(branch: BranchEntry[]): void {
    this.contract = undefined;
    this.input = undefined;
    this.receipts.clear();
    this.fault = undefined;
    try {
      const latestSnapshot = [...branch].reverse().find((entry) => entry.type === "custom" && entry.customType === LEDGER_ENTRY);
      for (const entry of branch) {
        if (entry.type !== "custom") continue;
        if (entry.customType === LEDGER_ENTRY) {
          if (entry !== latestSnapshot) continue;
          const c = structuredClone(object(entry.data)) as unknown as Contract;
          if (c.version !== 1 || !c.id || !Number.isSafeInteger(c.revision) || c.revision < 1 ||
              !Number.isSafeInteger(c.continuations) || c.continuations < 0 || !Number.isSafeInteger(c.noProgress) || c.noProgress < 0 ||
              !["open", "complete"].includes(c.status) || !["actionable", "waiting", "blocked"].includes(c.disposition) ||
              !c.input?.id || !c.confirmedInput || !Array.isArray(c.evidence) || c.evidence.length > 80 || !Array.isArray(c.blockers)) {
            throw new Error("Invalid ledger snapshot");
          }
          // Validate schema without reinterpreting compaction prose; missing source roots fail closed.
          definition(c);
          this.contract = c;
        } else if (entry.customType === INPUT_ENTRY) {
          const input = structuredClone(object(entry.data)) as unknown as InputProvenance;
          if (input.version !== 1 || !input.id || !["interactive", "rpc"].includes(input.source)) throw new Error("Invalid input provenance");
          this.input = input;
        } else if (entry.customType === RECEIPT_ENTRY) {
          const receipt = structuredClone(object(entry.data)) as unknown as Receipt;
          if (receipt.version !== 1 || !receipt.toolCallId || typeof receipt.isError !== "boolean") throw new Error("Invalid execution receipt");
          this.receipts.set(receipt.toolCallId, receipt);
          if (this.receipts.size > 256) this.receipts.delete(this.receipts.keys().next().value!);
        }
      }
    } catch (error) {
      this.fault = `Workflow restore failed closed: ${String(error)}`;
    }
  }
  private healthy(): void { if (this.fault) throw new Error(this.fault); }
  private save(): void { this.append(LEDGER_ENTRY, structuredClone(this.contract)); }
  require(): Contract { this.healthy(); if (!this.contract) throw new Error("No active objective; start one explicitly"); return this.contract; }
  receiveInput(source: string, raw: string, beforeLeaf: string | null, owner: boolean): void {
    if (source !== "interactive" && source !== "rpc") return;
    const input: InputProvenance = { version: 1, id: randomUUID(), source, authority: owner ? "user-input" : "delegated-input", textHash: digest(raw), beforeLeaf };
    if (this.contract?.status === "complete") {
      input.precedingCompletion = { id: this.contract.id, revision: this.contract.revision };
    }
    if (raw.startsWith("workflow-scope ")) {
      try {
        const authorization = object(JSON.parse(raw.slice("workflow-scope ".length)));
        if (!["start", "revise"].includes(String(authorization.action))) throw new Error("Scope authorization action must be start or revise");
        input.authorization = { action: authorization.action as "start" | "revise", revision: authorization.revision as number | undefined, definition: definition(authorization.definition) };
      } catch (error) { input.invalidAuthorization = String(error); }
    }
    this.input = input;
    this.append(INPUT_ENTRY, structuredClone(input));
    if (this.contract?.status === "complete") { this.contract.status = "open"; this.save(); }
  }
  private authorized(action: "start" | "revise", next: Definition): boolean {
    const auth = this.input?.authorization;
    return !!auth && auth.action === action && digest(auth.definition) === digest(next) &&
      (action === "start" || auth.revision === this.contract?.revision);
  }
  start(value: unknown, inputId: string): Contract {
    this.healthy();
    if (!this.input || this.input.id !== inputId) throw new Error("Use the latest genuine input ID from workflow status");
    if (this.input.invalidAuthorization) throw new Error(this.input.invalidAuthorization);
    if (this.contract?.input.id === inputId) throw new Error("Replacing an objective requires a NEW genuine input; continuation budgets cannot be reset");
    const next = definition(value);
    if (this.input.authorization && !this.authorized("start", next)) throw new Error("Start differs from the exact authorized scope");
    const finishedBeforeInput = this.contract && this.input.precedingCompletion?.id === this.contract.id
      && this.input.precedingCompletion.revision === this.contract.revision;
    if (this.contract && !finishedBeforeInput && !this.authorized("start", next)) throw new Error("Replacing an objective requires explicit workflow-scope start input; old requirements are not silently dropped");
    this.contract = { ...next, version: 1, id: randomUUID(), revision: 1, input: this.input, confirmedInput: inputId,
      evidence: [], blockers: [], disposition: "actionable", status: "open", continuations: 0, noProgress: 0 };
    this.save();
    return this.contract;
  }
  revise(value: unknown, revision: number, inputId: string): void {
    const c = this.require();
    if (c.revision !== revision || inputId !== this.input?.id) throw new Error("Scope/input revision mismatch");
    const next = definition(value);
    if (digest(scope(c)) === digest(next)) { this.confirm(revision, inputId); return; }
    const pendingAuthorization = this.input?.authorization && c.confirmedInput !== inputId;
    const additive = !pendingAuthorization && !this.input?.invalidAuthorization && strengthens(c, next);
    if (!additive && !this.authorized("revise", next)) throw new Error("Scope changes require exact genuine workflow-scope input with the current revision; mandatory requirements cannot be silently weakened");
    Object.assign(c, next, { revision: c.revision + 1, input: this.input, confirmedInput: inputId, evidence: [], status: "open" });
    this.save();
  }
  confirm(revision: number, inputId: string): void {
    const c = this.require();
    if (c.revision !== revision || inputId !== this.input?.id) throw new Error("Scope/input revision mismatch");
    if (this.input.invalidAuthorization) throw new Error(this.input.invalidAuthorization);
    if (c.confirmedInput === inputId) return;
    if (this.input.authorization && digest(this.input.authorization.definition) !== digest(scope(c))) throw new Error("Authorized scope changed; use revise, not unchanged confirmation");
    c.confirmedInput = inputId;
    this.save();
  }
  stamp(): WorkspaceStamp { const c = this.require(); return fingerprint(c.roots, c.externalInputs); }
  begin(tool: string, inputHash: string): void {
    const c = this.contract;
    if (!c) return;
    const retained = c.evidence.filter((e) => e.receipt.tool !== tool || e.receipt.inputHash !== inputHash);
    if (retained.length === c.evidence.length) return;
    c.evidence = retained;
    c.status = "open";
    this.save();
  }
  record(receipt: Receipt): void {
    this.begin(receipt.tool, receipt.inputHash);
    this.receipts.set(receipt.toolCallId, receipt);
    if (this.receipts.size > 256) this.receipts.delete(this.receipts.keys().next().value!);
    this.append(RECEIPT_ENTRY, receipt);
  }
  addEvidence(value: unknown, branch: BranchEntry[]): void {
    const c = this.require();
    const data = object(value);
    const kind = data.kind;
    if (kind !== "requirement" && kind !== "journey") throw new Error("Only executed requirement/journey evidence is accepted; child reports are attestations");
    const target = (kind === "journey" ? c.journeys : c.requirements).find((r) => r.id === data.target);
    if (!target) throw new Error("Unknown evidence target");
    if (data.expected !== target.expected) throw new Error("Expected outcome differs from the contract");
    if (target.artifactRequired && !data.artifact) throw new Error("Contract requires an artifact locator in the tool output");
    const observed = text(data.observed, "observed outcome");
    const receipt = this.receipts.get(text(data.toolCallId, "finalized tool-call ID", 200));
    if (!receipt || receipt.objectiveId !== c.id || receipt.revision !== c.revision || receipt.isError || receipt.before !== receipt.after) throw new Error("Missing, failed, or source-changing execution receipt");
    if (receipt.after !== this.stamp().revision) throw new Error("Stale workspace evidence; rerun against current inputs");
    const result = resultOnBranch(branch, receipt);
    if (!result || result.hash !== receipt.resultHash || !result.output.includes(observed) || !observed.includes(target.expected)) throw new Error("Observed/expected outcome not present in finalized non-error tool output on this branch");
    if (kind === "journey") {
      const journey = target as Journey;
      if (receipt.tool !== journey.tool || receipt.inputHash !== digest(journey.input)) throw new Error("Journey did not execute its declared real interface and arguments");
    }
    if (["subagent", "workflow_contract", "writer_lease"].includes(receipt.tool)) throw new Error("Child/ledger attestations are not acceptance evidence");
    let artifact: string | undefined;
    let artifactRevision: string | undefined;
    if (data.artifact !== undefined) {
      artifact = text(data.artifact, "artifact locator");
      if (!path.isAbsolute(artifact) || !result.output.includes(artifact)) throw new Error("Artifact must be an absolute local locator in the tool output");
      artifactRevision = fingerprint([], [artifact]).revision;
    }
    c.evidence = c.evidence.filter((e) => !(e.target === target.id && e.kind === kind));
    c.evidence.push({ target: target.id, kind, expected: target.expected, observed, receipt, artifact, artifactRevision });
    c.status = "open";
    this.save();
  }
  issues(branch: BranchEntry[]): string[] {
    const c = this.require();
    const issues = [...c.blockers];
    if (this.input?.id !== c.confirmedInput) issues.push("New input needs scope confirmation/revision");
    if (c.disposition !== "actionable") issues.push(`Disposition: ${c.disposition}`);
    let stamp: string;
    try { stamp = this.stamp().revision; } catch (error) { return [...issues, `Inputs unavailable: ${String(error)}`]; }
    for (const target of [...c.requirements.filter((r) => r.mandatory), ...c.journeys]) {
      const evidence = c.evidence.find((e) => e.target === target.id);
      const receipt = evidence?.receipt;
      const result = receipt && resultOnBranch(branch, receipt);
      let valid = !!evidence && !!receipt && !receipt.isError && receipt.objectiveId === c.id && receipt.revision === c.revision && receipt.before === stamp && receipt.after === stamp &&
        !!result && result.hash === receipt.resultHash && result.output.includes(evidence.observed) && evidence.observed.includes(target.expected);
      if (target.artifactRequired && !evidence?.artifact) valid = false;
      const journey = c.journeys.find((j) => j.id === target.id);
      if (journey && (evidence?.kind !== "journey" || receipt?.tool !== journey.tool || receipt.inputHash !== digest(journey.input))) valid = false;
      if (evidence?.artifact) {
        try { valid = valid && fingerprint([], [evidence.artifact]).revision === evidence.artifactRevision; } catch { valid = false; }
      }
      if (!valid) issues.push(`Missing/failed/stale evidence: ${target.id}`);
    }
    return issues;
  }
  complete(branch: BranchEntry[]): void {
    const c = this.require();
    const issues = this.issues(branch);
    if (issues.length) { c.status = "open"; this.save(); throw new Error(`UNACCEPTED: ${issues.join("; ")}`); }
    c.status = "complete";
    this.save();
  }
  refresh(branch: BranchEntry[]): string[] {
    const issues = this.issues(branch);
    if (issues.length && this.contract?.status === "complete") { this.contract.status = "open"; this.save(); }
    return issues;
  }
  disposition(value: Contract["disposition"], reasons: string[]): void {
    const c = this.require();
    if (!["actionable", "waiting", "blocked"].includes(value)) throw new Error("Unknown disposition");
    const checked = list(reasons, 16).map((r) => text(r, "disposition reason"));
    if (!checked.length) throw new Error("Record an explicit disposition reason");
    c.disposition = value;
    c.blockers = value === "actionable" ? [] : checked;
    c.status = "open";
    this.save();
  }
  continuation(branch: BranchEntry[], controls: { enabled: boolean; owner: boolean; aborted: boolean; pending: boolean; failed: boolean }): string[] | undefined {
    if (!this.contract || this.fault) return;
    const c = this.contract;
    const issues = this.refresh(branch);
    if (c.status === "complete" || !controls.enabled || !controls.owner || controls.aborted || controls.failed || controls.pending ||
        c.disposition !== "actionable" || c.blockers.length || this.input?.id !== c.confirmedInput) return;
    const progress = digest({ revision: c.revision, issues, evidence: c.evidence.map((e) => [e.target, e.expected, e.observed, e.receipt.after, e.artifactRevision]) });
    c.noProgress = c.progressFingerprint === progress ? c.noProgress + 1 : 0;
    c.progressFingerprint = progress;
    if (c.continuations >= 3 || c.noProgress >= 2) {
      c.disposition = "blocked";
      c.blockers = ["Bounded remediation stopped: no progress or continuation limit reached; objective remains unaccepted"];
      this.save();
      return;
    }
    c.continuations += 1;
    this.save();
    return issues.length ? issues : ["Evidence ready; explicitly call workflow_contract complete"];
  }
}
