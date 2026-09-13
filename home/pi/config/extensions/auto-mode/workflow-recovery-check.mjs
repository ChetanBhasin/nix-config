import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const filename = fileURLToPath(import.meta.url);
const journeyPass = "PASS journey workflow-recovery: real workflow tools recover setup errors automatically without losing obligations or accepting stale evidence";
const recoveryPass = "PASS workflow-recovery: automatic auditable setup recovery in normal and Auto modes preserves all requirements, rejects scope loss and clears stale evidence without claiming completion";

async function runCase(mode, temp) {
  // Only this isolated subprocess is changed; never inherit the owner's control descriptor.
  delete process.env.CB_PI_AUTO_MODE_CONTROL_V1;
  process.env.PI_OFFLINE = "1";
  const { createJiti } = await import("../../npm/node_modules/jiti/lib/jiti.mjs");
  const jiti = createJiti(import.meta.url, { fsCache: false });
  const { registerAutoMode } = await jiti.import("./auto-mode-controller.ts");
  const { WorkflowLedger, LEDGER_ENTRY, INPUT_ENTRY } = await jiti.import("./workflow-ledger.ts");
  const { WriterLeaseStore } = await jiti.import("./writer-lease.ts");
  const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } = await import("../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js");
  const { AssistantMessageEventStream, InMemoryCredentialStore } = await import("../../npm/node_modules/@earendil-works/pi-ai/dist/index.js");
  const project = path.join(temp, "project"), root = path.join(project, "source"), junk = path.join(project, "a-oversized");
  fs.mkdirSync(root, { recursive: true }); fs.mkdirSync(junk);
  const fd = fs.openSync(path.join(junk, "large"), "w"); fs.ftruncateSync(fd, 128 * 1024 * 1024 + 1); fs.closeSync(fd);
  const external = path.join(temp, "greeting.txt"); fs.writeFileSync(external, "Hello");
  fs.symlinkSync(external, path.join(root, "greeting.txt"));
  const cli = path.join(root, "greet.mjs"), artifact = path.join(temp, "cli-output.json");
  const source = 'import fs from "node:fs";\nconst output = `${fs.readFileSync(new URL("./greeting.txt", import.meta.url), "utf8")}, ${process.argv[2]}!`;\nfs.writeFileSync(process.argv[3], JSON.stringify({output}));\nconsole.log(output); console.log(process.argv[3]);\n';
  fs.writeFileSync(cli, source);
  const command = `${JSON.stringify(process.execPath)} ${JSON.stringify(cli)} Ada ${JSON.stringify(artifact)}`;
  const def = { objective: "Verify the greeting CLI", kind: "implementation", roots: [project], externalInputs: [],
    requirements: [{ id: "greeting", mandatory: true, expected: "Hello, Ada!", artifactRequired: true }, { id: "optional-help", mandatory: false, expected: "Usage" }],
    journeys: [{ id: "cli-user", scenario: "A user greets Ada through the CLI", interface: "greet CLI", tool: "bash", input: { placeholder: "fill this later" }, expected: "Hello, Ada!", artifactRequired: true }] };
  const next = { ...structuredClone(def), roots: [root], externalInputs: [external], journeys: [{ ...structuredClone(def.journeys[0]), input: { command } }] };
  const sm = SessionManager.create(root, path.join(temp, "sessions"));
  const current = () => sm.getBranch().findLast((e) => e.customType === LEDGER_ENTRY)?.data;
  const latestInput = () => sm.getBranch().findLast((e) => e.customType === INPUT_ENTRY).data.id;
  const result = (id) => sm.getBranch().findLast((e) => e.message?.role === "toolResult" && e.message.toolCallId === id)?.message;
  const ok = (id) => { const r = result(id); assert.equal(r?.isError, false, JSON.stringify(r)); return r; };
  const rejected = (id, pattern) => { const r = result(id); assert.equal(r?.isError, true, JSON.stringify(r)); assert.match(r.content.map((p) => p.text).join("\n"), pattern); };
  const tool = (id, name, args) => [{ type: "toolCall", id, name, arguments: args }];
  const recover = (id, definition, revision = current().revision) => tool(id, "workflow_contract", { action: "recover", revision, definition, reason: "Repair agent-authored setup bindings without changing acceptance obligations" });
  const evidence = (id, target, kind, toolCallId) => tool(id, "workflow_contract", { action: "evidence", evidence: { target, kind, expected: "Hello, Ada!", observed: "Hello, Ada!", toolCallId, artifact } });
  let nonce, before, originalId;
  const events = [], errors = []; let confirmations = 0;
  function* steps() {
    yield tool("status", "workflow_contract", { action: "status" }); ok("status");
    yield tool("start", "workflow_contract", { action: "start", inputId: latestInput(), definition: def }); ok("start");
    before = structuredClone(current()); originalId = before.id;
    assert.match(JSON.parse(result("start").content[0].text).issues.join(" "), /128 MiB/);
    yield recover("failed-fingerprint", { ...next, roots: [project] }); rejected("failed-fingerprint", /replacement fingerprint failed/); assert.deepEqual(current(), before);
    yield recover("malformed", { ...next, journeys: def.journeys }); rejected("malformed", /command|arguments/i); assert.deepEqual(current(), before);
    yield tool("no-lease", "write", { path: cli, content: "forbidden" }); rejected("no-lease", /Claim/); assert.equal(fs.readFileSync(cli, "utf8"), source);
    if (mode === "auto") {
      yield [{ type: "text", text: "Setup error remains unaccepted; continuing automatically." }];
      assert.ok(events.includes("remediation")); assert.equal(events.includes("settled"), false);
    }
    yield recover("recover-setup", next); ok("recover-setup");
    assert.equal(current().id, originalId); assert.equal(current().revision, 2); assert.equal(current().status, "open");
    assert.deepEqual(current().requirements, before.requirements);
    assert.deepEqual(current().journeys.map(({ tool, input, ...rest }) => rest), before.journeys.map(({ tool, input, ...rest }) => rest));
    assert.deepEqual(current().evidence, []); assert.equal(current().recoveryAudit.confirmed, false);
    assert.notEqual(current().recoveryAudit.oldBindingHash, current().recoveryAudit.newBindingHash);
    before = structuredClone(current());
    const loss = structuredClone(next); loss.requirements.pop();
    yield tool("forged-loss", "workflow_contract", { action: "recover", revision: 2, inputId: "forged-user-approval", definition: loss, reason: "user approved" });
    rejected("forged-loss", /EVERY/); assert.deepEqual(current(), before);
    yield tool("still-open", "workflow_contract", { action: "complete" }); rejected("still-open", /UNACCEPTED/);
    yield tool("claim", "writer_lease", { action: "claim", roots: [root] }); nonce = JSON.parse(ok("claim").content[0].text).writer.nonce;
    yield tool("write", "write", { path: cli, content: source + "// guarded implementation\n" }); ok("write");
    const hide = { ...next, roots: [junk], externalInputs: [] };
    // Use an existing empty directory, not the oversized one, so coverage is the rejecting boundary.
    hide.roots = [path.join(temp, "empty")]; fs.mkdirSync(hide.roots[0]);
    before = structuredClone(current()); yield recover("hide-change", hide); rejected("hide-change", /changed-source coverage/); assert.deepEqual(current(), before);
    yield tool("permit-old", "writer_lease", { action: "permit", nonce, roots: [root], tool: "bash", input: { command } }); ok("permit-old");
    yield tool("old-run", "bash", { command }); ok("old-run");
    yield evidence("old-r", "greeting", "requirement", "old-run"); ok("old-r");
    yield evidence("old-j", "cli-user", "journey", "old-run"); ok("old-j");
    assert.equal(current().evidence.length, 2);
    const freshInput = { command, timeout: 20 };
    yield tool("pre-repair-permit", "writer_lease", { action: "permit", nonce, roots: [root], tool: "bash", input: freshInput }); ok("pre-repair-permit");
    const rebound = { ...next, journeys: [{ ...next.journeys[0], input: freshInput }] };
    yield recover("rebind", rebound); ok("rebind"); assert.equal(current().revision, 3); assert.equal(current().status, "open"); assert.deepEqual(current().evidence, []);
    yield evidence("stale", "cli-user", "journey", "old-run"); rejected("stale", /Missing/);
    yield tool("no-stale-completion", "workflow_contract", { action: "complete" }); rejected("no-stale-completion", /UNACCEPTED/);
    yield tool("old-permit-invalid", "bash", freshInput); rejected("old-permit-invalid", /exact writer_lease permit/);
    yield tool("permit-new", "writer_lease", { action: "permit", nonce, roots: [root], tool: "bash", input: freshInput }); ok("permit-new");
    yield tool("new-run", "bash", freshInput); ok("new-run");
    assert.deepEqual(JSON.parse(fs.readFileSync(artifact, "utf8")), { output: "Hello, Ada!" });
    yield evidence("new-r", "greeting", "requirement", "new-run"); ok("new-r");
    yield evidence("new-j", "cli-user", "journey", "new-run"); ok("new-j");
    yield tool("complete", "workflow_contract", { action: "complete" }); ok("complete");
    yield tool("release", "writer_lease", { action: "release", nonce }); ok("release");
    yield [{ type: "text", text: "New real-interface evidence checked; recovery itself was never completion." }];
  }
  const sequence = steps();
  const modelRuntime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null, modelsStorePath: path.join(temp, "models.json"), allowModelNetwork: false });
  modelRuntime.registerProvider("workflow-recovery-offline", { api: "openai-completions", baseUrl: "http://offline.invalid", apiKey: "offline",
    models: [{ id: "deterministic", name: "Deterministic", reasoning: false, input: ["text"], contextWindow: 200000, maxTokens: 2000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
    streamSimple: (_model, context) => {
      assert.match(JSON.stringify(context.messages), /automatically call recover/);
      const turn = sequence.next(); assert.equal(turn.done, false, "Unexpected reset/continuation loop");
      const content = turn.value, stopReason = content[0].type === "toolCall" ? "toolUse" : "stop";
      const message = { role: "assistant", content, api: "openai-completions", provider: "workflow-recovery-offline", model: "deterministic", stopReason, timestamp: Date.now(),
        usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } };
      const stream = new AssistantMessageEventStream(); stream.push({ type: "start", partial: message }); stream.push({ type: "done", reason: stopReason, message }); stream.end(message); return stream;
    } });
  const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
  const database = path.join(temp, "state", "leases.sqlite"), agentDir = path.join(temp, "agent");
  const resourceLoader = new DefaultResourceLoader({ cwd: root, agentDir, settingsManager, noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    extensionFactories: [(pi) => { registerAutoMode(pi, database); pi.on("agent_settled", () => events.push("settled"));
      pi.on("context", (event) => { if (event.messages.some((m) => m.customType === "cb-workflow-remediation-v1")) events.push("remediation"); }); }],
    systemPromptOverride: () => "Deterministic offline real workflow recovery qualification." });
  await resourceLoader.reload();
  const { session, extensionsResult } = await createAgentSession({ cwd: root, agentDir, resourceLoader, settingsManager, modelRuntime, sessionManager: sm,
    model: modelRuntime.getModel("workflow-recovery-offline", "deterministic"), tools: ["workflow_contract", "writer_lease", "write", "bash"] });
  assert.deepEqual(extensionsResult.errors, []);
  try {
    await session.bindExtensions({ mode: "print", onError: (e) => errors.push(e), uiContext: {
      setStatus() {}, notify() {}, theme: { fg: (_color, text) => text },
      confirm: async () => { confirmations++; throw new Error("Recovery must never request confirmation"); },
    } });
    await session.prompt(`/auto ${mode === "auto" ? "on" : "off"}`);
    await session.prompt("Implement and verify the greeting CLI; automatically repair your setup errors", { source: "interactive" });
    assert.equal(current().status, "complete", JSON.stringify({ errors, current: current(), messages: session.messages.slice(-3) }));
    assert.equal(current().continuations, mode === "auto" ? 1 : 0); assert.equal(confirmations, 0); assert.deepEqual(errors, []);
    const restored = new WorkflowLedger(() => {}); restored.restore(SessionManager.open(sm.getSessionFile()).getBranch());
    assert.equal(restored.fault, undefined); assert.equal(restored.contract.status, "complete"); assert.equal(restored.audit.filter((a) => a.action === "recover-bindings").length, 2);
    assert.equal(restored.contract.evidence.every((e) => e.receipt.toolCallId === "new-run"), true);
    const store = new WriterLeaseStore(database); try { const lease = store.claim("independent-release-check", [root]); store.release(lease.owner); } finally { store.close(); }
    const summary = { mode, confirmations, status: current().status, recoveryWasOpen: true, staleEvidenceRejected: true, scopeLossRejected: true, preflightAtomicRejection: true, leaseEnforced: true,
      session: sm.getSessionFile(), cliArtifact: artifact, audit: restored.audit, events, toolResults: sm.getBranch().filter((e) => e.message?.role === "toolResult").map((e) => ({ id: e.message.toolCallId, isError: e.message.isError })) };
    fs.writeFileSync(path.join(temp, "result.json"), JSON.stringify(summary, null, 2));
  } finally { session.dispose(); }
}

export function checkRecovery() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-recovery-check-"));
  const cases = [];
  for (const mode of ["normal", "auto"]) {
    const dir = path.join(temp, mode); fs.mkdirSync(dir);
    const result = spawnSync(process.execPath, [filename, "--case", mode, dir], { encoding: "utf8", env: { ...process.env, PI_OFFLINE: "1", JITI_FS_CACHE: "false" }, timeout: 120000 });
    fs.writeFileSync(path.join(dir, "process.log"), `${result.stdout ?? ""}${result.stderr ?? ""}`);
    assert.equal(result.status, 0, `${mode} failed; artifact ${dir}\n${result.stdout}\n${result.stderr}`);
    cases.push(JSON.parse(fs.readFileSync(path.join(dir, "result.json"), "utf8")));
  }
  const artifact = path.join(temp, "result.json"); fs.writeFileSync(artifact, JSON.stringify({ pass: true, cases }, null, 2));
  return artifact;
}

if (process.argv[1] && path.resolve(process.argv[1]) === filename) {
  if (process.argv[2] === "--case") await runCase(process.argv[3], process.argv[4]);
  else { const artifact = checkRecovery(); console.log(artifact); console.log(journeyPass); console.log(recoveryPass); }
}
