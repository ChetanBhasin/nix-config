import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';
import { getAgentDir, truncateHead } from '@earendil-works/pi-coding-agent';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { promoteOwnerLaunchToAsync, DELEGATION_GUIDANCE } from '../auto-mode/execution-strategy-handoff.ts';
import { strategySchema } from './schema.ts';
import { StrategyLedger, emptyState } from './ledger.mjs';
import { readPolicy, isOwner, policyContext, STATE_ENTRY } from './policy.mjs';
import { statePatch, restore } from './persistence.mjs';
import { check, digest } from './workspace.mjs';
import { observedUsage } from './packets.mjs';

const TELEMETRY = 'execution-strategy:telemetry:v1';
/** Tool provenance, not tool name alone, identifies the native result boundary. */
function nativeTool(pi: ExtensionAPI, name: string): string | false {
  const source = pi.getAllTools().find(t => t.name === name)?.sourceInfo;
  if (!source || source.source === 'sdk' || source.source === 'builtin') return false;
  let dir = dirname(source.path);
  while (dir !== dirname(dir)) {
    try { return JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).name === 'pi-subagents' ? dir : false; }
    catch { dir = dirname(dir); }
  }
  return false;
}

export default function executionStrategy(pi: ExtensionAPI) {
  let ledger = new StrategyLedger(emptyState('unbound'));
  let context: ExtensionContext | undefined;
  let policy = readPolicy([], getAgentDir(), isOwner());
  let restoreError: string | undefined;
  let policyHash = '', coverageHash = '';
  const earlyCompletions = new Map<string, { name: string; data: Record<string, any> }>();
  const trustedCalls = new Set<string>();
  const disposers: Array<() => void> = [];

  function append(type: string, data: unknown) {
    try { pi.appendEntry(type, data); }
    catch (error) {
      restoreError = `Execution strategy persistence uncertain: ${String(error)}. Restore the authoritative session branch before proceeding.`;
      earlyCompletions.clear(); trustedCalls.clear();
      throw new Error(restoreError, { cause: error });
    }
  }
  function telemetry(kind: string, data: unknown) {
    if (!context || restoreError) return;
    append(TELEMETRY, { version: 1, kind, session: context.sessionManager.getSessionId(), workflow: ledger.state.plan?.workflow ?? null, branchLeaf: context.sessionManager.getLeafId(), data });
  }
  function refresh(ctx: ExtensionContext, rebuild = false) {
    context = ctx;
    if (rebuild || ledger.state.session !== ctx.sessionManager.getSessionId()) {
      try { ledger = new StrategyLedger(restore(ctx.sessionManager.getBranch(), ctx.sessionManager.getSessionId())); restoreError = undefined; }
      catch (error) { restoreError = String(error); }
      earlyCompletions.clear(); trustedCalls.clear(); policyHash = ''; coverageHash = '';
    }
    policy = readPolicy(ctx.sessionManager.getBranch(), getAgentDir(), isOwner(process.env, ctx.sessionManager.getSessionId()));
    if (!restoreError && digest(policy) !== policyHash) { telemetry('policy', policy); policyHash = digest(policy); }
  }
  function change<T>(fn: (draft: StrategyLedger) => T): T {
    check(!restoreError, `branch strategy restore failed: ${restoreError}`);
    const before = ledger.state, draft = new StrategyLedger(structuredClone(before));
    const result = fn(draft);
    if (digest(before) !== digest(draft.state)) {
      draft.state.revision = Math.max(before.revision + 1, draft.state.revision);
      append(STATE_ENTRY, statePatch(before, draft.state));
      ledger = draft;
    }
    return result;
  }
  function completion(name: string, data: Record<string, any>) {
    return change(d => name === 'subagent:foreground-complete'
      ? d.nativeForegroundComplete(data)
      : d.nativeComplete(data.runId ?? data.id, data, 'native async completion event'));
  }
  function gate() {
    check(!restoreError, restoreError);
    const result = ledger.gate(policy);
    if (coverageHash !== digest(result)) { telemetry('coverage', result); coverageHash = digest(result); }
    return result;
  }
  function status() {
    return { policy, restoreError: restoreError ?? null, workflow: ledger.state.plan?.workflow ?? null, revision: ledger.state.revision,
      plan: ledger.state.plan,
      attempts: ledger.state.attempts.map((a: Record<string, unknown>) => ({ id: a.id, lane: a.lane, role: a.role, status: a.status, toolCallId: a.toolCallId ?? null, runId: a.runId ?? null, childRunId: a.childRunId ?? null, nativeLocator: { foregroundHistory: a.foregroundHistory ?? null, parentSession: a.parentSession ?? null }, consumed: a.consumed, failure: a.failure ?? null, reconciliationGap: a.reconciliationGap ?? null, lastObservedState: a.lastObservedState ?? null, plannedConfig: a.plannedConfig, actual: a.actual, packetHash: a.packetHash ?? null, parentDiscoveryOverlap: a.parentDiscoveryOverlap ?? [] })),
      parentWork: ledger.state.parentWork, parentDiscovery: ledger.state.discovery, unowned: ledger.state.unknown, findings: ledger.state.findings, review: gate(),
      telemetry: { entryType: TELEMETRY, parentUsage: 'per-message native provenance entries; absent fields unknown', childUsage: 'per-attempt actual; not summed with parent', savings: null, savingsReason: 'not measured; overlap does not prove savings' } };
  }
  pi.registerTool({
    name: 'execution_strategy', label: 'Execution strategy', parameters: strategySchema,
    description: 'Branch-local strategy plan, exact native launch preparation, authentic packet consumption and review gaps. Never launches, writes source, grants leases or completes workflow_contract. No packet/path upload accepted. status output bounded to 48KB; full state in branch entries. Read README for schema.',
    promptSnippet: 'Plan scoped dependency-aware ownership; prepare native subagent calls; consume authentic packets and inspect review gaps',
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      refresh(ctx);
      check(!restoreError, restoreError);
      change(d => d.reconcile());
      if (!['status', 'gate'].includes(params.action)) check(policy.owner && policy.effective, policy.reason ?? 'ordinary children cannot orchestrate');
      let result: unknown;
      switch (params.action) {
        case 'status': result = status(); break;
        case 'gate': result = gate(); break;
        case 'plan': case 'extend': result = change(d => d.plan(params.plan, params.action === 'extend')); break;
        case 'prepare': result = change(d => d.prepare(params.lane, policy, { ...(params.async === undefined ? {} : { async: params.async }), foregroundOnly: params.foregroundOnly })); break;
        case 'consume': result = change(d => d.consume(params.attempt, policy)); break;
        case 'parent': result = change(d => d.parent(params.lane, params.conclusion, params.evidence)); break;
        case 'input': result = change(d => d.updateInput(params.input, params.value)); break;
        case 'cancel': result = change(d => {
          const a = d.state.attempts.find((a: Record<string, unknown>) => a.id === params.attempt);
          check(a?.status === 'prepared', 'cancel only an unlaunched preparation; native runtime owns live stop');
          a.status = 'cancelled'; return { cancelled: a.id };
        }); break;
      }
      telemetry('tool', { toolCallId: _toolCallId, action: params.action, revision: ledger.state.revision });
      const rendered = truncateHead(JSON.stringify(result), { maxBytes: 48000, maxLines: 1900 });
      return { content: [{ type: 'text', text: rendered.content + (rendered.truncated ? '\n[Truncated; inspect execution-strategy branch entries for full state.]' : '') }], details: result };
    },
  });

  pi.on('session_start', (_event, ctx) => refresh(ctx, true));
  pi.on('session_tree', (_event, ctx) => refresh(ctx, true));
  pi.on('resources_discover', (_event, ctx) => refresh(ctx));
  pi.on('before_agent_start', (event, ctx) => { refresh(ctx); return { systemPrompt: `${event.systemPrompt}\n\n${policyContext(policy)}\n${policy.owner && policy.effective ? DELEGATION_GUIDANCE : ''}` }; });
  pi.on('context', (event, ctx) => {
    refresh(ctx);
    return { messages: [...event.messages, { role: 'custom', customType: 'execution-strategy-policy', content: policyContext(policy), display: false, timestamp: Date.now() }] };
  });
  pi.on('tool_call', async (event, ctx) => {
    try { refresh(ctx); } catch (error) { return { block: true, reason: String(error) }; }
    if (restoreError) return event.toolName === 'subagent' ? { block: true, reason: restoreError } : undefined;
    if (event.toolName === 'subagent' && !policy.owner && [undefined, 'resume', 'project.open', 'schedule.create', 'schedule.run'].includes(event.input.action as string | undefined)) {
      return { block: true, reason: 'Ordinary child cannot become an execution-strategy orchestrator.' };
    }
    if (event.toolName === 'subagent' && event.input.action === undefined) {
      if (!policy.owner) return { block: true, reason: 'Ordinary child cannot become an execution-strategy orchestrator.' };
      if (policy.effective) promoteOwnerLaunchToAsync(event.input, { enabled: true, owner: true });
      const nativeRoot = nativeTool(pi, 'subagent');
      if (!nativeRoot) { telemetry('unowned-launch', { toolCallId: event.toolCallId, reason: 'subagent tool provenance not native pi-subagents' }); return; }
      // Read the actual runtime's exported location, not a guessed or caller-supplied cache path.
      let foregroundHistory: string;
      try {
        const runtime = await import(pathToFileURL(join(nativeRoot, 'src/shared/types.ts')).href);
        check(typeof runtime.DIRS?.results === 'string', 'native foreground history location unavailable');
        foregroundHistory = join(runtime.DIRS.results, 'foreground-history.json');
      } catch (error) { return { block: true, reason: `Native lifecycle binding unavailable: ${String(error)}` }; }
      trustedCalls.add(event.toolCallId);
      change(d => d.launch(event.toolCallId, event.input, policy, foregroundHistory));
    } else if (policy.owner && ['read', 'grep', 'find', 'ls', 'read_symbol', 'read_enclosing', 'module_report', 'symbol_search', 'project_report', 'bash'].includes(event.toolName)) {
      const path = 'path' in event.input && typeof event.input.path === 'string' ? resolve(ctx.cwd, event.input.path) : ['grep', 'find', 'ls'].includes(event.toolName) ? ctx.cwd : undefined;
      change(d => d.observeDiscovery(event.toolCallId, path, event.toolName));
    }
  });
  pi.on('tool_result', (event, ctx) => {
    refresh(ctx);
    if (event.toolName === 'execution_strategy') telemetry('strategy-tool-result', { toolCallId: event.toolCallId, isError: event.isError, failure: event.isError ? JSON.stringify(event.content).slice(0, 4000) : null });
    if (trustedCalls.has(event.toolCallId)) telemetry('native-tool-result', { toolCallId: event.toolCallId, isError: event.isError, provenance: 'tool_result observed; finalized at tool_execution_end' });
  });
  pi.on('tool_execution_end', (event, ctx) => {
    refresh(ctx);
    if (!trustedCalls.delete(event.toolCallId)) return;
    try {
      const result = event.result as { details?: Record<string, unknown> };
      const attempt = change(d => d.bindResult(event.toolCallId, result.details ?? {}, event.isError, ctx.sessionManager.getSessionFile() ?? ctx.sessionManager.getSessionId()));
      for (const key of [attempt?.runId, attempt?.childRunId]) {
        const early = key && earlyCompletions.get(key);
        if (early) { earlyCompletions.delete(key); completion(early.name, early.data); }
      }
      telemetry('native-finalized', { toolCallId: event.toolCallId, attempt: attempt?.id ?? null });
    } catch (error) { telemetry('observer-gap', { toolCallId: event.toolCallId, error: String(error) }); }
  });
  pi.on('message_end', (event, ctx) => {
    refresh(ctx);
    if (event.message.role === 'assistant') telemetry('parent-usage', { provenance: 'native parent assistant message; not child totals', timestamp: event.message.timestamp, model: event.message.model, provider: event.message.provider, usage: observedUsage(event.message.usage) });
  });
  for (const name of ['subagent:async-started', 'subagent:async-complete', 'subagent:foreground-complete', 'subagent:process-terminal', 'subagent:child-status']) {
    disposers.push(pi.events.on(name, (raw: unknown) => {
      if (!context || !raw || typeof raw !== 'object') return;
      const data = raw as Record<string, any>;
      const runId = data.runId ?? data.id;
      if (typeof runId !== 'string') return;
      const session = context.sessionManager;
      if (data.sessionId && ![session.getSessionId(), session.getSessionFile()].includes(data.sessionId)) return;
      const isCompletion = name === 'subagent:async-complete' || name === 'subagent:foreground-complete';
      const attempt = ledger.state.attempts.find((a: Record<string, unknown>) => a.runId === runId || (name === 'subagent:foreground-complete' && a.childRunId === runId));
      if (!attempt) {
        // Events cannot create ownership. Buffer only during a verified native tool call, bounded by in-flight calls.
        if (isCompletion && trustedCalls.size && earlyCompletions.size < trustedCalls.size) earlyCompletions.set(runId, { name, data });
        return;
      }
      telemetry('native-lifecycle', { event: name, runId, attempt: attempt.id, state: data.status ?? data.state ?? null, childId: data.childId ?? null, childRunId: data.childRunId ?? null, success: data.success ?? null, processTerminal: data.processTerminal ?? null, config: 'unknown unless returned per-child' });
      if (isCompletion) {
        try { completion(name, data); }
        catch (error) { telemetry('observer-gap', { runId, error: String(error) }); }
      }
    }));
  }
  pi.on('session_shutdown', () => { disposers.splice(0).forEach(dispose => dispose()); context = undefined; earlyCompletions.clear(); trustedCalls.clear(); });
}
