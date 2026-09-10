/**
 * Pi 0.84.4 native-context acceptance. Run with Node >= 22.13:
 *   PI_TEST_PACKAGE_DIR=/path/to/pi-monorepo node --test home/pi/native-context-acceptance.test.mjs
 * Read-only inputs (override for captured installations):
 *   PI_NATIVE_CONTEXT_CORE_DIR       coding-agent package root
 *   PI_NATIVE_CONTEXT_HELPERS_DIR    runtime-reliability helper directory
 *   PI_NATIVE_CONTEXT_CONVERTER_FILE MC bundle exporting cbConvertLegacyMessages
 * No resource discovery, credentials, live databases, or provider calls. All writes
 * are private OS temporary files and are removed after the suite.
 */
import test, { after, mock } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const corePath = process.env.PI_NATIVE_CONTEXT_CORE_DIR || process.env.PI_TEST_PACKAGE_DIR;
assert.ok(corePath, 'Set PI_TEST_PACKAGE_DIR (or PI_NATIVE_CONTEXT_CORE_DIR) to the wrapped coding-agent package root');
const coreDir = path.resolve(corePath);
const helpersDir = path.resolve(process.env.PI_NATIVE_CONTEXT_HELPERS_DIR || path.join(os.homedir(), '.pi/agent/extensions/runtime-reliability'));
const converterFile = path.resolve(process.env.PI_NATIVE_CONTEXT_CONVERTER_FILE || path.join(os.homedir(), '.pi/agent/npm/node_modules/@cortexkit/pi-magic-context/dist/index-kamc8t8p.js'));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-native-context-acceptance-'));
const networkAttempts = [];
const denyNetwork = (...args) => {
  networkAttempts.push(String(args[0]));
  throw new Error('Acceptance suite forbids network access');
};
mock.method(globalThis, 'fetch', denyNetwork);
mock.method(net.Socket.prototype, 'connect', denyNetwork);
const environment = {
  PI_OFFLINE: '1', PI_SKIP_VERSION_CHECK: '1', PI_TELEMETRY: '0',
  PI_CODING_AGENT_DIR: path.join(scratch, 'agent'),
  XDG_DATA_HOME: path.join(scratch, 'data'),
  XDG_CACHE_HOME: path.join(scratch, 'cache'),
  XDG_CONFIG_HOME: path.join(scratch, 'config'),
};
const previousEnvironment = Object.fromEntries(Object.keys(environment).map(key => [key, process.env[key]]));
Object.assign(process.env, environment);
after(() => {
  mock.restoreAll();
  fs.rmSync(scratch, { recursive: true, force: true });
  for (const [key, value] of Object.entries(previousEnvironment)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  assert.deepEqual(networkAttempts, [], 'no network attempt, even one swallowed by the native runner');
});

const importFile = file => import(pathToFileURL(file).href);
const { version } = JSON.parse(fs.readFileSync(path.join(coreDir, 'package.json'), 'utf8'));
assert.equal(version, '0.84.4', 'requalify native seams before accepting a different Pi release');
const { AgentSession } = await importFile(path.join(coreDir, 'dist/core/agent-session.js'));
const { ExtensionRunner } = await importFile(path.join(coreDir, 'dist/core/extensions/runner.js'));
const { createExtensionRuntime, loadExtensionFromFactory } = await importFile(path.join(coreDir, 'dist/core/extensions/loader.js'));
const { createEventBus } = await importFile(path.join(coreDir, 'dist/core/event-bus.js'));
const { SessionManager } = await importFile(path.join(coreDir, 'dist/core/session-manager.js'));
const { SettingsManager } = await importFile(path.join(coreDir, 'dist/core/settings-manager.js'));
const { prepareCompaction } = await importFile(path.join(coreDir, 'dist/core/compaction/compaction.js'));
const { serializeConversation } = await importFile(path.join(coreDir, 'dist/core/compaction/utils.js'));
const { convertToLlm } = await importFile(path.join(coreDir, 'dist/core/messages.js'));
const { Agent } = await importFile(path.join(coreDir, 'node_modules/@earendil-works/pi-agent-core/dist/agent.js'));
const { buildLegacyHistory, reduceHistory, registerContextBridge } = await importFile(path.join(helpersDir, 'context-bridge.mjs'));
const { boundToolOutput, registerToolSafety } = await importFile(path.join(helpersDir, 'tool-safety.mjs'));
const { cbConvertLegacyMessages: convertMessages } = await importFile(converterFile);
assert.equal(typeof convertMessages, 'function', 'the real MC conversion export is required');

const LEGACY_SUMMARY = 'Magic Context compacted 2 segments: titles only';
const MODEL = {
  id: 'native-context-acceptance', name: 'Native context acceptance',
  provider: 'acceptance', api: 'acceptance-stub', baseUrl: 'https://invalid.invalid',
  reasoning: false, input: ['text'], contextWindow: 1000000, maxTokens: 8192,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
};
const text = value => ({ type: 'text', text: value });
const user = value => ({ role: 'user', content: value, timestamp: 1 });
const assistant = (value, overrides = {}) => ({
  role: 'assistant', content: [text(value)], stopReason: 'stop', timestamp: 1,
  api: MODEL.api, provider: MODEL.provider, model: MODEL.id,
  usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
  ...overrides,
});
const toolResult = (value, id = 'read-call') => ({
  role: 'toolResult', toolName: 'read', toolCallId: id,
  content: [text(value)], isError: false, timestamp: 1,
});
const promptText = context => context.messages.map(message => typeof message.content === 'string'
  ? message.content : message.content.filter(part => part.type === 'text').map(part => part.text).join('\n')).join('\n');
const serialized = messages => serializeConversation(convertToLlm(messages));
const compactions = sm => sm.getEntries().filter(entry => entry.type === 'compaction');
const hash = value => createHash('sha256').update(value).digest('hex');
const settings = { enabled: false, reserveTokens: 4096, keepRecentTokens: 1100 };

// The stub can preserve only sentinels actually supplied by the native compactor.
// In particular it cannot invent the prior summary for the second compaction.
function summarize(context) {
  const sentinels = [...new Set(promptText(context).match(/ACCEPT_[A-Z0-9_]+/g) || [])];
  return assistant('## Preserved facts\n' + (sentinels.join('\n') || '(no sentinel in request)'));
}

function responseStream(response) {
  return {
    result: async () => response,
    async *[Symbol.asyncIterator]() {
      if (response.stopReason === 'aborted') yield { type: 'error', reason: 'aborted', error: response };
      else yield { type: 'done', reason: response.stopReason, message: response };
    },
  };
}

function temporary(t) {
  const directory = fs.mkdtempSync(path.join(scratch, 'case-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function historyFiles(directory, suffix) {
  const root = path.join(directory, 'reliability/history');
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root).filter(name => name.endsWith(suffix)).map(name => path.join(root, name));
}

function assertNoRecoveryCheckpoint(directory) {
  assert.deepEqual(historyFiles(directory, '.summary.md'), [], 'failed recovery must not persist a successful summary');
  assert.deepEqual(historyFiles(directory, '.chunks.json'), [], 'failed/aborted first chunk must not be checkpointed');
}

/** Real AgentSession owns preparation, hook dispatch, native compact(), and append. */
async function harness(t, {
  directory = temporary(t), sessionManager = SessionManager.inMemory(directory),
  model = MODEL, bridge = true, toolSafety = false, bridgeOptions = {},
  complete = async (_model, context) => summarize(context),
} = {}) {
  const runtime = createExtensionRuntime();
  const preparations = [];
  const hookResults = [];
  const errors = [];
  const contexts = [];
  const nativeCalls = [];
  const recoveryCalls = [];
  const events = [];
  const extension = await loadExtensionFromFactory(pi => {
    pi.on('session_before_compact', event => { preparations.push(structuredClone(event.preparation)); });
    if (bridge) registerContextBridge(pi, {
      agentDir: directory, database: path.join(directory, 'deliberately-missing.db'), convertMessages, ...bridgeOptions,
    });
    if (toolSafety) registerToolSafety(pi, { agentDir: directory });
  }, directory, createEventBus(), runtime, '<inline:native-context-acceptance>');
  const resourceLoader = {
    getExtensions: () => ({ extensions: [extension], runtime, errors: [] }),
    getSystemPrompt: () => 'Acceptance test; never call a live provider.',
    getAppendSystemPrompt: () => [], getSkills: () => ({ skills: [] }),
    getAgentsFiles: () => ({ agentsFiles: [] }), getPrompts: () => ({ prompts: [] }),
  };
  let runner;
  const agent = new Agent({
    initialState: { model, thinkingLevel: 'off', messages: sessionManager.buildSessionContext().messages },
    convertToLlm,
    transformContext: async (messages, signal) => {
      const record = { signal, before: structuredClone(messages) };
      contexts.push(record);
      record.after = await runner.emitContext(messages);
      return record.after;
    },
    streamFn: (_model, context, options) => {
      nativeCalls.push({ context: structuredClone(context), signal: options.signal, abortedAtCall: options.signal?.aborted === true });
      const response = options.signal?.aborted
        ? assistant('', { stopReason: 'aborted', errorMessage: 'Acceptance request cancelled' })
        : summarize(context);
      return responseStream(response);
    },
  });
  const session = new AgentSession({
    agent, cwd: directory, sessionManager, resourceLoader, baseToolsOverride: {},
    settingsManager: SettingsManager.inMemory({ compaction: settings, retry: { enabled: false } }),
    modelRuntime: {
      getAuth: async () => undefined,
      complete: async (selectedModel, context, options) => {
        recoveryCalls.push({ context: structuredClone(context), signal: options.signal });
        return complete(selectedModel, context, options);
      },
    },
  });
  t.after(() => session.dispose());
  runner = session.extensionRunner;
  assert.ok(runner instanceof ExtensionRunner);
  // Observe, do not replace, native runner error swallowing/cancel propagation.
  const nativeEmit = runner.emit.bind(runner);
  t.mock.method(runner, 'emit', async event => {
    const result = await nativeEmit(event);
    if (event.type === 'session_before_compact') hookResults.push(result);
    return result;
  });
  session.subscribe(event => events.push(event));
  await session.bindExtensions({ onError: error => errors.push(error) });
  return { directory, sessionManager, agent, session, runner, preparations, hookResults,
    errors, contexts, nativeCalls, recoveryCalls, events };
}

function legacySession(directory, history = 'ACCEPT_PRIOR_SUMMARY') {
  const sm = SessionManager.inMemory(directory);
  sm.appendMessage(user(history));
  sm.appendMessage(assistant('Historical answer'));
  const boundary = sm.appendMessage(user('First retained turn'));
  sm.appendMessage(assistant('First retained answer'));
  // First compaction keeps this user turn; the next can split it.
  const nextBoundary = sm.appendMessage(user('Retained turn payload ' + 'k'.repeat(8000)));
  sm.appendMessage(assistant('Retained work'));
  sm.appendCompaction(LEGACY_SUMMARY, boundary, 12345);
  sm.appendMessage(assistant('Continued retained work'));
  return { sm, boundary, nextBoundary };
}

for (const failure of ['archive-write', 'converter', 'missing-converter', 'completion']) {
  test(`registerContextBridge: actual emit cancels ${failure} failure without native checkpoint`, async t => {
    const directory = temporary(t);
    const large = failure === 'completion' ? 'ACCEPT_LARGE_HISTORY\n' + 'a'.repeat(150000) : 'ACCEPT_PRIOR_SUMMARY';
    const { sm } = legacySession(directory, large);
    const bridgeOptions = {};
    if (failure === 'archive-write') fs.writeFileSync(path.join(directory, 'reliability'), 'not a directory');
    if (failure === 'converter') bridgeOptions.convertMessages = () => { throw new Error('Acceptance converter unavailable'); };
    if (failure === 'missing-converter') bridgeOptions.convertMessages = undefined;
    const h = await harness(t, { directory, sessionManager: sm, bridgeOptions,
      model: { ...MODEL, contextWindow: 20000 },
      complete: async () => { throw new Error('Acceptance completion unavailable'); },
    });
    const before = structuredClone(sm.getEntries());
    await assert.rejects(h.session.compact(), /cancel/i);
    assert.equal(h.hookResults.at(-1)?.cancel, true, 'emit must receive explicit cancellation, not swallow a thrown recovery error');
    assert.equal(h.nativeCalls.length, 0, 'native compactor must never see an unrecovered title-only marker');
    assert.deepEqual(sm.getEntries(), before, 'no incomplete compaction entry appended');
    assert.equal(h.events.findLast(event => event.type === 'compaction_end')?.aborted, true);
    assert.deepEqual(h.errors, [], 'bridge must handle recovery exceptions itself');
    assertNoRecoveryCheckpoint(directory);
  });

  test(`registerContextBridge: actual emitContext aborts active signal on ${failure} failure`, async t => {
    const directory = temporary(t);
    const { sm } = legacySession(directory, failure === 'completion' ? 'b'.repeat(150000) : 'ACCEPT_PRIOR_SUMMARY');
    const bridgeOptions = {};
    if (failure === 'archive-write') fs.writeFileSync(path.join(directory, 'reliability'), 'not a directory');
    if (failure === 'converter') bridgeOptions.convertMessages = () => { throw new Error('Acceptance converter unavailable'); };
    if (failure === 'missing-converter') bridgeOptions.convertMessages = undefined;
    const h = await harness(t, { directory, sessionManager: sm, bridgeOptions,
      model: { ...MODEL, contextWindow: 20000 },
      complete: async () => { throw new Error('Acceptance completion unavailable'); },
    });
    const before = structuredClone(compactions(sm));
    await h.agent.prompt(user('Attempt recovery'));
    assert.equal(h.contexts.length, 1);
    assert.equal(h.contexts[0].signal.aborted, true, 'ctx.abort must abort the real active Agent signal');
    assert.ok(h.nativeCalls.every(call => call.abortedAtCall), 'no non-aborted provider request may consume title-only history');
    assert.equal(h.agent.state.messages.at(-1).stopReason, 'aborted');
    assert.deepEqual(compactions(sm), before);
    assert.deepEqual(h.errors, [], 'emitContext swallowing an exception is not fail-closed recovery');
    assertNoRecoveryCheckpoint(directory);
  });
}

test('registerContextBridge: two actual native compactions preserve prior summary across an empty-history split turn', async t => {
  const directory = temporary(t);
  const { sm, nextBoundary } = legacySession(directory);
  const h = await harness(t, { directory, sessionManager: sm });
  const first = await h.session.compact();
  assert.equal(first.firstKeptEntryId, nextBoundary);
  assert.ok(first.summary.includes('ACCEPT_PRIOR_SUMMARY'));
  assert.equal(h.preparations[0].isSplitTurn, false);
  assert.ok(h.preparations[0].messagesToSummarize.length > 0);
  assert.equal(compactions(sm).at(-1).fromHook, false, 'only native compactor may create the retained summary');

  sm.appendMessage(assistant('ACCEPT_NEW_SUFFIX\n' + 's'.repeat(8000)));
  const prep = prepareCompaction(sm.getBranch(), settings);
  assert.ok(prep);
  assert.equal(prep.isSplitTurn, true, 'fixture must split the first retained user turn');
  assert.deepEqual(prep.messagesToSummarize, [], 'exercise native empty-history fast path');
  assert.ok(prep.turnPrefixMessages.length > 0);
  assert.equal(prep.previousSummary, first.summary);
  assert.ok(!serialized(prep.turnPrefixMessages).includes('ACCEPT_PRIOR_SUMMARY'), 'sentinel must be available ONLY through previousSummary');
  const callBoundary = h.nativeCalls.length;
  const second = await h.session.compact();
  assert.deepEqual(h.preparations[1].messagesToSummarize, []);
  const requests = h.nativeCalls.slice(callBoundary).map(call => promptText(call.context));
  assert.equal(requests.length, 2, 'native history update plus native turn-prefix summarization');
  const historyRequest = requests.find(request => request.includes('<previous-summary>'));
  assert.ok(historyRequest?.includes('ACCEPT_PRIOR_SUMMARY'));
  const carry = historyRequest.match(/<conversation>\n([\s\S]*?)\n<\/conversation>/)?.[1];
  assert.ok(carry && carry.length < 512, 'carry-forward must be a small synthetic instruction, not a duplicate summary');
  assert.ok(!carry.includes('ACCEPT_PRIOR_SUMMARY'));
  assert.ok(second.summary.includes('ACCEPT_PRIOR_SUMMARY'), 'native result must retain the first native summary');
  assert.ok(!second.summary.includes('No prior history.'));
  assert.equal(compactions(sm).length, 3, 'legacy marker plus two actual native checkpoints');
  assert.equal(compactions(sm).at(-1).summary, second.summary);
  assert.equal(compactions(sm).at(-1).fromHook, false);
  assert.ok(serialized(sm.buildSessionContext().messages).includes('ACCEPT_PRIOR_SUMMARY'));
  assert.deepEqual(h.errors, []);
});

test('registerContextBridge: legacy empty-history split also uses a small native carry-forward instruction', async t => {
  const directory = temporary(t);
  const sm = SessionManager.inMemory(directory);
  sm.appendMessage(user('ACCEPT_LEGACY_PRIOR_SUMMARY'));
  sm.appendMessage(assistant('Historical answer'));
  const boundary = sm.appendMessage(user('Start the first retained turn'));
  sm.appendMessage(assistant('Prefix of retained work'));
  sm.appendCompaction(LEGACY_SUMMARY, boundary, 12345);
  sm.appendMessage(assistant('Recent suffix ' + 's'.repeat(8000)));
  const h = await harness(t, { directory, sessionManager: sm });
  const result = await h.session.compact();
  assert.equal(h.preparations[0].isSplitTurn, true);
  assert.deepEqual(h.preparations[0].messagesToSummarize, []);
  assert.equal(h.preparations[0].previousSummary, LEGACY_SUMMARY);
  assert.equal(h.nativeCalls.length, 2);
  const request = h.nativeCalls.map(call => promptText(call.context)).find(value => value.includes('<previous-summary>'));
  assert.ok(request?.includes('ACCEPT_LEGACY_PRIOR_SUMMARY'));
  const carry = request.match(/<conversation>\n([\s\S]*?)\n<\/conversation>/)?.[1];
  assert.ok(carry && carry.length < 512);
  assert.ok(!carry.includes('ACCEPT_LEGACY_PRIOR_SUMMARY'), 'do not duplicate recovered history in the synthetic message');
  assert.ok(result.summary.includes('ACCEPT_LEGACY_PRIOR_SUMMARY'));
  assert.equal(compactions(sm).at(-1).fromHook, false);
  assert.deepEqual(h.errors, []);
});

function projectionSession(directory) {
  const sm = SessionManager.inMemory(directory);
  sm.appendMessage(user('ACCEPT_RAW_USER'));
  sm.appendCustomMessageEntry('acceptance-hidden', 'ACCEPT_CUSTOM_MESSAGE', false, { retained: true });
  sm.branchWithSummary(sm.getLeafId(), 'ACCEPT_BRANCH_SUMMARY');
  sm.appendCustomEntry('acceptance-state-only', { secret: 'ACCEPT_EXCLUDED_STATE' });
  for (const excluded of [false, true]) sm.appendMessage({
    role: 'bashExecution', command: excluded ? 'private-command' : 'context-command',
    output: excluded ? 'ACCEPT_EXCLUDED_BASH' : 'ACCEPT_CONTEXT_BASH',
    exitCode: 0, cancelled: false, truncated: false, excludeFromContext: excluded, timestamp: 1,
  });
  sm.appendMessage(assistant('Read the historical result', {
    content: [{ type: 'toolCall', id: 'boundary-call', name: 'read', arguments: { path: 'historical.txt' } }],
    stopReason: 'toolUse',
  }));
  sm.appendMessage(toolResult('ACCEPT_TOOL_BOUNDARY', 'boundary-call'));
  const boundary = sm.appendMessage(user('ACCEPT_KEPT_USER'));
  sm.appendMessage(assistant('Kept answer'));
  sm.appendCompaction(LEGACY_SUMMARY, boundary, 12345);
  sm.appendMessage(user('New retained turn ' + 'r'.repeat(8000)));
  sm.appendMessage(assistant('Newest answer'));
  return { sm, boundary };
}

const recoveredSentinels = ['ACCEPT_RAW_USER', 'ACCEPT_CUSTOM_MESSAGE', 'ACCEPT_BRANCH_SUMMARY', 'ACCEPT_CONTEXT_BASH', 'ACCEPT_TOOL_BOUNDARY'];
function assertProjection(value) {
  for (const sentinel of recoveredSentinels) assert.ok(value.includes(sentinel), `missing original-position content: ${sentinel}`);
  for (const excluded of ['ACCEPT_EXCLUDED_BASH', 'ACCEPT_EXCLUDED_STATE']) assert.ok(!value.includes(excluded), `${excluded} must remain outside model context`);
}

function archivedEntryObjects(value) {
  if (!value || typeof value !== 'object') return [];
  const own = !Array.isArray(value) && typeof value.id === 'string' && typeof value.type === 'string' ? [value] : [];
  return own.concat(Object.values(value).flatMap(archivedEntryObjects));
}

test('buildLegacyHistory/registerContextBridge: native recovery preserves original-position tool/custom/branch/bash content', async t => {
  const directory = temporary(t);
  const { sm, boundary } = projectionSession(directory);
  const entries = sm.getBranch();
  const merged = convertMessages(entries).find(message => message.id === boundary);
  assert.ok(JSON.stringify(merged.parts).includes('ACCEPT_TOOL_BOUNDARY'), 'real MC converter must merge the tool result into the kept user');
  assert.ok(!serialized(sm.buildSessionContext().messages).includes('ACCEPT_TOOL_BOUNDARY'), 'native retained context has already excluded that tool result');
  const recovery = buildLegacyHistory({ sessionId: sm.getSessionId(), entries,
    catalog: { source: 'acceptance', rows: [], facts: [] }, convertMessages,
    archiveFile: path.join(directory, 'projection.json'),
  });
  assertProjection(recovery.text);
  assert.ok(!recovery.text.includes('ACCEPT_KEPT_USER'), 'recovery must not pull retained-user text across the boundary');
  const h = await harness(t, { directory, sessionManager: sm });
  const before = structuredClone(entries);
  const context = await h.runner.emitContext(sm.buildSessionContext().messages);
  assertProjection(serialized(context));
  assert.deepEqual(sm.getBranch(), before, 'context recovery is non-mutating');
  const archives = historyFiles(directory, '.json').filter(file => !file.endsWith('catalog.json') && !file.endsWith('.chunks.json'));
  assert.equal(archives.length, 1);
  assert.equal(fs.statSync(archives[0]).mode & 0o777, 0o600);
  const archived = archivedEntryObjects(JSON.parse(fs.readFileSync(archives[0], 'utf8')));
  for (const entry of entries.slice(0, entries.findIndex(entry => entry.id === boundary))) {
    // Match on-disk session JSON semantics: undefined optional fields are omitted.
    assert.deepEqual(archived.find(candidate => candidate.id === entry.id), JSON.parse(JSON.stringify(entry)), `archive must preserve exact original entry ${entry.type}/${entry.id}, not only MC conversion`);
  }
  const result = await h.session.compact();
  assertProjection(result.summary);
  assertProjection(serialized(sm.buildSessionContext().messages));
  assert.deepEqual(h.errors, []);
});

test('buildLegacyHistory: endpoint-matched MC rows cannot cover away skipped context-bearing entries', t => {
  const directory = temporary(t);
  const { sm, boundary } = projectionSession(directory);
  const entries = sm.getBranch();
  const start = entries.find(entry => entry.type === 'message' && entry.message.role === 'user');
  const end = entries.find(entry => entry.type === 'message' && entry.message.role === 'assistant');
  const recovery = buildLegacyHistory({ sessionId: sm.getSessionId(), entries, convertMessages,
    archiveFile: path.join(directory, 'projection.json'),
    catalog: { source: 'acceptance', facts: [], rows: [{
      session_id: sm.getSessionId(), start_message_id: start.id, end_message_id: end.id,
      title: 'Endpoint-bound summary', p1: 'ACCEPT_ROW_HISTORY', content: 'ACCEPT_ROW_HISTORY',
    }] },
  });
  assert.equal(recovery.selected, 1, 'exercise supplement logic inside a selected MC range');
  assert.ok(recovery.text.includes('ACCEPT_ROW_HISTORY'));
  for (const sentinel of recoveredSentinels.filter(value => value !== 'ACCEPT_RAW_USER')) {
    assert.ok(recovery.text.includes(sentinel), `selected row must not erase ${sentinel}`);
  }
  for (const excluded of ['ACCEPT_EXCLUDED_BASH', 'ACCEPT_EXCLUDED_STATE', 'ACCEPT_KEPT_USER']) {
    assert.ok(!recovery.text.includes(excluded));
  }
  assert.equal(recovery.boundaryId, boundary);
});

for (const invalid of ['length', 'toolUse', 'toolCall-with-stop']) {
  test(`registerContextBridge: ${invalid} completion cannot become a recovery or native checkpoint`, async t => {
    const directory = temporary(t);
    const { sm } = legacySession(directory, 'ACCEPT_LARGE_HISTORY\n' + 'a'.repeat(150000));
    const content = [text('ACCEPT_INVALID_PARTIAL')];
    if (invalid !== 'length') content.push({ type: 'toolCall', id: 'unexpected', name: 'read', arguments: { path: 'never-execute' } });
    const h = await harness(t, { directory, sessionManager: sm, model: { ...MODEL, contextWindow: 20000 },
      complete: async () => assistant('', { content, stopReason: invalid === 'toolCall-with-stop' ? 'stop' : invalid }),
    });
    const before = structuredClone(compactions(sm));
    await assert.rejects(h.session.compact(), /cancel/i);
    assert.equal(h.hookResults.at(-1)?.cancel, true);
    assert.equal(h.recoveryCalls.length, 1, 'stop immediately on the first unsafe chunk');
    assert.equal(h.nativeCalls.length, 0);
    assert.deepEqual(compactions(sm), before);
    assertNoRecoveryCheckpoint(directory);
    assert.deepEqual(h.errors, []);
  });
}

test('reduceHistory: old unversioned chunk checkpoints are invalidated, not trusted after stronger completion checks', async t => {
  const directory = temporary(t);
  const checkpointFile = path.join(directory, 'old.chunks.json');
  const chunks = ['a'.repeat(64000), 'b'.repeat(64000)];
  fs.writeFileSync(checkpointFile, JSON.stringify(Object.fromEntries(chunks.map(chunk => [hash(chunk), 'ACCEPT_OLD_TRUNCATED']))), { mode: 0o600 });
  const calls = [];
  const result = await reduceHistory(chunks.join(''), { maxChars: 1000, checkpointFile,
    complete: async chunk => { calls.push(chunk); return `Revalidated ${chunk[0]}`; },
  });
  assert.equal(calls.length, chunks.length, 'every old checkpoint must be revalidated');
  assert.deepEqual(calls, chunks, 'old acceptance rules must not bypass the new summarizer');
  assert.ok(!result.includes('ACCEPT_OLD_TRUNCATED'));
  assert.ok(result.includes('Revalidated a') && result.includes('Revalidated b'));
  assert.ok(JSON.parse(fs.readFileSync(checkpointFile, 'utf8')).version >= 2, 'new checkpoints need a versioned envelope');
});

test('reduceHistory: abort during the final chunk rejects and never checkpoints a late successful response', async t => {
  const directory = temporary(t);
  const checkpointFile = path.join(directory, 'aborted.chunks.json');
  const controller = new AbortController();
  let calls = 0;
  await assert.rejects(reduceHistory('x'.repeat(20000), { maxChars: 1000, checkpointFile, signal: controller.signal,
    complete: async (_chunk, signal) => {
      calls += 1;
      assert.equal(signal, controller.signal);
      controller.abort();
      return 'ACCEPT_ABORTED_CHUNK';
    },
  }), { name: 'AbortError' });
  assert.equal(calls, 1);
  assert.equal(fs.existsSync(checkpointFile), false);
});

test('registerContextBridge: active context cancellation reaches chunk, prevents later chunks, and evicts aborted recovery', async t => {
  const directory = temporary(t);
  const { sm } = legacySession(directory, 'ACCEPT_LARGE_HISTORY\n' + 'a'.repeat(64000) + 'b'.repeat(64000) + 'c'.repeat(64000));
  const entered = Promise.withResolvers();
  const release = Promise.withResolvers();
  let cancelling = true;
  const h = await harness(t, { directory, sessionManager: sm, model: { ...MODEL, contextWindow: 20000 },
    complete: async (_model, context, options) => {
      if (!cancelling) return summarize(context);
      entered.resolve(options.signal);
      await release.promise;
      // Deliberately ignore abort as a provider can: the bridge must reject this.
      return assistant('ACCEPT_ABORTED_CHUNK');
    },
  });
  const before = structuredClone(compactions(sm));
  const running = h.agent.prompt(user('Recover with cancellation'));
  const signal = await Promise.race([entered.promise, running.then(() => { throw new Error('Recovery ended before entering a chunk'); })]);
  // Release even if an assertion fails, so the test cannot strand the real Agent.
  h.agent.abort();
  release.resolve();
  await running;
  assert.equal(signal, h.contexts[0].signal, 'ctx.signal must be passed into ModelRegistry.complete');
  assert.equal(signal.aborted, true);
  assert.equal(h.recoveryCalls.length, 1, 'no later chunk after abort');
  assertNoRecoveryCheckpoint(directory);
  assert.deepEqual(compactions(sm), before);

  cancelling = false;
  const failedChunk = promptText(h.recoveryCalls[0].context);
  await h.agent.prompt(user('Retry recovery with a fresh signal'));
  assert.ok(h.recoveryCalls.length > 2, 'retry must execute new chunk work, not reuse aborted inFlight cache');
  assert.equal(promptText(h.recoveryCalls[1].context), failedChunk, 'the aborted first chunk must be recomputed');
  assert.notEqual(h.recoveryCalls[1].signal, signal);
  assert.equal(h.recoveryCalls[1].signal.aborted, false);
  const recovered = serialized(h.contexts.at(-1).after);
  assert.ok(recovered.includes('ACCEPT_LARGE_HISTORY'));
  assert.ok(!recovered.includes('ACCEPT_ABORTED_CHUNK'));
  assert.ok(!recovered.includes(LEGACY_SUMMARY));
  assert.equal(historyFiles(directory, '.summary.md').length, 1);
  assert.deepEqual(h.errors, []);
});

function assertArchiveLocator(message, archive) {
  const nativeText = serialized([message]);
  assert.ok(nativeText.includes(archive.archive), 'exact archive locator must survive native 2000-character serialization');
  assert.ok(nativeText.includes(archive.readable), 'paged locator must survive native 2000-character serialization');
}

test('boundToolOutput: a newly bounded result retains locators through native serializeConversation', t => {
  const directory = temporary(t);
  const original = toolResult(('long result ' + 'x'.repeat(300) + '\n').repeat(1000) + 'ACCEPT_ARCHIVE_TAIL');
  const patch = boundToolOutput(original, { directory });
  assert.ok(patch);
  const bounded = { ...original, ...patch };
  const archive = bounded.details.runtimeReliabilityArchive;
  assertArchiveLocator(bounded, archive);
  assert.ok(bounded.content[0].text.length <= 64000);
  assert.deepEqual(JSON.parse(fs.readFileSync(archive.archive, 'utf8')).content, original.content);
  assert.equal(fs.statSync(archive.archive).mode & 0o777, 0o600);
  assert.equal(boundToolOutput(bounded, { directory }), null, 'new format is idempotent');
});

for (const alreadyBounded of [false, true]) {
  test(`registerToolSafety: ${alreadyBounded ? 'legacy already-bounded' : 'new'} result locators reach actual native compactor`, async t => {
    const directory = temporary(t);
    const exact = toolResult(('old result ' + 'x'.repeat(300) + '\n').repeat(1000) + 'ACCEPT_ARCHIVE_TAIL');
    let message = exact;
    let originalArchive;
    if (alreadyBounded) {
      originalArchive = { archive: path.join(directory, 'original.json'), readable: path.join(directory, 'original.txt'), originalCharacters: exact.content[0].text.length };
      fs.writeFileSync(originalArchive.archive, JSON.stringify({ toolName: exact.toolName, toolCallId: exact.toolCallId, content: exact.content }), { mode: 0o600 });
      fs.writeFileSync(originalArchive.readable, exact.content[0].text, { mode: 0o600 });
      // A persisted pre-fix result: under the output budget, but locator at the end.
      message = { ...exact, content: [text(('preview ' + 'p'.repeat(250) + '\n').repeat(40)
        + `\n[Output bounded for context safety, not deleted. Full exact result: ${originalArchive.archive}\nPaged text: ${originalArchive.readable}. Use read with offset/limit for remaining details. Do not infer omitted content.]`)],
      details: { runtimeReliabilityArchive: originalArchive, preserved: true } };
      assert.ok(!serialized([message]).includes(originalArchive.archive), 'fixture must lose the old suffix locator without repair');
    }
    const sm = SessionManager.inMemory(directory);
    sm.appendMessage(user('Historical read'));
    sm.appendMessage(assistant('', { content: [{ type: 'toolCall', id: exact.toolCallId, name: 'read', arguments: { path: 'history.txt' } }], stopReason: 'toolUse' }));
    sm.appendMessage(message);
    sm.appendMessage(user('Keep this user turn ' + 'k'.repeat(8000)));
    sm.appendMessage(assistant('Recent answer'));
    const h = await harness(t, { directory, sessionManager: sm, bridge: false, toolSafety: true });
    const before = structuredClone(sm.getEntries());
    const context = await h.runner.emitContext(sm.buildSessionContext().messages);
    const repaired = context.find(item => item.role === 'toolResult');
    const archive = repaired.details.runtimeReliabilityArchive;
    if (originalArchive) assert.deepEqual(archive, originalArchive, 'do not archive an already-truncated preview over the original locator');
    assertArchiveLocator(repaired, archive);
    assert.deepEqual(sm.getEntries(), before);
    assert.deepEqual(JSON.parse(fs.readFileSync(archive.archive, 'utf8')).content, exact.content);
    await h.session.compact();
    const requests = h.nativeCalls.map(call => promptText(call.context));
    assert.ok(requests.some(request => request.includes(archive.archive) && request.includes(archive.readable)), 'session_before_compact must promote the locator before native serialization truncates the preview');
    assert.equal(compactions(sm).at(-1).fromHook, false);
    assert.deepEqual(h.errors, []);
  });
}

for (const older of [LEGACY_SUMMARY, 'Earlier native summary ACCEPT_OLD_CHECKPOINT']) {
  test(`continued native context excludes an obsolete kept checkpoint: ${older}`, async t => {
    const directory = temporary(t);
    const sm = SessionManager.inMemory(directory);
    sm.appendMessage(user('Historical fact ACCEPT_RESTART_FACT'));
    sm.appendMessage(assistant('Historical answer'));
    const kept = sm.appendMessage(user('Keep this user turn'));
    sm.appendCompaction(older, kept, 100);
    sm.appendMessage(assistant('Retained answer'));
    const current = 'Native summary preserving ACCEPT_RESTART_FACT';
    sm.appendCompaction(current, kept, 200);
    const original = structuredClone(sm.getEntries());
    const restored = sm.buildSessionContext().messages;
    assert.equal(restored.filter(message => message.role === 'compactionSummary').length, 2, 'real Pi 0.84.4 reintroduces the obsolete checkpoint inside the kept range');
    const h = await harness(t, { directory, sessionManager: sm });
    h.session.modelRuntime.hasConfiguredAuth = () => true;
    await h.session.prompt('Continue from the current checkpoint', { expandPromptTemplates: false });
    assert.equal(h.nativeCalls.length, 1);
    assert.equal(h.nativeCalls[0].abortedAtCall, false, 'obsolete legacy marker must not abort a native continuation');
    const summaries = h.contexts.at(-1).after.filter(message => message.role === 'compactionSummary');
    assert.deepEqual(summaries.map(message => message.summary), [current]);
    assert.equal(h.agent.state.messages.at(-1).stopReason, 'stop');
    assert.deepEqual(sm.getEntries().slice(0, original.length), original, 'history must not be rewritten');
    assert.deepEqual(h.errors, []);
  });
}

// Shared only by the automatic-compaction acceptance companion.
export { harness, legacySession, user, assistant, MODEL, SessionManager, prepareCompaction, settings, text, promptText, serialized };
