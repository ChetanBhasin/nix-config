import assert from 'node:assert/strict';
import fs from 'node:fs';
import { join } from 'node:path';
import { launchRpc, success, rejected, textOf } from './rpc.mjs';
import { strategy, inspectChild, records } from './review.mjs';
import { lifecycle } from './lifecycle.mjs';

export function receiptPlan(fixture) {
  const fact = join(fixture.root, 'work/fact.txt');
  fs.writeFileSync(fact, 'Native fixture fact: supported Pi version is 0.84.4; pi-subagents version is 0.56.0.\n');
  return { workflow: 'native-fixture-receipts', goal: 'Observe native failure and success receipts without inventing telemetry', inputs: [],
    obligations: [{ id: 'fact', kind: 'requirement', description: 'Read the assigned pinned version fact', scopes: [fact], inputs: [], dependsOn: [] }],
    lanes: [['preflight', 'fixture-agent-does-not-exist'], ['runtime-failure', 'reviewer'], ['lookup', 'lookup']].map(([id, agent]) => ({ id, agent, role: 'discovery', owner: 'child', access: 'read', goal: 'Read the single local pinned version fact; no network or mutation', constraints: ['Deterministic offline fixture; no Terra qualification'], scopes: [fact], obligations: ['fact'], inputs: [], dependsOn: [] })),
  };
}
function linked(attempt, rpc, plan) {
  const entries = records(join(plan.root, 'parent.jsonl'));
  const parent = entries[0];
  assert.ok(attempt.toolCallId); assert.ok(attempt.runId); assert.ok(attempt.childRunId);
  assert.notEqual(attempt.runId, attempt.childRunId);
  assert.equal(attempt.plannedConfig.profile, 'max');
  assert.equal(attempt.plannedConfig.context, 'fresh');
  assert.equal(attempt.actual.agent, attempt.plannedConfig.agent);
  const child = inspectChild(attempt, rpc, { packet: attempt.status === 'complete' });
  assert.equal(child.identity.parentSessionEnvironment, parent.id);
  assert.equal(child.identity.session, attempt.actual.sessionFile);
  const telemetry = entries.filter(entry => entry.customType === 'execution-strategy:telemetry:v1').map(entry => entry.data);
  const finalized = telemetry.find(row => row.kind === 'native-finalized' && row.data.attempt === attempt.id);
  assert.ok(finalized, 'Missing finalized tool provenance');
  assert.equal(finalized.session, parent.id); assert.equal(finalized.workflow, plan.workflow);
  assert.equal(finalized.data.toolCallId, attempt.toolCallId); assert.ok(finalized.branchLeaf);
  assert.ok(telemetry.some(row => row.kind === 'native-tool-result' && row.data.toolCallId === attempt.toolCallId));
  assert.match(attempt.actual.provenance, /native/);
  return { child, finalized, parentId: parent.id };
}
export async function telemetryReceipts(fixture, report) {
  const rpc = launchRpc(fixture), api = strategy(rpc);
  report.plan = receiptPlan(fixture); report.transfers = [];
  try {
    await rpc.request('prompt', { message: '/subagents-load-profile max' });
    await api({ action: 'plan', plan: report.plan });
    const prepared = await api({ action: 'prepare', lane: 'preflight', foregroundOnly: true });
    const launched = await rpc.call('subagent', prepared.input);
    const state = await api({ action: 'status' });
    const attempt = state.attempts.find(row => row.id === prepared.attempt);
    report.preflight = { prepared, launched, attempt, review: state.review };
    rejected(launched, /not found|unknown agent|available agents/i);
    assert.ok(['unknown', 'failed'].includes(attempt.status)); assert.ok(attempt.failure);
    assert.equal(attempt.childRunId, null); assert.equal(attempt.actual.model, null);
    assert.equal(attempt.actual.thinking, null); assert.equal(attempt.actual.usage.value, null);
    assert.match(attempt.actual.usage.provenance, /unknown/); assert.equal(attempt.packetHash, null);
    assert.equal(state.review.pass, false); assert.ok(state.review.gaps.length);
    report.preflight.consumeRejection = rejected(await rpc.call('execution_strategy', { action: 'consume', attempt: attempt.id }), /native|packet|identity/i);
    const failedPrepared = await api({ action: 'prepare', lane: 'runtime-failure', foregroundOnly: true });
    const failedLaunch = await rpc.call('subagent', failedPrepared.input);
    const failedState = await api({ action: 'status' });
    const failedAttempt = failedState.attempts.find(row => row.id === failedPrepared.attempt);
    report.runtimeFailure = { prepared: failedPrepared, launched: failedLaunch, attempt: failedAttempt };
    // Retain failure assertions, but also exercise lookup before reporting a frozen-core gap.
    let failureGap;
    try {
      assert.equal(failedAttempt.status, 'failed', JSON.stringify(failedAttempt));
      assert.match(JSON.stringify(failedLaunch), /DETERMINISTIC_FIXTURE_RUNTIME_FAILURE/);
      assert.equal(failedAttempt.packetHash, null); assert.equal(failedAttempt.consumed, false);
      Object.assign(report.runtimeFailure, linked(failedAttempt, rpc, { ...report.plan, root: fixture.root }));
      assert.ok(report.runtimeFailure.child.results.some(row => row.toolName === 'read' && textOf(row).includes('0.84.4')));
      assert.ok(failedAttempt.actual.usage.value.input > 0); assert.equal(failedAttempt.actual.usage.value.cost, 0);
      assert.match(failedAttempt.actual.usage.provenance, /native returned usage/);
    } catch (error) { failureGap = error; report.runtimeFailure.integrationGap = error.stack; }
    report.runtimeFailure.nativeStatus = await rpc.call('subagent', { action: 'status' });
    const discovered = await rpc.call('subagent', { action: 'get', agent: 'lookup' }); success(discovered);
    report.lookupDiscovery = textOf(discovered);
    assert.match(report.lookupDiscovery, /native-acceptance-fixture\/child-lookup-scripted/);
    assert.match(report.lookupDiscovery, /file-only/); assert.match(report.lookupDiscovery, /lookup.md/);
    const lookupPrepared = await api({ action: 'prepare', lane: 'lookup', foregroundOnly: true });
    const lookupLaunch = await rpc.call('subagent', lookupPrepared.input);
    const lookupAttempt = (await api({ action: 'status' })).attempts.find(row => row.id === lookupPrepared.attempt);
    const lookup = { prepared: lookupPrepared, launched: lookupLaunch, attempt: lookupAttempt };
    report.lookup = lookup; report.transfers.push(lookup);
    const nativeLookup = success(lookupLaunch).results[0];
    assert.equal(nativeLookup.exitCode, 0); assert.equal(nativeLookup.outputMode, 'file-only');
    assert.equal(nativeLookup.acceptance.status, 'attested'); // Real read-only lookup default, not a disabled guard.
    Object.assign(lookup, linked(lookupAttempt, rpc, { ...report.plan, root: fixture.root }));
    lookup.child = inspectChild(lookupAttempt, rpc, { packet: true });
    assert.ok(fs.readFileSync(nativeLookup.savedOutputPath, 'utf8').includes('```execution-packet'));
    lookup.nativeSuccess = true; lookup.outputPath = nativeLookup.savedOutputPath;
    lookup.consume = await rpc.call('execution_strategy', { action: 'consume', attempt: lookupAttempt.id });
    let lookupGap;
    try { assert.equal(lookupAttempt.status, 'complete', JSON.stringify(lookupAttempt)); success(lookup.consume); }
    catch (error) { lookupGap = error; lookup.integrationGap = error.stack; }
    const actual = lookup.attempt.actual;
    assert.match(actual.model, /^native-acceptance-fixture\/child-lookup-scripted/);
    assert.equal(actual.thinking, 'medium'); assert.ok(actual.usage.value.input > 0);
    assert.equal(actual.usage.value.cost, 0); assert.equal(actual.usage.value.totalTokens, null);
    assert.match(actual.usage.provenance, /native returned usage/);
    const active = report.lookup.child.identity.activeTools;
    for (const tool of ['read', 'grep', 'symbol_search', 'module_report', 'read_symbol', 'web_run']) assert.ok(active.includes(tool), `${tool}: ${JSON.stringify(active)}`);
    for (const tool of ['bash', 'write', 'edit', 'subagent']) assert.ok(!active.includes(tool), `Lookup unexpectedly has ${tool}`);
    assert.ok(actual.outputPath && fs.existsSync(actual.outputPath));
    assert.ok(fs.readFileSync(actual.outputPath, 'utf8').includes('execution-packet'));
    assert.ok(report.lookup.child.results.every(row => row.toolName === 'read'), 'Lookup used unexpected capabilities');
    report.final = await api({ action: 'status' });
    assert.equal(report.final.review.pass, false); assert.equal(report.final.review.workflowAcceptance, false);
    assert.equal(report.final.telemetry.savings, null);
    const entries = (await rpc.request('get_entries')).entries;
    report.telemetry = entries.filter(row => row.customType === 'execution-strategy:telemetry:v1').map(row => row.data);
    const parentUsage = report.telemetry.filter(row => row.kind === 'parent-usage');
    assert.ok(parentUsage.some(row => row.data.provider === 'native-acceptance-fixture' && row.data.model === 'parent-scripted'));
    assert.ok(parentUsage.every(row => /not child totals/.test(row.data.provenance)));
    report.boundary = 'Native preflight failure has no child; no invented identity/model/usage. Runtime failure follows a successful native child read. Lookup uses the actual lookup role prompt, read-only tools and file-only output with honestly named deterministic model; zero cost is fixture-native returned usage, not real Terra. Production Terra qualification is parent-owned separate evidence. Guards remain enabled.';
    report.lookup.nativeQualification = 'passed: real read-only tools, native attested acceptance and file-only output with deterministic fixture model';
    if (lookupGap) throw lookupGap;
    if (failureGap) throw failureGap;
  } finally { await rpc.close(); }
}
export async function receipts(fixture, report) {
  report.failures = [];
  for (const [name, run] of [['telemetry', telemetryReceipts], ['lifecycle', lifecycle]]) {
    report[name] = {};
    try { await run(fixture, report[name]); report[name].status = 'passed'; }
    catch (error) { report[name].status = 'failed'; report[name].error = error.stack ?? String(error); report.failures.push(`${name}: ${report[name].error}`); }
  }
  assert.deepEqual(report.failures, [], 'All native receipt/lifecycle obligations must pass');
}
