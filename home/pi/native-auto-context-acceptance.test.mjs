/**
 * Pi 0.84.4 automatic-compaction acceptance (Node >= 22.13).
 * Run with PI_TEST_PACKAGE_DIR set, as documented in the shared fixture:
 *   node --test home/pi/native-auto-context-acceptance.test.mjs
 * PI_NATIVE_CONTEXT_FIXTURE_FILE optionally overrides the sibling shared fixture.
 * The fixture blocks fetch/socket access and supplies real Agent/AgentSession,
 * ExtensionRunner, SessionManager, native compaction, and unchanged helpers.
 * Only authentication and model responses are stubbed; no compaction entrypoint
 * or extension hook is invoked directly by this companion.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const fixture = process.env.PI_NATIVE_CONTEXT_FIXTURE_FILE
  ? pathToFileURL(path.resolve(process.env.PI_NATIVE_CONTEXT_FIXTURE_FILE))
  : new URL('./native-context-acceptance.test.mjs', import.meta.url);
const { harness, legacySession, assistant, MODEL, prepareCompaction, settings, promptText, serialized } = await import(fixture.href);

const AUTO_MODEL = { ...MODEL, contextWindow: 20000 };
const PRIOR = 'ACCEPT_AUTO_PRIOR_HISTORY';
const RETAINED_PROMPT = 'Retain this working turn ' + 'k'.repeat(8000);
const LEGACY_MARKER = 'Magic Context compacted 2 segments: titles only';
const compactions = h => h.sessionManager.getEntries().filter(entry => entry.type === 'compaction');
const eventsOf = (h, type) => h.events.filter(event => event.type === type);
const usage = input => ({ ...assistant('').usage, input, totalTokens: input + 1 });
const thresholdResponse = () => assistant('Completed requested work', { usage: usage(17000) });
const overflowResponse = () => assistant('', {
  stopReason: 'error', errorMessage: 'Your input exceeds the context window of this model',
});

function responseStream(response) {
  return {
    result: async () => response,
    async *[Symbol.asyncIterator]() {
      const message = await response;
      if (message.stopReason === 'error' || message.stopReason === 'aborted') {
        yield { type: 'error', reason: message.stopReason, error: message };
      } else {
        yield { type: 'done', reason: message.stopReason, message };
      }
    },
  };
}

async function automaticHarness(t, {
  responses = [], prePrompt = false, history = PRIOR, enabled = true,
  bridgeOptions = {}, complete, nativeSummary,
} = {}) {
  // Core compares response timestamps with persisted compaction timestamps.
  // Advance only Date (not timers) so retries are newer without wall-clock races.
  t.mock.timers.enable({ apis: ['Date'], now: 1800000000000 });
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'native-auto-context-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const { sm } = legacySession(directory, history);
  t.mock.timers.tick(1);
  if (prePrompt) sm.appendMessage({ ...thresholdResponse(), timestamp: Date.now() });
  const originalEntries = structuredClone(sm.getEntries());
  const h = await harness(t, { directory, sessionManager: sm, model: AUTO_MODEL, bridgeOptions, complete });
  // The shared harness never needs prompt preflight auth for its manual lane.
  h.session.modelRuntime.hasConfiguredAuth = () => true;
  h.session.setAutoCompactionEnabled(enabled);
  assert.equal(h.session.autoCompactionEnabled, enabled);
  assert.equal(h.session.autoRetryEnabled, false, 'generic API retries must not mask overflow recovery');
  const conversationCalls = [];
  const summaryCalls = [];
  const nativeStream = h.agent.streamFunction;
  t.mock.method(h.agent, 'streamFunction', (model, context, options) => {
    const call = { context: structuredClone(context), signal: options.signal, abortedAtCall: options.signal?.aborted === true };
    if (context.systemPrompt !== h.session.systemPrompt) {
      summaryCalls.push(call);
      assert.equal(options.cacheRetention, 'none', 'native standalone summary request');
      assert.ok(promptText(context).startsWith('<conversation>'));
      return nativeSummary ? nativeSummary(model, context, options) : nativeStream(model, context, options);
    }
    conversationCalls.push(call);
    t.mock.timers.tick(1);
    if (options.signal.aborted) {
      return responseStream(assistant('', { stopReason: 'aborted', timestamp: Date.now() }));
    }
    const response = responses[conversationCalls.length - 1];
    assert.ok(response, 'unexpected extra provider request: automatic continuation must be bounded');
    return responseStream({ ...response, timestamp: Date.now() });
  });
  return { ...h, originalEntries, conversationCalls, summaryCalls };
}

function assertSettled(h) {
  assert.equal(h.session.isIdle, true);
  assert.equal(h.session.isCompacting, false);
  assert.equal(h.session.retryAttempt, 0);
  assert.equal(h.session.pendingMessageCount, 0);
  assert.equal(eventsOf(h, 'auto_retry_start').length, 0);
  assert.deepEqual(h.errors, [], 'swallowed extension exceptions are not success');
  assert.deepEqual(h.sessionManager.getEntries().slice(0, h.originalEntries.length), h.originalEntries,
    'automatic compaction must preserve the exact original history');
}

function assertNativeSuccess(h, reason, willRetry, count = 1) {
  const starts = eventsOf(h, 'compaction_start');
  const ends = eventsOf(h, 'compaction_end');
  assert.equal(starts.length, count);
  assert.equal(ends.length, count);
  assert.ok(starts.every(event => event.reason === reason));
  for (const end of ends) {
    assert.equal(end.reason, reason);
    assert.equal(end.aborted, false);
    assert.equal(end.willRetry, willRetry);
    assert.equal(end.errorMessage, undefined);
    assert.ok(end.result.summary.includes(PRIOR));
  }
  assert.equal(h.preparations.length, count);
  assert.equal(h.hookResults.length, count);
  assert.ok(h.hookResults.every(result => !result?.compaction && !result?.cancel), 'bridge cannot own the checkpoint');
  assert.equal(compactions(h).length, count + 1, 'legacy marker plus native checkpoints only');
  for (const entry of compactions(h).slice(1)) {
    assert.equal(entry.fromHook, false);
    assert.ok(entry.summary.includes(PRIOR));
  }
  assert.ok(h.summaryCalls.some(call => promptText(call.context).includes(`<previous-summary>\n`) && promptText(call.context).includes(PRIOR)));
  assert.ok(serialized(h.sessionManager.buildSessionContext().messages).includes(PRIOR));
  assert.ok(!serialized(h.agent.state.messages).includes(LEGACY_MARKER));
  assertSettled(h);
}

function assertNoRecoveryCheckpoint(h) {
  const root = path.join(h.directory, 'reliability/history');
  const files = fs.existsSync(root) ? fs.readdirSync(root) : [];
  assert.deepEqual(files.filter(name => name.endsWith('.summary.md') || name.endsWith('.chunks.json')), []);
}

test('AgentSession automatic threshold: post-run then pre-prompt split retain history under native ownership', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, { responses: [thresholdResponse(), assistant('Continue after split')] });
  assert.ok(!serialized(h.agent.state.messages).includes(PRIOR), 'legacy marker initially hides the sentinel');
  assert.ok(17001 > AUTO_MODEL.contextWindow - settings.reserveTokens);
  assert.ok(17000 < AUTO_MODEL.contextWindow, 'threshold, not successful-response overflow');
  await h.session.prompt(RETAINED_PROMPT);
  assertNativeSuccess(h, 'threshold', false);
  assert.equal(h.conversationCalls.length, 1, 'completed response is not retried');
  assert.ok(promptText(h.conversationCalls[0].context).includes(PRIOR), 'real context hook recovers legacy history');
  assert.equal(h.preparations[0].isSplitTurn, false);
  assert.equal(h.summaryCalls.length, 1);
  const first = compactions(h).at(-1);
  const eventTypes = h.events.map(event => event.type);
  assert.deepEqual(eventTypes.filter(type => type === 'agent_end' || type === 'compaction_start'),
    ['agent_end', 'compaction_start'], 'first threshold dispatch is post-run');

  // Restore a later suffix in the same kept turn, as from a resumed session.
  t.mock.timers.tick(1);
  h.sessionManager.appendMessage(assistant('Later retained suffix ' + 's'.repeat(8000), {
    usage: usage(17000), timestamp: Date.now(),
  }));
  h.agent.state.messages = h.sessionManager.buildSessionContext().messages;
  const prep = prepareCompaction(h.sessionManager.getBranch(), { ...settings, enabled: true });
  assert.ok(prep);
  assert.equal(prep.isSplitTurn, true);
  assert.deepEqual(prep.messagesToSummarize, []);
  assert.equal(prep.previousSummary, first.summary);
  assert.ok(!serialized(prep.turnPrefixMessages).includes(PRIOR), 'prior summary is the only remaining sentinel source');
  const eventBoundary = h.events.length;
  const callBoundary = h.summaryCalls.length;
  await h.session.prompt('Continue after the resumed suffix');
  assertNativeSuccess(h, 'threshold', false, 2);
  assert.equal(h.conversationCalls.length, 2, 'one ordinary response per user prompt');
  assert.deepEqual(h.preparations[1].messagesToSummarize, []);
  const secondEvents = h.events.slice(eventBoundary).map(event => event.type);
  assert.deepEqual(secondEvents.filter(type => type === 'compaction_start' || type === 'agent_start'),
    ['compaction_start', 'agent_start'], 'second dispatch is prompt preflight');
  const requests = h.summaryCalls.slice(callBoundary).map(call => promptText(call.context));
  assert.equal(requests.length, 2, 'native history carry-forward plus native split-turn summary');
  const historyRequest = requests.find(request => request.includes('<previous-summary>'));
  assert.ok(historyRequest?.includes(PRIOR));
  const carry = historyRequest.match(/<conversation>\n([\s\S]*?)\n<\/conversation>/)?.[1];
  assert.ok(carry && carry.length < 512);
  assert.ok(!carry.includes(PRIOR), 'carry instruction must not duplicate the previous summary');
  assert.ok(!compactions(h).at(-1).summary.includes('No prior history.'));
  assert.equal(h.recoveryCalls.length, 0, 'small legacy recovery needs no separate summarizer');
});

test('AgentSession automatic overflow: native compact-and-retry preserves history and excludes failed response', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, { responses: [overflowResponse(), assistant('Recovered turn')] });
  await h.session.prompt(RETAINED_PROMPT);
  assertNativeSuccess(h, 'overflow', true);
  assert.equal(h.conversationCalls.length, 2);
  assert.equal(h.summaryCalls.length, 1);
  assert.equal(h.contexts.length, 2);
  assert.equal(h.contexts[1].before.at(-1).role, 'user', 'native retry must remove the reloaded failed assistant');
  assert.ok(!h.contexts[1].before.some(message => message.role === 'assistant' && message.stopReason === 'error'));
  assert.ok(promptText(h.conversationCalls[1].context).includes(PRIOR));
  assert.equal(h.agent.state.messages.at(-1).stopReason, 'stop');
  assert.equal(h.sessionManager.getEntries().filter(entry => entry.type === 'message' && entry.message.stopReason === 'error').length, 1,
    'failed response stays in the durable session history');
});

test('AgentSession automatic overflow: a second overflow stops after exactly one compact-and-retry', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, { responses: [overflowResponse(), overflowResponse()] });
  await h.session.prompt(RETAINED_PROMPT);
  assert.equal(h.conversationCalls.length, 2);
  assert.equal(h.summaryCalls.length, 1);
  assert.equal(h.preparations.length, 1);
  assert.equal(h.hookResults.length, 1);
  assert.ok(!h.hookResults[0]?.compaction && !h.hookResults[0]?.cancel);
  assert.equal(eventsOf(h, 'compaction_start').length, 1);
  const ends = eventsOf(h, 'compaction_end');
  assert.equal(ends.length, 2);
  assert.equal(ends[0].reason, 'overflow');
  assert.equal(ends[0].willRetry, true);
  assert.ok(ends[0].result.summary.includes(PRIOR));
  assert.equal(ends[1].reason, 'overflow');
  assert.equal(ends[1].result, undefined);
  assert.equal(ends[1].aborted, false);
  assert.equal(ends[1].willRetry, false);
  assert.match(ends[1].errorMessage, /after one compact-and-retry attempt/);
  assert.equal(compactions(h).length, 2);
  assert.equal(compactions(h).at(-1).fromHook, false);
  assert.ok(compactions(h).at(-1).summary.includes(PRIOR));
  assert.ok(promptText(h.conversationCalls[1].context).includes(PRIOR));
  assert.equal(h.agent.state.messages.at(-1).stopReason, 'error');
  assertSettled(h);
});

test('AgentSession automatic overflow: successful oversized response compacts without retry', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, { responses: [assistant('Completed despite oversized input', { usage: usage(21000) })] });
  await h.session.prompt(RETAINED_PROMPT);
  assertNativeSuccess(h, 'overflow', false);
  assert.equal(h.conversationCalls.length, 1);
  assert.equal(h.summaryCalls.length, 1);
  assert.ok(serialized(h.agent.state.messages).includes('Completed despite oversized input'));
});

test('AgentSession automatic compaction: disabled setting suppresses the threshold entrypoint', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, { enabled: false, responses: [thresholdResponse()] });
  await h.session.prompt(RETAINED_PROMPT);
  assert.equal(h.conversationCalls.length, 1);
  assert.equal(h.summaryCalls.length, 0);
  assert.equal(h.preparations.length, 0);
  assert.equal(h.hookResults.length, 0);
  assert.equal(eventsOf(h, 'compaction_start').length, 0);
  assert.equal(eventsOf(h, 'compaction_end').length, 0);
  assert.equal(compactions(h).length, 1);
  assertSettled(h);
});

for (const failure of ['converter', 'completion']) {
  test(`AgentSession automatic threshold: ${failure} recovery failure cancels without native checkpoint`, { timeout: 5000 }, async t => {
    const h = await automaticHarness(t, {
      prePrompt: true,
      history: failure === 'completion' ? PRIOR + '\n' + 'a'.repeat(150000) : PRIOR,
      bridgeOptions: failure === 'converter' ? { convertMessages: () => { throw new Error('Acceptance converter unavailable'); } } : {},
      complete: async () => { throw new Error('Acceptance recovery unavailable'); },
    });
    await h.session.prompt('Do not consume unrecovered title-only history');
    assert.equal(h.preparations.length, 1);
    assert.equal(h.hookResults.length, 1);
    assert.equal(h.hookResults[0]?.cancel, true, 'native runner must receive explicit cancellation');
    assert.equal(h.summaryCalls.length, 0);
    assert.equal(h.nativeCalls.length, 0);
    assert.equal(compactions(h).length, 1);
    assert.equal(eventsOf(h, 'compaction_start').length, 1);
    const ends = eventsOf(h, 'compaction_end');
    assert.equal(ends.length, 1);
    assert.equal(ends[0].reason, 'threshold');
    assert.equal(ends[0].aborted, true);
    assert.equal(ends[0].willRetry, false);
    assert.equal(ends[0].result, undefined);
    // Preflight cancellation does not cancel prompt submission. Its context hook
    // must independently fail closed, not make a live request with a title marker.
    assert.equal(h.contexts.length, 1);
    assert.equal(h.contexts[0].signal.aborted, true);
    assert.ok(h.conversationCalls.length <= 1);
    assert.ok(h.conversationCalls.every(call => call.abortedAtCall), 'no provider request may start before context cancellation');
    assert.equal(h.agent.state.messages.at(-1).stopReason, 'aborted');
    assert.equal(h.recoveryCalls.length, failure === 'completion' ? 2 : 0,
      'one failed preflight chunk and at most one independent context recovery; no internal retry loop');
    assertNoRecoveryCheckpoint(h);
    assertSettled(h);
  });
}

test('AgentSession automatic overflow: native summary failure never retries the interrupted turn', { timeout: 5000 }, async t => {
  const h = await automaticHarness(t, {
    responses: [overflowResponse()],
    nativeSummary: () => responseStream(assistant('', { stopReason: 'error', errorMessage: 'Acceptance summary unavailable' })),
  });
  await h.session.prompt(RETAINED_PROMPT);
  assert.equal(h.conversationCalls.length, 1);
  assert.equal(h.summaryCalls.length, 1);
  assert.equal(h.preparations.length, 1);
  assert.equal(h.hookResults.length, 1);
  assert.ok(!h.hookResults[0]?.cancel && !h.hookResults[0]?.compaction);
  assert.equal(compactions(h).length, 1);
  assert.equal(eventsOf(h, 'compaction_start').length, 1);
  const ends = eventsOf(h, 'compaction_end');
  assert.equal(ends.length, 1);
  assert.equal(ends[0].reason, 'overflow');
  assert.equal(ends[0].result, undefined);
  assert.equal(ends[0].aborted, false);
  assert.equal(ends[0].willRetry, false);
  assert.match(ends[0].errorMessage, /Context overflow recovery failed:.*Acceptance summary unavailable/);
  assertSettled(h);
});

for (const reason of ['threshold', 'overflow']) {
  test(`AgentSession automatic ${reason}: abortCompaction rejects a late successful native summary`, { timeout: 5000 }, async t => {
    const entered = Promise.withResolvers();
    const release = Promise.withResolvers();
    const h = await automaticHarness(t, {
      responses: [reason === 'threshold' ? thresholdResponse() : overflowResponse()],
      nativeSummary: (_model, _context, options) => {
        entered.resolve(options.signal);
        return responseStream(release.promise);
      },
    });
    const running = h.session.prompt(RETAINED_PROMPT);
    let signal;
    try {
      signal = await Promise.race([entered.promise, running.then(() => { throw new Error('Prompt ended before native summary'); })]);
      assert.equal(h.session.isCompacting, true);
      h.session.abortCompaction();
      assert.equal(signal.aborted, true);
    } finally {
      // A provider may ignore cancellation and still return success.
      release.resolve(assistant('ACCEPT_LATE_ABORTED_SUMMARY'));
    }
    await running;
    await h.session.waitForIdle();
    assert.equal(h.summaryCalls.length, 1);
    assert.equal(h.summaryCalls[0].signal, signal);
    assert.equal(h.conversationCalls.length, 1, 'abort must not continue even an interrupted overflow turn');
    assert.equal(h.preparations.length, 1);
    assert.equal(compactions(h).length, 1);
    assert.equal(eventsOf(h, 'compaction_start').length, 1);
    const ends = eventsOf(h, 'compaction_end');
    assert.equal(ends.length, 1);
    assert.equal(ends[0].reason, reason);
    assert.equal(ends[0].aborted, true);
    assert.equal(ends[0].willRetry, false);
    assert.equal(ends[0].result, undefined);
    assert.ok(!JSON.stringify(h.sessionManager.getEntries()).includes('ACCEPT_LATE_ABORTED_SUMMARY'));
    assertSettled(h);
  });
}
