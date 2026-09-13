import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { launchRpc, success, rejected, textOf } from './rpc.mjs';
import { strategy, records } from './review.mjs';

async function barrier(root) {
  const sockets = new Set();
  let resolveReady;
  const ready = new Promise(resolve => { resolveReady = resolve; });
  const server = createServer(socket => {
    sockets.add(socket); socket.on('close', () => sockets.delete(socket));
    let input = '';
    socket.on('data', chunk => { input += chunk; if (input.endsWith('\n')) resolveReady(JSON.parse(input)); });
  });
  server.listen(join(root, 'tmp/lifecycle.sock')); await once(server, 'listening');
  return { ready, release() { for (const socket of sockets) socket.write('release\n'); }, async close() { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); } };
}
async function waitOwnedHistory(attempt, release) {
  const { foregroundHistory: path, parentSession } = attempt.nativeLocator;
  assert.equal(typeof path, 'string', 'Use only the native runtime locator bound at launch');
  let watcher, timer;
  try {
    return await new Promise((resolve, reject) => {
      const inspect = () => {
        try {
          const data = JSON.parse(fs.readFileSync(path, 'utf8'));
          const runs = data.runs.filter(run => run.runId === attempt.childRunId && run.sessionId === parentSession);
          if (runs.length !== 1 || runs[0].children.length !== 1) return;
          const child = runs[0].children[0];
          if (['completed', 'failed', 'stopped'].includes(child.status) && Number.isInteger(child.exitCode)) resolve({ path, run: runs[0] });
        } catch (error) { if (error.code !== 'ENOENT') reject(error); }
      };
      watcher = fs.watch(dirname(path), inspect); watcher.on('error', reject);
      timer = setTimeout(() => reject(new Error('Native owned foreground history did not record terminal exit')), 60000);
      release(); inspect();
    });
  } finally { watcher?.close(); clearTimeout(timer); }
}

function lifecyclePlan(fixture, label) {
  const a = join(fixture.root, `work/${label}-a.txt`), b = join(fixture.root, `work/${label}-b.txt`);
  fs.writeFileSync(a, 'Deterministic lifecycle fixture: read only, no mutation before or after detachment.\n');
  fs.writeFileSync(b, 'Writer B must remain unprepared while writer A termination is unknown.\n');
  return { workflow: `native-fixture-receipts-lifecycle-${label}`, goal: 'Qualify real native foreground lifecycle ownership', inputs: [],
    obligations: [{ id: 'lifecycle', kind: 'requirement', description: 'Second writer waits for actual terminal proof', scopes: [a, b], inputs: [], dependsOn: [] }],
    lanes: [['writer-a', a], ['writer-b', b]].map(([id, scope]) => ({ id, agent: 'worker', role: 'writer', owner: 'child', access: 'write', goal: 'Fixture-only lifecycle probe. Read the assigned text. Do not write anything. The provider pauses and fails intentionally after native detach.', constraints: ['No file mutation, no lease acquisition, no subprocess or child orchestration'], scopes: [scope], obligations: ['lifecycle'], inputs: [], dependsOn: [] })),
  };
}
async function lifecycleCase(fixture, report, restoreWhilePaused) {
  const label = restoreWhilePaused ? 'disk-fallback' : 'terminal-event';
  let rpc = launchRpc(fixture, label);
  let control, sequenceSettled;
  report.plan = lifecyclePlan(fixture, label);
  try {
    control = await barrier(fixture.root);
    const api = strategy(rpc);
    await rpc.request('prompt', { message: '/subagents-load-profile max' });
    await api({ action: 'plan', plan: report.plan });
    const prepared = await api({ action: 'prepare', lane: 'writer-a', foregroundOnly: true });
    report.prepared = prepared;
    const launchId = `fixture-${randomUUID()}`, blockedId = `fixture-${randomUUID()}`, statusId = `fixture-${randomUUID()}`;
    const steps = [
      { id: launchId, name: 'subagent', input: prepared.input },
      { id: blockedId, name: 'execution_strategy', input: { action: 'prepare', lane: 'writer-b', foregroundOnly: true } },
      { id: statusId, name: 'execution_strategy', input: { action: 'status' } },
    ];
    const from = rpc.events.length;
    await rpc.request('prompt', { message: 'NATIVE_FIXTURE_CALL\n' + JSON.stringify({ steps }) });
    sequenceSettled = rpc.wait(event => event.type === 'agent_settled', from);
    // Attach immediately: a test assertion must not leave an unhandled rejection.
    sequenceSettled.catch(() => {});
    report.barrier = await Promise.race([control.ready, rpc.wait(event => event.type === 'tool_execution_end' && event.toolCallId === launchId, from).then(event => { throw new Error(`Native launch ended before barrier: ${JSON.stringify(event)}`); })]);
    assert.equal(report.barrier.attempt, prepared.attempt); assert.notEqual(report.barrier.pid, rpc.pid);
    process.kill(report.barrier.pid, 0);
    const detachFrom = rpc.events.length;
    await rpc.request('prompt', { message: '/subagents-detach' });
    report.detachEvents = rpc.events.slice(detachFrom);
    const blocked = await rpc.wait(event => event.type === 'tool_execution_end' && event.toolCallId === blockedId, from);
    report.writerBeforeTerminal = blocked;
    rejected(blocked, /writer.*pending|one writer/);
    report.pending = success(await rpc.wait(event => event.type === 'tool_execution_end' && event.toolCallId === statusId, from));
    const pendingAttempt = report.pending.attempts.find(row => row.id === prepared.attempt);
    assert.ok(['unknown', 'paused', 'running'].includes(pendingAttempt.status), JSON.stringify(pendingAttempt));
    report.launched = await rpc.wait(event => event.type === 'tool_execution_end' && event.toolCallId === launchId, from);
    assert.equal(pendingAttempt.packetHash, null);
    assert.ok(report.pending.review.gaps.some(gap => gap.includes('unfinished/unknown')));
    process.kill(report.barrier.pid, 0);
    if (restoreWhilePaused) {
      // Supported reload, not history editing or fake lifecycle emission. The native child
      // must survive this seam; otherwise this case fails rather than claiming fallback.
      await rpc.request('prompt', { message: '/native-fixture-reload' });
      report.reloadWhilePaused = true;
      process.kill(report.barrier.pid, 0);
    }
    // Reload intentionally drops stale native event routing and in-memory wait tracking.
    // Observe the actual native-owned history write instead; never count "nothing to wait for" as exit proof.
    if (restoreWhilePaused) report.nativeHistory = await waitOwnedHistory(pendingAttempt, () => control.release());
    else control.release();
    await sequenceSettled;
    // RPC transport settlement is not child termination; wait through the real native tool.
    const nativeId = textOf(report.launched).match(/subagent_wait\(\{ id: "([0-9a-f-]+)"/)?.[1];
    assert.ok(nativeId, 'Use only the exact foreground ID returned by the native detach control');
    report.nativeDetachedId = nativeId;
    report.nativeWait = await rpc.call('subagent_wait', { id: nativeId, timeoutMs: 60000 });
    success(report.nativeWait);
    const final = await strategy(rpc)({ action: 'status' }); report.final = final;
    const attempt = final.attempts.find(row => row.id === prepared.attempt);
    report.integrationGaps = [];
    const check = fn => { try { fn(); } catch (error) { report.integrationGaps.push(error.stack); } };
    check(() => assert.ok(pendingAttempt.childRunId, 'Native detached tool result must bind owned child identity'));
    check(() => assert.equal(attempt.status, 'failed', JSON.stringify(attempt)));
    check(() => assert.equal(attempt.childRunId, pendingAttempt.childRunId));
    assert.equal(attempt.packetHash, null); assert.equal(final.review.pass, false); assert.equal(final.review.workflowAcceptance, false);
    const entries = records(join(fixture.root, `${label}.jsonl`));
    report.terminalEvents = entries.filter(entry => entry.customType === 'native-fixture-terminal-observation').map(entry => entry.data);
    if (restoreWhilePaused) {
      check(() => assert.equal(report.terminalEvents.length, 0, 'Stale runtime completion must not be routed to the replacement runtime'));
      check(() => assert.equal(report.nativeHistory.run.runId, attempt.childRunId));
      check(() => assert.ok(Number.isInteger(report.nativeHistory.run.children[0].exitCode)));
    } else check(() => assert.ok(report.terminalEvents.some(event => event.runId === attempt.childRunId && Number.isInteger(event.exitCode)), 'Missing authentic correlated native terminal event with exit evidence'));
    report.writerAfterTerminal = await rpc.call('execution_strategy', { action: 'prepare', lane: 'writer-b', foregroundOnly: true });
    check(() => success(report.writerAfterTerminal));
    if (!report.writerAfterTerminal.isError) await strategy(rpc)({ action: 'cancel', attempt: report.writerAfterTerminal.result.details.attempt });
    report.consumeRejection = rejected(await rpc.call('execution_strategy', { action: 'consume', attempt: attempt.id }), /native|packet|failure|successful/i);
    check(() => { assert.equal(attempt.actual.usage.value, null); assert.match(attempt.actual.metadataGap, /usage/); });
    await rpc.request('prompt', { message: '/native-fixture-reload' });
    report.reloaded = await strategy(rpc)({ action: 'status' });
    await rpc.close(); rpc = launchRpc(fixture, label);
    report.diskRestored = await strategy(rpc)({ action: 'status' });
    const restored = report.diskRestored.attempts.find(row => row.id === prepared.attempt);
    check(() => { assert.equal(restored.status, 'failed'); assert.equal(restored.childRunId, attempt.childRunId); });
    assert.equal(report.diskRestored.review.pass, false);
    if (restoreWhilePaused) check(() => assert.match(attempt.actual.provenance, /verified native owned foreground history\/session/, 'Must exercise history fallback, not merely restore an already-terminal ledger'));
    assert.deepEqual(report.integrationGaps, [], 'No lifecycle seam failure may print PASS');
  } finally {
    control?.release();
    await rpc.close(); await sequenceSettled?.catch(() => {});
    await control?.close();
  }
}
export async function lifecycle(fixture, report) {
  report.failures = [];
  for (const fallback of [false, true]) {
    const key = fallback ? 'fallback' : 'event'; report[key] = {};
    try { await lifecycleCase(fixture, report[key], fallback); report[key].status = 'passed'; }
    catch (error) { report[key].status = 'failed'; report[key].error = error.stack ?? String(error); report.failures.push(report[key].error); }
  }
  assert.deepEqual(report.failures, [], 'Real foreground event and restoration cases must both pass');
}
