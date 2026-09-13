import { check, contains, digest, hashPaths, id, intersects, object, scopes, text, unique } from './workspace.mjs';

export function graphCheck(items, field, label) {
  const map = new Map(items.map(item => [item.id, item]));
  check(map.size === items.length, `${label}: duplicate IDs`);
  const visiting = new Set(), done = new Set();
  function visit(key) {
    check(map.has(key), `${label}: unknown dependency ${key}`);
    check(!visiting.has(key), `${label}: dependency cycle at ${key}`);
    if (done.has(key)) return;
    visiting.add(key);
    for (const dep of map.get(key)[field]) visit(dep);
    visiting.delete(key); done.add(key);
  }
  items.forEach(item => visit(item.id));
}
export function ancestors(lanes, lane) {
  const found = new Set();
  function visit(key) { if (found.has(key)) return; found.add(key); lanes.find(l => l.id === key).dependsOn.forEach(visit); }
  lane.dependsOn.forEach(visit); return [...found];
}
export function validatePlan(raw) {
  check(object(raw), 'plan required');
  const plan = structuredClone(raw);
  id(plan.workflow); text(plan.goal, 'goal');
  check(Array.isArray(plan.inputs) && Array.isArray(plan.obligations) && Array.isArray(plan.lanes), 'inputs, obligations and lanes arrays required');
  for (const input of plan.inputs) {
    id(input.id); check(['dependency', 'contract', 'assumption'].includes(input.kind), 'invalid input kind');
    input.paths = scopes(input.paths); text(input.value, 'input value/revision');
  }
  unique(plan.inputs.map(i => i.id), 'input IDs');
  for (const obligation of plan.obligations) {
    id(obligation.id); text(obligation.description, 'obligation description');
    check(['requirement', 'risk'].includes(obligation.kind), 'invalid obligation kind');
    obligation.scopes = scopes(obligation.scopes);
    check(obligation.scopes.length > 0, 'obligation must cover source scopes');
    unique(obligation.inputs, 'obligation inputs').forEach(key => check(plan.inputs.some(i => i.id === key), `unknown input ${key}`));
    unique(obligation.dependsOn, 'obligation dependencies').forEach(id);
  }
  check(plan.obligations.some(o => o.kind === 'requirement'), 'at least one requirement required');
  graphCheck(plan.obligations, 'dependsOn', 'obligations');
  for (const lane of plan.lanes) {
    id(lane.id); text(lane.goal, 'lane goal');
    check(['discovery', 'writer', 'reviewer', 'integration'].includes(lane.role), 'invalid lane role');
    check(['parent', 'child'].includes(lane.owner), 'lane owner required');
    check(lane.owner !== 'parent' || lane.role === 'integration', 'parent lanes must be integration');
    check(lane.role !== 'integration' || lane.owner === 'parent', 'integration is parent owned');
    if (lane.owner === 'child') id(lane.agent);
    check(['read', 'write'].includes(lane.access), 'lane access required');
    check(lane.role === 'writer' || lane.role === 'integration' || lane.access === 'read', 'discovery/reviewer cannot own writes');
    check(lane.role !== 'writer' || lane.access === 'write', 'writer must declare write access');
    unique(lane.constraints, 'constraints').forEach(c => text(c, 'constraint'));
    lane.scopes = scopes(lane.scopes); check(lane.scopes.length > 0, 'lane needs owned source scopes');
    unique(lane.dependsOn, 'lane dependencies').forEach(id);
    unique(lane.inputs, 'lane inputs').forEach(key => check(plan.inputs.some(i => i.id === key), `unknown input ${key}`));
    unique(lane.obligations, 'lane obligations').forEach(key => {
      const obligation = plan.obligations.find(o => o.id === key);
      check(obligation, `unknown obligation ${key}`);
      if (lane.role === 'reviewer') {
        check(obligation.scopes.every(p => lane.scopes.some(s => contains(s, p))), `review lane ${lane.id} lacks scope for ${key}`);
        check(obligation.inputs.every(i => lane.inputs.includes(i)), `review lane ${lane.id} must declare inputs of ${key}`);
      }
    });
  }
  graphCheck(plan.lanes, 'dependsOn', 'lanes');
  for (const lane of plan.lanes.filter(l => l.access === 'write')) {
    check(lane.scopes.every(scope => plan.obligations.some(o => o.scopes.some(s => contains(s, scope)))), `write scope lacks requirement/risk review obligation: ${lane.id}`);
  }
  for (const a of plan.lanes) for (const b of plan.lanes) {
    if (a.id >= b.id || !intersects(a.scopes, b.scopes) || (a.access === 'read' && b.access === 'read')) continue;
    check(ancestors(plan.lanes, a).includes(b.id) || ancestors(plan.lanes, b).includes(a.id), `unsafe scope overlap: ${a.id}/${b.id}; declare a dependency`);
  }
  return plan;
}
export function obligationSnapshot(plan, key, laneInputs = []) {
  const obligation = plan.obligations.find(o => o.id === key);
  const inputs = [...new Set([...obligation.inputs, ...laneInputs])].sort().map(k => plan.inputs.find(i => i.id === k));
  return digest({ obligation, paths: hashPaths(obligation.scopes), inputs: inputs.map(i => ({ ...i, hashes: hashPaths(i.paths) })), dependencies: obligation.dependsOn.map(k => obligationSnapshot(plan, k)) });
}
function dependencySnapshots(plan, lane) {
  return ancestors(plan.lanes, lane).map(k => {
    const dep = plan.lanes.find(l => l.id === k);
    return { id: k, hashes: hashPaths(dep.scopes),
      inputs: dep.inputs.map(i => { const input = plan.inputs.find(x => x.id === i); return { ...input, hashes: hashPaths(input.paths) }; }),
      obligations: dep.obligations.map(id => obligationSnapshot(plan, id, dep.inputs)) };
  });
}
export function laneSnapshot(plan, lane) {
  return digest({ lane, obligations: reviewSnapshots(plan, lane), paths: hashPaths(lane.scopes), inputs: lane.inputs.map(k => { const i = plan.inputs.find(x => x.id === k); return { ...i, hashes: hashPaths(i.paths) }; }), dependencies: dependencySnapshots(plan, lane) });
}
export function coverageSnapshot(plan, lane, key) {
  return digest({ obligation: obligationSnapshot(plan, key, lane.inputs), dependencies: dependencySnapshots(plan, lane) });
}
export function reviewSnapshots(plan, lane) {
  return Object.fromEntries(lane.obligations.map(key => [key, coverageSnapshot(plan, lane, key)]));
}
