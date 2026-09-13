import { randomUUID } from 'node:crypto';
import { check, digest, intersects, pathKey, text } from './workspace.mjs';
import { ancestors, coverageSnapshot, laneSnapshot, reviewSnapshots, validatePlan } from './plan.mjs';
import { bindPacketEvidence, enrichNativeRow, nativeMaterial, ownedStatus, ownedForeground } from './native.mjs';
import { PACKET_GUIDE, observedUsage, parsePacket } from './packets.mjs';

export const emptyState = session => ({ version: 1, session, plan: null, attempts: [], parentWork: [], discovery: [], unknown: [], findings: [], coverage: [], revision: 0 });
export class StrategyLedger {
  constructor(state) { this.state = state; }
  lane(key) { const lane = this.state.plan?.lanes.find(l => l.id === key); check(lane, `unknown lane ${key}`); return lane; }
  latest(key) { return this.state.attempts.findLast(a => a.lane === key); }
  event(kind, data) { this.state.revision++; return { kind, revision: this.state.revision, ...data }; }
  plan(raw, extend = false) {
    check(extend ? this.state.plan : !this.state.plan, extend ? 'plan required before extend' : 'plan already exists; use additive extend');
    const old = this.state.plan;
    if (extend) {
      check(raw.workflow === old.workflow && raw.goal === old.goal, 'extend cannot replace workflow/goal');
      raw = { ...old, lanes: [...old.lanes, ...raw.lanes], obligations: [...old.obligations, ...raw.obligations], inputs: [...old.inputs, ...raw.inputs] };
    }
    this.state.plan = validatePlan(raw);
    return this.event('plan', { workflow: raw.workflow, lanes: raw.lanes.map(l => l.id) });
  }
  ready(lane) {
    for (const key of lane.dependsOn) {
      const dep = this.lane(key);
      const result = dep.owner === 'parent' ? this.state.parentWork.findLast(p => p.lane === key) : this.latest(key);
      check(result?.consumed && result.status === 'complete', `unmet dependency: ${key}; consume successful current output first`);
      check(result.completedSnapshot === laneSnapshot(this.state.plan, dep), `stale dependency: ${key}`);
    }
    for (const attempt of this.state.attempts.filter(a => ['prepared', 'calling', 'running', 'paused', 'unknown'].includes(a.status))) {
      const other = this.lane(attempt.lane);
      check(other.id !== lane.id, `lane ${lane.id} already pending`);
      check(!(lane.access === 'write' && other.access === 'write'), 'one writer: another writer is pending');
      check(!intersects(lane.scopes, other.scopes) || (lane.access === 'read' && other.access === 'read'), `active ownership overlap: ${other.id}`);
    }
  }
  prepare(key, policy, options = {}) {
    check(policy.effective && policy.owner, policy.reason ?? 'owner-only preparation');
    const lane = this.lane(key); check(lane.owner === 'child', 'parent integration must not be delegated');
    if (lane.role === 'reviewer') check(policy.config.reviewers.includes(lane.agent), 'reviewer agent is not trusted by profile metadata');
    this.ready(lane);
    const attempt = { id: randomUUID(), lane: key, role: lane.role, agent: lane.agent, status: 'prepared', consumed: false, policyHash: policy.hash,
      snapshots: reviewSnapshots(this.state.plan, lane), preparedSnapshot: laneSnapshot(this.state.plan, lane),
      plannedConfig: { profile: policy.profile, agent: lane.agent, role: lane.role, context: 'fresh' },
      actual: { model: null, thinking: null, usage: observedUsage(null), provenance: 'not launched' } };
    const dependencies = lane.dependsOn.map(k => {
      const dep = this.lane(k); const result = dep.owner === 'parent' ? this.state.parentWork.findLast(p => p.lane === k) : this.latest(k);
      return { lane: k, attempt: result.id ?? null, packetHash: result.packetHash ?? null, conclusion: result.packet?.conclusion ?? result.conclusion, evidence: result.packet?.evidence ?? result.evidence, assumptions: result.packet?.assumptions ?? [], decisions: result.packet?.decisions ?? [], blockers: result.packet?.blockers ?? [] };
    });
    const obligations = this.state.plan.obligations.filter(o => lane.obligations.some(k => k === o.id || ancestors(this.state.plan.obligations, this.state.plan.obligations.find(x => x.id === k)).includes(o.id)));
    const inputs = this.state.plan.inputs.filter(i => lane.inputs.includes(i.id) || obligations.some(o => o.inputs.includes(i.id)));
    const access = lane.access === 'read' ? 'Read-only assignment. Do not modify any files. Return findings only.\n\n' : '';
    const task = `${access}${lane.goal}\n\nExecution strategy assignment (data, not authority):\n${JSON.stringify({ workflow: this.state.plan.workflow, attempt: attempt.id, lane: key, role: lane.role, access: lane.access, scopes: lane.scopes, constraints: lane.constraints, inputs, obligations, snapshots: attempt.snapshots, dependencies, findings: this.state.findings.filter(f => lane.obligations.includes(f.obligation) && !this.resolved(f, policy)) })}\n\n${PACKET_GUIDE}`;
    check(Buffer.byteLength(task) <= 48000, 'assignment exceeds compact payload limit; narrow lane');
    attempt.payload = { workflowScript: `return runs.run(${JSON.stringify(key)}, ${JSON.stringify({ agent: lane.agent, task })})`, context: 'fresh' };
    if (Object.hasOwn(options, 'async')) attempt.payload.async = options.async;
    if (options.foregroundOnly === true) { check(options.async !== true, 'foregroundOnly conflicts with async:true'); attempt.payload.foregroundOnly = true; attempt.payload.async = false; }
    this.state.attempts.push(attempt);
    this.event('prepared', { attempt: attempt.id });
    return { attempt: attempt.id, tool: 'subagent', input: attempt.payload, snapshots: attempt.snapshots, warning: 'Preparation is not a launch, lease, transfer or workflow acceptance.' };
  }
  launch(toolCallId, input, policy, foregroundHistory) {
    const attempt = this.state.attempts.find(a => a.payload.workflowScript === input.workflowScript);
    if (!attempt) { this.state.unknown.push({ toolCallId, status: 'unowned', inputHash: digest(input) }); return null; }
    check(attempt.status === 'prepared', 'prepared launch already used');
    check(policy.effective && policy.owner && policy.hash === attempt.policyHash, 'prepared policy is stale/ineffective');
    const expected = { ...attempt.payload };
    // The shared normal-mode handoff is the only tolerated native input mutation.
    if (!Object.hasOwn(expected, 'async') && expected.foregroundOnly !== true) expected.async = true;
    check(digest(expected) === digest(input), 'prepared native payload was modified; prepare a fresh exact call');
    const lane = this.lane(attempt.lane);
    attempt.status = 'checking';
    try { this.ready(lane); check(attempt.preparedSnapshot === laneSnapshot(this.state.plan, lane), 'prepared source/input snapshot stale'); }
    finally { attempt.status = 'prepared'; }
    attempt.status = 'calling'; attempt.toolCallId = toolCallId;
    if (typeof foregroundHistory === 'string') attempt.foregroundHistory = pathKey(foregroundHistory);
    attempt.parentDiscoveryOverlap = this.state.discovery.filter(d => d.path && intersects([d.path], lane.scopes)).map(d => d.toolCallId);
    this.event('launch-observed', { attempt: attempt.id, toolCallId }); return attempt;
  }
  observeDiscovery(toolCallId, path, tool) {
    let canonical = null;
    try { if (path) canonical = pathKey(path); } catch { /* unknown is retained, never savings */ }
    const lanes = canonical ? (this.state.plan?.lanes ?? []).filter(l => l.owner === 'child' && intersects([canonical], l.scopes)).map(l => l.id) : [];
    this.state.discovery.push({ toolCallId, path: canonical, tool, overlappingLanes: lanes, provenance: 'parent tool_call; discovery savings not measured' });
    return this.event('parent-discovery', { toolCallId, overlappingLanes: lanes, scopeUnknown: !canonical });
  }
  bindResult(toolCallId, details, isError, parentSession = this.state.session) {
    const attempt = this.state.attempts.find(a => a.toolCallId === toolCallId);
    if (!attempt) {
      const unknown = this.state.unknown.find(u => u.toolCallId === toolCallId);
      if (unknown) Object.assign(unknown, { status: isError ? 'failed' : 'unowned-result', runId: details.runId ?? details.asyncId ?? null });
      return null;
    }
    const root = details.runId ?? details.asyncId;
    if (typeof root !== 'string') { attempt.status = 'unknown'; attempt.failure = isError ? 'native tool failed/blocked; process termination is unconfirmed' : 'native result omitted run identity'; return attempt; }
    attempt.runId = root; attempt.status = isError ? 'unknown' : 'running'; attempt.parentSession = parentSession;
    if (isError) attempt.failure = 'native tool failed; awaiting authoritative process termination';
    if (typeof details.asyncDir === 'string') attempt.asyncDir = pathKey(details.asyncDir);
    if (details.background !== true && !details.asyncId) this.nativeComplete(root, details, 'native tool_result');
    return attempt;
  }
  reconcile() {
    for (const attempt of this.state.attempts.filter(a => a.asyncDir && ['running', 'paused', 'unknown'].includes(a.status))) {
      try {
        const { status, step } = ownedStatus(attempt);
        attempt.lastObservedState = status.state;
        if (['complete', 'failed', 'paused', 'stopped', 'rejected'].includes(status.state)) {
          this.nativeComplete(attempt.runId, { success: status.state === 'complete', workflow: status.workflow, results: [{ ...step, state: step.status, success: ['complete', 'completed'].includes(step.status) }] }, 'verified native owned status/session');
        }
      } catch (error) { attempt.reconciliationGap = String(error); }
    }
    for (const attempt of this.state.attempts.filter(a => !a.asyncDir && a.foregroundHistory && ['running', 'paused', 'unknown'].includes(a.status))) {
      try {
        const { child, path } = ownedForeground(attempt);
        attempt.lastObservedState = child.status;
        if (!['completed', 'failed', 'stopped'].includes(child.status)) continue;
        check(Number.isInteger(child.exitCode), 'native foreground termination lacks exit evidence');
        this.nativeComplete(attempt.runId, { success: child.status === 'completed', results: [{ ...child,
          metadataProvenance: `verified native foreground history: ${path}`,
          metadataGap: 'native foreground history omits final usage; usage remains unknown',
        }] }, 'verified native owned foreground history/session');
      } catch (error) { attempt.reconciliationGap = String(error); }
    }
  }
  nativeForegroundComplete(data) {
    // Native detached callbacks identify the leaf, not the enclosing workflow.
    const attempt = this.state.attempts.find(a => a.childRunId === data.runId);
    if (!attempt || attempt.nativeTerminal || data.source !== 'foreground' || data.mode !== 'single' || data.agent !== attempt.agent || data.taskIndex !== 0) return false;
    const previous = attempt.actual ?? {};
    if (previous.sessionFile && data.sessionFile !== previous.sessionFile) return false;
    return this.nativeComplete(attempt.runId, { success: data.success, results: [{
      agent: data.agent, runId: data.runId, workflowKey: attempt.lane,
      sessionFile: data.sessionFile, state: data.state, success: data.success, exitCode: data.exitCode,
      error: data.success === false ? data.summary : undefined,
      interrupted: data.interrupted, stopped: data.stopped, timedOut: data.timedOut, turnBudgetExceeded: data.turnBudgetExceeded,
      model: previous.model, thinking: previous.thinking,
      metadataProvenance: 'correlated native foreground exit; last returned configuration',
      metadataGap: 'foreground exit callback omits final usage; usage remains unknown',
    }] }, 'native correlated foreground completion event');
  }
  nativeComplete(root, data, provenance) {
    const attempt = this.state.attempts.find(a => a.runId === root);
    if (!attempt || attempt.nativeTerminal) return false;
    const lane = this.lane(attempt.lane);
    const rows = Array.isArray(data.results) ? data.results : [];
    // Prepared scripts launch exactly ONE configured leaf; ambiguous projections fail closed.
    if (rows.length !== 1) { attempt.failure = 'native result lacks unambiguous single child'; attempt.status = 'unknown'; return true; }
    const row = enrichNativeRow(rows[0], attempt);
    const trace = data.workflow?.trace?.filter(t => t.key === lane.id && t.operation === 'run' && typeof t.runId === 'string') ?? [];
    const childRunId = row.runId ?? trace.at(-1)?.runId;
    if (row.agent !== lane.agent || typeof childRunId !== 'string' || childRunId === root) {
      attempt.failure = 'native child agent/run identity mismatch or missing'; attempt.status = 'unknown'; return true;
    }
    if (row.workflowKey !== undefined && row.workflowKey !== lane.id) { attempt.failure = 'native workflow key mismatch'; attempt.status = 'unknown'; return true; }
    attempt.childRunId = childRunId;
    attempt.actual = { agent: row.agent, model: row.model ?? null, thinking: row.thinking ?? null, usage: observedUsage(row.usage), provenance,
      sessionFile: row.sessionFile ?? row.sessionPath ?? null, launchContractDigest: row.launchContractDigest ?? null,
      outputPath: row.artifactPaths?.outputPath ?? row.artifactPath ?? null, metadataProvenance: row.metadataProvenance ?? null, metadataGap: row.metadataGap ?? null };
    const phase = row.state ?? row.status ?? data.state;
    if (row.detached || row.processTerminal === false || data.processTerminal === false || ['paused', 'running', 'queued', 'stopping'].includes(phase)) {
      attempt.status = phase === 'paused' ? 'paused' : 'unknown';
      attempt.failure = 'native child has not confirmed process termination';
      return true; // Preserve ownership and accept a later authoritative completion.
    }
    const terminal = row.processTerminal === true || data.processTerminal === true || Number.isInteger(row.exitCode) || row.success === true || data.success === true || ['complete', 'completed', 'failed', 'stopped', 'rejected'].includes(phase);
    if (!terminal) { attempt.status = 'unknown'; attempt.failure = 'native result does not confirm process termination'; return true; }
    const failed = data.success === false || row.success === false || (row.exitCode !== undefined && row.exitCode !== 0) || row.error || row.timedOut || row.stopped || row.interrupted || row.detached || row.turnBudgetExceeded || row.structuredOutputFailed || ['failed', 'paused', 'stopped', 'rejected'].includes(row.state ?? row.status);
    const success = !failed && (row.success === true || row.exitCode === 0 || row.status === 'complete' || row.status === 'completed');
    attempt.nativeTerminal = true; attempt.status = success ? 'complete' : 'failed';
    if (!success) { attempt.failure = row.error ?? 'native child not successful/terminal'; return true; }
    try {
      check(row.outputState !== 'absent', 'native result has no substantive output');
      const material = nativeMaterial(row, this.state.session);
      const parsed = parsePacket(material.output, attempt, lane);
      bindPacketEvidence(parsed.packet, material);
      Object.assign(attempt, { packet: parsed.packet, packetHash: parsed.hash, outputHash: parsed.outputHash, evidenceProvenance: material.provenance });
      attempt.completedSnapshot = laneSnapshot(this.state.plan, lane);
      if (lane.access === 'read') check(attempt.preparedSnapshot === attempt.completedSnapshot, 'read-only lane source/inputs changed during review');
      delete attempt.failure; delete attempt.reconciliationGap;
    } catch (error) { attempt.failure = `packet gap: ${error.message}`; attempt.status = 'failed'; }
    return true;
  }
  resolved(finding, policy) {
    const key = finding.resolution?.attempt;
    const coverage = this.state.coverage.findLast(c => c.attempt === key && c.obligation === finding.obligation && c.verdict === 'pass');
    const attempt = key && this.state.attempts.find(a => a.id === key);
    return Boolean(coverage && attempt?.consumed && attempt.status === 'complete'
      && policy.config?.reviewers.includes(attempt.actual.agent)
      && coverage.snapshot === coverageSnapshot(this.state.plan, this.lane(coverage.lane), finding.obligation));
  }
  consume(key, policy) {
    const attempt = this.state.attempts.find(a => a.id === key);
    check(attempt?.packet && attempt.status === 'complete', attempt?.failure ?? 'successful authentic native packet required');
    const lane = this.lane(attempt.lane), packet = attempt.packet;
    check(attempt.completedSnapshot === laneSnapshot(this.state.plan, lane), 'packet stale since completion');
    if (attempt.consumed) return { attempt: key, consumed: true, packetHash: attempt.packetHash };
    if (lane.role === 'reviewer') {
      check(policy.effective && policy.config.reviewers.includes(attempt.actual.agent), 'actual reviewer agent no longer trusted');
      check(attempt.childRunId && !this.state.attempts.some(a => a.role === 'writer' && a.childRunId === attempt.childRunId), 'reviewer identity must be independent of writer');
      for (const resolution of packet.resolutions) {
        const finding = this.state.findings.find(f => f.id === resolution.finding);
        check(finding && lane.obligations.includes(finding.obligation), 'resolution of unknown/unassigned finding');
        const coverage = packet.coverage.find(c => c.obligation === finding.obligation && c.verdict === 'pass');
        check(coverage && coverage.snapshot === coverageSnapshot(this.state.plan, lane, finding.obligation), 'resolution requires current independent passing coverage');
      }
      for (const coverage of packet.coverage) this.state.coverage.push({ ...coverage, attempt: key, childRunId: attempt.childRunId, lane: lane.id, packetHash: attempt.packetHash, revision: this.state.revision });
      for (const resolution of packet.resolutions) this.state.findings.find(f => f.id === resolution.finding).resolution = { ...resolution, attempt: key, childRunId: attempt.childRunId };
    } else check(packet.coverage.length === 0 && packet.resolutions.length === 0, 'non-reviewer cannot grant coverage/resolve review');
    for (const finding of packet.findings) this.state.findings.push({ ...finding, id: `${key}/${finding.id}`, attempt: key, childRunId: attempt.childRunId });
    attempt.consumed = true;
    if (packet.blockers.length) attempt.status = 'blocked';
    this.event('packet-consumed', { attempt: key });
    return { attempt: key, consumed: true, packetHash: attempt.packetHash, packet };
  }
  parent(key, conclusion, evidence) {
    const lane = this.lane(key); check(lane.owner === 'parent', 'not parent-owned integration'); this.ready(lane);
    text(conclusion, 'conclusion'); check(Array.isArray(evidence) && evidence.length > 0, 'parent evidence links required'); evidence.forEach(e => text(e, 'evidence'));
    this.state.parentWork.push({ lane: key, conclusion, evidence, consumed: true, status: 'complete', completedSnapshot: laneSnapshot(this.state.plan, lane), provenance: 'parent attestation; never independent review' });
    return this.event('parent-integration', { lane: key });
  }
  updateInput(key, value) {
    const input = this.state.plan?.inputs.find(i => i.id === key); check(input, 'unknown input'); text(value, 'input value/revision'); input.value = value;
    return this.event('input-revised', { input: key });
  }
  gate(policy) {
    const gaps = [];
    if (!policy.effective) gaps.push(policy.reason);
    if (!this.state.plan) return { pass: false, gaps: [...gaps, 'no plan'], workflowAcceptance: false };
    const coverage = this.state.plan.obligations.map(o => {
      const rows = this.state.coverage.filter(c => c.obligation === o.id);
      const current = rows.filter(c => {
        const a = this.state.attempts.find(a => a.id === c.attempt), lane = this.lane(c.lane);
        return a.consumed && a.status === 'complete' && policy.config?.reviewers.includes(a.actual.agent) && c.snapshot === coverageSnapshot(this.state.plan, lane, o.id);
      });
      const latest = current.at(-1);
      const state = latest?.verdict ?? (rows.length ? 'stale' : 'missing');
      if (state !== 'pass') gaps.push(`${o.kind} ${o.id}: ${state}`);
      return { obligation: o.id, state, attempt: latest?.attempt ?? null, packetHash: latest?.packetHash ?? null };
    });
    for (const finding of this.state.findings) if (finding.severity === 'blocker') {
      if (!this.resolved(finding, policy)) gaps.push(`unresolved/stale blocker: ${finding.id}`);
    }
    for (const lane of this.state.plan.lanes) {
      const latest = lane.owner === 'parent' ? this.state.parentWork.findLast(p => p.lane === lane.id) : this.state.attempts.findLast(a => a.lane === lane.id && a.status !== 'cancelled');
      if (!latest?.consumed || latest.status !== 'complete') gaps.push(`lane ${lane.id}: ${latest?.status ?? 'missing'}/unconsumed`);
      else if (lane.role !== 'reviewer' && latest.completedSnapshot !== laneSnapshot(this.state.plan, lane)) gaps.push(`lane ${lane.id}: stale work`);
    }
    for (const a of this.state.attempts) if (['prepared', 'calling', 'running', 'paused', 'unknown'].includes(a.status)) gaps.push(`unfinished/unknown lane: ${a.lane}/${a.id}`);
    return { pass: gaps.length === 0, gaps, coverage, workflowAcceptance: false, note: 'Review bookkeeping only; workflow_contract and native runtime remain authoritative.' };
  }
}
