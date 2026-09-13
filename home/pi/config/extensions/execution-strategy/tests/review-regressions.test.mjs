import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { test } from 'node:test';
import { activeMessages, bindPacketEvidence, nativeMaterial } from '../native.mjs';
import { observedUsage } from '../packets.mjs';
import { finish, lane, ledgerFor, packetFor, planFor, policy, workspace } from './fixtures.mjs';

// Unit fixtures exercise the state machine; they are not native-child acceptance.
function begin(ledger, key, foregroundHistory) {
  const prepared = ledger.prepare(key, policy, { async: false });
  const a = ledger.latest(key);
  ledger.launch(`call-${a.id}`, prepared.input, policy, foregroundHistory);
  ledger.bindResult(a.toolCallId, { asyncId: `root-${a.id}`, background: true }, false);
  return a;
}
function completion(a, role = 'reviewer') {
  return { success: true, results: [{ runId: `child-${a.id}`, agent: a.agent, status: 'completed', exitCode: 0,
    finalOutput: `\`\`\`execution-packet\n${JSON.stringify(packetFor(a, role))}\n\`\`\``,
    messages: [{ role: 'toolResult', toolCallId: 'child-read', isError: false, content: [{ type: 'text', text: 'alpha' }] }] }] };
}
function writers() {
  const { a, b } = workspace(), plan = planFor(a, b);
  plan.lanes = [lane('writer-a', [a], 'writer', [], ['a']), lane('writer-b', [b], 'writer', [], ['b'])];
  return ledgerFor(plan);
}

test('foreground detached completion correlates the leaf and releases only after a genuine terminal callback shape', () => {
  for (const failed of [false, true]) {
    const ledger = writers(), a = begin(ledger, 'writer-a');
    const { dir } = workspace(), sessionFile = join(dir, 'child.jsonl');
    const packet = packetFor(a, 'writer');
    const entries = [{ type: 'session', id: 'child-session' },
      { id: 'read', parentId: null, type: 'message', message: { role: 'toolResult', toolCallId: 'child-read', isError: false, content: 'alpha' } },
      { id: 'reply', parentId: 'read', type: 'message', message: { role: 'assistant', stopReason: 'stop', content: `\`\`\`execution-packet\n${JSON.stringify(packet)}\n\`\`\`` } }];
    writeFileSync(sessionFile, entries.map(entry => JSON.stringify(entry)).join('\n'));
    ledger.nativeComplete(a.runId, { success: false, results: [{ runId: `child-${a.id}`, agent: a.agent, status: 'paused', detached: true, sessionFile, usage: { input: 5 } }] }, 'unit detached receipt');
    const event = { source: 'foreground', mode: 'single', taskIndex: 0, runId: a.childRunId, agent: a.agent, sessionFile, state: failed ? 'failed' : 'complete', success: !failed, exitCode: failed ? 1 : 0, summary: 'fixture failure detail' };
    for (const mismatch of [{ runId: a.runId }, { agent: 'unowned' }, { mode: 'parallel' }, { taskIndex: 1 }, { sessionFile: '/tmp/unowned.jsonl' }]) {
      assert.equal(ledger.nativeForegroundComplete({ ...event, ...mismatch }), false);
      assert.throws(() => ledger.prepare('writer-b', policy), /one writer/);
    }
    assert.equal(ledger.nativeForegroundComplete(event), true);
    assert.equal(a.status, failed ? 'failed' : 'complete');
    assert.equal(a.nativeTerminal, true);
    assert.equal(a.actual.usage.value, null, 'A partial receipt cannot invent final usage');
    assert.match(a.actual.metadataGap, /final usage/);
    if (failed) assert.equal(a.failure, event.summary);
    else { assert.equal(a.failure, undefined); ledger.consume(a.id, policy); }
    assert.equal(ledger.nativeForegroundComplete(event), false, 'Duplicate callback is idempotent');
    assert.ok(ledger.prepare('writer-b', policy));
  }
});

test('restored foreground ownership verifies native history and cannot invent packet coverage', () => {
  const { dir } = workspace(), historyPath = join(dir, 'foreground-history.json');
  const ledger = writers(), a = begin(ledger, 'writer-a', historyPath);
  const sessionFile = join(dir, 'missing-child-transcript.jsonl');
  ledger.nativeComplete(a.runId, { success: false, results: [{ runId: `child-${a.id}`, agent: a.agent, status: 'paused', detached: true, sessionFile }] }, 'unit detached receipt');
  const restored = new ledger.constructor(structuredClone(ledger.state));
  const child = { agent: a.agent, index: 0, status: 'completed', exitCode: 0, sessionFile };
  const run = { runId: a.childRunId, sessionId: a.parentSession, mode: 'single', children: [child] };
  const save = value => writeFileSync(historyPath, JSON.stringify({ version: 1, runs: [value] }));
  for (const invalid of [{ ...run, sessionId: 'foreign' }, { ...run, children: [child, child] }, { ...run, children: [{ ...child, exitCode: undefined }] }, { ...run, children: [{ ...child, status: 'paused' }] }]) {
    save(invalid); restored.reconcile();
    assert.notEqual(restored.latest('writer-a').nativeTerminal, true);
    assert.throws(() => restored.prepare('writer-b', policy), /one writer/);
  }
  save(run); restored.reconcile();
  const settled = restored.latest('writer-a');
  assert.equal(settled.nativeTerminal, true);
  assert.equal(settled.status, 'failed', 'Terminal process does not imply a valid packet');
  assert.match(settled.failure, /packet gap/);
  assert.equal(restored.gate(policy).pass, false);
  assert.ok(restored.prepare('writer-b', policy));
});

test('paused/detached writers retain ownership and can later reconcile terminal completion', () => {
  const ledger = writers(), a = begin(ledger, 'writer-a');
  ledger.nativeComplete(a.runId, { success: false, results: [{ runId: `child-${a.id}`, agent: a.agent, status: 'paused', detached: true, processTerminal: false }] }, 'unit paused receipt');
  assert.equal(a.status, 'paused'); assert.notEqual(a.nativeTerminal, true);
  assert.throws(() => ledger.prepare('writer-b', policy), /one writer/);
  assert.equal(ledger.gate(policy).pass, false);
  ledger.nativeComplete(a.runId, completion(a, 'writer'), 'unit later terminal receipt');
  assert.equal(a.status, 'complete'); assert.equal(a.nativeTerminal, true);
  ledger.consume(a.id, policy);
  assert.ok(ledger.prepare('writer-b', policy));
});

test('unknown/error receipts do not prove writer termination', () => {
  for (const mode of ['identity-gap', 'tool-error', 'terminal-gap']) {
    const ledger = writers(), p = ledger.prepare('writer-a', policy, { async: false });
    const a = ledger.latest('writer-a'); ledger.launch('call', p.input, policy);
    const data = mode === 'terminal-gap' ? { runId: 'root', results: [{ agent: 'worker', runId: 'child' }] } : {};
    ledger.bindResult('call', data, mode === 'tool-error');
    assert.equal(a.status, 'unknown', mode); assert.notEqual(a.nativeTerminal, true);
    assert.throws(() => ledger.prepare('writer-b', policy), /one writer/);
  }
});

test('non-reviewer blocker findings cannot disappear behind later passing coverage', () => {
  const { a, b } = workspace(), plan = planFor(a, b);
  plan.lanes.unshift(lane('writer', [a], 'writer', [], ['a']));
  plan.lanes.find(l => l.id === 'review-a').dependsOn = ['writer'];
  const ledger = ledgerFor(plan);
  const writer = finish(ledger, 'writer', p => p.findings.push({ id: 'open', obligation: 'a', severity: 'blocker', issue: 'Must resolve this finding', evidence: ['e1'] }));
  ledger.consume(writer.id, policy);
  assert.equal(ledger.state.findings.length, 1);
  for (const key of ['review-a', 'review-b']) ledger.consume(finish(ledger, key).id, policy);
  assert.equal(ledger.gate(policy).pass, false);
  assert.ok(ledger.gate(policy).gaps.some(g => g.includes(`${writer.id}/open`)));
});

test('only selected-branch tool results can substantiate a native packet', () => {
  const { dir } = workspace(), path = join(dir, 'child.jsonl');
  const tool = { role: 'toolResult', toolCallId: 'abandoned', isError: false, content: [{ type: 'text', text: 'alpha' }] };
  const entries = [{ type: 'session', id: 'child', version: 3 },
    { type: 'message', id: 'root', parentId: null, message: { role: 'user', content: 'Check' } },
    { type: 'message', id: 'sibling-a', parentId: 'root', message: tool },
    { type: 'message', id: 'sibling-b', parentId: 'root', message: { role: 'assistant', stopReason: 'stop', content: [{ type: 'text', text: 'selected branch' }] } }];
  writeFileSync(path, entries.map(e => JSON.stringify(e)).join('\n'));
  const material = nativeMaterial({ sessionFile: path }, 'parent');
  assert.equal(material.output, 'selected branch');
  assert.equal(material.messages.some(m => m.toolCallId === 'abandoned'), false);
  assert.throws(() => bindPacketEvidence({ evidence: [{ id: 'e', link: 'tool:abandoned', observation: 'alpha' }], coverage: [{ evidence: ['e'] }], findings: [], resolutions: [] }, material), /successful native child/);
  assert.throws(() => activeMessages([...entries, { id: 'cycle', parentId: 'cycle' }]), /ancestry/);
  assert.throws(() => activeMessages([...entries, { id: 'orphan', parentId: 'missing' }]), /ancestry/);
});

function transitive() {
  const { a, b } = workspace(), plan = planFor(a, b);
  plan.inputs = [{ id: 'contract', kind: 'contract', paths: [], value: 'v1' }];
  plan.obligations[0].inputs = ['contract']; plan.obligations[1].dependsOn = ['a'];
  plan.lanes[0].inputs = ['contract'];
  plan.lanes.push(lane('consumer', [b], 'discovery', ['review-b'], []));
  return ledgerFor(plan);
}
test('transitive obligation inputs invalidate launch, completion, consumption and dependency barriers', () => {
  const launchLedger = transitive(), prepared = launchLedger.prepare('review-b', policy, { async: false });
  assert.match(prepared.input.workflowScript, /contract/); // Relevant upstream assumptions are in the brief.
  launchLedger.updateInput('contract', 'v2');
  assert.throws(() => launchLedger.launch('call', prepared.input, policy), /stale/);

  const completionLedger = transitive(), a = begin(completionLedger, 'review-b');
  completionLedger.updateInput('contract', 'v2');
  completionLedger.nativeComplete(a.runId, completion(a), 'unit completion');
  assert.equal(a.status, 'failed'); assert.match(a.failure, /changed during review/);

  const consumeLedger = transitive(), b = finish(consumeLedger, 'review-b');
  consumeLedger.updateInput('contract', 'v2');
  assert.throws(() => consumeLedger.consume(b.id, policy), /stale/);

  const dependencyLedger = transitive(), c = finish(dependencyLedger, 'review-b');
  dependencyLedger.consume(c.id, policy); dependencyLedger.updateInput('contract', 'v2');
  assert.throws(() => dependencyLedger.consume(c.id, policy), /stale/);
  assert.throws(() => dependencyLedger.prepare('consumer', policy), /stale dependency/);
});

test('usage accepts numeric native costs and nested SDK costs without inventing missing usage', () => {
  assert.equal(observedUsage({ cost: 1.25, input: 9 }).value.cost, 1.25);
  assert.equal(observedUsage({ cost: { total: 2.5 } }).value.cost, 2.5);
  assert.equal(observedUsage({ cost: -1 }).value.cost, null);
  assert.equal(observedUsage({}).value.input, null);
  assert.equal(observedUsage(null).value, null);
});
