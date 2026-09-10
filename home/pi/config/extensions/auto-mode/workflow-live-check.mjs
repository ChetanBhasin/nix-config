// Explicit billable qualification: node workflow-live-check.mjs --live
// All application/session/lease state is isolated in /tmp. SDK auth may refresh normally.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createJiti } from '../../npm/node_modules/jiti/lib/jiti.mjs';

if (!process.argv.includes('--live')) {
  console.error('Pass --live to authorize real Astra/max provider requests.');
  process.exit(2);
}
const live = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi/agent');
const packageDir = process.env.PI_TEST_PACKAGE_DIR || path.join(live, 'npm/node_modules/@earendil-works/pi-coding-agent');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-workflow-live-'));
const root = path.join(scratch, 'app');
const agentDir = path.join(scratch, 'agent');
fs.mkdirSync(root);
const cli = path.join(root, 'greet.mjs');
fs.writeFileSync(cli, 'console.log("not implemented");\n');
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
const invoke = `${quote(process.execPath)} ${quote(cli)}`;
const success = `${invoke} Ada`;
const failure = `output="$(${invoke} 2>&1)"; status=$?; printf '%s\\nexit=%s\\n' "$output" "$status"; test "$status" -eq 2`;
const definition = {
  objective: 'Implement and verify an isolated greeting CLI', kind: 'implementation', roots: [root], externalInputs: [],
  requirements: [{ id: 'named', mandatory: true, expected: 'Hello, Ada!' }, { id: 'missing', mandatory: true, expected: 'Name required' }],
  journeys: [
    { id: 'user-success', scenario: 'User greets Ada through the CLI', interface: cli, tool: 'bash', input: { command: success }, expected: 'Hello, Ada!' },
    { id: 'user-failure', scenario: 'User omits the required name and gets a diagnostic with exit code 2', interface: cli, tool: 'bash', input: { command: failure }, expected: 'Name required\nexit=2' },
  ],
};
let session, deadline, report;
let stage = 'setup';
const requests = [], errors = [], observedCalls = [];
Object.assign(process.env, { PI_SKIP_VERSION_CHECK: '1', PI_TELEMETRY: '0',
  XDG_DATA_HOME: path.join(scratch, 'data'), XDG_CACHE_HOME: path.join(scratch, 'cache'), XDG_CONFIG_HOME: path.join(scratch, 'config') });
try {
  const { createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager, SettingsManager } =
    await import(pathToFileURL(path.join(packageDir, 'dist/index.js')).href);
  const jiti = createJiti(import.meta.url);
  const { registerWorkflow } = await jiti.import('./workflow-controller.ts');
  const { WorkflowLedger, LEDGER_ENTRY } = await jiti.import('./workflow-ledger.ts');
  const { WriterLeaseStore } = await jiti.import('./writer-lease.ts');
  const modelsStorePath = path.join(scratch, 'models-store.json');
  if (fs.existsSync(path.join(live, 'models-store.json'))) fs.copyFileSync(path.join(live, 'models-store.json'), modelsStorePath);
  const modelRuntime = await ModelRuntime.create({ authPath: path.join(live, 'auth.json'), modelsPath: path.join(live, 'models.json'),
    modelsStorePath, allowModelNetwork: false, signal: AbortSignal.timeout(15000) });
  const model = modelRuntime.getModel('openai-codex', 'gpt-6-astra');
  assert.ok(model, 'Exact Astra registry metadata required; no fallback');
  const stream = modelRuntime.streamSimple.bind(modelRuntime);
  modelRuntime.streamSimple = (selected, context, options) => {
    requests.push({ provider: selected.provider, model: selected.id, thinking: options?.reasoning });
    return stream(selected, context, options);
  };
  const settingsManager = SettingsManager.inMemory({ packages: [], extensions: [], compaction: { enabled: false },
    retry: { enabled: false, provider: { maxRetries: 0, timeoutMs: 60000 } }, enableInstallTelemetry: false, enableAnalytics: false });
  const sm = SessionManager.create(root, path.join(scratch, 'sessions'));
  const db = path.join(scratch, 'writer-leases.sqlite');
  const loader = new DefaultResourceLoader({ cwd: root, agentDir, settingsManager,
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    systemPromptOverride: () => 'You are an autonomous implementation worker in an isolated acceptance fixture. Follow the workflow/lease tools. Do not modify anything outside the given app root. No network or package installation. This tiny fixture is JavaScript; preserve its language. Read the stub, then intentionally replace its entire tiny body with the correct CLI. Stop only after validated completion and releasing ownership.',
    extensionFactories: [(pi) => registerWorkflow(pi, () => ({ enabled: true, owner: true }), db)] });
  await loader.reload(); assert.deepEqual(loader.getExtensions().errors, []);
  ({ session } = await createAgentSession({ cwd: root, agentDir, resourceLoader: loader, settingsManager, sessionManager: sm,
    modelRuntime, model, thinkingLevel: 'max', tools: ['read', 'write', 'bash', 'workflow_contract', 'writer_lease'] }));
  await session.bindExtensions({ mode: 'print', onError: error => errors.push({ name: error?.name, event: error?.event }) });
  assert.equal(session.thinkingLevel, 'max');
  session.subscribe(event => {
    if (event.type === 'tool_execution_start') observedCalls.push({ id: event.toolCallId, tool: event.toolName });
  });
  stage = 'auth';
  assert.ok(await modelRuntime.getAuth(model, { signal: AbortSignal.timeout(15000) }));
  deadline = setTimeout(() => { void session.abort(); }, 1200000);
  stage = 'implementation-and-acceptance';
  await session.prompt([
    'Implement this tiny CLI: one supplied name prints Hello, <name>!; a missing name prints Name required to stderr and exits 2.',
    'Start with workflow_contract status to obtain inputId, then start with exactly the following definition:',
    JSON.stringify(definition),
    'Claim writer_lease for the app root before writing. Read the stub and intentionally fully replace it. Do not add dependencies or unrelated files.',
    'Every bash call requires a one-use writer_lease permit with its exact input. Use the two pinned journey commands exactly, without adding timeout fields or changing arguments.',
    'After finalized successful tool results, add evidence separately for both requirements and both journeys using their exact expected strings and toolCallIds.',
    'Call complete only after validation passes. Release the nonce in a later turn after the mutation batch has drained. Do not revise or weaken the supplied definition.',
    'Your final reply should be concise. The parent will independently inspect the application, replay both commands and revalidate the persisted ledger.',
  ].join('\n'), { expandPromptTemplates: false, source: 'interactive' });
  const contract = sm.getBranch().findLast(entry => entry.customType === LEDGER_ENTRY)?.data;
  assert.equal(contract?.status, 'complete', 'Real agent did not reach checked acceptance');
  const restored = new WorkflowLedger(() => {}); restored.restore(sm.getBranch());
  assert.deepEqual(restored.issues(sm.getBranch()), []);
  stage = 'independent-outcome-replay';
  assert.equal(execFileSync(process.execPath, [cli, 'Ada'], { encoding: 'utf8' }).trim(), 'Hello, Ada!');
  assert.equal(execFileSync('bash', ['-c', failure], { encoding: 'utf8' }).trim(), 'Name required\nexit=2');
  const store = new WriterLeaseStore(db);
  try { const probe = store.claim('parent-replay', [root]); store.release(probe.owner); }
  finally { store.close(); }
  assert.ok(requests.length > 0);
  assert.ok(requests.every(request => request.provider === 'openai-codex' && request.model === 'gpt-6-astra' && request.thinking === 'max'));
  assert.deepEqual(errors, []);
  report = { passed: true, provider: 'openai-codex', model: 'gpt-6-astra', thinking: 'max', scratch,
    journeys: contract.journeys.map(journey => journey.id), evidence: contract.evidence.map(evidence => ({ target: evidence.target, callId: evidence.receipt.toolCallId })),
    continuations: contract.continuations, leaseReleased: true, independentReplay: true, requests: requests.length, observedCalls };
} catch (error) {
  report = { passed: false, stage, errorType: error?.name, assertionSite: error?.stack?.match(/workflow-live-check\.mjs:\d+:\d+/)?.[0], scratch, requests, errors, observedCalls };
  process.exitCode = 1;
} finally {
  clearTimeout(deadline);
  session?.dispose();
  fs.rmSync(path.join(scratch, 'models-store.json'), { force: true });
  fs.writeFileSync(path.join(scratch, 'result.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify(report));
}
