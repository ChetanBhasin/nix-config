import assert from "node:assert/strict";
import { test } from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createJiti } from "../../npm/node_modules/jiti/lib/jiti.mjs";
import { AgentSessionRuntime, createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } from "../../npm/node_modules/@earendil-works/pi-coding-agent/dist/index.js";
import { AssistantMessageEventStream, InMemoryCredentialStore } from "../../npm/node_modules/@earendil-works/pi-ai/dist/index.js";
const jiti = createJiti(import.meta.url);
const { registerWorkflow } = await jiti.import("./workflow-controller.ts");
const { LEDGER_ENTRY, INPUT_ENTRY } = await jiti.import("./workflow-ledger.ts");

function response(content, stopReason = "toolUse") {
  const stream = new AssistantMessageEventStream();
  const message = { role: "assistant", content, api: "openai-completions", provider: "workflow-offline", model: "deterministic",
    usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    stopReason, timestamp: Date.now() };
  stream.push({ type: "start", partial: message });
  if (content[0]?.type === "text") stream.push({ type: "text_delta", contentIndex: 0, delta: content[0].text, partial: message });
  stream.push({ type: "done", reason: stopReason, message }); stream.end(message);
  return stream;
}
const call = (id, name, args) => ({ type: "toolCall", id, name, arguments: args });

for (const mode of ["remediate", "off", "aborted", "runtime-error", "waiting"]) test(`Pi 0.84.4 AgentSession: ${mode} gates and settlement`, async (t) => {
  process.env.PI_OFFLINE = "1";
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-session-"));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const root = path.join(temp, "source"); fs.mkdirSync(root);
  const external = path.join(temp, "external.txt"); fs.writeFileSync(external, "Hello");
  const cli = path.join(root, "greet.mjs");
  fs.writeFileSync(cli, 'import fs from "node:fs"; console.log(`${fs.readFileSync(process.argv[3], "utf8")}, ${process.argv[2]}!`);\n');
  const command = `${JSON.stringify(process.execPath)} ${JSON.stringify(cli)} Ada ${JSON.stringify(external)}`;
  const definition = { objective: "A real greeting CLI journey", kind: "implementation", roots: [root], externalInputs: [external],
    requirements: [{ id: "r1", mandatory: true, expected: "Hello, Ada!" }],
    journeys: [{ id: "j1", scenario: "A user runs greet with their name and sees the greeting", interface: cli, tool: "bash", input: { command }, expected: "Hello, Ada!" }] };
  const sm = SessionManager.create(root, path.join(temp, "sessions"));
  const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
  let enabled = true;
  let phase = 0;
  let nonce;
  const events = [];
  const errors = [];
  const modelRuntime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null,
    modelsStorePath: path.join(temp, "models-store.json"), refreshOnCreate: false, allowModelNetwork: false });
  const latestInput = () => sm.getBranch().findLast((e) => e.customType === INPUT_ENTRY).data.id;
  const step = (_model, context) => {
    events.push(`provider:${phase}`);
    const result = (id) => context.messages.findLast((m) => m.role === "toolResult" && m.toolCallId === id);
    switch (phase++) {
      case 0: return response([call("unclaimed", "write", { path: path.join(root, "forbidden"), content: "must not write" })]);
      case 1:
        assert.equal(result("unclaimed").isError, true);
        return response([call("start", "workflow_contract", { action: "start", inputId: latestInput(), definition })]);
      case 2:
        assert.equal(result("start").isError, false, JSON.stringify(result("start")));
        return response([call("premature", "workflow_contract", { action: "complete" })]);
      case 3:
        assert.equal(result("premature").isError, true, "throw marks real Pi tool errors");
        if (mode === "waiting") return response([call("wait", "workflow_contract", { action: "disposition", disposition: "waiting", reasons: ["delegated work pending"] })]);
        if (mode === "off") enabled = false;
        return response([{ type: "text", text: "Original answer: done." }], mode === "aborted" ? "aborted" : mode === "runtime-error" ? "error" : "stop");
      case 4:
        if (mode === "waiting") return response([{ type: "text", text: "Waiting on delegated work." }], "stop");
        assert.equal(mode, "remediate");
        assert.equal(events.includes("settled"), false, "agent_end followUp runs before settlement");
        assert.ok(context.messages.some((m) => JSON.stringify(m.content).includes("[workflow-remediation")));
        return response([call("claim", "writer_lease", { action: "claim", roots: [root] })]);
      case 5:
        nonce = JSON.parse(result("claim").content[0].text).writer.nonce;
        return response([call("permit", "writer_lease", { action: "permit", roots: [root], nonce, tool: "bash", input: { command } })]);
      case 6: return response([call("early-release", "writer_lease", { action: "release", nonce }), call("journey", "bash", { command })]);
      case 7:
        assert.equal(result("early-release").isError, true, "release must fail while a sibling mutation batch is reserved");
        assert.equal(result("journey").isError, false);
        assert.match(result("journey").content[0].text, /Hello, Ada!/);
        return response([call("evidence-r", "workflow_contract", { action: "evidence", evidence: { target: "r1", kind: "requirement", toolCallId: "journey", expected: "Hello, Ada!", observed: "Hello, Ada!" } }),
          call("evidence-j", "workflow_contract", { action: "evidence", evidence: { target: "j1", kind: "journey", toolCallId: "journey", expected: "Hello, Ada!", observed: "Hello, Ada!" } })]);
      case 8:
        assert.equal(result("evidence-r").isError, false, JSON.stringify(result("evidence-r")));
        assert.equal(result("evidence-j").isError, false, JSON.stringify(result("evidence-j")));
        return response([call("complete", "workflow_contract", { action: "complete" }), call("release", "writer_lease", { action: "release", nonce })]);
      case 9:
        assert.equal(result("complete").isError, false);
        assert.equal(result("release").isError, false);
        return response([{ type: "text", text: "Checked final answer." }], "stop");
      default: throw new Error("Unexpected unbounded continuation");
    }
  };
  modelRuntime.registerProvider("workflow-offline", { api: "openai-completions", baseUrl: "http://offline.invalid", apiKey: "offline-test",
    models: [{ id: "deterministic", name: "Deterministic (no network)", reasoning: false, input: ["text"], contextWindow: 200000, maxTokens: 1000,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }], streamSimple: step });
  const resourceLoader = new DefaultResourceLoader({ cwd: root, agentDir: path.join(temp, "agent"), settingsManager,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    extensionFactories: [(pi) => {
      registerWorkflow(pi, () => ({ enabled, owner: true }), path.join(temp, "state", "lease.sqlite"));
      pi.on("agent_end", () => { events.push("end"); });
      pi.on("agent_settled", () => { events.push("settled"); });
    }], systemPromptOverride: () => "Offline deterministic acceptance fixture." });
  await resourceLoader.reload();
  const { session, extensionsResult } = await createAgentSession({ cwd: root, agentDir: path.join(temp, "agent"), resourceLoader, settingsManager,
    modelRuntime, model: modelRuntime.getModel("workflow-offline", "deterministic"), sessionManager: sm, tools: ["write", "bash", "workflow_contract", "writer_lease"] });
  assert.deepEqual(extensionsResult.errors, []);
  t.after(() => session.dispose());
  await session.bindExtensions({ mode: "print", onError: (error) => errors.push(error) });
  session.subscribe((event) => { if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") events.push(`stream:${event.assistantMessageEvent.delta}`); });
  await session.prompt("Implement and verify the greeting CLI", { source: "interactive" });
  const contract = sm.getBranch().findLast((e) => e.customType === LEDGER_ENTRY)?.data;
  assert.ok(contract, JSON.stringify({ errors, events, phase }));
  assert.equal(fs.existsSync(path.join(root, "forbidden")), false);
  assert.equal(contract.status, mode === "remediate" ? "complete" : "open", JSON.stringify({ events, errors, messages: session.messages.slice(-3) }));
  assert.equal(contract.continuations, mode === "remediate" ? 1 : 0);
  assert.equal(events.filter((e) => e === "settled").length, 1);
  assert.equal(events.at(-1), "settled");
  if (mode === "remediate") {
    assert.equal(events.filter((e) => e === "end").length, 2);
    assert.ok(events.indexOf("stream:Original answer: done.") < events.indexOf("end"));
    assert.ok(sm.getBranch().some((e) => e.message?.role === "assistant" && e.message.content.some((c) => c.text === "Original answer: done.")));
    assert.equal(SessionManager.open(sm.getSessionFile()).getBranch().findLast((e) => e.customType === LEDGER_ENTRY).data.status, "complete");
  }
  assert.deepEqual(errors, []);
  console.log(`Pi ${mode}: ${events.join(" -> ")}; acceptance=${contract.status}; followUps=${contract.continuations}`);
});

test("Pi AgentSessionRuntime in-memory fork releases the outgoing owner before creating the next session", async (t) => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "workflow-real-fork-"));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const root = path.join(temp, "source"); fs.mkdirSync(root);
  const agentDir = path.join(temp, "agent"), db = path.join(temp, "leases.sqlite");
  const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
  const modelRuntime = await ModelRuntime.create({ credentials: new InMemoryCredentialStore(), modelsPath: null,
    modelsStorePath: path.join(temp, "models-store.json"), refreshOnCreate: false, allowModelNetwork: false });
  let phase = 0;
  modelRuntime.registerProvider("workflow-fork", { api: "openai-completions", baseUrl: "http://offline.invalid", apiKey: "offline-test",
    models: [{ id: "deterministic", name: "Deterministic", reasoning: false, input: ["text"], contextWindow: 200000, maxTokens: 1000,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
    streamSimple: () => {
      const step = phase++;
      return step % 2 === 0
        ? response([call(`claim-${step}`, "writer_lease", { action: "claim", roots: [root] })])
        : response([{ type: "text", text: "Ownership checked." }], "stop");
    } });
  const create = async (options) => {
    const resourceLoader = new DefaultResourceLoader({ cwd: root, agentDir, settingsManager,
      noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
      extensionFactories: [(pi) => registerWorkflow(pi, () => ({ enabled: false, owner: true }), db)],
      systemPromptOverride: () => "Deterministic fork acceptance fixture." });
    await resourceLoader.reload();
    const result = await createAgentSession({ ...options, resourceLoader, settingsManager, modelRuntime,
      model: modelRuntime.getModel("workflow-fork", "deterministic"), tools: ["writer_lease", "workflow_contract"] });
    assert.deepEqual(result.extensionsResult.errors, []);
    return { ...result, services: { cwd: root, agentDir, resourceLoader, settingsManager, modelRuntime } };
  };
  const sm = SessionManager.inMemory(root);
  const initial = await create({ cwd: root, agentDir, sessionManager: sm });
  const runtime = new AgentSessionRuntime(initial.session, initial.services, create);
  t.after(() => runtime.dispose());
  const errors = [];
  const bind = (session) => session.bindExtensions({ mode: "print", onError: (error) => errors.push(error) });
  runtime.setRebindSession(bind); await bind(runtime.session);
  await runtime.session.prompt("Claim the source root");
  const first = sm.getBranch().findLast((entry) => entry.message?.toolCallId === "claim-0").message;
  assert.equal(first.isError, false, JSON.stringify(first));
  const before = JSON.parse(first.content[0].text).writer;
  const oldId = sm.getSessionId();
  const user = sm.getBranch().find((entry) => entry.message?.role === "user");
  assert.equal((await runtime.fork(user.id)).cancelled, false);
  assert.notEqual(sm.getSessionId(), oldId);
  await runtime.session.prompt("Claim the root in the forked session");
  const second = sm.getBranch().findLast((entry) => entry.message?.toolCallId === "claim-2").message;
  assert.equal(second.isError, false, JSON.stringify(second));
  const after = JSON.parse(second.content[0].text).writer;
  assert.equal(after.session, sm.getSessionId()); assert.notEqual(after.nonce, before.nonce);
  assert.deepEqual(errors, []);
});
