import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { launchRpc, parentTuple, branchMarker, success, rejected, textOf } from './rpc.mjs';
import { nativeDir } from './fixture.mjs';

async function identity(rpc) {
  const { entries } = await rpc.request('get_entries');
  const info = entries.findLast(entry => entry.customType === 'native-fixture-identity').data;
  assert.equal(info.provider, 'native-acceptance-fixture');
  const tool = info.tools.find(tool => tool.name === 'subagent');
  assert.ok(tool.sourceInfo.path.startsWith(nativeDir + '/'), JSON.stringify(tool));
  assert.notEqual(tool.sourceInfo.source, 'sdk');
  return info;
}

async function inspectProfile(rpc, fixture, name) {
  assert.equal(await branchMarker(rpc), name);
  const status = success(await rpc.call('execution_strategy', { action: 'status' }));
  assert.equal(status.policy.effective, true, JSON.stringify(status.policy));
  assert.equal(status.policy.profile, name);
  assert.equal(status.policy.config.delegation, fixture.originals[name].subagents.executionStrategy.delegation);
  const list = await rpc.call('subagent', { action: 'list' }); success(list);
  const roles = {};
  for (const role of ['worker', 'reviewer', 'scout', 'lookup']) {
    const got = await rpc.call('subagent', { action: 'get', agent: role }); success(got);
    const output = textOf(got);
    const expected = fixture.originals[name].subagents.agentOverrides[role];
    assert.ok(output.includes(`Model: ${expected.model}`), `${name}/${role}: ${output}`);
    assert.ok(output.includes(`Thinking: ${expected.thinking}`), `${name}/${role}: ${output}`);
    roles[role] = { toolCallId: got.toolCallId, output, model: expected.model, thinking: expected.thinking };
  }
  const { entries } = await rpc.request('get_entries');
  const guidance = entries.findLast(entry => entry.customType === 'native-fixture-context')?.data.guidance ?? [];
  return { name, policy: status.policy, guidance, roles, listCallId: list.toolCallId, list: textOf(list), parent: parentTuple(await rpc.request('get_state')) };
}

export async function profiles(fixture, report) {
  const settings = fs.readFileSync(join(fixture.agent, 'settings.json'));
  const expectedParent = { provider: 'native-acceptance-fixture', model: 'parent-scripted', thinking: 'high' };
  report.checks = [];
  let rpc = launchRpc(fixture);
  try {
    report.identity = await identity(rpc);
    const commands = await rpc.request('get_commands');
    assert.ok(commands.commands.some(command => command.name === 'subagents-load-profile'));
    assert.deepEqual(parentTuple(await rpc.request('get_state')), expectedParent);
    for (const name of ['simple', 'complex', 'max']) {
      await rpc.request('prompt', { message: `/subagents-load-profile ${name}` });
      const selected = await inspectProfile(rpc, fixture, name);
      assert.deepEqual(selected.parent, expectedParent);
      await rpc.request('prompt', { message: '/native-fixture-reload' });
      const reloaded = await inspectProfile(rpc, fixture, name);
      assert.deepEqual(reloaded.parent, expectedParent);
      assert.deepEqual(reloaded.policy, selected.policy);
      report.checks.push({ selected, reloaded });
    }
    assert.equal(new Set(report.checks.map(check => check.selected.roles.worker.model)).size, 3);
    const from = rpc.events.length;
    await rpc.request('prompt', { message: '/subagents-load-profile invalid' });
    assert.ok(rpc.events.slice(from).some(event => event.method === 'notify' && event.notifyType === 'error'));
    report.invalid = await inspectProfile(rpc, fixture, 'max');
    assert.deepEqual(report.invalid.parent, expectedParent);
    assert.equal(rpc.events.filter(event => event.method === 'confirm').length, 0, 'Parent-model prompt regression');
    assert.equal(rpc.events.filter(event => event.type === 'extension_error').length, 0);
    await rpc.close(); rpc = launchRpc(fixture);
    report.restored = await inspectProfile(rpc, fixture, 'max');
    assert.deepEqual(report.restored.parent, expectedParent);
    assert.deepEqual(fs.readFileSync(join(fixture.agent, 'settings.json')), settings);
    report.isolatedSettingsUnchanged = true;
    report.boundary = 'Actual copied live profiles and native get/list discovery; deterministic parent only, no child model execution in profiles mode.';
    // Metadata changes are insufficient if the actual parent is misclassified as a child.
    for (const check of [...report.checks.flatMap(row => [row.selected, row.reloaded]), report.restored]) {
      assert.equal(check.policy.owner, true, `Native parent lacks orchestration authority: ${JSON.stringify(check.policy)}`);
      assert.ok(check.guidance.some(line => line.startsWith(`Execution strategy (${check.name}):`)), `Provider did not receive effective ${check.name} strategy guidance`);
    }
  } finally { await rpc.close(); }
}

function makePlan(fixture) {
  const work = join(fixture.root, 'work'), other = join(fixture.root, 'other');
  for (const root of [work, other]) {
    fs.mkdirSync(root, { recursive: true });
    fs.writeFileSync(join(root, 'counter.mjs'), 'export const increment = value => value;\n');
  }
  const obligations = [['counter', work], ['other', other]].map(([id, scope]) => ({ id, kind: 'requirement', description: 'Counter increments positive and negative inputs', scopes: [scope], inputs: ['contract'], dependsOn: [] }));
  const lanes = obligations.flatMap(obligation => [
    { id: `write-${obligation.id}`, role: 'writer', owner: 'child', agent: 'worker', access: 'write', goal: 'Implement increment(value) = value + 1 and add counter.test.mjs with positive and negative assertions. Validate the test through the native bash tool.', constraints: ['Only the assigned fixture scope; no network, stage or commit'], scopes: obligation.scopes, dependsOn: [], obligations: [obligation.id], inputs: ['contract'] },
    { id: `review-${obligation.id}`, role: 'reviewer', owner: 'child', agent: 'reviewer', access: 'read', goal: 'Do not modify any files. Return findings only. Independently inspect counter.mjs and counter.test.mjs for positive and negative increment behavior.', constraints: ['Read-only fixture reviewer; no network'], scopes: obligation.scopes, dependsOn: [`write-${obligation.id}`], obligations: [obligation.id], inputs: ['contract'] },
  ]);
  lanes.push({ id: 'integrate', role: 'integration', owner: 'parent', access: 'read', goal: 'Integrate authentic consumed child packets', constraints: ['Do not repeat child-owned implementation or review'], scopes: [work, other], dependsOn: ['review-counter', 'review-other'], obligations: ['counter', 'other'], inputs: ['contract'] });
  return { workflow: 'native-fixture-normal', goal: 'Exercise actual native delegation and barriers with offline fixture models', inputs: [{ id: 'contract', kind: 'contract', paths: [], value: 'v1' }], obligations, lanes };
}

function readChild(attempt, parentPid) {
  assert.ok(attempt.actual.sessionFile, `No native session provenance: ${JSON.stringify(attempt)}`);
  const entries = fs.readFileSync(attempt.actual.sessionFile, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  const info = entries.find(entry => entry.customType === 'native-fixture-identity')?.data;
  assert.ok(info, 'Missing native child process identity');
  assert.notEqual(info.pid, parentPid); assert.equal(info.child, '1');
  assert.equal(info.provider, 'native-acceptance-fixture');
  const results = entries.filter(entry => entry.type === 'message' && entry.message.role === 'toolResult').map(entry => entry.message);
  assert.ok(results.some(result => result.toolName === 'read' && !result.isError));
  assert.ok(entries.some(entry => entry.type === 'message' && entry.message.role === 'assistant' && textOf(entry.message).includes('```execution-packet')));
  if (attempt.role === 'writer') {
    assert.ok(results.some(result => result.toolName === 'bash' && textOf(result).includes('fixture child interface ok') && !result.isError));
    assert.ok(results.some(result => result.toolName === 'workflow_contract' && textOf(result).includes('"acceptance":"complete"')));
    assert.ok(results.some(result => result.toolName === 'writer_lease' && !result.isError));
  }
  return { identity: info, sessionFile: attempt.actual.sessionFile, toolResults: results };
}

export async function delegation(fixture, report) {
  const rpc = launchRpc(fixture);
  report.barriers = {}; report.transfers = [];
  try {
    report.identity = await identity(rpc);
    const before = parentTuple(await rpc.request('get_state'));
    await rpc.request('prompt', { message: '/auto off' });
    assert.ok(rpc.events.some(event => event.method === 'notify' && /already OFF|mode OFF/.test(event.message)));
    await rpc.request('prompt', { message: '/subagents-load-profile max' });
    const plan = makePlan(fixture); report.plan = plan;
    const strategy = async input => success(await rpc.call('execution_strategy', input));
    report.barriers.guardNoLease = rejected(await rpc.call('write', { path: join(fixture.root, 'work/counter.mjs'), content: 'forbidden parent write' }), /Claim writer_lease/);
    const claim = await rpc.call('writer_lease', { action: 'claim', roots: [join(fixture.root, 'work')] }); success(claim);
    const nonce = JSON.parse(textOf(claim)).writer.nonce;
    report.barriers.guardNoPermit = rejected(await rpc.call('bash', { command: 'true', timeout: 5 }), /exact writer_lease permit/);
    success(await rpc.call('writer_lease', { action: 'release', nonce }));
    success(await rpc.call('read', { path: join(fixture.root, 'work/counter.mjs') })); // Intentionally duplicate parent discovery.
    await strategy({ action: 'plan', plan });
    report.barriers.unmet = rejected(await rpc.call('execution_strategy', { action: 'prepare', lane: 'review-counter', foregroundOnly: true }), /unmet dependency/);
    const stale = await strategy({ action: 'prepare', lane: 'write-counter', foregroundOnly: true });
    await strategy({ action: 'input', input: 'contract', value: 'v2' });
    report.barriers.stale = rejected(await rpc.call('subagent', stale.input), /snapshot stale/);
    await strategy({ action: 'cancel', attempt: stale.attempt });
    const first = await strategy({ action: 'prepare', lane: 'write-counter', foregroundOnly: true });
    report.barriers.secondWriter = rejected(await rpc.call('execution_strategy', { action: 'prepare', lane: 'write-other', foregroundOnly: true }), /writer/);
    for (const lane of ['write-counter', 'review-counter', 'write-other', 'review-other']) {
      const prepared = lane === 'write-counter' ? first : await strategy({ action: 'prepare', lane, foregroundOnly: true });
      const inputBefore = JSON.stringify(prepared.input);
      const launched = await rpc.call('subagent', prepared.input); success(launched);
      const start = rpc.events.find(event => event.type === 'tool_execution_start' && event.toolCallId === launched.toolCallId);
      assert.equal(JSON.stringify(start.args), inputBefore, 'Exact returned native input must be unchanged');
      const status = await strategy({ action: 'status' });
      const attempt = status.attempts.find(attempt => attempt.id === prepared.attempt);
      assert.equal(attempt.status, 'complete', JSON.stringify(attempt));
      assert.ok(attempt.packetHash, 'No authentic returned packet');
      assert.equal(attempt.consumed, false);
      const child = readChild(attempt, rpc.pid);
      if (lane === 'write-counter') {
        report.barriers.unconsumed = rejected(await rpc.call('execution_strategy', { action: 'prepare', lane: 'review-counter', foregroundOnly: true }), /unmet dependency/);
        assert.ok(attempt.parentDiscoveryOverlap.length > 0, 'Duplicate parent discovery must be recorded');
      }
      if (lane === 'review-other') {
        report.barriers.integration = rejected(await rpc.call('execution_strategy', { action: 'parent', lane: 'integrate', conclusion: 'Premature', evidence: ['not consumed'] }), /unmet dependency/);
      }
      const consumed = await strategy({ action: 'consume', attempt: prepared.attempt });
      report.transfers.push({ prepared, launched, attempt, child, consumed });
    }
    await strategy({ action: 'parent', lane: 'integrate', conclusion: 'Integrated actual consumed writer and reviewer fixture packets', evidence: report.transfers.map(transfer => `native:${transfer.attempt.childRunId};packet:${transfer.attempt.packetHash}`) });
    report.final = await strategy({ action: 'status' });
    assert.equal(report.final.review.pass, true, JSON.stringify(report.final.review));
    assert.equal(report.final.review.workflowAcceptance, false);
    assert.equal(report.final.telemetry.savings, null);
    assert.ok(report.final.parentDiscovery.some(row => row.path === join(fixture.root, 'work/counter.mjs')));
    assert.deepEqual(parentTuple(await rpc.request('get_state')), before);
    assert.equal(await branchMarker(rpc), 'max');
    report.autoOff = true;
    report.boundary = 'Native dispatch, workflows, child processes, native child read/write/bash, guard and acceptance enabled. Explicit isolated fixture worker/reviewer models, prompts and tool overrides; scripted coverage is structural, not semantic review. Parent discovery duplication is intentional and savings remain null.';
    report.nativeStatus = await rpc.call('subagent', { action: 'status' }); success(report.nativeStatus);
  } finally { await rpc.close(); }
}
