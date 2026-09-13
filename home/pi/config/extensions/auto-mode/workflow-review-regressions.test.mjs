import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createJiti } from "../../npm/node_modules/jiti/lib/jiti.mjs";

const jiti = createJiti(import.meta.url, { fsCache: false });
const { WorkflowLedger, LEDGER_ENTRY } = await jiti.import("./workflow-ledger.ts");

function fixture(t) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-review-"));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const root = path.join(temp, "source");
  fs.mkdirSync(root);
  const file = path.join(root, "cli.mjs");
  fs.writeFileSync(file, 'console.log("ok");\n');
  const def = { objective: "Verify CLI", kind: "implementation", roots: [root], externalInputs: [],
    requirements: [{ id: "r", mandatory: true, expected: "ok" }],
    journeys: [{ id: "j", scenario: "Run CLI", interface: "CLI", tool: "bash", input: { command: `node ${file}` }, expected: "ok" }] };
  const branch = [];
  const ledger = new WorkflowLedger((customType, data) => branch.push({ type: "custom", customType, data: structuredClone(data) }));
  const start = (definition = def) => {
    ledger.receiveInput("interactive", "Implement CLI", null, true);
    ledger.start(definition, ledger.input.id);
  };
  return { temp, root, file, def, branch, ledger, start };
}

function git(cwd, ...args) {
  return execFileSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
    "-c", "user.name=Workflow fixture", "-c", "user.email=fixture@example.invalid", "-C", cwd, ...args], { encoding: "utf8" });
}

test("guarded symlink replacement retains the original lexical worktree HEAD", (t) => {
  const f = fixture(t);
  const a = path.join(f.temp, "a"), b = path.join(f.temp, "b");
  for (const dir of [a, b]) {
    fs.mkdirSync(dir); git(dir, "init", "-q"); git(dir, "commit", "--allow-empty", "-qm", "initial");
  }
  const src = path.join(a, "src"), target = path.join(b, "cli");
  fs.mkdirSync(src); fs.writeFileSync(target, "target");
  const link = path.join(src, "cli"); fs.writeFileSync(link, "initial");
  const original = { ...f.def, roots: [src], externalInputs: [target] };
  f.start(original);
  // This is the same pre-mutation retention invoked by the guarded controller.
  f.ledger.retainMutation([link]);
  assert.ok(f.ledger.contract.recoveryCoverage.trees.includes(a));
  fs.unlinkSync(link); fs.symlinkSync(target, link);
  const hidden = { ...original, roots: [target], externalInputs: [link] };
  assert.throws(() => f.ledger.recover(hidden, 1, "Cannot hide the link owner"), /HEAD coverage/);
  f.ledger.recover({ ...original, roots: [src, target], externalInputs: [] }, 1, "Keep both source identities");
  const before = f.ledger.stamp().revision;
  git(a, "commit", "--allow-empty", "-qm", "changed head");
  assert.notEqual(f.ledger.stamp().revision, before, "the original worktree HEAD still participates");
});

test("deleted file roots remain recoverable after restoration, not silently acceptable", (t) => {
  const f = fixture(t), original = { ...f.def, roots: [f.file] };
  f.start(original); f.ledger.retainMutation([f.file]); fs.unlinkSync(f.file);
  const loaded = new WorkflowLedger((customType, data) => f.branch.push({ type: "custom", customType, data: structuredClone(data) }));
  loaded.restore(f.branch);
  assert.equal(loaded.fault, undefined);
  assert.throws(() => loaded.complete(f.branch), /UNACCEPTED/);
  loaded.recover({ ...original, roots: [f.root] }, 1, "Retain the surviving parent of a guarded deletion");
  assert.equal(loaded.contract.revision, 2);
  assert.ok(loaded.contract.recoveryCoverage.retained.includes(f.file));
  assert.throws(() => loaded.complete(f.branch), /UNACCEPTED/);
  const corrupt = structuredClone(f.branch);
  corrupt.findLast((entry) => entry.customType === LEDGER_ENTRY).data.roots = ["relative"];
  loaded.restore(corrupt);
  assert.match(loaded.fault, /absolute/);
  corrupt.findLast((entry) => entry.customType === LEDGER_ENTRY).data.roots = [];
  loaded.restore(corrupt);
  assert.match(loaded.fault, /1–16 explicit roots/);
});

test("genuine scope revision rebases recovery while autonomous strengthening retains changes", (t) => {
  const f = fixture(t); f.start();
  f.ledger.retainMutation([f.file]); fs.appendFileSync(f.file, "// change\n");
  const b = path.join(f.temp, "b"); fs.mkdirSync(b); fs.writeFileSync(path.join(b, "cli"), "ok");
  const strengthened = { ...f.def, roots: [f.root, b] };
  f.ledger.revise(strengthened, 1, f.ledger.input.id);
  assert.ok(f.ledger.contract.recoveryCoverage.retained.includes(f.file));
  const approved = { ...f.def, roots: [b] };
  f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 2, definition: approved })}`, null, true);
  f.ledger.revise(approved, 2, f.ledger.input.id);
  fs.rmSync(f.root, { recursive: true });
  const loaded = new WorkflowLedger((customType, data) => f.branch.push({ type: "custom", customType, data: structuredClone(data) }));
  loaded.restore(f.branch); assert.equal(loaded.fault, undefined);
  const corrected = structuredClone(approved); corrected.journeys[0].input.command = `node ${path.join(b, "cli")}`;
  loaded.recover(corrected, 3, "Correct the executable binding within the user-authorized scope");
  assert.equal(loaded.contract.revision, 4);
  assert.deepEqual(loaded.contract.recoveryCoverage.baseline.roots, [b]);
});

for (const change of ["requirement", "artifact"]) {
  test(`explicitly authorized ${change} strengthening cannot retire guarded sources`, (t) => {
    const f = fixture(t); f.start();
    f.ledger.retainMutation([f.file]); fs.appendFileSync(f.file, "// guarded change\n");
    const b = path.join(f.temp, "untouched"); fs.mkdirSync(b); fs.writeFileSync(path.join(b, "cli"), "ok");
    const approved = structuredClone(f.def);
    if (change === "requirement") approved.requirements.push({ id: "extra", mandatory: true, expected: "extra" });
    else approved.requirements[0].artifactRequired = true;
    f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: approved })}`, null, true);
    f.ledger.revise(approved, 1, f.ledger.input.id);
    const loaded = new WorkflowLedger(() => {}); loaded.restore(f.branch);
    assert.equal(loaded.fault, undefined);
    assert.ok(loaded.contract.recoveryCoverage.retained.includes(f.file));
    assert.throws(() => loaded.recover({ ...approved, roots: [b] }, 2, "Cannot conceal prior edits"), /changed-source coverage/);
    assert.equal(loaded.contract.revision, 2);
  });
}

test("actual SDK post-append subscriber failure makes recovery fail closed until authoritative restore", async (t) => {
  const f = fixture(t);
  const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } = await import("../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js");
  const { InMemoryCredentialStore } = await import("../../npm/node_modules/@earendil-works/pi-ai/dist/index.js");
  const modelRuntime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null,
    modelsStorePath: path.join(f.temp, "models-store.json"), allowModelNetwork: false });
  const sm = SessionManager.create(f.root, path.join(f.temp, "sessions"));
  const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false } });
  const agentDir = path.join(f.temp, "agent");
  let api;
  const resourceLoader = new DefaultResourceLoader({ cwd: f.root, agentDir, settingsManager,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    extensionFactories: [(pi) => { api = pi; }] });
  await resourceLoader.reload();
  const { session } = await createAgentSession({ cwd: f.root, agentDir, modelRuntime, sessionManager: sm,
    settingsManager, resourceLoader, noTools: "all" });
  t.after(() => session.dispose());
  await session.bindExtensions({ mode: "print", onError: (error) => { throw error; } });
  // Explicit fixture history enables normal SDK disk persistence; no model request is made.
  sm.appendMessage({ role: "assistant", content: [{ type: "text", text: "fixture seed" }],
    api: "openai-completions", provider: "fixture", model: "fixture", stopReason: "stop", timestamp: Date.now(),
    usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } });
  const ledger = new WorkflowLedger((type, data) => api.appendEntry(type, data));
  ledger.receiveInput("interactive", "Implement", null, true); ledger.start(f.def, ledger.input.id);
  const unsubscribe = session.subscribe((event) => {
    if (event.type === "entry_appended" && event.entry.customType === LEDGER_ENTRY && event.entry.data?.recoveryAudit) {
      throw new Error("injected post-persistence subscriber failure");
    }
  });
  t.after(unsubscribe);
  const next = structuredClone(f.def); next.journeys[0].input.timeout = 20;
  assert.throws(() => ledger.recover(next, 1, "Test SDK append uncertainty"), /persistence uncertain/);
  assert.equal(sm.getBranch().findLast((entry) => entry.customType === LEDGER_ENTRY).data.revision, 2);
  assert.match(ledger.fault, /subscriber failure/);
  assert.equal(ledger.receipts.size, 0);
  assert.throws(() => ledger.complete(sm.getBranch()), /persistence uncertain/);
  assert.throws(() => ledger.recover(next, 1, "Cannot retry uncertain state"), /persistence uncertain/);
  const reopened = SessionManager.open(sm.getSessionFile());
  const loaded = new WorkflowLedger(() => {}); loaded.restore(reopened.getBranch());
  assert.equal(loaded.fault, undefined); assert.equal(loaded.contract.revision, 2);
  assert.deepEqual(loaded.contract.evidence, []);
  assert.throws(() => loaded.complete(reopened.getBranch()), /UNACCEPTED/);
});
