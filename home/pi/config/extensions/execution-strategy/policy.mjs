import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { check, digest, object, unique, id } from './workspace.mjs';

export const PROFILE_ENTRY = 'pi-subagents-profile';
export const STATE_ENTRY = 'execution-strategy:v1';
export function isOwner(env = process.env, sessionId = '') {
  // Native pi-subagents sets this forwarding address in the root parent too.
  const forwarding = env.PI_SUBAGENT_PARENT_SESSION;
  return !env.PI_SUBAGENT_CHILD && (!forwarding || forwarding === sessionId) && (!env.PI_SUBAGENT_DEPTH || env.PI_SUBAGENT_DEPTH === '0');
}
export function readPolicy(branch, agentDir, owner) {
  const marker = [...branch].reverse().find(e => e.type === 'custom' && e.customType === PROFILE_ENTRY);
  const base = { effective: false, owner, profile: marker?.data?.name ?? null, profileEntry: marker?.id ?? null };
  try {
    check(marker?.data?.version === 1 && typeof marker.data.name === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(marker.data.name), 'missing/malformed native profile marker');
    const file = join(agentDir, 'profiles', 'pi-subagents', `${marker.data.name}.json`);
    const profile = JSON.parse(readFileSync(file, 'utf8'));
    check(object(profile.subagents?.agentOverrides), 'invalid native profile: agentOverrides missing');
    const config = profile.subagents.executionStrategy;
    check(object(config) && config.version === 1, 'missing/malformed executionStrategy metadata');
    check(Object.keys(config).every(k => ['version', 'delegation', 'reviewers'].includes(k)), 'unknown executionStrategy metadata field');
    check(['useful', 'proactive', 'comprehensive'].includes(config.delegation), 'invalid delegation policy');
    check(unique(config.reviewers, 'reviewers').length > 0, 'trusted reviewer agent names required');
    config.reviewers.forEach(id);
    return { ...base, effective: true, config, hash: digest(config), file, reason: owner ? null : 'ordinary child: observation only; no orchestration authority' };
  } catch (error) { return { ...base, reason: `ineffective configuration: ${error.message}` }; }
}
export function policyContext(policy) {
  if (!policy.effective) return `Execution strategy: ${policy.reason}. Do not claim delegation/review is configured. Parent provider/model/thinking are untouched.`;
  if (!policy.owner) return 'Execution strategy: bounded child, not an orchestrator. Complete only your assigned role and return an execution-packet; never plan or launch children.';
  const guidance = {
    useful: 'Transfer useful independent/context-heavy work before doing it locally; keep trivial deterministic work local.',
    proactive: 'Proactively transfer discovery, implementation and independent review before duplicating them locally; retain only parent integration.',
    comprehensive: 'Seek comprehensive independent requirement/risk review and transfer separable work early; increase depth from actual risks, not lane quotas or budgets.',
  }[policy.config.delegation];
  return `Execution strategy (${policy.profile}): ${guidance} Use execution_strategy to plan stable scoped lanes, inputs and obligations, prepare exact subagent payloads, then call native subagent normally. Consume authentic packets at dependency barriers. One writer; leases and protected-action policy remain authoritative. Record parent-owned integration separately. Gate gaps require affected-only re-review; bookkeeping NEVER completes workflow_contract. Explicit async/foregroundOnly intent is preserved. No provider/model/thinking changes.`;
}
