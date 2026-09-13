import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Test-only runtime stores and source fixtures; never loads ambient extensions or real credentials.
const require = createRequire(join(homedir(), '.pi/agent/npm/package.json'));
function packageRoot(resolver, name) {
  const file = resolver.resolve.paths(name).map(base => join(base, name, 'package.json')).find(existsSync);
  assert.ok(file, `Install ${name} or set PI_SDK_ROOT`); return dirname(file);
}
const sdkRoot = process.env.PI_SDK_ROOT ?? packageRoot(require, '@earendil-works/pi-coding-agent');
mkdirSync('/tmp/execution-strategy-tests', { recursive: true });
const dir = mkdtempSync('/tmp/execution-strategy-tests/sdk-');
const agentDir = join(dir, 'agent'); mkdirSync(agentDir, { recursive: true });
for (const key of Object.keys(process.env)) if (key.startsWith('PI_SUBAGENT') || key.startsWith('PI_AGENT_')) delete process.env[key];
Object.assign(process.env, { PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1', JITI_FS_CACHE: 'false', XDG_CACHE_HOME: join(dir, 'cache') });
const sdk = await import(pathToFileURL(join(sdkRoot, 'dist/index.js')).href);
const sdkRequire = createRequire(join(sdkRoot, 'package.json'));
const ai = await import(pathToFileURL(join(packageRoot(sdkRequire, '@earendil-works/pi-ai'), 'dist/index.js')).href);
const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } = sdk;
const source = join(dir, 'source.txt'); writeFileSync(source, 'deterministic source');
const profileDir = join(agentDir, 'profiles/pi-subagents'); mkdirSync(profileDir, { recursive: true });
writeFileSync(join(profileDir, 'complex.json'), JSON.stringify({ subagents: { agentOverrides: {}, executionStrategy: { version: 1, delegation: 'proactive', reviewers: ['reviewer'] } } }));
writeFileSync(join(profileDir, 'simple.json'), JSON.stringify({ subagents: { agentOverrides: {} } }));
const plan = { workflow: 'sdk', goal: 'Exercise real strategy tool dispatch', inputs: [{ id: 'binding', kind: 'contract', paths: [], value: 'v1' }], obligations: [{ id: 'requirement', kind: 'requirement', description: 'Review source', scopes: [source], inputs: ['binding'], dependsOn: [] }], lanes: [
  { id: 'writer', role: 'writer', owner: 'child', agent: 'worker', access: 'write', goal: 'Implement', scopes: [source], constraints: ['No scope expansion'], dependsOn: [], obligations: ['requirement'], inputs: [] },
  { id: 'review', role: 'reviewer', owner: 'child', agent: 'reviewer', access: 'read', goal: 'Independently review', scopes: [source], constraints: ['No edits'], dependsOn: ['writer'], obligations: ['requirement'], inputs: ['binding'] },
] };
const requests = [
  { action: 'status' }, { action: 'plan', plan }, { action: 'prepare', lane: 'review' }, { action: 'prepare', lane: 'writer', foregroundOnly: true },
  { action: 'consume', attempt: 'forged-parent-packet-path' }, { action: 'gate' },
];
let turn = 0;
const contexts = [];
const provider = pi => pi.registerProvider('strategy-deterministic', {
  api: 'strategy-deterministic', baseUrl: 'http://unused.invalid', apiKey: 'not-a-real-key',
  models: [{ id: 'parent-fixed', name: 'Deterministic parent', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 4096 }],
  streamSimple(model, context) {
    contexts.push(context);
    const stream = ai.createAssistantMessageEventStream();
    const request = requests[turn++];
    const call = request ? { type: 'toolCall', id: `strategy-call-${turn}`, name: 'execution_strategy', arguments: request } : null;
    const message = { role: 'assistant', api: model.api, provider: model.provider, model: model.id, content: call ? [call] : [{ type: 'text', text: 'Done deterministic strategy interface journey.' }], stopReason: call ? 'toolUse' : 'stop', usage: { input: 7, output: 3, cacheRead: 0, cacheWrite: 0, totalTokens: 10, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } }, timestamp: Date.now() };
    queueMicrotask(() => { stream.push({ type: 'start', partial: message }); if (call) stream.push({ type: 'toolcall_end', contentIndex: 0, toolCall: call, partial: message }); stream.push({ type: 'done', reason: message.stopReason, message }); stream.end(); });
    return stream;
  },
});
const settingsManager = SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } });
const modelRuntime = await ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: join(dir, 'models.json'), modelsStorePath: join(dir, 'models-store.json'), allowModelNetwork: false });
const loader = new DefaultResourceLoader({ cwd: dir, agentDir, settingsManager, noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true,
  additionalExtensionPaths: [resolve(dirname(fileURLToPath(import.meta.url)), '../index.ts')], extensionFactories: [provider],
  agentsFilesOverride: () => ({ agentsFiles: [] }), systemPromptOverride: () => 'Execute deterministic test requests.' });
await loader.reload();
assert.deepEqual(loader.getExtensions().errors, []);
let sm = SessionManager.create(dir, join(dir, 'sessions'));
sm.appendCustomEntry('pi-subagents-profile', { version: 1, name: 'complex' });
const model = { id: 'parent-fixed', name: 'Deterministic parent', provider: 'strategy-deterministic', api: 'strategy-deterministic', baseUrl: 'http://unused.invalid', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 4096 };
let { session } = await createAgentSession({ cwd: dir, agentDir, modelRuntime, model, thinkingLevel: 'off', resourceLoader: loader, sessionManager: sm, settingsManager, tools: ['execution_strategy'] });
const events = []; session.subscribe(event => { if (['tool_execution_start', 'tool_execution_end', 'message_end'].includes(event.type)) events.push(event); });
async function dispatch(batch, prompt) {
  turn = requests.length; requests.push(...batch);
  await session.prompt(prompt);
  return session.messages.filter(m => m.role === 'toolResult').slice(-batch.length);
}
async function restoreFromDisk() {
  const file = sm.getSessionFile(); assert.ok(file && existsSync(file));
  session.dispose(); sm = SessionManager.open(file, join(dir, 'sessions'));
  await loader.reload(); assert.deepEqual(loader.getExtensions().errors, []);
  ({ session } = await createAgentSession({ cwd: dir, agentDir, modelRuntime, model, thinkingLevel: 'off', resourceLoader: loader, sessionManager: sm, settingsManager, tools: ['execution_strategy'] }));
  await session.bindExtensions({});
}
try {
  await session.bindExtensions({});
  await session.prompt('Exercise execution_strategy through real native tool dispatch.');
  const results = session.messages.filter(m => m.role === 'toolResult');
  assert.equal(results.length, 6, JSON.stringify(session.messages));
  assert.equal(results[0].isError, false); assert.equal(results[0].details.policy.effective, true);
  assert.equal(results[1].isError, false); assert.equal(results[2].isError, true); assert.match(JSON.stringify(results[2].content), /unmet dependency/);
  assert.equal(results[3].isError, false); assert.equal(results[3].details.input.async, false); assert.equal(results[3].details.input.foregroundOnly, true);
  assert.equal(results[4].isError, true); assert.match(JSON.stringify(results[4].content), /authentic/);
  assert.equal(results[5].details.pass, false); assert.equal(results[5].details.workflowAcceptance, false);
  assert.equal(session.model.id, 'parent-fixed'); assert.equal(session.model.provider, 'strategy-deterministic'); assert.equal(session.thinkingLevel, 'off');
  assert.ok(contexts.some(c => JSON.stringify(c).includes('Execution strategy (complex)')));
  const branch = sm.getBranch(); assert.ok(branch.some(e => e.customType === 'execution-strategy:v1'));
  assert.ok(branch.some(e => e.customType === 'execution-strategy:telemetry:v1' && e.data.kind === 'parent-usage'));
  // Selected-profile refresh is observed on the very next tool/context turn without a model setter.
  sm.appendCustomEntry('pi-subagents-profile', { version: 1, name: 'simple' });
  requests.push({ action: 'status' }); turn = 6;
  await session.prompt('Observe malformed selected metadata.');
  const last = session.messages.filter(m => m.role === 'toolResult').at(-1);
  assert.equal(last.details.policy.effective, false); assert.match(last.details.policy.reason, /ineffective/);
  assert.equal(session.model.id, 'parent-fixed');
  // Real SDK appends persist before subscribers run. Neither state nor telemetry failures may leave a passing live gate.
  sm.appendCustomEntry('pi-subagents-profile', { version: 1, name: 'complex' });
  for (const [kind, value] of [['state', 'v2'], ['telemetry', 'v3']]) {
    let armed = true, persisted = false;
    session.subscribe(event => {
      const entry = event.type === 'entry_appended' ? event.entry : undefined;
      const target = kind === 'state' ? entry?.customType === 'execution-strategy:v1' : entry?.customType === 'execution-strategy:telemetry:v1' && entry.data.kind === 'tool';
      if (armed && target) { armed = false; persisted = true; throw new Error(`injected ${kind} subscriber failure after append`); }
    });
    const failed = await dispatch([{ action: 'input', input: 'binding', value }, { action: 'gate' }, { action: 'prepare', lane: 'writer' }], `Exercise ${kind} persistence uncertainty.`);
    assert.equal(persisted, true);
    for (const result of failed) { assert.equal(result.isError, true); assert.match(JSON.stringify(result.content), /persistence uncertain/); }
    await restoreFromDisk();
    const [restored] = await dispatch([{ action: 'status' }], 'Restore authoritative persisted state without granting acceptance.');
    assert.equal(restored.isError, false); assert.equal(restored.details.plan.inputs[0].value, value);
    assert.equal(restored.details.review.pass, false); assert.equal(restored.details.restoreError, null);
  }
  const artifact = join(dir, 'sdk-evidence.json');
  writeFileSync(artifact, JSON.stringify({ acceptance: 'isolated actual Pi SDK execution_strategy interface ONLY; no native delegation acceptance', sdkRoot, model: session.model, results: session.messages.filter(m => m.role === 'toolResult'), events, branch: sm.getBranch() }, null, 2));
  console.log(`SDK execution_strategy success/failure journey passed; artifact path in /tmp: ${artifact}`);
} finally { session.dispose(); }
