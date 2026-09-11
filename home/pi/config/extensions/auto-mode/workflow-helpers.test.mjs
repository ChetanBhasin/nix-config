import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, fork } from "node:child_process";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { createJiti } from "../../npm/node_modules/jiti/lib/jiti.mjs";
const jiti = createJiti(import.meta.url);
const { WorkflowLedger, LEDGER_ENTRY, AUDIT_ENTRY, definition } = await jiti.import("./workflow-ledger.ts");
const { WriterLeaseStore, processProbe, demonstratedDead, mutationTargets } = await jiti.import("./writer-lease.ts");
const { digest, fingerprint } = await jiti.import("./workflow-workspace.ts");
const { canonicalToolName, sameToolName, hasActiveTool } = await jiti.import("./workflow-tool-name.ts");

if (process.argv[2] === "contender") {
  const store = new WriterLeaseStore(process.argv[3]);
  process.send("ready");
  process.on("message", (message) => {
    if (message === "go") {
      try { const lease = store.claim(String(process.pid), [process.argv[4]]); process.send({ won: true, lease }); }
      catch (error) { process.send({ won: false, error: String(error) }); }
    } else if (message === "quit") { store.close(); process.exit(0); }
  });
} else {
  function fixture(t) {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-helpers-"));
    t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
    const root = path.join(temp, "source");
    fs.mkdirSync(root);
    fs.writeFileSync(path.join(root, "main.txt"), "initial");
    const external = path.join(temp, "external.txt");
    fs.writeFileSync(external, "input");
    const branch = [];
    const ledger = new WorkflowLedger((customType, data) => branch.push({ type: "custom", customType, data: structuredClone(data) }));
    ledger.receiveInput("interactive", "Implement greeting CLI", null, true);
    const def = { objective: "Greeting CLI", kind: "implementation", roots: [root], externalInputs: [external],
      requirements: [{ id: "r1", mandatory: true, expected: "Hello, Ada!" }],
      journeys: [{ id: "j1", scenario: "User greets Ada through the CLI", interface: "./greet Ada", tool: "bash", input: { command: "./greet Ada" }, expected: "Hello, Ada!" }] };
    ledger.start(def, ledger.input.id);
    const executed = (id = "run-1", isError = false, tool = "bash", input = def.journeys[0].input, output = "Hello, Ada!") => {
      const content = [{ type: "text", text: output }];
      const stamp = ledger.stamp().revision;
      branch.push({ type: "message", message: { role: "assistant", content: [{ type: "toolCall", id, name: tool, arguments: input }] } });
      branch.push({ type: "message", message: { role: "toolResult", toolCallId: id, toolName: tool, content, isError } });
      ledger.record({ version: 1, objectiveId: ledger.contract.id, revision: ledger.contract.revision, toolCallId: id, tool,
        inputHash: digest(input), resultHash: digest(content), before: stamp, after: stamp, isError });
      return id;
    };
    const evidence = (target = "j1", toolCallId = "run-1", extra = {}) => ledger.addEvidence({ target, kind: target === "r1" ? "requirement" : "journey", expected: "Hello, Ada!", observed: "Hello, Ada!", toolCallId, ...extra }, branch);
    return { temp, root, external, ledger, def, branch, executed, evidence };
  }
  test("ledger rejects unrun, failed, self-attested, wrong-interface and missing journeys", (t) => {
    const f = fixture(t);
    assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
    assert.throws(() => f.evidence(), /Missing/);
    f.executed("failed", true);
    assert.throws(() => f.evidence("j1", "failed"), /failed/);
    f.executed("child", false, "subagent");
    assert.throws(() => f.evidence("r1", "child"), /attestations/);
    assert.throws(() => f.evidence("j1", "child"), /real interface/);
    assert.throws(() => f.evidence("j1", "child", { kind: "attestation" }), /attestations/);
    f.executed(); f.evidence("r1");
    assert.throws(() => f.ledger.complete(f.branch), /j1/);
    f.evidence(); f.ledger.complete(f.branch);
    assert.equal(f.ledger.contract.status, "complete");
  });
  test("a newer failed or unfinalized journey invalidates a prior pass, including after reload", (t) => {
    const f = fixture(t);
    f.executed(); f.evidence(); f.evidence("r1");
    f.executed("new-failure", true);
    assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
    assert.throws(() => f.evidence("j1", "run-1"), /not present/);
    const restored = new WorkflowLedger(() => {}); restored.restore(f.branch);
    assert.throws(() => restored.complete(f.branch), /UNACCEPTED/);
    f.executed("recovered"); f.evidence("j1", "recovered"); f.evidence("r1", "recovered");
    f.branch.push({ type: "message", message: { role: "assistant", content: [{ type: "toolCall", id: "unfinalized", name: "bash", arguments: f.def.journeys[0].input }] } });
    assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
  });
  test("artifact-required outcomes cannot pass with a missing artifact, and scope budgets cannot reset", (t) => {
    const f = fixture(t);
    const next = structuredClone(f.def); next.journeys[0].artifactRequired = true;
    f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: next })}`, null, true);
    f.ledger.revise(next, 1, f.ledger.input.id);
    f.executed(); assert.throws(() => f.evidence(), /requires an artifact/);
    f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "start", definition: f.def })}`, null, true);
    f.ledger.start(f.def, f.ledger.input.id);
    assert.throws(() => f.ledger.start(f.def, f.ledger.input.id), /NEW genuine input/);
    f.ledger.receiveInput("interactive", "workflow-scope invalid", null, true);
    assert.ok(f.ledger.input.invalidAuthorization);
    assert.throws(() => f.ledger.confirm(1, f.ledger.input.id));
  });
  test("active evidence binds output and finalized branch results; checked history stays immutable", (t) => {
    const f = fixture(t);
    f.executed();
    assert.throws(() => f.evidence("j1", "run-1", { observed: "invented Hello, Ada!" }), /not present/);
    f.evidence(); f.evidence("r1");
    const result = f.branch.find((e) => e.message?.role === "toolResult");
    result.message.isError = true;
    assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
    result.message.isError = false;
    f.ledger.complete(f.branch);
    f.branch.splice(f.branch.indexOf(result), 1);
    assert.doesNotThrow(() => f.ledger.complete(f.branch));
    assert.equal(f.ledger.contract.status, "complete");
  });
  for (const change of ["existing", "untracked", "external", "ignored"]) test(`${change} input changes invalidate acceptance`, (t) => {
    const f = fixture(t);
    execFileSync("git", ["init", "-q", f.root]);
    fs.writeFileSync(path.join(f.root, ".gitignore"), ".ignored\n");
    f.executed(); f.evidence(); f.evidence("r1");
    const file = change === "external" ? f.external : path.join(f.root, change === "existing" ? "main.txt" : change === "ignored" ? ".ignored" : "new.txt");
    fs.writeFileSync(file, "changed");
    if (change === "ignored") assert.equal(execFileSync("git", ["-C", f.root, "check-ignore", ".ignored"], { encoding: "utf8" }).trim(), ".ignored");
    if (change === "untracked") assert.match(execFileSync("git", ["-C", f.root, "status", "--porcelain"], { encoding: "utf8" }), /\?\? new\.txt/);
    assert.throws(() => f.ledger.complete(f.branch), /stale/);
    assert.equal(f.ledger.contract.status, "open");
    assert.throws(() => f.evidence(), /Stale/);
  });
  test("checked completion remains historical across later workspace and settings changes", (t) => {
    const f = fixture(t);
    f.executed(); f.evidence(); f.evidence("r1"); f.ledger.complete(f.branch);
    fs.writeFileSync(path.join(f.root, "main.txt"), "later change");
    fs.writeFileSync(f.external, "later setting");
    f.ledger.receiveInput("interactive", "Show the active profile in the footer", null, true);
    assert.doesNotThrow(() => f.ledger.complete(f.branch));
    assert.deepEqual(f.ledger.issues(f.branch), []);
    assert.equal(f.ledger.contract.status, "complete");
  });
  test("explicit symlink external inputs and artifacts are checked", (t) => {
    const f = fixture(t);
    fs.symlinkSync(f.external, path.join(f.root, "linked"));
    assert.throws(() => fingerprint([f.root], []), /external symlink/);
    assert.ok(fingerprint([f.root], [f.external]).revision);
    const artifact = path.join(f.temp, "run.log"); fs.writeFileSync(artifact, "log");
    f.executed("artifact", false, "bash", f.def.journeys[0].input, `Hello, Ada!\n${artifact}`);
    f.evidence("j1", "artifact", { artifact }); f.evidence("r1", "artifact");
    fs.writeFileSync(artifact, "replaced");
    assert.throws(() => f.ledger.complete(f.branch), /stale/);
  });
  test("branch/reload/compaction/fork restoration uses only provided active branch entries", (t) => {
    const f = fixture(t); const before = structuredClone(f.branch);
    f.executed(); f.evidence(); f.evidence("r1"); f.ledger.complete(f.branch);
    f.branch.push({ type: "compaction", summary: "all done", data: { status: "complete" } });
    const loaded = new WorkflowLedger(() => {}); loaded.restore(f.branch);
    assert.equal(loaded.contract.status, "complete"); assert.deepEqual(loaded.issues(f.branch), []);
    loaded.restore(before); assert.equal(loaded.contract.status, "open"); assert.equal(loaded.receipts.size, 0);
    loaded.restore([{ type: "compaction", summary: JSON.stringify(f.ledger.contract) }]); assert.equal(loaded.contract, undefined);
    loaded.restore(structuredClone(f.branch)); assert.deepEqual(loaded.issues(f.branch), []); // fork path, not all entries
    loaded.restore([{ type: "custom", customType: LEDGER_ENTRY, data: { version: 99 } }]); assert.match(loaded.fault, /failed closed/);
    assert.throws(() => loaded.start(f.def, "x"), /failed closed/);
    const malformedAuditEntries = [];
    const malformedAudit = new WorkflowLedger((type, data) => malformedAuditEntries.push({ type, data }));
    assert.doesNotThrow(() => malformedAudit.restore([{ type: "custom", customType: AUDIT_ENTRY, data: null }]));
    assert.match(malformedAudit.fault, /failed closed/);
    const restorationFault = malformedAudit.fault;
    for (const [operation, mutate] of [
      ["start", () => malformedAudit.start(f.def, "x")],
      ["reset", () => malformedAudit.retire("reset", "cannot bypass malformed audit")],
      ["logHuman", () => malformedAudit.logHuman("reset", "cannot append around fault", false)],
      ["receiveInput", () => malformedAudit.receiveInput("interactive", "new request", null, true)],
      ["begin", () => malformedAudit.begin("bash", "input")],
      ["record", () => malformedAudit.record({ version: 1, toolCallId: "call", tool: "bash", inputHash: "input", isError: false })],
      ["continuation", () => malformedAudit.continuation([], { enabled: true, owner: true, aborted: false, pending: false, failed: false })],
    ]) {
      assert.throws(mutate, /failed closed/, operation);
      assert.equal(malformedAudit.fault, restorationFault, `${operation} must preserve the restoration fault`);
    }
    assert.deepEqual(malformedAuditEntries, []);
    assert.equal(malformedAudit.contract, undefined);
    assert.equal(malformedAudit.input, undefined);
    assert.equal(malformedAudit.receipts.size, 0);
  });
  test("restore validates the latest snapshot, not removed roots from superseded scope history", (t) => {
    const f = fixture(t);
    const replacement = path.join(f.temp, "replacement"); fs.mkdirSync(replacement);
    const next = { ...f.def, roots: [replacement] };
    f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: next })}`, null, true);
    f.ledger.revise(next, 1, f.ledger.input.id);
    fs.rmSync(f.root, { recursive: true });
    const restored = new WorkflowLedger(() => {}); restored.restore(f.branch);
    assert.equal(restored.fault, undefined);
    assert.deepEqual(restored.contract.roots, [replacement]);
  });
  test("source-reader aliases cannot masquerade as executed interface journeys", (t) => {
    const f = fixture(t);
    for (const tool of ["read_symbol", "read_enclosing", "module_report", "symbol_search", "project_report", "ast_grep_search", "lsp_navigation", "ctx_expand"]) {
      const next = structuredClone(f.def); next.journeys[0].tool = tool;
      assert.throws(() => definition(next), /real interface/, tool);
    }
  });
  test("provider-qualified function aliases canonicalize narrowly", (t) => {
    const f = fixture(t);
    assert.equal(canonicalToolName("functions.bash"), "bash");
    assert.equal(canonicalToolName("bash"), "bash");
    assert.equal(canonicalToolName("other.bash"), "other.bash");
    assert.equal(sameToolName("functions.bash", "bash"), true);
    assert.equal(sameToolName("other.bash", "bash"), false);
    assert.equal(hasActiveTool(["bash"], "functions.bash"), true);
    const aliased = structuredClone(f.def); aliased.journeys[0].tool = "functions.bash";
    assert.equal(definition(aliased).journeys[0].tool, "bash");
    const prohibited = structuredClone(f.def); prohibited.journeys[0].tool = "functions.read";
    assert.throws(() => definition(prohibited), /real interface/);
    f.executed("aliased-run", false, "functions.bash");
    f.evidence("j1", "aliased-run"); f.evidence("r1", "aliased-run");
    assert.doesNotThrow(() => f.ledger.complete(f.branch));
  });
  test("autonomous strengthening preserves all obligations, scope and continuation budgets", (t) => {
    const f = fixture(t); f.executed(); f.evidence(); f.evidence("r1");
    f.ledger.contract.continuations = 1; f.ledger.contract.noProgress = 1;
    const next = structuredClone(f.def);
    next.requirements.push({ id: "failure", mandatory: true, expected: "invalid argument" });
    next.journeys.push({ ...next.journeys[0], id: "failure-cli", input: { command: "./greet --invalid" }, expected: "invalid argument" });
    next.journeys[0].artifactRequired = true;
    f.ledger.revise(next, 1, f.ledger.input.id);
    assert.equal(f.ledger.contract.revision, 2);
    assert.equal(f.ledger.contract.continuations, 1); assert.equal(f.ledger.contract.noProgress, 1);
    assert.deepEqual(f.ledger.contract.evidence, []);
    assert.throws(() => f.ledger.complete(f.branch), /UNACCEPTED/);
    for (const weaken of [
      (d) => d.requirements.splice(0, 1),
      (d) => { d.requirements[0].mandatory = false; },
      (d) => { d.requirements[0].expected = "easier"; },
      (d) => { d.journeys[0].artifactRequired = false; },
      (d) => { d.journeys[0].input.command = "cat source"; },
      (d) => d.journeys.splice(0, 1),
      (d) => { d.externalInputs = []; },
      (d) => { d.roots = [f.temp]; },
      (d) => { d.objective = "different work"; },
    ]) {
      const weakened = structuredClone(next); weaken(weakened);
      assert.throws(() => f.ledger.revise(weakened, 2, f.ledger.input.id), /genuine/);
    }
    f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision: 2, definition: f.def })}`, null, true);
    f.ledger.revise(f.def, 2, f.ledger.input.id);
    f.ledger.revise(next, 3, f.ledger.input.id); // consumed approval must not prevent later strengthening
    assert.equal(f.ledger.contract.revision, 4); assert.equal(f.ledger.contract.continuations, 1);
    const saved = f.branch.length;
    f.ledger.confirm(4, f.ledger.input.id);
    f.ledger.revise(next, 4, f.ledger.input.id);
    assert.equal(f.branch.length, saved, "unchanged confirmation/revision remains a no-op after strengthening");
  });
  test("new genuine input after checked completion can start a new goal, never reset unfinished work", (t) => {
    const f = fixture(t), next = { ...f.def, objective: "Next requested CLI" };
    f.ledger.receiveInput("interactive", "New task", null, true);
    assert.throws(() => f.ledger.start(next, f.ledger.input.id), /explicit/);
    f.ledger.confirm(1, f.ledger.input.id); f.executed(); f.evidence(); f.evidence("r1"); f.ledger.complete(f.branch);
    f.ledger.receiveInput("extension", "New task", null, true);
    assert.throws(() => f.ledger.start(next, f.ledger.input.id), /NEW genuine input/);
    f.ledger.receiveInput("interactive", "Now implement the next CLI", null, true);
    const restored = new WorkflowLedger(() => {}); restored.restore(f.branch);
    const started = restored.start(next, restored.input.id);
    assert.equal(started.objective, next.objective); assert.equal(started.continuations, 0);
    assert.throws(() => restored.start(f.def, restored.input.id), /NEW genuine/);
  });
  test("individual source files avoid dependency trees while retaining whole-worktree ownership", (t) => {
    const f = fixture(t); execFileSync("git", ["init", "-q", f.root]);
    const first = path.join(f.root, "main.txt"), second = path.join(f.root, "package.json");
    fs.writeFileSync(second, "{}");
    const store = new WriterLeaseStore(path.join(f.temp, "files.sqlite")); t.after(() => store.close());
    const lease = store.claim("file-owner", [first]);
    assert.throws(() => store.claim("second-owner", [second]), /conflict/);
    assert.equal(definition({ ...f.def, roots: [first, second] }).roots.length, 2);
    const before = fingerprint([first, second], []);
    fs.mkdirSync(path.join(f.root, "node_modules")); fs.writeFileSync(path.join(f.root, "node_modules", "cache"), "not a declared input");
    assert.equal(fingerprint([first, second], []).revision, before.revision);
    fs.writeFileSync(second, '{"changed":true}');
    assert.notEqual(fingerprint([first, second], []).revision, before.revision);
    store.release(lease.owner);
  });

  test("dangling file roots and dangling mutation targets fail closed, including missing descendants", (t) => {
    for (const git of [false, true]) {
      const f = fixture(t);
      if (git) execFileSync("git", ["init", "-q", f.root]);
      const file = path.join(f.root, "main.txt"), absent = path.join(f.temp, "outside-missing");
      const store = new WriterLeaseStore(path.join(f.temp, "dangling.sqlite")); t.after(() => store.close());
      const fileLease = store.claim("file-owner", [file]);
      fs.unlinkSync(file); fs.symlinkSync(absent, file);
      assert.throws(() => store.check(fileLease.owner), /identity|symlink/);
      assert.throws(() => store.reserve(fileLease.owner, "escape", [file]), /identity|symlink/);
      assert.throws(() => store.release(fileLease.owner), /identity|symlink/);
      assert.throws(() => store.claim("new-owner", [f.external]), /identity|symlink/);
      fs.unlinkSync(file); fs.writeFileSync(file, "restored");
      assert.deepEqual(store.check(fileLease.owner).inFlight, []);
      store.release(fileLease.owner);
      const directoryLease = store.claim("directory-owner", [f.root]);
      fs.symlinkSync(absent, path.join(f.root, "dangling"));
      for (const target of [path.join(f.root, "dangling"), path.join(f.root, "dangling", "nested", "file")]) {
        assert.throws(() => store.reserve(directoryLease.owner, "escape", [target]), /identity|symlink/);
      }
      assert.deepEqual(store.check(directoryLease.owner).inFlight, []);
      store.release(directoryLease.owner);
    }
  });

  test("scope changes need exact genuine authorization, unchanged confirmation is cheap", (t) => {
    const f = fixture(t); const originalInput = f.ledger.input.id;
    f.ledger.receiveInput("extension", "background continuation", null, true);
    assert.equal(f.ledger.input.id, originalInput);
    f.ledger.confirm(1, originalInput); const n = f.branch.length;
    f.ledger.confirm(1, originalInput); assert.equal(f.branch.length, n);
    f.executed(); f.evidence();
    const changed = { ...f.def, requirements: [{ id: "r2", mandatory: true, expected: "Hi" }] };
    assert.throws(() => f.ledger.revise(changed, 1, originalInput), /genuine/);
    assert.throws(() => f.ledger.start(changed, originalInput), /Replacing/);
    const raw = `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition: changed })}`;
    f.ledger.receiveInput("extension", raw, null, true);
    assert.throws(() => f.ledger.revise(changed, 1, originalInput), /genuine/);
    f.ledger.receiveInput("rpc", raw, "leaf", true);
    assert.throws(() => f.ledger.confirm(1, f.ledger.input.id), /Authorized scope changed/);
    f.ledger.revise(changed, 1, f.ledger.input.id);
    assert.equal(f.ledger.contract.revision, 2); assert.deepEqual(f.ledger.contract.evidence, []);
    assert.equal(f.ledger.contract.input.source, "rpc");
    f.ledger.receiveInput("interactive", "delegated task", null, false); assert.equal(f.ledger.input.authority, "delegated-input");
  });
  test("bounded continuations persist no-progress; off/abort/error/pending/child/waiting suppress", (t) => {
    const f = fixture(t);
    const controls = { enabled: true, owner: true, aborted: false, pending: false, failed: false };
    for (const override of [{ enabled: false }, { owner: false }, { aborted: true }, { failed: true }, { pending: true }]) {
      assert.equal(f.ledger.continuation(f.branch, { ...controls, ...override }), undefined);
    }
    f.ledger.disposition("waiting", ["child still running"]);
    assert.equal(f.ledger.continuation(f.branch, controls), undefined);
    f.ledger.disposition("actionable", ["child returned; verify artifacts"]);
    assert.ok(f.ledger.continuation(f.branch, controls));
    const restored = new WorkflowLedger((customType, data) => f.branch.push({ type: "custom", customType, data })); restored.restore(f.branch);
    assert.ok(restored.continuation(f.branch, controls));
    assert.equal(restored.continuation(f.branch, controls), undefined);
    assert.equal(restored.contract.continuations, 2); assert.equal(restored.contract.noProgress, 2);
    assert.equal(restored.contract.disposition, "blocked");
    assert.throws(() => restored.complete(f.branch), /UNACCEPTED/);
  });
  test("three-continuation ceiling survives genuine scope revisions and off/on", (t) => {
    const f = fixture(t), controls = { enabled: true, owner: true, aborted: false, pending: false, failed: false };
    for (let revision = 1; revision <= 4; revision++) {
      const next = { ...f.def, objective: `CLI revision ${revision}` };
      f.ledger.receiveInput("interactive", `workflow-scope ${JSON.stringify({ action: "revise", revision, definition: next })}`, null, true);
      f.ledger.revise(next, revision, f.ledger.input.id);
      const result = f.ledger.continuation(f.branch, controls);
      assert.equal(Boolean(result), revision <= 3);
      assert.equal(f.ledger.continuation(f.branch, { ...controls, enabled: false }), undefined);
    }
    assert.equal(f.ledger.contract.continuations, 3);
    assert.equal(f.ledger.contract.disposition, "blocked");
  });
  test("lease matching token/session/process and in-flight exclusion", (t) => {
    const f = fixture(t); const store = new WriterLeaseStore(path.join(f.temp, "state", "lease.db")); t.after(() => store.close());
    const lease = store.claim("one", [f.root]);
    assert.throws(() => store.claim("two", [f.root]), /conflict/);
    assert.throws(() => store.release({ ...lease.owner, nonce: "wrong" }), /mismatch/);
    assert.throws(() => store.release({ ...lease.owner, session: "wrong" }), /mismatch/);
    store.reserve(lease.owner, "mutate", [path.join(f.root, "new")]);
    assert.throws(() => store.release(lease.owner), /not drained/);
    assert.throws(() => store.reserve(lease.owner, "outside", [f.external]), /outside/);
    store.drain(lease.owner, ["mutate"]); store.release(lease.owner);
    const next = store.claim("two", [f.root]); assert.throws(() => store.release(lease.owner), /mismatch/); store.release(next.owner);
  });
  test("overlapping roots and symlink aliases conflict; independent worktrees proceed", (t) => {
    const f = fixture(t); const store = new WriterLeaseStore(path.join(f.temp, "state", "lease.db")); t.after(() => store.close());
    const nested = path.join(f.root, "nested"); fs.mkdirSync(nested);
    const alias = path.join(f.temp, "alias"); fs.symlinkSync(f.root, alias);
    const held = store.claim("one", [f.root]);
    assert.throws(() => store.claim("two", [nested]), /conflict/); assert.throws(() => store.claim("two", [alias]), /conflict/);
    store.release(held.owner);
    execFileSync("git", ["init", "-q", f.root]);
    const second = path.join(f.temp, "worktree");
    execFileSync("git", ["-C", f.root, "worktree", "add", "--orphan", "-b", "independent", second], { stdio: "ignore" });
    const a = store.claim("a", [nested]);
    assert.throws(() => store.claim("same-tree", [f.root]), /conflict/);
    const b = store.claim("b", [second]); store.release(a.owner); store.release(b.owner);
  });
  test("death/PID reuse only; unknown/EPERM/malformed state never reclaimed by age", (t) => {
    const f = fixture(t); const filename = path.join(f.temp, "state", "lease.db");
    const birth = processProbe(process.pid).birth; assert.ok(birth);
    const store = new WriterLeaseStore(filename); const lease = store.claim("old", [f.root]); store.close();
    assert.equal(demonstratedDead(lease.owner, () => ({ state: "unknown" })), false);
    assert.equal(demonstratedDead(lease.owner, () => ({ state: "alive" })), false);
    assert.equal(demonstratedDead(lease.owner, () => ({ state: "dead" })), true);
    assert.equal(demonstratedDead(lease.owner, () => ({ state: "alive", birth: "reused" })), true);
    const db = new DatabaseSync(filename);
    const dead = { ...lease, owner: { ...lease.owner, pid: 2147483646 } };
    db.prepare("UPDATE leases SET data = ?").run(JSON.stringify(dead));
    const reclaim = new WriterLeaseStore(filename); const next = reclaim.claim("new", [f.root]); reclaim.release(next.owner); reclaim.close();
    db.prepare("INSERT INTO leases VALUES (?, ?)").run("malformed", "{}");
    const bad = new WriterLeaseStore(filename); assert.throws(() => bad.claim("new", [f.root]), /Malformed/); bad.close(); db.close();
  });
  test("SQLite acquisition refuses unknown owners and reclaims demonstrated PID reuse", (t) => {
    const f = fixture(t), filename = path.join(f.temp, "state", "lease.db");
    const store = new WriterLeaseStore(filename); const lease = store.claim("old", [f.root]); store.close();
    const db = new DatabaseSync(filename);
    const old = { ...lease, owner: { ...lease.owner, pid: 424242, birth: "old-process" } };
    db.prepare("UPDATE leases SET data = ?").run(JSON.stringify(old));
    const unknown = new WriterLeaseStore(filename, (pid) => pid === process.pid ? processProbe(pid) : { state: "unknown" });
    assert.throws(() => unknown.claim("new", [f.root]), /conflict/); unknown.close();
    const reused = new WriterLeaseStore(filename, (pid) => pid === process.pid ? processProbe(pid) : { state: "alive", birth: "new-process" });
    const claimed = reused.claim("new", [f.root]); reused.release(claimed.owner); reused.close(); db.close();
    const kill = process.kill;
    try {
      process.kill = () => { throw Object.assign(new Error("permission denied"), { code: "EPERM" }); };
      assert.equal(processProbe(process.pid).state, "unknown");
    } finally { process.kill = kill; }
  });
  test("two real processes compete transactionally: exactly one winner", async (t) => {
    const f = fixture(t); const db = path.join(f.temp, "state", "lease.db");
    const initial = new WriterLeaseStore(db); initial.close();
    const children = [1, 2].map(() => fork(fileURLToPath(import.meta.url), ["contender", db, f.root], { stdio: ["ignore", "ignore", "inherit", "ipc"] }));
    t.after(() => children.forEach((child) => child.kill()));
    const onceMessage = (child) => new Promise((resolve, reject) => { child.once("message", resolve); child.once("error", reject); });
    await Promise.all(children.map(onceMessage));
    const results = children.map(onceMessage); children.forEach((child) => child.send("go"));
    const received = await Promise.all(results); assert.equal(received.filter((r) => r.won).length, 1);
    children.forEach((child) => child.send("quit"));
    await Promise.all(children.map((child) => new Promise((resolve) => child.once("exit", resolve))));
    const after = new WriterLeaseStore(db); const held = after.claim("reclaimed-dead-winner", [f.root]); after.release(held.owner); after.close();
  });
  test("mutation surface matrix: file, Hashline, AST, LSP rename, shell and unknown plugins", () => {
    for (const tool of ["write", "edit", "replace", "insert", "undo_last_change"]) assert.deepEqual(mutationTargets(tool, { path: "new.ts" }, "/tmp"), ["/tmp/new.ts"]);
    for (const tool of ["bash", "powershell", "shell", "unknown"]) assert.equal(mutationTargets(tool, { command: "cat file" }, "/tmp"), "permit");
    assert.equal(mutationTargets("lsp_navigation", { action: "rename", path: "file" }, "/tmp"), "permit");
    assert.equal(mutationTargets("lsp_navigation", { action: "references" }, "/tmp"), undefined);
    assert.deepEqual(mutationTargets("ast_grep_replace", { paths: ["/tmp/file"] }, "/tmp"), ["/tmp/file"]);
    assert.equal(mutationTargets("ast_grep_replace", { paths: ["**/*.ts"] }, "/tmp"), "permit");
    for (const tool of ["read", "grep", "module_report", "lens_diagnostics", "ast_grep_search"]) assert.equal(mutationTargets(tool, {}, "/tmp"), undefined);
  });
}
