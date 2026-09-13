import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { validatePlan } from '../plan.mjs';
import { isOwner, readPolicy, STATE_ENTRY } from '../policy.mjs';
import { emptyState } from '../ledger.mjs';
import { restore, statePatch } from '../persistence.mjs';
import { hashScope, pathKey } from '../workspace.mjs';
import { observedUsage } from '../packets.mjs';
import { bindPacketEvidence, nativeMaterial } from '../native.mjs';
import { finish, lane, ledgerFor, obligation, packetFor, planFor, policy, workspace } from './fixtures.mjs';

const setup = () => { const w = workspace(); return { ...w, plan: planFor(w.a, w.b), ledger: ledgerFor(planFor(w.a, w.b)) }; };
test('native profile marker refresh; missing/malformed metadata ineffective; child owner fails closed', () => {
  const { dir } = workspace(); const profiles = join(dir, 'profiles/pi-subagents'); mkdirSync(profiles, { recursive: true });
  const branch = [{ id: 'marker1', type: 'custom', customType: 'pi-subagents-profile', data: { version: 1, name: 'complex' } }];
  assert.equal(readPolicy([], dir, true).effective, false);
  writeFileSync(join(profiles, 'complex.json'), JSON.stringify({ subagents: { agentOverrides: {} } }));
  assert.match(readPolicy(branch, dir, true).reason, /ineffective/);
  writeFileSync(join(profiles, 'complex.json'), JSON.stringify({ subagents: { agentOverrides: {}, executionStrategy: policy.config } }));
  assert.equal(readPolicy(branch, dir, true).effective, true);
  assert.equal(readPolicy(branch, dir, false).owner, false);
  const bad = { ...policy.config, model: 'must-not-be-used' };
  writeFileSync(join(profiles, 'complex.json'), JSON.stringify({ subagents: { agentOverrides: {}, executionStrategy: bad } }));
  assert.match(readPolicy(branch, dir, true).reason, /unknown/);
  assert.equal(isOwner({}), true); assert.equal(isOwner({ PI_SUBAGENT_CHILD: '1' }), false);
  assert.equal(isOwner({ PI_SUBAGENT_DEPTH: 'invalid' }), false);
  assert.equal(isOwner({ PI_SUBAGENT_PARENT_SESSION: 'self' }, 'self'), true);
  assert.equal(isOwner({ PI_SUBAGENT_PARENT_SESSION: 'foreign' }, 'self'), false);
  assert.equal(isOwner({ PI_SUBAGENT_PARENT_SESSION: 'self', PI_SUBAGENT_CHILD: '1' }, 'self'), false);
  assert.equal(isOwner({ PI_SUBAGENT_PARENT_SESSION: 'self', PI_SUBAGENT_DEPTH: '1' }, 'self'), false);
  assert.equal(readPolicy([...branch, { ...branch[0], data: { version: 0, name: 'complex' } }], dir, true).effective, false);
});
test('cycles, duplicate stable IDs, undeclared input, unsafe overlap rejected', () => {
  const { a, plan } = setup();
  assert.throws(() => validatePlan({ ...plan, lanes: [...plan.lanes, plan.lanes[0]] }), /duplicate/);
  const cycle = structuredClone(plan); cycle.lanes[0].dependsOn = ['review-b']; cycle.lanes[1].dependsOn = ['review-a'];
  assert.throws(() => validatePlan(cycle), /cycle/);
  const overlap = structuredClone(plan); overlap.lanes.push(lane('writer', [a], 'writer', [], ['a']));
  assert.throws(() => validatePlan(overlap), /unsafe scope overlap/);
  const wrong = structuredClone(plan); wrong.lanes[0].inputs = ['missing']; assert.throws(() => validatePlan(wrong), /unknown input/);
  const contractCycle = structuredClone(plan); contractCycle.obligations[0].dependsOn = ['b']; contractCycle.obligations[1].dependsOn = ['a'];
  assert.throws(() => validatePlan(contractCycle), /cycle/);
});
test('canonical aliases overlap; nested symlinks and unreviewed writer scopes fail closed', () => {
  const { dir, a, b, plan } = setup(); const alias = join(dir, 'alias'); symlinkSync(a, alias);
  assert.equal(pathKey(alias), pathKey(a)); assert.throws(() => hashScope(dir), /symlink/);
  plan.lanes.push(lane('writer', [join(dir, 'unreviewed')], 'writer', [], ['a']));
  assert.throws(() => validatePlan(plan), /lacks requirement/);
  assert.notEqual(hashScope(a), hashScope(b));
});
test('prepare returns only exact supported native fields; normal promotion, explicit async and foregroundOnly', async () => {
  const { ledger } = setup();
  const p = ledger.prepare('review-a', policy); assert.deepEqual(Object.keys(p.input).sort(), ['context', 'workflowScript']);
  assert.match(p.input.workflowScript, /^return runs.run\("review-a", /);
  let observed;
  await new Function('runs', p.input.workflowScript)({ run: (key, input) => { observed = { key, input }; return Promise.resolve(); } });
  assert.deepEqual(Object.keys(observed.input).sort(), ['agent', 'task']);
  assert.match(observed.input.task, /attempt/);
  ledger.launch('tool', { ...p.input, async: true }, policy);
  assert.equal(ledger.latest('review-a').status, 'calling');
  assert.throws(() => ledger.launch('tool2', { ...p.input, async: true }, policy), /already used/);
  const other = setup().ledger; const f = other.prepare('review-a', policy, { foregroundOnly: true });
  assert.equal(f.input.async, false); assert.equal(f.input.foregroundOnly, true);
  other.launch('foreground', f.input, policy);
  assert.throws(() => setup().ledger.prepare('review-a', { ...policy, owner: false }), /owner/);
  assert.throws(() => setup().ledger.prepare('review-a', policy, { foregroundOnly: true, async: true }), /conflicts/);
});
test('unmet dependency launch/preparation, active one-writer and stale preparation rejected', () => {
  const { a, b, plan } = setup();
  plan.lanes = [lane('writer-a', [a], 'writer', [], ['a']), lane('writer-b', [b], 'writer', [], ['b']), lane('review-a', [a], 'reviewer', ['writer-a'], ['a'])];
  const ledger = ledgerFor(plan);
  assert.throws(() => ledger.prepare('review-a', policy), /unmet dependency/);
  const p = ledger.prepare('writer-a', policy, { async: false });
  assert.throws(() => ledger.prepare('writer-b', policy), /one writer/);
  writeFileSync(a, 'new revision'); assert.throws(() => ledger.launch('call', p.input, policy), /stale/);
});
test('unplanned launches remain unowned and cannot provide packets or transfer savings', () => {
  const { ledger, a } = setup();
  ledger.observeDiscovery('read-before', a, 'read');
  ledger.launch('unplanned', { workflowScript: 'return 3' }, policy);
  ledger.bindResult('unplanned', { runId: 'unowned-run', results: [] }, false);
  assert.equal(ledger.state.unknown[0].status, 'unowned-result');
  assert.equal(ledger.nativeComplete('unowned-run', { results: [] }, 'fixture'), false);
  assert.throws(() => ledger.consume('unplanned', policy), /authentic/);
  const p = ledger.prepare('review-a', policy, { async: false }); ledger.launch('planned', p.input, policy);
  assert.deepEqual(ledger.latest('review-a').parentDiscoveryOverlap, ['read-before']);
});
test('authentic native fixture packet consumption, observed usage unknowns and complete coverage', () => {
  const { ledger } = setup();
  assert.equal(ledger.gate(policy).pass, false);
  const a = finish(ledger, 'review-a'); assert.equal(a.status, 'complete');
  assert.equal(a.actual.model, null); assert.equal(a.actual.usage.value, null);
  assert.equal(ledger.gate(policy).pass, false); ledger.consume(a.id, policy);
  const b = finish(ledger, 'review-b', () => {}, { model: 'provider/child', thinking: 'high', usage: { input: 10, output: 20 } });
  ledger.consume(b.id, policy); assert.equal(ledger.gate(policy).pass, true); assert.equal(ledger.gate(policy).workflowAcceptance, false);
  assert.equal(b.actual.usage.value.cacheRead, null); assert.equal(b.actual.usage.value.input, 10);
  assert.equal(ledger.state.coverage[0].childRunId, a.childRunId);
  assert.equal(ledger.latest('review-a').packet.evidence[0].proof.toolCallId, 'child-read');
});
test('affected-only source re-review keeps unrelated current coverage', () => {
  const { ledger, a } = setup(); ledger.consume(finish(ledger, 'review-a').id, policy); ledger.consume(finish(ledger, 'review-b').id, policy);
  writeFileSync(a, 'changed');
  let gate = ledger.gate(policy); assert.equal(gate.pass, false);
  assert.deepEqual(gate.coverage.map(c => c.state), ['stale', 'pass']);
  ledger.consume(finish(ledger, 'review-a').id, policy); gate = ledger.gate(policy); assert.equal(gate.pass, true);
});
test('declared dependency/contract/assumption changes invalidate dependents, not unrelated obligations', () => {
  const { a, b, plan } = setup();
  plan.inputs = [{ id: 'api', kind: 'contract', paths: [], value: 'v1' }, { id: 'platform', kind: 'assumption', paths: [a], value: 'linux' }];
  plan.obligations[0].inputs = ['api', 'platform']; plan.lanes[0].inputs = ['api', 'platform'];
  const ledger = ledgerFor(plan);
  ledger.consume(finish(ledger, 'review-a').id, policy); ledger.consume(finish(ledger, 'review-b').id, policy);
  ledger.updateInput('api', 'v2'); assert.deepEqual(ledger.gate(policy).coverage.map(c => c.state), ['stale', 'pass']);
  ledger.consume(finish(ledger, 'review-a').id, policy); ledger.updateInput('platform', 'darwin');
  assert.deepEqual(ledger.gate(policy).coverage.map(c => c.state), ['stale', 'pass']);
  const withDep = planFor(a, b); withDep.lanes[0].dependsOn = ['review-b'];
  const depLedger = ledgerFor(withDep); depLedger.consume(finish(depLedger, 'review-b').id, policy); depLedger.consume(finish(depLedger, 'review-a').id, policy);
  writeFileSync(b, 'dependency changed'); assert.deepEqual(depLedger.gate(policy).coverage.map(c => c.state), ['stale', 'stale']);
});
test('missing, partial, failed, wrong reviewer, forged links/packet paths and stale packet cannot pass', () => {
  for (const mutate of [p => { p.coverage[0].verdict = 'partial'; }, p => { p.coverage = []; }]) {
    const { ledger } = setup(); ledger.consume(finish(ledger, 'review-a', mutate).id, policy);
    assert.equal(ledger.gate(policy).pass, false);
  }
  for (const extra of [{ agent: 'worker' }, { exitCode: 1 }, { finalOutput: '/tmp/parent-forged.json' }, { messages: [] }]) {
    const { ledger } = setup(); const a = finish(ledger, 'review-a', () => {}, extra);
    assert.notEqual(a.status, 'complete'); assert.throws(() => ledger.consume(a.id, policy));
  }
  const { ledger, a } = setup(); const result = finish(ledger, 'review-a', p => { p.evidence[0].link = 'tool:forged'; });
  assert.match(result.failure, /native child tool results/);
  const fresh = setup().ledger; const valid = finish(fresh, 'review-a');
  writeFileSync(fresh.lane('review-a').scopes[0], 'after review'); assert.throws(() => fresh.consume(valid.id, policy), /stale/);
  assert.equal(observedUsage(undefined).value, null); assert.equal(observedUsage({ input: 0 }).value.output, null);
});
test('findings remain open until evidence-backed independent current resolution; parent cannot resolve', () => {
  const { ledger } = setup();
  const first = finish(ledger, 'review-a', p => { p.findings = [{ id: 'bug', obligation: 'a', severity: 'blocker', issue: 'Broken contract', evidence: ['e1'] }]; });
  ledger.consume(first.id, policy); ledger.consume(finish(ledger, 'review-b').id, policy);
  assert.equal(ledger.gate(policy).pass, false);
  const finding = ledger.state.findings[0].id;
  const resolved = finish(ledger, 'review-a', p => { p.resolutions = [{ finding, evidence: ['e1'], explanation: 'Verified fixed with child tool output' }]; });
  ledger.consume(resolved.id, policy); assert.equal(ledger.gate(policy).pass, true);
  assert.equal(ledger.state.findings[0].resolution.childRunId, resolved.childRunId);
});
test('parent integration separated from child work and cannot be prepared or grant review', () => {
  const { a, b, plan } = setup(); plan.lanes = [lane('integrate', [a], 'integration', [], ['a']), lane('review-a', [a], 'reviewer', ['integrate'], ['a']), lane('review-b', [b], 'reviewer', [], ['b'])];
  const ledger = ledgerFor(plan); assert.throws(() => ledger.prepare('integrate', policy), /parent integration/);
  ledger.parent('integrate', 'Merged', ['tool:parent-build']); assert.equal(ledger.state.coverage.length, 0);
  assert.match(ledger.state.parentWork[0].provenance, /never independent/);
  ledger.consume(finish(ledger, 'review-a').id, policy); ledger.consume(finish(ledger, 'review-b').id, policy); assert.equal(ledger.gate(policy).pass, true);
});
test('branch index patches reconstruct only current path; other session cannot inherit ownership', () => {
  const { ledger } = setup(); const zero = emptyState('parent-session');
  const first = statePatch(zero, ledger.state); const before = structuredClone(ledger.state);
  finish(ledger, 'review-a'); ledger.state.revision++;
  const second = statePatch(before, ledger.state);
  const entries = [first, second].map(data => ({ type: 'custom', customType: STATE_ENTRY, data }));
  assert.deepEqual(restore(entries, 'parent-session'), ledger.state);
  assert.equal(restore(entries.slice(0, 1), 'parent-session').attempts.length, 0);
  assert.equal(restore(entries, 'child-session').plan, null);
  assert.ok(!Object.hasOwn(second, 'plan')); assert.equal(second.arrays.attempts.length, 1);
});
test('native async result correlation and duplicate completion idempotence', () => {
  const { ledger } = setup(); const p = ledger.prepare('review-a', policy); const a = ledger.latest('review-a');
  ledger.launch('async-call', { ...p.input, async: true }, policy);
  ledger.bindResult('async-call', { asyncId: 'native-root', background: true }, false);
  const packet = packetFor(a); const output = `\`\`\`execution-packet\n${JSON.stringify(packet)}\n\`\`\``;
  const native = { success: true, results: [{ runId: 'native-leaf', workflowKey: a.lane, agent: 'reviewer', success: true, output, messages: [{ role: 'toolResult', toolCallId: 'child-read', isError: false, content: [{ type: 'text', text: 'alpha' }] }] }] };
  assert.equal(ledger.nativeComplete('native-root', native, 'unit native event fixture'), true);
  assert.equal(ledger.nativeComplete('native-root', native, 'duplicate'), false);
  ledger.consume(a.id, policy); assert.equal(ledger.latest('review-a').childRunId, 'native-leaf');
});
test('native owned transcript locators provide real evidence, not caller-selected packet files', () => {
  const { dir } = workspace(); const sessionFile = join(dir, 'native-child.jsonl');
  const messages = [{ role: 'toolResult', toolCallId: 'actual', isError: false, content: [{ type: 'text', text: 'observed alpha' }] }];
  writeFileSync(sessionFile, [JSON.stringify({ type: 'session', id: 'child' }), ...messages.map((message, i) => JSON.stringify({ type: 'message', id: `m${i}`, parentId: i ? `m${i - 1}` : null, message }))].join('\n'));
  const material = nativeMaterial({ sessionFile, finalOutput: 'actual returned text' }, 'parent');
  assert.equal(material.output, 'actual returned text'); assert.ok(material.transcriptHash);
  const packet = { evidence: [{ id: 'one', link: 'tool:actual', observation: 'observed alpha' }], coverage: [{ evidence: ['one'] }], findings: [], resolutions: [] };
  bindPacketEvidence(packet, material); assert.ok(packet.evidence[0].proof);
  assert.throws(() => nativeMaterial({ sessionFile }, 'child'), /identity/);
});
test('async metadata gap is explicit; verified owned status/session reconciles missed completion', () => {
  const { ledger, dir } = setup(); const p = ledger.prepare('review-a', policy); const a = ledger.latest('review-a');
  ledger.launch('owned-async', { ...p.input, async: true }, policy);
  ledger.bindResult('owned-async', { asyncId: 'owned-root', asyncDir: dir, background: true }, false, '/parent/session.jsonl');
  const packet = packetFor(a); const output = `\`\`\`execution-packet\n${JSON.stringify(packet)}\n\`\`\``;
  const child = join(dir, 'child.jsonl');
  writeFileSync(child, [JSON.stringify({ type: 'session', id: 'native-child-session' }), JSON.stringify({ type: 'message', id: 'read', parentId: null, message: { role: 'toolResult', toolCallId: 'child-read', isError: false, content: [{ type: 'text', text: 'alpha' }] } }), JSON.stringify({ type: 'message', id: 'answer', parentId: 'read', message: { role: 'assistant', stopReason: 'stop', content: [{ type: 'text', text: output }] } })].join('\n'));
  const status = { runId: 'owned-root', sessionId: '/parent/session.jsonl', state: 'complete', steps: [{ runId: 'owned-leaf', workflowKey: 'review-a', agent: 'reviewer', status: 'completed', sessionFile: child, model: 'native/child-model', thinking: 'high' }] };
  writeFileSync(join(dir, 'status.json'), JSON.stringify({ ...status, sessionId: 'foreign' }));
  ledger.reconcile(); assert.match(a.reconciliationGap, /ownership mismatch/); assert.equal(a.status, 'running');
  writeFileSync(join(dir, 'status.json'), JSON.stringify(status));
  ledger.reconcile(); assert.equal(a.status, 'complete'); ledger.consume(a.id, policy);
  assert.equal(a.actual.model, 'native/child-model'); assert.equal(a.actual.usage.value, null); assert.match(a.actual.metadataProvenance, /verified owned status/);
});
