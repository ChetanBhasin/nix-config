import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createJiti } from "../../npm/node_modules/jiti/lib/jiti.mjs";
import { SessionManager } from "../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js";
const jiti = createJiti(import.meta.url);
const { registerWorkflow } = await jiti.import("./workflow-controller.ts");

function fixture(t) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-controller-"));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const root = path.join(temp, "source"); fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, "input"), "value");
  const db = path.join(temp, "state", "lease.sqlite");
  return { root, db, temp };
}
async function harness(t, f, controls = { enabled: true, owner: true }, sm = SessionManager.inMemory(f.root)) {
  const tools = new Map(), commands = new Map(), handlers = new Map(), sent = [], notices = [];
  const flags = { pending: false, activeTools: ["read", "bash", "workflow_contract", "writer_lease"] };
  const ctx = { cwd: f.root, sessionManager: sm, hasPendingMessages: () => flags.pending, isIdle: () => true,
    ui: { setStatus() {}, notify: (...args) => notices.push(args) } };
  const pi = { registerTool: (tool) => tools.set(tool.name, tool), registerCommand: (name, command) => commands.set(name, command),
    appendEntry: (name, data) => sm.appendCustomEntry(name, structuredClone(data)),
    on: (name, handler) => handlers.set(name, [...(handlers.get(name) ?? []), handler]),
    getActiveTools: () => flags.activeTools,
    sendMessage: (message, options) => sent.push({ message, options }) };
  registerWorkflow(pi, () => controls, f.db);
  const fire = async (name, data = {}) => {
    let result;
    for (const handler of handlers.get(name) ?? []) { const next = await handler({ type: name, ...data }, ctx); if (next !== undefined) result = next; }
    return result;
  };
  const tool = async (name, args) => {
    const result = await tools.get(name).execute("control", args, undefined, undefined, ctx);
    return JSON.parse(result.content[0].text);
  };
  const status = () => tool("workflow_contract", { action: "status" });
  const start = async (roots = [f.root]) => {
    await fire("input", { source: "interactive", text: "Implement CLI" });
    const { input } = await status();
    return tool("workflow_contract", { action: "start", inputId: input.id, definition: { objective: "CLI", kind: "implementation", roots, externalInputs: [],
      requirements: [{ id: "r", mandatory: true, expected: "worked" }],
      journeys: [{ id: "j", scenario: "User runs CLI", interface: "cli", tool: "bash", input: { command: "cli" }, expected: "worked" }] } });
  };
  await fire("session_start", { reason: "startup" });
  t.after(() => fire("session_shutdown", { reason: "quit" }));
  return { sm, ctx, controls, flags, fire, tool, status, start, sent, notices, commands };
}

test("deleting a file root drains and releases ownership without accepting missing inputs", async (t) => {
  for (const git of [false, true]) {
    const f = fixture(t);
    if (git) execFileSync("git", ["-C", f.root, "init", "-q"]);
    const file = path.join(f.root, "input"), h = await harness(t, f);
    await h.start([file]);
    const { writer } = await h.tool("writer_lease", { action: "claim", roots: [file] });
    const input = { command: `rm -- ${JSON.stringify(file)}` };
    await h.tool("writer_lease", { action: "permit", nonce: writer.nonce, tool: "bash", input, roots: [file] });
    await h.fire("tool_call", { toolName: "bash", toolCallId: "delete-file", input });
    execFileSync("bash", ["-c", input.command]);
    await h.fire("tool_execution_end", { toolName: "bash", toolCallId: "delete-file", result: { content: [{ type: "text", text: "worked" }] }, isError: false });
    await h.fire("turn_end", {});
    assert.deepEqual((await h.status()).writer.inFlight, []);
    await assert.rejects(() => h.tool("workflow_contract", { action: "complete" }), /UNACCEPTED/);
    await h.tool("writer_lease", { action: "release", nonce: writer.nonce });
    assert.equal((await h.status()).writer, undefined);
    const other = await harness(t, f, { enabled: false, owner: false });
    const acquired = await other.tool("writer_lease", { action: "claim", roots: [f.root] });
    await other.tool("writer_lease", { action: "release", nonce: acquired.writer.nonce });
  }
});

test("read-only roles need no contract; child and parent share one writer", async (t) => {
  const f = fixture(t), parent = await harness(t, f), child = await harness(t, f, { enabled: true, owner: false });
  for (const toolName of ["read", "grep", "web_run", "view_image", "module_report", "todo", "ctx_search", "ctx_expand", "ctx_memory", "ctx_note", "ctx_reduce", "subagent_wait", "subagent_supervisor", "agent_browser", "runtime_health"]) {
    await child.fire("tool_call", { toolName, toolCallId: toolName, input: {} });
  }
  await assert.rejects(() => child.fire("tool_call", { toolName: "runtime_health", toolCallId: "repair", input: { action: "repair" } }), /Claim/);
  assert.equal((await child.status()).acceptance, "no active contract");
  await assert.rejects(() => child.fire("tool_call", { toolName: "replace", toolCallId: "no-claim", input: { path: path.join(f.root, "input") } }), /Claim/);
  const p = await parent.tool("writer_lease", { action: "claim", roots: [f.root] });
  await assert.rejects(() => child.tool("writer_lease", { action: "claim", roots: [f.root] }), /conflict/);
  await parent.tool("writer_lease", { action: "release", nonce: p.writer.nonce });
  const c = await child.tool("writer_lease", { action: "claim", roots: [f.root] });
  await assert.rejects(() => parent.tool("writer_lease", { action: "release", nonce: c.writer.nonce }), /Claim/);
  await child.tool("writer_lease", { action: "release", nonce: c.writer.nonce });
});

test("Hashline/AST reservations exclude release for the whole batch; aliases outside scope block", async (t) => {
  const f = fixture(t), h = await harness(t, f);
  const { writer } = await h.tool("writer_lease", { action: "claim", roots: [f.root] });
  for (const [i, toolName] of ["write", "edit", "replace", "insert", "undo_last_change", "ast_grep_replace"].entries()) {
    await h.fire("tool_call", { toolName, toolCallId: `m${i}`, input: toolName === "ast_grep_replace" ? { paths: [f.root] } : { path: path.join(f.root, "input") } });
    await h.fire("tool_execution_end", { toolName, toolCallId: `m${i}`, result: { content: [] }, isError: false });
  }
  await assert.rejects(() => h.tool("writer_lease", { action: "release", nonce: writer.nonce }), /not drained/);
  assert.deepEqual(await h.fire("session_before_fork"), { cancel: true });
  assert.deepEqual(await h.fire("session_before_switch"), { cancel: true });
  fs.symlinkSync(f.temp, path.join(f.root, "outside"));
  await assert.rejects(() => h.fire("tool_call", { toolName: "write", toolCallId: "escape", input: { path: path.join(f.root, "outside", "new") } }), /outside/);
  await h.fire("turn_end");
  await assert.rejects(() => h.tool("writer_lease", { action: "release", nonce: "wrong" }), /nonce/);
  await h.tool("writer_lease", { action: "release", nonce: writer.nonce });
});

test("a broader lease cannot widen a contract; explicit multi-root revision permits live config outside cwd", async (t) => {
  const f = fixture(t), h = await harness(t, f); const initial = await h.start();
  const externalRoot = path.join(f.temp, "live-config"); fs.mkdirSync(externalRoot);
  const { writer } = await h.tool("writer_lease", { action: "claim", roots: [f.root, externalRoot] });
  const input = { path: path.join(externalRoot, "config.ts") };
  await assert.rejects(() => h.fire("tool_call", { toolName: "write", toolCallId: "outside-contract", input }), /exceeds/);
  const { id, revision, evidence, disposition, blockers, continuations, noProgress, ...definition } = initial.objective;
  definition.roots.push(externalRoot);
  await h.fire("input", { source: "interactive", text: `workflow-scope ${JSON.stringify({ action: "revise", revision: 1, definition })}` });
  await h.tool("workflow_contract", { action: "revise", revision: 1, inputId: (await h.status()).input.id, definition });
  await h.fire("tool_call", { toolName: "write", toolCallId: "inside-revised", input });
  await h.fire("tool_execution_end", { toolName: "write", toolCallId: "inside-revised", result: { content: [] }, isError: false });
  await h.fire("turn_end"); await h.tool("writer_lease", { action: "release", nonce: writer.nonce });
});

test("shell/LSP rename/unknown plugins require exact one-use scope permits, ! shell stays blocked", async (t) => {
  const f = fixture(t), h = await harness(t, f);
  const { writer } = await h.tool("writer_lease", { action: "claim", roots: [f.root] });
  for (const name of ["bash", "lsp_navigation", "unknown_mutator"]) {
    const input = name === "lsp_navigation" ? { action: "rename", path: path.join(f.root, "input"), newName: "next" } : { command: "cat input" };
    await assert.rejects(() => h.fire("tool_call", { toolName: name, toolCallId: "unpermitted", input }), /exact/);
    await h.tool("writer_lease", { action: "permit", nonce: writer.nonce, roots: [f.root], tool: name, input });
    await assert.rejects(() => h.fire("tool_call", { toolName: name, toolCallId: "changed", input: { ...input, extra: true } }), /exact/);
    await h.fire("tool_call", { toolName: name, toolCallId: name, input });
    await assert.rejects(() => h.fire("tool_call", { toolName: name, toolCallId: "replay", input }), /exact/);
    await h.fire("tool_execution_end", { toolName: name, toolCallId: name, result: { content: [] }, isError: false });
  }
  assert.equal((await h.fire("user_bash", { command: "cat input" })).result.exitCode, 1);
  await h.fire("turn_end"); await h.tool("writer_lease", { action: "release", nonce: writer.nonce });
});

test("active SessionManager branch only; reload/compaction/new/fork never imports another lease", async (t) => {
  const f = fixture(t), h = await harness(t, f);
  const original = await h.start(); const leaf = h.sm.getLeafId();
  h.sm.appendCompaction("Everything is complete (not authoritative)", leaf, 100, { status: "complete" });
  await h.fire("session_tree"); assert.equal((await h.status()).acceptance, "open");
  const { writer } = await h.tool("writer_lease", { action: "claim", roots: [f.root] });
  await h.fire("session_shutdown", { reason: "reload" });
  const reload = await harness(t, f, h.controls, h.sm);
  assert.equal((await reload.status()).objective.id, original.objective.id);
  assert.equal((await reload.status()).writer, undefined);
  const reclaimed = await reload.tool("writer_lease", { action: "claim", roots: [f.root] });
  assert.notEqual(reclaimed.writer.nonce, writer.nonce);
  await h.fire("session_shutdown", { reason: "reload" }); // obsolete instance cannot release reloader's nonce
  const fresh = await harness(t, f);
  await assert.rejects(() => fresh.tool("writer_lease", { action: "claim", roots: [f.root] }), /conflict/);
  await reload.tool("writer_lease", { action: "release", nonce: reclaimed.writer.nonce });
  const fork = SessionManager.inMemory(f.root);
  for (const entry of h.sm.getBranch()) if (entry.type === "custom") fork.appendCustomEntry(entry.customType, entry.data);
  const forked = await harness(t, f, { enabled: true, owner: false }, fork);
  assert.equal((await forked.status()).objective.id, original.objective.id);
  assert.equal((await forked.status()).writer, undefined);
  h.sm.resetLeaf(); await h.fire("session_tree"); assert.equal((await h.status()).acceptance, "no active contract");
  h.sm.newSession(); await h.fire("session_start", { reason: "new" }); assert.equal((await h.status()).objective, undefined);
});

test("shutdown releases captured ownership after Pi replaces the in-memory session ID", async (t) => {
  const f = fixture(t), h = await harness(t, f);
  const { writer } = await h.tool("writer_lease", { action: "claim", roots: [f.root] });
  const oldId = h.sm.getSessionId();
  h.sm.newSession(); assert.notEqual(h.sm.getSessionId(), oldId);
  await assert.rejects(() => h.tool("writer_lease", { action: "release", nonce: writer.nonce }), /Claim/);
  await h.fire("session_shutdown", { reason: "fork" });
  const next = await harness(t, f, h.controls, h.sm);
  const claimed = await next.tool("writer_lease", { action: "claim", roots: [f.root] });
  assert.notEqual(claimed.writer.nonce, writer.nonce);
  assert.deepEqual(h.notices, []);
});

for (const missing of ["workflow_contract", "writer_lease", "bash"]) test(`unavailable ${missing} blocks remediation without spending budget`, async (t) => {
  const f = fixture(t), h = await harness(t, f); await h.start();
  h.flags.activeTools = h.flags.activeTools.filter((tool) => tool !== missing);
  const end = () => h.fire("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
  await end(); await end(); await end();
  const before = await h.status();
  assert.equal(before.objective.continuations, 0); assert.equal(before.objective.noProgress, 0);
  assert.equal(h.sent.filter((entry) => entry.options.triggerTurn).length, 0);
  assert.ok(before.issues.includes(`Required tool unavailable: ${missing}`));
  assert.ok(h.sent.some((entry) => entry.message.content.includes("Capability blocker")));
  assert.ok(!h.flags.activeTools.includes(missing), "the controller must never widen an allowlist");
  h.flags.activeTools.push(missing); await end();
  assert.equal((await h.status()).objective.continuations, 1);
  assert.equal(h.sent.filter((entry) => entry.options.triggerTurn).length, 1);
});

test("pending input, Auto off, abort, error, UI and waiting suppress remediation without accepting", async (t) => {
  const f = fixture(t), h = await harness(t, f); await h.start();
  const end = (stopReason = "stop") => h.fire("agent_end", { messages: [{ role: "assistant", stopReason }] });
  h.flags.pending = true; await end(); h.flags.pending = false;
  h.controls.enabled = false; await end(); h.controls.enabled = true;
  await end("aborted"); await end("error");
  await h.fire("ui_prompt_start"); await end(); await h.fire("ui_prompt_end");
  await h.fire("tool_call", { toolName: "subagent", toolCallId: "child", input: { agent: "worker", async: true } });
  await end();
  assert.equal((await h.status()).objective.disposition, "waiting");
  assert.equal(h.sent.filter((entry) => entry.options.triggerTurn).length, 0);
  assert.ok(h.sent.some((entry) => entry.message.content.includes("UNACCEPTED")));
  await h.tool("workflow_contract", { action: "disposition", disposition: "actionable", reasons: ["child returned; verify it"] });
  await end(); assert.equal(h.sent.filter((entry) => entry.options.triggerTurn).length, 1);
  await h.fire("input", { source: "extension", text: "background continuation" });
  await end(); await end();
  assert.equal((await h.status()).objective.disposition, "blocked");
  await assert.rejects(() => h.tool("workflow_contract", { action: "complete" }), /UNACCEPTED/);
});
