import assert from 'node:assert/strict';
import { writeFileSync, symlinkSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { nativeMaterial, ownedForeground } from '../native.mjs';
import { finish, ledgerFor, planFor, policy, workspace } from './fixtures.mjs';

// These are state-machine regressions, not native-child acceptance evidence.
const reply = text => ({ role: 'assistant', stopReason: 'stop', content: text });
const packet = '```execution-packet\n{"unitFixture":true}\n```';

test('file-only output uses verified child material, not the displayed pathname', () => {
  const messages = [reply(packet)];
  const row = { outputMode: 'file-only', finalOutput: 'Output saved to: /unowned/not-a-packet', messages };
  assert.equal(nativeMaterial(row, 'parent').output, packet);
  assert.equal(nativeMaterial({ finalOutput: row.finalOutput, messages }, 'parent').output, packet);
  assert.throws(() => nativeMaterial({ ...row, messages: [] }, 'parent'), /packet artifact unavailable/);
  assert.equal(nativeMaterial({ finalOutput: packet, messages: [reply('Saved report')] }, 'parent').output, packet);
});

test('file-only artifact fallback requires an explicit native-owned regular bounded artifact', () => {
  const { dir } = workspace(), savedOutputPath = join(dir, 'packet.md');
  writeFileSync(savedOutputPath, packet);
  const row = { outputMode: 'file-only', finalOutput: 'Output saved to: /unowned/ignored', savedOutputPath, messages: [reply('Saved report')] };
  assert.equal(nativeMaterial(row, 'parent').output, packet);
  const link = join(dir, 'symlink.md'); symlinkSync(savedOutputPath, link);
  assert.throws(() => nativeMaterial({ ...row, savedOutputPath: link }, 'parent'), /invalid native file-only/);
  writeFileSync(savedOutputPath, 'x'.repeat(128 * 1024 + 1));
  assert.throws(() => nativeMaterial(row, 'parent'), /invalid native file-only/);
});

test('file-only foreground and restored-history packets remain consumable with native tool evidence', () => {
  for (const mode of ['normal', 'event', 'restored-history']) {
    const { dir, a, b } = workspace(), ledger = ledgerFor(planFor(a, b));
    const sessionFile = join(dir, 'child.jsonl'), history = join(dir, 'foreground-history.json');
    // finish supplies a native-shaped ordinary receipt. Its packet is also persisted
    // as selected-branch child material before that receipt is bound.
    const attempt = finish(ledger, 'review-a', p => {
      writeFileSync(sessionFile, [
        { type: 'session', id: 'unit-child' },
        { type: 'message', id: 'read', parentId: null, message: { role: 'toolResult', toolCallId: 'child-read', isError: false, content: 'alpha' } },
        { type: 'message', id: 'reply', parentId: 'read', message: reply(`\`\`\`execution-packet\n${JSON.stringify(p)}\n\`\`\``) },
      ].map(entry => JSON.stringify(entry)).join('\n'));
    }, { sessionFile, messages: undefined, outputMode: 'file-only', finalOutput: 'Output saved to: /unowned/ignored', ...(mode === 'normal' ? {} : { detached: true, status: 'paused' }) });
    let target = ledger;
    if (mode === 'event') {
      assert.equal(attempt.status, 'paused');
      assert.equal(ledger.nativeForegroundComplete({ source: 'foreground', mode: 'single', taskIndex: 0, runId: attempt.childRunId, agent: attempt.agent, sessionFile, state: 'completed', success: true, exitCode: 0 }), true);
    }
    if (mode === 'restored-history') {
      attempt.foregroundHistory = history;
      writeFileSync(history, JSON.stringify({ version: 1, runs: [{ runId: attempt.childRunId, sessionId: attempt.parentSession, mode: 'single', children: [{ index: 0, agent: attempt.agent, sessionFile, status: 'completed', exitCode: 0, finalOutput: 'Output saved to: /unowned/ignored' }] }] }));
      target = new ledger.constructor(structuredClone(ledger.state)); target.reconcile();
    }
    assert.equal(target.latest('review-a').status, 'complete', mode);
    target.consume(attempt.id, policy);
    assert.equal(target.gate(policy).coverage.find(c => c.obligation === 'a').state, 'pass', mode);
  }
});

test('owned terminal history can supply a missing session locator, never replace an observed identity', () => {
  const { dir } = workspace(), foregroundHistory = join(dir, 'history.json');
  const attempt = { foregroundHistory, childRunId: 'child', parentSession: 'parent', agent: 'worker', actual: { sessionFile: null, launchContractDigest: 'owned-launch' } };
  const child = { index: 0, agent: 'worker', sessionFile: join(dir, 'child.jsonl'), launchContractDigest: 'owned-launch', status: 'failed', exitCode: 1 };
  const save = entry => writeFileSync(foregroundHistory, JSON.stringify({ version: 1, runs: [{ runId: 'child', sessionId: 'parent', mode: 'single', children: [entry] }] }));
  save(child); assert.equal(ownedForeground(attempt).child.sessionFile, child.sessionFile);
  assert.throws(() => ownedForeground({ ...attempt, actual: { ...attempt.actual, sessionFile: '/known/different.jsonl' } }), /identity mismatch/);
  for (const invalid of [{ ...child, launchContractDigest: 'foreign' }, { ...child, sessionFile: undefined }, { ...child, agent: 'foreign' }]) {
    save(invalid); assert.throws(() => ownedForeground(attempt), /identity mismatch/);
  }
});

test('current resolutions survive replacement coverage; stale resolutions return in the next brief', () => {
  const { a, b } = workspace(), plan = planFor(a, b);
  plan.inputs = [{ id: 'api', kind: 'contract', paths: [], value: 'v1' }];
  plan.obligations[0].inputs = ['api']; plan.lanes[0].inputs = ['api'];
  const ledger = ledgerFor(plan);
  const opened = finish(ledger, 'review-a', p => p.findings.push({ id: 'defect', obligation: 'a', severity: 'blocker', issue: 'Check this regression', evidence: ['e1'] }));
  ledger.consume(opened.id, policy); ledger.consume(finish(ledger, 'review-b').id, policy);
  const finding = ledger.state.findings[0];
  const resolve = p => p.resolutions.push({ finding: finding.id, evidence: ['e1'], explanation: 'Independent current regression evidence' });
  ledger.consume(finish(ledger, 'review-a', resolve).id, policy);
  assert.equal(ledger.gate(policy).pass, true);
  const originalResolution = finding.resolution.attempt;
  ledger.consume(finish(ledger, 'review-a').id, policy);
  assert.equal(ledger.gate(policy).pass, true, 'Unchanged valid resolution need not be duplicated by another reviewer');
  assert.equal(finding.resolution.attempt, originalResolution);
  const unrelated = ledger.gate(policy).coverage.find(c => c.obligation === 'b');
  for (const mutate of [() => writeFileSync(a, 'alpha revised'), () => ledger.updateInput('api', 'v2')]) {
    mutate(); assert.equal(ledger.gate(policy).pass, false);
    const preview = new ledger.constructor(structuredClone(ledger.state));
    const prepared = preview.prepare('review-a', policy, { async: false });
    assert.ok(prepared.input.workflowScript.includes(finding.id), 'Stale resolution must be visible to its assigned reviewer');
    ledger.consume(finish(ledger, 'review-a', resolve).id, policy);
    assert.equal(ledger.gate(policy).pass, true);
    assert.notEqual(finding.resolution.attempt, originalResolution);
    assert.deepEqual(ledger.gate(policy).coverage.find(c => c.obligation === 'b'), unrelated);
  }
});
