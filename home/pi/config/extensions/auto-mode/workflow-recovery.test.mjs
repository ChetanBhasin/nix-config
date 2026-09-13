import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createJiti } from "../../npm/node_modules/jiti/lib/jiti.mjs";
const jiti = createJiti(import.meta.url);
const { WorkflowLedger, LEDGER_ENTRY } = await jiti.import("./workflow-ledger.ts");
const { digest } = await jiti.import("./workflow-workspace.ts");
const { promoteOwnerLaunchToAsync, DELEGATION_GUIDANCE } = await jiti.import("./execution-strategy-handoff.ts");

function fixture(t, oversized = false) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-recovery-unit-"));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const root = path.join(temp, "source"); fs.mkdirSync(root);
  const file = path.join(root, "main.mjs"); fs.writeFileSync(file, 'console.log("Hello, Ada!");\n');
  const other = path.join(root, "unrelated"); fs.mkdirSync(other);
  if (oversized) { const fd = fs.openSync(path.join(other, "oversized"), "w"); fs.ftruncateSync(fd, 128 * 1024 * 1024 + 1); fs.closeSync(fd); }
  const def = { objective: "Greeting CLI", kind: "implementation", roots: [root], externalInputs: [],
    requirements: [{ id: "r", mandatory: true, expected: "Hello, Ada!", artifactRequired: true }, { id: "optional", mandatory: false, expected: "help" }],
    journeys: [{ id: "j", scenario: "User greets Ada", interface: "greeting CLI", tool: "bash", input: { placeholder: true }, expected: "Hello, Ada!", artifactRequired: true }] };
  const branch = []; let failAppend = false;
  const ledger = new WorkflowLedger((customType, data) => { if (failAppend) throw new Error("append failed"); branch.push({ type: "custom", customType, data: structuredClone(data) }); });
  ledger.receiveInput("interactive", "Implement greeting", null, true); ledger.start(def, ledger.input.id);
  const corrected = () => ({ ...structuredClone(def), roots: [file], journeys: [{ ...structuredClone(def.journeys[0]), input: { command: `node ${file}` } }] });
  const reject = (next, pattern) => {
    const before = structuredClone(ledger.contract), n = branch.length, receipts = [...ledger.receipts];
    assert.throws(() => ledger.recover(next, ledger.contract.revision, "Correct the accidental technical binding"), pattern);
    assert.deepEqual(ledger.contract, before); assert.equal(branch.length, n); assert.deepEqual([...ledger.receipts], receipts);
  };
  return { temp, root, file, other, def, ledger, branch, corrected, reject, fail: () => { failAppend = true; } };
}

test("oversized initial roots and placeholder bindings recover without confirmation, retaining all obligations", (t) => {
  const f = fixture(t, true), before = f.ledger.contract;
  assert.match(f.ledger.issues(f.branch).join(" "), /128 MiB/);
  f.ledger.contract.continuations = 2; f.ledger.contract.noProgress = 1;
  f.ledger.recover(f.corrected(), 1, "Accidentally included unrelated oversized files; bind the actual CLI command");
  const c = f.ledger.contract, audit = f.ledger.audit.at(-1);
  assert.equal(c.id, before.id); assert.equal(c.revision, 2); assert.equal(c.status, "open");
  assert.deepEqual(c.requirements, before.requirements); assert.equal(c.continuations, 2); assert.equal(c.noProgress, 1);
  assert.equal(audit.confirmed, false); assert.equal(audit.action, "recover-bindings");
  assert.notEqual(audit.oldBindingHash, audit.newBindingHash); assert.match(audit.workspaceRevision, /^[a-f0-9]{64}$/);
  assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
  f.reject(f.corrected(), /no binding correction/);
  const restored = new WorkflowLedger(() => {}); restored.restore(f.branch);
  assert.deepEqual(restored.contract, c); assert.equal(restored.audit.length, 1);
});

test("replacement preflight is atomic; persistence errors fail closed without disabling fingerprint bounds", (t) => {
  const f = fixture(t, true), next = f.corrected(); next.roots = [f.root];
  f.reject(next, /replacement fingerprint failed/);
  next.externalInputs = [path.join(f.temp, "missing")]; f.reject(next, /replacement fingerprint failed/);
  f.fail(); f.reject(f.corrected(), /append failed/);
  assert.match(f.ledger.fault, /persistence uncertain/);
  assert.throws(() => f.ledger.complete(f.branch), /persistence uncertain/);
});

test("recovery preserves even optional flags, every journey field and artifacts; no forged scope authorization", (t) => {
  const f = fixture(t);
  for (const mutate of [
    (d) => { d.objective = "replace unfinished work"; }, (d) => { d.kind = "inspection"; },
    (d) => { d.requirements.pop(); }, (d) => { d.requirements[0].id = "different"; },
    (d) => { d.requirements[0].expected = "easier"; }, (d) => { d.requirements[0].mandatory = false; d.requirements[1].mandatory = true; },
    (d) => { d.requirements[1].mandatory = true; }, (d) => { d.requirements[0].artifactRequired = false; },
    (d) => { d.journeys[0].id = "different"; }, (d) => { d.journeys[0].scenario = "different"; },
    (d) => { d.journeys[0].interface = "different"; }, (d) => { d.journeys[0].expected = "easier"; },
    (d) => { d.journeys[0].artifactRequired = false; },
  ]) { const next = f.corrected(); mutate(next); f.reject(next, /EVERY/); }
  const removed = f.corrected(); removed.journeys = []; f.reject(removed, /journey/);
  const reader = f.corrected(); reader.journeys[0].tool = "read"; f.reject(reader, /real interface/);
  const loss = f.corrected(); loss.requirements.pop();
  f.ledger.receiveInput("extension", `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: loss })}`, null, true);
  f.reject(loss, /EVERY/); assert.throws(() => f.ledger.revise(loss, 1, f.ledger.input.id), /genuine/);
  f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: loss })}`, null, false);
  f.reject(f.corrected(), /impersonate/); assert.throws(() => f.ledger.revise(loss, 1, f.ledger.input.id), /genuine/);
});

test("changed, new, deleted, ignored and external sources retain coverage across repeated repairs", (t) => {
  const f = fixture(t), changed = path.join(f.other, "changed"), removed = path.join(f.other, "removed");
  fs.writeFileSync(removed, "original");
  // Rebase the fixture before work so deletions are present in its baseline.
  f.ledger = new WorkflowLedger(() => {}); f.ledger.receiveInput("interactive", "Implement", null, true); f.ledger.start(f.def, f.ledger.input.id);
  fs.writeFileSync(changed, "new"); fs.unlinkSync(removed);
  f.ledger.retainMutation([f.file]); fs.writeFileSync(f.file, 'console.log("Hello, Ada!"); // changed\n');
  assert.throws(() => f.ledger.recover(f.corrected(), 1, "Narrow roots"), /changed-source coverage/);
  const next = f.corrected(); next.roots.push(f.other);
  f.ledger.recover(next, 1, "Keep deleted parent and all changed files covered");
  assert.ok(f.ledger.contract.recoveryCoverage.retained.includes(changed));
  assert.ok(f.ledger.contract.recoveryCoverage.retained.includes(removed));
  const hide = f.corrected(); hide.journeys[0].input.command += " ";
  assert.throws(() => f.ledger.recover(hide, 2, "Cannot drop retained changes"), /changed-source coverage/);
});

test("ignored files and external changes cannot disappear from recovered fingerprints", (t) => {
  const f = fixture(t), ignored = path.join(f.root, ".ignored"), external = path.join(f.temp, "external");
  execFileSync("git", ["init", "-q", f.root]); fs.writeFileSync(path.join(f.root, ".gitignore"), ".ignored\n");
  fs.writeFileSync(ignored, "initial"); fs.writeFileSync(external, "initial");
  const def = { ...f.def, externalInputs: [external] }, ledger = new WorkflowLedger(() => {});
  ledger.receiveInput("interactive", "Implement", null, true); ledger.start(def, ledger.input.id);
  fs.writeFileSync(ignored, "changed"); fs.writeFileSync(external, "changed");
  assert.equal(execFileSync("git", ["-C", f.root, "check-ignore", ".ignored"], { encoding: "utf8" }).trim(), ".ignored");
  const next = f.corrected();
  assert.throws(() => ledger.recover(next, 1, "Cannot hide ignored changes"), /changed-source coverage/);
  next.externalInputs = [ignored];
  assert.throws(() => ledger.recover(next, 1, "Cannot hide external changes"), /changed-source coverage/);
  next.externalInputs.push(external); ledger.recover(next, 1, "Retain ignored and external changes explicitly");
  const stamp = ledger.stamp().revision; fs.writeFileSync(external, "changed again"); assert.notEqual(ledger.stamp().revision, stamp);
});

test("symlink dependencies cannot be omitted, even after a binding correction", (t) => {
  const f = fixture(t), external = path.join(f.temp, "dependency"); fs.writeFileSync(external, "load-bearing");
  fs.symlinkSync(external, path.join(f.root, "linked"));
  const next = f.corrected(); next.roots = [f.root]; f.reject(next, /external symlink input/);
  next.externalInputs = [external]; f.ledger.recover(next, 1, "Declare required external symlink dependency");
  const hide = structuredClone(next); hide.externalInputs = []; f.reject(hide, /external symlink input/);
});

test("unproven post-start coverage and legacy histories reject source-obscuring recovery", (t) => {
  const f = fixture(t, true); f.ledger.retainMutation([f.file]);
  f.reject(f.corrected(), /changed-source coverage/);
  const legacy = fixture(t); delete legacy.ledger.contract.recoveryCoverage;
  legacy.reject(legacy.corrected(), /changed-source coverage/);
  const corrupt = structuredClone(legacy.branch);
  corrupt.findLast((e) => e.customType === LEDGER_ENTRY).data.recoveryCoverage = { version: 1, started: false, retained: "fake" };
  const restored = new WorkflowLedger(() => {}); restored.restore(corrupt);
  assert.match(restored.fault, /failed closed/); assert.throws(() => restored.recover(legacy.corrected(), 1, "repair"), /failed closed/);
});

test("old receipts/evidence are invalid after recovery and reload; only a new real-interface run can complete", (t) => {
  const f = fixture(t);
  const def = structuredClone(f.def); def.journeys[0].input = { command: `node ${f.file}` };
  f.ledger.recover(def, 1, "Bind actual executable before testing");
  const artifact = path.join(f.temp, "run.txt"); fs.writeFileSync(artifact, "Hello, Ada!");
  const execute = (id) => {
    const input = f.ledger.contract.journeys[0].input, content = [{ type: "text", text: `Hello, Ada!\n${artifact}` }], stamp = f.ledger.stamp().revision;
    f.branch.push({ type: "message", message: { role: "assistant", content: [{ type: "toolCall", id, name: "bash", arguments: input }] } },
      { type: "message", message: { role: "toolResult", toolCallId: id, toolName: "bash", isError: false, content } });
    f.ledger.record({ version: 1, objectiveId: f.ledger.contract.id, revision: f.ledger.contract.revision, toolCallId: id, tool: "bash", inputHash: digest(input), resultHash: digest(content), before: stamp, after: stamp, isError: false });
  };
  const evidence = (id, target, kind) => f.ledger.addEvidence({ target, kind, expected: "Hello, Ada!", observed: "Hello, Ada!", toolCallId: id, artifact }, f.branch);
  execute("old"); evidence("old", "r", "requirement"); evidence("old", "j", "journey");
  def.journeys[0].input.command += " "; f.ledger.recover(def, 2, "Correct command binding whitespace");
  assert.deepEqual(f.ledger.contract.evidence, []); assert.equal(f.ledger.receipts.size, 0);
  assert.throws(() => evidence("old", "j", "journey"), /Missing/); assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
  const loaded = new WorkflowLedger(() => {}); loaded.restore(f.branch); assert.equal(loaded.receipts.size, 0); assert.throws(() => loaded.complete(f.branch), /UNACCEPTED/);
  execute("new"); evidence("new", "r", "requirement"); evidence("new", "j", "journey"); f.ledger.complete(f.branch);
  assert.equal(f.ledger.contract.status, "complete"); assert.throws(() => f.ledger.recover(def, 3, "No historical reset"), /historical/);
});

test("async/default delegation capability remains an independently owned strategy, never an Auto hook", () => {
  assert.doesNotMatch(DELEGATION_GUIDANCE, /4–8|aggregation delegate|review wave/);
  for (const owner of [true, false]) for (const enabled of [true, false]) {
    for (const original of [{ agent: "worker" }, { workflowScript: "source bytes" }, { agent: "worker", async: false }, { agent: "worker", async: true }, { agent: "worker", foregroundOnly: true }, { agent: "worker", action: "resume" }, { action: "schedule" }]) {
      const input = structuredClone(original); promoteOwnerLaunchToAsync(input, { owner, enabled });
      const expected = structuredClone(original);
      if (owner && enabled && !original.action && !Object.hasOwn(original, "async") && original.foregroundOnly !== true && (original.agent || original.workflowScript)) expected.async = true;
      assert.deepEqual(input, expected);
    }
  }
});
