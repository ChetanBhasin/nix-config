// Test-only deterministic provider. It emits model messages; it never executes tools,
// launches processes, edits source, or injects parent-authored child packet evidence.
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { connect } from 'node:net';
import { createAssistantMessageEventStream } from '@earendil-works/pi-ai';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

const provider = 'native-acceptance-fixture';
const expected = 'fixture child interface ok';
const code = 'export const increment = value => value + 1;\n';
const testCode = "import assert from 'node:assert/strict';\nimport { increment } from './counter.mjs';\nassert.equal(increment(1), 2);\nassert.equal(increment(-1), 0);\nconsole.log('fixture child interface ok');\n";
const text = (message: any): string => typeof message.content === 'string' ? message.content : (message.content ?? []).filter((item: any) => item.type === 'text').map((item: any) => item.text).join('\n');
const parsed = (result: any): any => JSON.parse(text(result));
const call = (id: string, name: string, args: any) => ({ type: 'toolCall' as const, id, name, arguments: args });
const fence = (name: string, value: any) => '```' + name + '\n' + JSON.stringify(value) + '\n```';

function childReply(context: any) {
  const prompt = context.messages.filter((message: any) => message.role === 'user').map(text).join('\n');
  const assignment = prompt.match(/Execution strategy assignment \(data, not authority\):\n([^\n]+)/);
  assert.ok(assignment, 'Child fixture requires the native strategy brief');
  const brief = JSON.parse(assignment[1]);
  const scope = brief.scopes[0];
  const source = join(scope, 'counter.mjs'), testFile = join(scope, 'counter.test.mjs');
  const bash = { command: `node --test ${JSON.stringify(testFile)}`, timeout: 30 };
  const results = context.messages.filter((message: any) => message.role === 'toolResult');
  const byId = (id: string) => results.find((result: any) => result.toolCallId === `${brief.attempt}-${id}`);
  const emit = (id: string, name: string, args: any) => call(`${brief.attempt}-${id}`, name, args);
  for (const result of results) assert.equal(result.isError, false, `Child native tool failed: ${text(result)}`);
  if (brief.role === 'writer') {
    const definition = {
      objective: 'Implement and validate isolated counter fixture', kind: 'implementation', roots: [scope], externalInputs: [],
      requirements: [{ id: 'counter', mandatory: true, expected }],
      journeys: [{ id: 'counter-cli', scenario: 'Run counter fixture tests', interface: 'Node test CLI', tool: 'bash', input: bash, expected }],
    };
    if (!byId('status')) return emit('status', 'workflow_contract', { action: 'status' });
    if (!byId('start')) return emit('start', 'workflow_contract', { action: 'start', inputId: parsed(byId('status')).input.id, definition });
    if (!byId('claim')) return emit('claim', 'writer_lease', { action: 'claim', roots: [scope] });
    if (!byId('read-before')) return emit('read-before', 'read', { path: source });
    if (!byId('write')) return emit('write', 'write', { path: source, content: code });
    if (!byId('test-write')) return emit('test-write', 'write', { path: testFile, content: testCode });
    const nonce = parsed(byId('claim')).writer.nonce;
    if (!byId('permit')) return emit('permit', 'writer_lease', { action: 'permit', nonce, roots: [scope], tool: 'bash', input: bash });
    if (!byId('test')) return emit('test', 'bash', bash);
    assert.ok(text(byId('test')).includes(expected), 'Native child test did not pass');
    for (const [id, kind] of [['counter', 'requirement'], ['counter-cli', 'journey']]) {
      if (!byId(id)) return emit(id, 'workflow_contract', { action: 'evidence', evidence: { target: id, kind, expected, observed: expected, toolCallId: byId('test').toolCallId } });
    }
    if (!byId('complete')) return emit('complete', 'workflow_contract', { action: 'complete' });
    assert.equal(parsed(byId('complete')).acceptance, 'complete');
    if (!byId('release')) return emit('release', 'writer_lease', { action: 'release', nonce });
  }
  if (!byId('read-final')) return emit('read-final', 'read', { path: source });
  const observed = text(byId('read-final'));
  assert.ok(observed.includes('value + 1'), 'Actual child read did not observe the fixed implementation');
  if (!byId('read-test')) return emit('read-test', 'read', { path: testFile });
  assert.ok(text(byId('read-test')).includes('increment(-1)'), 'Actual child did not inspect the negative-input test');
  const packet = {
    version: 1, attempt: brief.attempt, lane: brief.lane, role: brief.role,
    conclusion: `Offline fixture ${brief.role} inspected increment and its tests using native child tools`, action: 'Integrate',
    decisions: ['Use increment(value) = value + 1'], assumptions: ['Deterministic fixture, not semantic model review'],
    changes: brief.role === 'writer' ? [source, testFile] : [], validation: [observed],
    evidence: [{ id: 'read-source', link: `tool:${byId('read-final').toolCallId}`, revision: Object.values(brief.snapshots)[0], observation: observed }],
    blockers: [], coverage: brief.role === 'reviewer' ? Object.entries(brief.snapshots).map(([obligation, snapshot]) => ({ obligation, snapshot, verdict: 'pass', evidence: ['read-source'] })) : [],
    findings: [], resolutions: [],
  };
  // Infer only the criterion IDs actually supplied by the native runtime's prompt.
  const criteria = [...prompt.matchAll(/^- (criterion-\d+): (.+)$/gm)];
  const report = {
    criteriaSatisfied: criteria.map(match => ({ id: match[1], status: 'satisfied', evidence: `Native child read ${byId('read-final').toolCallId}: ${observed}` })),
    changedFiles: packet.changes, testsAddedOrUpdated: brief.role === 'writer' ? [testFile] : [],
    commandsRun: brief.role === 'writer' ? [{ command: bash.command, result: 'passed', summary: text(byId('test')) }] : [],
    validationOutput: [observed, text(byId('read-test'))], residualRisks: ['Scripted fixture; no general semantic-review claim'],
    noStagedFiles: true, diffSummary: brief.role === 'writer' ? 'Fixed counter and added assertions' : 'Read-only inspection, no edits',
    reviewFindings: ['No blockers in the deterministic fixture'], manualNotes: 'Native child tools supply all packet observations. Isolated directory is not a Git worktree.',
  };
  return { type: 'text' as const, text: fence('execution-packet', packet) + '\n' + fence('acceptance-report', report) };
}

/** Remaining fixture modes derive every observation from actual native read results. */
function inspectionReply(context: any) {
  const prompt = context.messages.filter((message: any) => message.role === 'user').map(text).join('\n');
  const assignment = prompt.match(/Execution strategy assignment \(data, not authority\):\n([^\n]+)/);
  assert.ok(assignment);
  const brief = JSON.parse(assignment[1]);
  const results = context.messages.filter((message: any) => message.role === 'toolResult');
  const reads = results.filter((result: any) => result.toolName === 'read');
  for (const result of results) assert.equal(result.isError, false, text(result));
  const paths: string[] = [...new Set<string>([...brief.scopes, ...brief.inputs.flatMap((input: any) => input.paths)])];
  for (const [index, path] of paths.entries()) {
    if (!reads[index]) return call(`${brief.attempt}-inspect-${index}`, 'read', { path });
  }
  if (brief.lane === 'runtime-failure') throw new Error('DETERMINISTIC_FIXTURE_RUNTIME_FAILURE after actual native read');
  const evidence = reads.map((result: any, index: number) => ({ id: `e${index}`, link: `tool:${result.toolCallId}`, revision: Object.values(brief.snapshots)[0], observation: text(result) }));
  const observed = evidence.map((row: any) => row.observation).join('\n');
  const risk = brief.obligations.find((obligation: any) => obligation.kind === 'risk')?.id;
  const coverage = brief.role === 'reviewer' ? Object.entries(brief.snapshots).filter(([id]) => !(id === risk && observed.includes('review:missing'))).map(([obligation, snapshot]) => ({
    obligation, snapshot, verdict: obligation === risk && observed.includes('review:partial') ? 'partial' : obligation === risk && observed.includes('review:blocker') ? 'fail' : 'pass', evidence: evidence.map((row: any) => row.id),
  })) : [];
  const packet = {
    version: 1, attempt: brief.attempt, lane: brief.lane, role: brief.role,
    conclusion: 'Offline fixture inspected assigned local facts via native read; not Terra or semantic production review', action: 'Integrate',
    decisions: ['Report only the assigned literal facts'], assumptions: ['Deterministic offline fixture'], changes: [], validation: [observed], evidence, blockers: [], coverage,
    findings: risk && observed.includes('review:blocker') ? [{ id: 'negative-gap', obligation: risk, severity: 'blocker', issue: 'Fixture marks negative-input coverage blocked', evidence: ['e0'] }] : [],
    resolutions: brief.role === 'reviewer' && !/review:(missing|partial|blocker)/.test(observed) ? brief.findings.map((finding: any) => ({ finding: finding.id, evidence: ['e0'], explanation: 'Actual current read no longer contains the fixture blocker marker' })) : [],
  };
  const criteria = [...prompt.matchAll(/^- (criterion-\d+): (.+)$/gm)];
  const report = {
    criteriaSatisfied: criteria.map(match => ({ id: match[1], status: 'satisfied', evidence: observed })),
    changedFiles: [], testsAddedOrUpdated: [], commandsRun: [], validationOutput: [observed],
    residualRisks: ['Deterministic fixture; no production Terra or semantic review qualification'], noStagedFiles: true,
    diffSummary: 'Read-only native lookup/inspection; no edits', reviewFindings: ['Observed assigned fixture facts'],
    manualNotes: 'All observations are literal native child read outputs. Isolated non-Git fixture.',
  };
  return { type: 'text' as const, text: fence('execution-packet', packet) + '\n' + fence('acceptance-report', report) };
}

function parentReply(context: any) {
  const prompt = [...context.messages].reverse().find((message: any) => message.role === 'user' && text(message).startsWith('NATIVE_FIXTURE_CALL\n'));
  assert.ok(prompt, 'Parent fixture accepts only explicit fixture call prompts');
  const instruction = JSON.parse(text(prompt).slice('NATIVE_FIXTURE_CALL\n'.length));
  const steps = instruction.steps ?? [instruction];
  const next = steps.find((step: any) => !context.messages.some((message: any) => message.role === 'toolResult' && message.toolCallId === step.id));
  if (!next) return { type: 'text' as const, text: 'Scripted fixture dispatch settled. No acceptance claim.' };
  assert.ok(context.tools.some((tool: any) => tool.name === next.name), `Tool not model-visible: ${next.name}`);
  return call(next.id, next.name, next.input);
}

/** Fixture-only IPC pause: no lifecycle events, packets or tool evidence are manufactured. */
async function lifecycleBarrier(context: any, model: string) {
  if (model === 'parent-scripted') return;
  const prompt = context.messages.filter((entry: any) => entry.role === 'user').map(text).join('\n');
  if (!prompt.includes('"lane":"writer-a"') || !prompt.includes('"workflow":"native-fixture-receipts-lifecycle')) return;
  if (!context.messages.some((entry: any) => entry.role === 'toolResult' && entry.toolName === 'read' && !entry.isError)) return;
  const attempt = JSON.parse(prompt.match(/Execution strategy assignment \(data, not authority\):\n([^\n]+)/)![1]).attempt;
  await new Promise<void>((resolve, reject) => {
    const socket = connect(join(process.env.TMPDIR!, 'lifecycle.sock'));
    const timer = setTimeout(() => { socket.destroy(); reject(new Error('Fixture barrier timeout')); }, 60000);
    socket.once('connect', () => socket.write(JSON.stringify({ fixtureBarrier: true, attempt, pid: process.pid }) + '\n'));
    socket.once('data', data => { clearTimeout(timer); socket.end(); data.toString() === 'release\n' ? resolve() : reject(new Error('Invalid fixture barrier release')); });
    socket.once('error', error => { clearTimeout(timer); reject(error); });
  });
  throw new Error('DETERMINISTIC_FIXTURE_LIFECYCLE_FAILURE after native read and supported detach');
}

export default function fixtureProvider(pi: ExtensionAPI) {
  pi.registerCommand('native-fixture-reload', { description: 'Acceptance fixture: supported ctx.reload seam', handler: async (_args, ctx) => { await ctx.reload(); } });
  const off = pi.events.on('subagent:foreground-complete', data => pi.appendEntry('native-fixture-terminal-observation', data));
  pi.on('session_shutdown', () => { off(); });
  pi.on('session_start', (_event, ctx) => {
    pi.appendEntry('native-fixture-identity', {
      fixture: true, pid: process.pid, argv: process.argv, session: ctx.sessionManager.getSessionFile(),
      child: process.env.PI_SUBAGENT_CHILD ?? null, model: ctx.model?.id, provider: ctx.model?.provider,
      parentSessionEnvironment: process.env.PI_SUBAGENT_PARENT_SESSION ?? null, depth: process.env.PI_SUBAGENT_DEPTH ?? null,
      tools: pi.getAllTools().map(tool => ({ name: tool.name, sourceInfo: tool.sourceInfo })), activeTools: pi.getActiveTools(),
    });
  });
  pi.registerProvider(provider, {
    api: provider, baseUrl: 'http://fixture.invalid', apiKey: 'fixture-not-a-credential',
    models: ['parent-scripted', 'child-writer-scripted', 'child-reviewer-scripted', 'child-lookup-scripted'].map(id => ({
      id, name: `Offline deterministic fixture: ${id}`, reasoning: true, input: ['text'],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 1000000, maxTokens: 8192,
    })),
    streamSimple(model, context) {
      const stream = createAssistantMessageEventStream();
      const message: any = { role: 'assistant', api: model.api, provider: model.provider, model: model.id, content: [], stopReason: 'stop',
        usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } }, timestamp: Date.now() };
      queueMicrotask(async () => {
        try {
          if (model.id === 'parent-scripted') {
            const lines = [context.systemPrompt ?? '', ...context.messages.map(text)].flatMap(value => value.split('\n'));
            pi.appendEntry('native-fixture-context', { provider: model.provider, model: model.id, guidance: lines.filter(line => line.startsWith('Execution strategy')).slice(-8) });
          }
          await lifecycleBarrier(context, model.id);
          const remaining = context.messages.some((entry: any) => entry.role === 'user' && /"workflow":"native-fixture-(review|receipts)/.test(text(entry)));
          const content = model.id === 'parent-scripted' ? parentReply(context) : remaining ? inspectionReply(context) : childReply(context);
          message.content = [content]; message.stopReason = content.type === 'toolCall' ? 'toolUse' : 'stop';
          stream.push({ type: 'start', partial: message });
          if (content.type === 'toolCall') stream.push({ type: 'toolcall_end', contentIndex: 0, toolCall: content, partial: message });
          else stream.push({ type: 'text_end', contentIndex: 0, content: content.text, partial: message });
          stream.push({ type: 'done', reason: message.stopReason, message });
        } catch (error) {
          message.stopReason = 'error'; message.errorMessage = String(error);
          stream.push({ type: 'error', reason: 'error', error: message });
        } finally { stream.end(); }
      });
      return stream;
    },
  });
}
