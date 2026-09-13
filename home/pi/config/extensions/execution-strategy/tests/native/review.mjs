import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { launchRpc, success, rejected, textOf } from './rpc.mjs';

export const strategy = rpc => async input => success(await rpc.call('execution_strategy', input));
export const records = file => fs.readFileSync(file, 'utf8').trim().split('\n').map(line => JSON.parse(line));
export function inspectChild(attempt, rpc, { packet = true } = {}) {
  assert.ok(attempt.actual.sessionFile, JSON.stringify(attempt));
  const entries = records(attempt.actual.sessionFile);
  const identity = entries.find(entry => entry.customType === 'native-fixture-identity')?.data;
  assert.ok(identity); assert.notEqual(identity.pid, rpc.pid); assert.equal(identity.child, '1');
  assert.equal(identity.provider, 'native-acceptance-fixture');
  const results = entries.filter(entry => entry.type === 'message' && entry.message.role === 'toolResult').map(entry => entry.message);
  assert.ok(results.some(result => result.toolName === 'read' && !result.isError));
  if (packet) assert.ok(entries.some(entry => entry.type === 'message' && entry.message.role === 'assistant' && textOf(entry.message).includes('```execution-packet')));
  return { identity, sessionFile: attempt.actual.sessionFile, results };
}
export async function transfer(rpc, lane, target) {
  const api = strategy(rpc), prepared = await api({ action: 'prepare', lane, foregroundOnly: true });
  const launched = await rpc.call('subagent', prepared.input);
  const state = await api({ action: 'status' });
  const attempt = state.attempts.find(attempt => attempt.id === prepared.attempt);
  const row = { prepared, launched, attempt }; target.push(row);
  success(launched); assert.equal(attempt.status, 'complete', JSON.stringify(attempt));
  assert.equal(attempt.consumed, false); assert.ok(attempt.packetHash);
  row.child = inspectChild(attempt, rpc);
  row.consumed = await api({ action: 'consume', attempt: prepared.attempt });
  for (const evidence of row.consumed.packet.evidence) {
    const result = row.child.results.find(result => `tool:${result.toolCallId}` === evidence.link);
    assert.ok(result && !result.isError && textOf(result).includes(evidence.observation), JSON.stringify(evidence));
  }
  return row;
}
export const coverageById = gate => Object.fromEntries(gate.coverage.map(row => [row.obligation, row]));

export async function review(fixture, report) {
  const rpc = launchRpc(fixture), api = strategy(rpc);
  report.transfers = []; report.checks = [];
  const a = join(fixture.root, 'work/a.mjs'), b = join(fixture.root, 'work/b.mjs'), c = join(fixture.root, 'work/c.mjs');
  const dependency = join(fixture.root, 'dependency.txt');
  const source = marker => `export const increment = value => value + 1; // review:${marker}\n`;
  // These are actual fixture source/input revisions, never child packets or tool results.
  fs.writeFileSync(a, source('missing')); fs.writeFileSync(b, 'export const unrelated = true;\n');
  fs.writeFileSync(c, 'export const dependent = "increment caller";\n'); fs.writeFileSync(dependency, 'api revision 1\n');
  const obligations = [
    { id: 'increment', kind: 'requirement', description: 'Positive increment', scopes: [a], inputs: ['api', 'assumption'], dependsOn: [] },
    { id: 'negative', kind: 'risk', description: 'Negative input coverage', scopes: [a], inputs: ['api', 'assumption'], dependsOn: [] },
    { id: 'unrelated', kind: 'requirement', description: 'Unrelated independent behavior', scopes: [b], inputs: [], dependsOn: [] },
    { id: 'caller', kind: 'requirement', description: 'Caller follows increment dependency', scopes: [c], inputs: [], dependsOn: ['increment'] },
  ];
  const lanes = [
    ['review-a', [a], ['increment', 'negative'], ['api', 'assumption']],
    ['review-b', [b], ['unrelated'], []],
    ['review-c', [c, a], ['caller'], ['api', 'assumption']],
  ].map(([id, scopes, assigned, inputs]) => ({ id, role: 'reviewer', owner: 'child', agent: 'reviewer', access: 'read', goal: 'Independently inspect assigned local fixture files; report evidence, gaps and findings without edits', constraints: ['Read-only offline deterministic fixture'], scopes, dependsOn: [], obligations: assigned, inputs }));
  lanes.push({ id: 'integrate', role: 'integration', owner: 'parent', access: 'read', goal: 'Integrate authentic consumed child packets', constraints: ['Never author child observations'], scopes: [a, b, c], dependsOn: ['review-a', 'review-b', 'review-c'], obligations: obligations.map(row => row.id), inputs: ['api', 'assumption'] });
  report.plan = { workflow: 'native-fixture-review', goal: 'Actual independent native review and affected-only revision coverage', inputs: [{ id: 'api', kind: 'dependency', paths: [dependency], value: 'v1' }, { id: 'assumption', kind: 'assumption', paths: [], value: 'integers' }], obligations, lanes };
  const gate = async label => { const value = await api({ action: 'gate' }); report.checks.push({ label, ...value }); return value; };
  const integrate = () => api({ action: 'parent', lane: 'integrate', conclusion: 'Integrated consumed independent native packets', evidence: report.transfers.map(row => `native:${row.attempt.childRunId};packet:${row.attempt.packetHash}`) });
  try {
    await rpc.request('prompt', { message: '/subagents-load-profile max' });
    await api({ action: 'plan', plan: report.plan });
    assert.equal((await gate('no reviewers')).pass, false);
    await transfer(rpc, 'review-a', report.transfers);
    await transfer(rpc, 'review-b', report.transfers);
    await transfer(rpc, 'review-c', report.transfers);
    await integrate();
    const missing = await gate('risk omitted');
    assert.equal(coverageById(missing).increment.state, 'pass');
    assert.equal(coverageById(missing).negative.state, 'missing'); assert.equal(missing.pass, false);
    const retained = coverageById(missing).unrelated;
    for (const marker of ['partial', 'blocker']) {
      fs.writeFileSync(a, source(marker));
      await transfer(rpc, 'review-a', report.transfers);
      const result = await gate(marker);
      assert.equal(coverageById(result).negative.state, marker === 'partial' ? 'partial' : 'fail');
      assert.equal(result.pass, false); assert.deepEqual(coverageById(result).unrelated, retained);
    }
    report.openFinding = (await api({ action: 'status' })).findings[0];
    assert.equal(report.openFinding.severity, 'blocker'); assert.ok(!report.openFinding.resolution);
    fs.writeFileSync(a, source('pass'));
    const fixed = await transfer(rpc, 'review-a', report.transfers);
    assert.equal(fixed.consumed.packet.resolutions[0].finding, report.openFinding.id);
    await transfer(rpc, 'review-c', report.transfers); await integrate();
    assert.equal((await gate('resolved')).pass, true);
    report.resolvedFinding = (await api({ action: 'status' })).findings[0];
    assert.equal(report.resolvedFinding.resolution.childRunId, fixed.attempt.childRunId);
    assert.notEqual(report.resolvedFinding.childRunId, fixed.attempt.childRunId);
    for (const revision of ['source', 'dependency-file', 'dependency-value', 'assumption']) {
      if (revision === 'source') fs.appendFileSync(a, '// actual source revision\n');
      if (revision === 'dependency-file') fs.writeFileSync(dependency, 'api revision 2\n');
      if (revision === 'dependency-value') await api({ action: 'input', input: 'api', value: 'v2' });
      if (revision === 'assumption') await api({ action: 'input', input: 'assumption', value: 'finite integers' });
      const invalidated = await gate(revision);
      assert.equal(invalidated.pass, false);
      for (const id of ['increment', 'negative', 'caller']) assert.equal(coverageById(invalidated)[id].state, 'stale', revision + '/' + id);
      assert.deepEqual(coverageById(invalidated).unrelated, retained);
      const prepared = await api({ action: 'prepare', lane: 'review-a', foregroundOnly: true });
      const launched = await rpc.call('subagent', prepared.input); success(launched);
      const attempt = (await api({ action: 'status' })).attempts.find(row => row.id === prepared.attempt);
      const child = inspectChild(attempt, rpc);
      report.unconsumed = rejected(await rpc.call('execution_strategy', { action: 'parent', lane: 'integrate', conclusion: 'Premature', evidence: ['unconsumed'] }), /unmet dependency/);
      const consumed = await api({ action: 'consume', attempt: attempt.id });
      report.transfers.push({ prepared, launched, attempt, child, consumed });
      await transfer(rpc, 'review-c', report.transfers); await integrate();
      const restored = await gate(revision + ' re-reviewed');
      assert.deepEqual(coverageById(restored).unrelated, retained);
    }
    assert.equal(new Set(report.transfers.map(row => row.attempt.childRunId)).size, report.transfers.length);
    await rpc.request('prompt', { message: '/native-fixture-reload' });
    // Run every revision case before surfacing any frozen-core stale-resolution defect.
    for (const check of report.checks.filter(row => row.label.endsWith(' re-reviewed'))) assert.equal(check.pass, true, JSON.stringify(check));
    report.restored = await api({ action: 'status' }); assert.equal(report.restored.review.pass, true);
    report.boundary = 'Actual Pi RPC, native independent child processes and native read evidence. Source and input revisions are real fixture files/strategy calls. Scripted model decisions are structural fixtures, not semantic production review. Native acceptance and Auto guard remain enabled.';
  } finally { await rpc.close(); }
}
