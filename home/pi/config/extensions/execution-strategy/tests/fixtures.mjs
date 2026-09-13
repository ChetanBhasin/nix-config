import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { StrategyLedger, emptyState } from '../ledger.mjs';

export function workspace() {
  mkdirSync('/tmp/execution-strategy-tests', { recursive: true });
  const dir = mkdtempSync('/tmp/execution-strategy-tests/unit-');
  const a = join(dir, 'a.txt'), b = join(dir, 'b.txt');
  writeFileSync(a, 'alpha'); writeFileSync(b, 'beta');
  return { dir, a, b };
}
export const policy = { effective: true, owner: true, profile: 'complex', hash: 'test-policy', config: { version: 1, delegation: 'proactive', reviewers: ['reviewer'] } };
export const lane = (id, scopes, role = 'reviewer', dependsOn = [], obligations = [id]) => ({ id, role, owner: role === 'integration' ? 'parent' : 'child', agent: role === 'reviewer' ? 'reviewer' : 'worker', access: ['writer', 'integration'].includes(role) ? 'write' : 'read', goal: `Complete ${id}`, constraints: ['Stay in scope'], scopes, dependsOn, obligations, inputs: [] });
export const obligation = (id, scopes, kind = 'requirement') => ({ id, scopes, kind, description: `Check ${id}`, inputs: [], dependsOn: [] });
export function planFor(a, b) { return { workflow: 'test', goal: 'Test bounded strategy', inputs: [], obligations: [obligation('a', [a]), obligation('b', [b], 'risk')], lanes: [lane('review-a', [a], 'reviewer', [], ['a']), lane('review-b', [b], 'reviewer', [], ['b'])] }; }
export function ledgerFor(plan) { const ledger = new StrategyLedger(emptyState('parent-session')); ledger.plan(plan); return ledger; }
export function packetFor(attempt, role = 'reviewer') {
  return { version: 1, attempt: attempt.id, lane: attempt.lane, role, conclusion: 'Scoped checks passed', action: 'Proceed', decisions: [], assumptions: [], changes: [], validation: ['inspected'], evidence: [{ id: 'e1', link: 'tool:child-read', revision: 'source-revision', observation: 'alpha' }], blockers: [], coverage: role === 'reviewer' ? Object.entries(attempt.snapshots).map(([obligation, snapshot]) => ({ obligation, snapshot, verdict: 'pass', evidence: ['e1'] })) : [], findings: [], resolutions: [] };
}
// Deliberate UNIT fixtures; never described as full native delegation acceptance.
export function finish(ledger, key, mutate = () => {}, extra = {}) {
  const prepared = ledger.prepare(key, policy, { async: false });
  const attempt = ledger.latest(key);
  ledger.launch(`call-${attempt.id}`, prepared.input, policy);
  const packet = packetFor(attempt, ledger.lane(key).role); mutate(packet);
  const output = `\`\`\`execution-packet\n${JSON.stringify(packet)}\n\`\`\``;
  ledger.bindResult(attempt.toolCallId, { runId: `root-${attempt.id}`, workflow: { trace: [{ key, operation: 'run', state: 'completed', runId: `child-${attempt.id}` }] }, results: [{ index: 0, agent: attempt.agent, exitCode: 0, outputState: 'present', finalOutput: output, messages: [{ role: 'toolResult', toolCallId: 'child-read', isError: false, content: [{ type: 'text', text: 'alpha beta inspected' }] }], ...extra }] }, false);
  return ledger.latest(key);
}
