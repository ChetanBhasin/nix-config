import { digest, check } from './workspace.mjs';
import { emptyState } from './ledger.mjs';
import { STATE_ENTRY } from './policy.mjs';

const arrays = ['attempts', 'parentWork', 'discovery', 'unknown', 'findings', 'coverage'];
/** Index patches avoid repeating all old packets/telemetry on every observation. No deletion operation. */
export function statePatch(before, after) {
  const patch = { version: 1, session: after.session, revision: after.revision, arrays: {} };
  if (digest(before.plan) !== digest(after.plan)) patch.plan = after.plan;
  for (const key of arrays) {
    const changed = after[key].flatMap((value, index) => digest(before[key][index] ?? null) === digest(value) ? [] : [{ index, value }]);
    if (changed.length) patch.arrays[key] = changed;
  }
  return patch;
}
export function restore(branch, session) {
  const state = emptyState(session);
  for (const entry of branch) {
    if (entry.type !== 'custom' || entry.customType !== STATE_ENTRY || entry.data?.session !== session) continue;
    const patch = entry.data;
    check(patch.version === 1 && Number.isInteger(patch.revision) && patch.revision >= state.revision, 'invalid branch strategy revision');
    if (Object.hasOwn(patch, 'plan')) state.plan = patch.plan;
    for (const [key, changes] of Object.entries(patch.arrays)) {
      check(arrays.includes(key) && Array.isArray(changes), 'invalid strategy collection');
      for (const { index, value } of changes) {
        check(Number.isInteger(index) && index >= 0 && index <= state[key].length, 'invalid strategy patch index');
        state[key][index] = structuredClone(value);
      }
    }
    state.revision = patch.revision;
  }
  return state;
}
