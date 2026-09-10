// Explicit, billable qualification: node native-live-check.mjs --live
// Synthetic history and all test state stay in a private temporary directory.
// Normal SDK auth may refresh existing credentials; no credentials are logged.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { agentDirectory } from './patcher.mjs';

if (!process.argv.includes('--live') || !process.env.PI_TEST_PACKAGE_DIR) {
  console.error('Set PI_TEST_PACKAGE_DIR to the Pi SDK package root and pass --live. This makes real provider requests.');
  process.exit(2);
}
const live = agentDirectory();
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-native-live-'));
const agentDir = path.join(scratch, 'agent');
const provider = 'openai-codex';
const modelId = 'gpt-6-astra';
const sentinel = 'LIVE_NATIVE_RECOVERY_7D3C91';
const legacy = 'Magic Context compacted 2 segments: titles only';
const load = file => import(pathToFileURL(file).href);
const requests = [];
const errors = [];
let stage = 'setup';
let session;
let deadline;
let report;
Object.assign(process.env, {
  PI_SKIP_VERSION_CHECK: '1', PI_TELEMETRY: '0',
  XDG_DATA_HOME: path.join(scratch, 'data'),
  XDG_CACHE_HOME: path.join(scratch, 'cache'),
  XDG_CONFIG_HOME: path.join(scratch, 'config'),
});

try {
  const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } =
    await load(path.join(process.env.PI_TEST_PACKAGE_DIR, 'dist/index.js'));
  const { registerContextBridge } = await import('./context-bridge.mjs');
  const { cbConvertLegacyMessages: convertMessages } =
    await load(path.join(live, 'npm/node_modules/@cortexkit/pi-magic-context/dist/index-kamc8t8p.js'));
  assert.equal(typeof convertMessages, 'function');
  const modelsStorePath = path.join(scratch, 'models-store.json');
  const storedModels = path.join(live, 'models-store.json');
  if (fs.existsSync(storedModels)) fs.copyFileSync(storedModels, modelsStorePath);
  const runtime = await ModelRuntime.create({
    authPath: path.join(live, 'auth.json'), modelsPath: path.join(live, 'models.json'),
    modelsStorePath, allowModelNetwork: false, signal: AbortSignal.timeout(15000),
  });
  stage = 'exact-model';
  const model = runtime.getModel(provider, modelId);
  assert.ok(model, 'Exact Astra metadata is required; no synthesized model or fallback');
  const getAuth = runtime.getAuth.bind(runtime);
  runtime.getAuth = async (...args) => {
    try { return await getAuth(...args); } catch (error) {
      errors.push({ stage: 'auth-setup', type: error?.name,
        sites: error?.stack?.split('\n').filter(line => line.includes('/pi-monorepo/')) });
      throw error;
    }
  };
  // Observe the real transport without replacing it or fabricating any response.
  for (const method of ['streamSimple', 'complete']) {
    const original = runtime[method].bind(runtime);
    runtime[method] = (selected, context, options) => {
      requests.push({ method, provider: selected.provider, model: selected.id, reasoning: options?.reasoning, signalAborted: options?.signal?.aborted === true });
      return original(selected, context, options);
    };
  }
  const sm = SessionManager.create(scratch, path.join(scratch, 'sessions'));
  const user = content => ({ role: 'user', content, timestamp: Date.now() });
  const assistant = value => ({
    role: 'assistant', content: [{ type: 'text', text: value }],
    api: model.api, provider, model: modelId, stopReason: 'stop', timestamp: Date.now(),
    usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
  });
  sm.appendMessage(user(`The recovery sentinel is ${sentinel}. Preserve it exactly.`));
  sm.appendMessage(assistant('Historical answer'));
  const boundary = sm.appendMessage(user('First retained turn'));
  sm.appendMessage(assistant('First retained answer'));
  sm.appendMessage(user('Retained turn payload ' + 'k'.repeat(8000)));
  sm.appendMessage(assistant('Retained work'));
  const legacyId = sm.appendCompaction(legacy, boundary, 12345);
  sm.appendMessage(assistant('Continued retained work'));
  const settings = SettingsManager.inMemory({
    packages: [], extensions: [],
    compaction: { enabled: false, reserveTokens: 16384, keepRecentTokens: 1100 },
    retry: { enabled: false, provider: { maxRetries: 0, timeoutMs: 60000 } },
    enableInstallTelemetry: false, enableAnalytics: false,
  });
  let recoveredPreparation = false;
  let nativeCommit = false;
  const loader = new DefaultResourceLoader({
    cwd: scratch, agentDir, settingsManager: settings,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    systemPrompt: 'Answer briefly using the conversation history.', appendSystemPrompt: [],
    extensionFactories: [pi => {
      registerContextBridge(pi, { agentDir, database: path.join(scratch, 'missing.db'), convertMessages });
      pi.on('session_before_compact', event => {
        recoveredPreparation = event.preparation.previousSummary?.includes(sentinel) === true;
        if (!recoveredPreparation) return { cancel: true };
      });
      pi.on('session_compact', event => { nativeCommit = event.reason === 'manual' && !event.fromExtension; });
    }],
  });
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  const options = {
    cwd: scratch, agentDir, modelRuntime: runtime, model, thinkingLevel: 'max',
    settingsManager: settings, resourceLoader: loader, noTools: 'all',
  };
  ({ session } = await createAgentSession({ ...options, sessionManager: sm }));
  await session.bindExtensions({ onError: () => errors.push('extension-error') });
  assert.equal(session.model.provider, provider);
  assert.equal(session.model.id, modelId);
  assert.equal(session.thinkingLevel, 'max', 'Thinking must not be clamped');
  stage = 'auth';
  assert.ok(await runtime.getAuth(session.model, { signal: AbortSignal.timeout(15000) }));
  deadline = setTimeout(() => { session.abortCompaction(); void session.abort(); }, 240000);

  stage = 'compact';
  const result = await session.compact('Preserve the exact recovery sentinel from prior history.');
  assert.ok(recoveredPreparation && nativeCommit);
  assert.ok(result.summary.includes(sentinel), 'Native summary lost the hidden sentinel');
  assert.equal(sm.getEntry(legacyId).summary, legacy, 'Original history must be unchanged');
  assert.equal(sm.getEntries().filter(entry => entry.type === 'compaction').length, 2);
  const sessionFile = sm.getSessionFile();
  assert.ok(sessionFile.startsWith(scratch + path.sep));
  session.dispose();

  stage = 'restore-and-recall';
  const restored = SessionManager.open(sessionFile);
  assert.equal(restored.getEntry(legacyId).summary, legacy);
  // A disposed runner invalidates its shared extension runtime. Reload before
  // binding a new session; do not reuse captured extension APIs after disposal.
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  ({ session } = await createAgentSession({ ...options, sessionManager: restored }));
  await session.bindExtensions({ onError: () => errors.push('extension-error') });
  assert.equal(session.thinkingLevel, 'max');
  await session.prompt('What exact recovery sentinel was recorded earlier? Reply with that value only.', {
    expandPromptTemplates: false,
  });
  const reply = session.messages.findLast(message => message.role === 'assistant');
  assert.equal(reply.stopReason, 'stop');
  assert.equal(reply.provider, provider);
  assert.equal(reply.model, modelId);
  assert.ok(reply.content.some(part => part.type === 'text' && part.text.includes(sentinel)));
  assert.deepEqual(errors, []);
  assert.equal(requests.length, 2, 'One real compaction plus one real recall request');
  assert.ok(requests.every(request => request.provider === provider && request.model === modelId));
  assert.equal(requests.at(-1).reasoning, 'max');
  report = { passed: true, provider, model: modelId, thinking: session.thinkingLevel,
    nativeCompaction: nativeCommit, recoveredPreparation, restoredRecall: true, requests, scratch };
} catch (error) {
  report = { passed: false, stage, errorType: error?.name ?? 'Error', scratch, requests, errors,
    assertionSite: error?.stack?.match(/native-live-check\.mjs:\d+:\d+/)?.[0] };
  process.exitCode = 1;
} finally {
  clearTimeout(deadline);
  session?.dispose();
  // Cached model metadata is not needed in the durable evidence artifact.
  fs.rmSync(path.join(scratch, 'models-store.json'), { force: true });
  fs.writeFileSync(path.join(scratch, 'result.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify(report));
}
