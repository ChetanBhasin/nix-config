// Offline acceptance through Pi's real RPC/slash interface; no model requests.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { Rpc, isolateProcessEnvironment, assertRoleDetails, assertBuiltinModel, assertFreshProfileStatus, messageText } from './subagent-profiles-runtime.mjs';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const snapshot = fileURLToPath(new URL('./config', import.meta.url));
const runtime = path.join(os.homedir(), '.pi/agent');
// The repository projection is the default; explicitly select frozen live truth before capture.
const live = path.resolve(process.env.PI_TEST_AGENT_DIR ?? snapshot);
const packageDir = process.env.PI_TEST_PACKAGE_DIR ?? path.join(runtime, 'npm/node_modules/@earendil-works/pi-coding-agent');
const subagentsDir = process.env.PI_TEST_SUBAGENTS_DIR ?? path.join(runtime, 'npm/node_modules/pi-subagents');
// Save selectors before clearing the inherited environment; never pass them to discovery.
const deployed = process.env.PI_PROFILES_CHECK_DEPLOYED === '1';
const parentModelOverride = process.env.PI_PROFILES_TEST_PARENT_MODEL;
const source = path.join(live, 'profiles/pi-subagents');
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (cause) { throw new Error(`Cannot read JSON: ${file}`, { cause }); }
}
const profiles = Object.fromEntries(['simple', 'complex', 'max'].map(name => [name, readJson(path.join(source, `${name}.json`))]));
const liveSettings = readJson(path.join(live, 'settings.json'));
const scratchRoot = '/tmp/execution-strategy-tests/profile-qualification';
fs.mkdirSync(scratchRoot, { recursive: true });
const scratch = fs.mkdtempSync(path.join(scratchRoot, 'profiles-'));
const agentDir = path.join(scratch, '.pi/agent');
// This must precede Jiti/native imports, not just the RPC spawn.
const env = isolateProcessEnvironment(scratch, agentDir);
fs.mkdirSync(env.TMPDIR, { recursive: true });
fs.mkdirSync(path.join(agentDir, 'profiles/pi-subagents'), { recursive: true });
fs.cpSync(source, path.join(agentDir, 'profiles/pi-subagents'), { recursive: true });
// Copy the reviewed lookup definition, never its runtime/dependency trees.
fs.cpSync(path.join(live, 'extensions/lookup-role/agents'), path.join(agentDir, 'agents'), { recursive: true });
const initial = { ...liveSettings, packages: [], extensions: [], skills: [], prompts: [] };
if (parentModelOverride) initial.defaultModel = parentModelOverride;
fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify(initial));
// Fixture-only key exposes registry models without reading/refreshing real auth.
fs.writeFileSync(path.join(agentDir, 'auth.json'), JSON.stringify({ 'openai-codex': { type: 'api_key', key: 'fixture-no-network' } }));
// Pi 0.84.4's dynamic catalog is separate from credentials. Reuse only its
// public Codex model metadata for offline lookup, never live auth or tokens.
const catalog = readJson(path.join(runtime, 'models-store.json'))['openai-codex'];
assert.ok(catalog?.models?.length, 'A previously resolved Codex model catalog is required');
fs.writeFileSync(path.join(agentDir, 'models-store.json'), JSON.stringify({ 'openai-codex': catalog }));
fs.writeFileSync(path.join(agentDir, 'models.json'), JSON.stringify({ providers: { 'openai-codex': { apiKey: 'fixture-no-network' } } }));
const require = createRequire(path.join(subagentsDir, 'package.json'));
const { createJiti } = require('jiti');
const jiti = createJiti(import.meta.url, { fsCache: false });
const { resolveEffectiveSubagentModel, buildModelCandidates } = await jiti.import(path.join(subagentsDir, 'src/runs/shared/model-fallback.ts'));
const { assertThinkingWithinCeiling } = await jiti.import(path.join(subagentsDir, 'src/shared/thinking-ceiling.ts'));
const { toModelInfo, resolveEffectiveThinking, getSupportedThinkingLevels } = await jiti.import(path.join(subagentsDir, 'src/shared/model-info.ts'));
// Exercise the real RPC ExtensionCommandContext reload hook in isolated state.
const reloadHarness = path.join(scratch, 'profile-reload.mjs');
fs.writeFileSync(reloadHarness, 'export default pi => { pi.registerCommand("profile-test-reload", { handler: async (_args, ctx) => { await ctx.reload(); } }); };\n');
const parent = { provider: initial.defaultProvider, id: initial.defaultModel, thinking: initial.defaultThinkingLevel };
const expensiveParent = { provider: 'openai-codex', id: 'gpt-6-astra', thinking: 'max' };
const receipt = { scratch, profileRoot: live, packageDir, subagentsDir, switches: [], policy: [], checks: [], sessions: [], success: false };

function launchRpc(sessionPath) {
  const sessionArgs = sessionPath ? ['--session', sessionPath] : ['--session-id', randomUUID()];
  const child = spawn(process.execPath, [path.join(packageDir, 'dist/cli.js'), '--offline', '--mode', 'rpc', ...sessionArgs, '--no-extensions', '--no-skills', '--no-prompt-templates', '-e', path.join(subagentsDir, 'index.ts'), '-e', reloadHarness], { cwd: scratch, env, stdio: ['pipe', 'pipe', 'pipe'] });
  const rpc = new Rpc(child);
  const session = { pid: child.pid, events: rpc.events };
  receipt.sessions.push(session);
  child.on('close', (code, signal) => { session.terminal = { code, signal }; session.fault = rpc.fault?.message; });
  return rpc;
}

function pass(message) {
  receipt.checks.push(message);
  console.log(message);
}
function withoutModelFields(role) {
  const result = { ...role };
  delete result.model;
  delete result.thinking;
  return result;
}
function assertPreserved() {
  const maximum = profiles.max.subagents.agentOverrides;
  assert.deepEqual(Object.keys(maximum).sort(), ['delegate', 'lookup', 'oracle', 'researcher', 'reviewer', 'scout', 'worker']);
  const expected = {
    simple: { default: ['gpt-5.6-terra', 'medium'], delegation: 'useful' },
    complex: { default: ['gpt-5.6-sol', 'high'], delegation: 'proactive' },
    max: { default: ['gpt-6-astra', 'max'], delegation: 'comprehensive' },
  };
  for (const [name, profile] of Object.entries(profiles)) {
    const policy = expected[name];
    assert.deepEqual(profile.subagents.executionStrategy, { version: 1, delegation: policy.delegation, reviewers: ['reviewer'] });
    assert.equal(profile.subagents.defaultModel, `openai-codex/${policy.default[0]}`);
    assert.equal(profile.subagents.defaultProvider, 'openai-codex');
    assert.equal(profile.subagents.defaultThinking, policy.default[1]);
    assert.equal(Object.hasOwn(profile.subagents, 'modelScope'), false);
    assert.equal(Object.hasOwn(profile.subagents, 'maxThinking'), false);
    for (const [role, configured] of Object.entries(profile.subagents.agentOverrides)) {
      let [model, thinking] = policy.default;
      if (role === 'lookup') [model, thinking] = ['gpt-5.6-terra', 'medium'];
      if (name === 'complex' && ['delegate', 'scout', 'researcher'].includes(role)) model = 'gpt-5.6-terra';
      if (name === 'max' && role === 'scout') [model, thinking] = ['gpt-5.6-terra', 'xhigh'];
      if (name === 'max' && role === 'worker') thinking = 'xhigh';
      assert.equal(configured.model, `openai-codex/${model}`, `${name}/${role}`);
      assert.equal(configured.thinking, thinking, `${name}/${role}`);
      assert.equal(Object.hasOwn(configured, 'modelScope'), false);
      assert.equal(Object.hasOwn(configured, 'maxThinking'), false);
    }
  }
  for (const profile of Object.values(profiles)) {
    assert.deepEqual(Object.keys(profile.subagents.agentOverrides).sort(), Object.keys(maximum).sort());
    for (const [name, role] of Object.entries(profile.subagents.agentOverrides)) {
      assert.deepEqual(withoutModelFields(role), withoutModelFields(maximum[name]), name);
    }
  }
}

async function inspectActiveProfile(rpc, name, phase, statusStart) {
  const state = await rpc.send('get_state');
  assert.equal(`${state.model.provider}/${state.model.id}`, `${parent.provider}/${parent.id}`);
  assert.equal(state.thinkingLevel, parent.thinking);
  const models = (await rpc.send('get_available_models')).models.map(toModelInfo);
  const roles = {};
  const status = assertFreshProfileStatus(rpc.events, statusStart, name);
  // A prior footer must never qualify a reload that emits no new profile status.
  assert.throws(() => assertFreshProfileStatus(rpc.events, rpc.events.length, name), /Fresh profile footer/);
  for (const [role, configured] of Object.entries(profiles[name].subagents.agentOverrides)) {
    const before = rpc.events.length;
    await rpc.prompt(`/subagents ${role} details`);
    const details = messageText(rpc.events.slice(before), 'subagents-admin');
    const observed = assertRoleDetails(details, role, configured);
    // Negative assertions use the SAME actual native output, not a mirror overlay.
    assert.throws(() => assertRoleDetails(details, role, { ...configured, thinking: 'off' }), /active native settings/);
    const model = resolveEffectiveSubagentModel(undefined, observed.model, parent, models);
    const thinking = resolveEffectiveThinking(model, observed.thinking);
    assert.equal(model, configured.model);
    assert.equal(thinking, configured.thinking, `${name}/${role}: effective thinking`);
    const info = models.find(entry => entry.fullId === model);
    assert.ok(info, model);
    assert.ok(getSupportedThinkingLevels(info).includes(thinking), `${role}: ${model}/${thinking}`);
    let modelOutput;
    if (role !== 'lookup') {
      const modelStart = rpc.events.length;
      await rpc.prompt(`/subagents-models ${role}`);
      modelOutput = messageText(rpc.events.slice(modelStart), 'subagent-slash-result');
      assertBuiltinModel(modelOutput, role, configured.model);
      const otherModel = model === 'openai-codex/gpt-6-astra' ? 'openai-codex/gpt-5.6-terra' : 'openai-codex/gpt-6-astra';
      assert.throws(() => assertBuiltinModel(modelOutput, role, otherModel));
      assert.throws(() => assertRoleDetails(details, role, { ...configured, model: otherModel }), /active native settings/);
    }
    roles[role] = { model, thinking, details, modelOutput };
    const requested = resolveEffectiveSubagentModel('openai-codex/gpt-6-astra', observed.model, expensiveParent, models);
    assert.match(requested, /^openai-codex\/gpt-6-astra/);
    assert.ok(buildModelCandidates(model, ['openai-codex/gpt-6-astra'], models).length);
    assertThinkingWithinCeiling({ model: requested, configThinking: 'max', ceiling: configured.maxThinking, agent: role });
    assert.equal(configured.maxThinking, undefined);
    assert.equal(resolveEffectiveSubagentModel(undefined, observed.model, expensiveParent, models), model);
  }
  const deniedModel = await rpc.prompt('/run reviewer[model=nonexistent-provider/nonexistent-model] "Offline invalid-model guard; must reject before launch"');
  assert.match(deniedModel, /not found|unknown|unavailable|could not resolve|no models/i);
  receipt.policy.push({ name, phase, deniedModel });
  assert.equal(rpc.events.some(event => event.type === 'message_start' && event.message?.role === 'assistant'), false, 'No billable model turn is allowed');
  receipt.switches.push({ name, phase, statusStart, status, roles, events: [...rpc.events] });
}

try {
  assertPreserved();
  const persistedSettings = fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8');
  for (const name of ['simple', 'complex', 'max', 'simple', 'complex']) {
    let sessionFile;
    const rpc = launchRpc();
    try {
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      const beforeState = await rpc.send('get_state');
      assert.equal(`${beforeState.model.provider}/${beforeState.model.id}`, `${parent.provider}/${parent.id}`);
      // Startup model presets can override the global thinking default.
      // Compare against the actual pre-switch state, not that global default.
      if (receipt.switches.length === 0) parent.thinking = beforeState.thinkingLevel;
      const commands = (await rpc.send('get_commands')).commands;
      assert.ok(commands.some(command => command.name === 'subagents-load-profile'));
      assert.match(await rpc.prompt('/subagents-profiles'), /complex/);
      const selectionStart = rpc.events.length;
      assert.match(
        await rpc.prompt(`/subagents-load-profile ${name}`),
        new RegExp(`Loaded subagent profile for this session only: ${name}`),
      );
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      const afterState = await rpc.send('get_state');
      assert.deepEqual(afterState.model, beforeState.model);
      assert.equal(afterState.thinkingLevel, beforeState.thinkingLevel);
      sessionFile = afterState.sessionFile;
      assert.ok(sessionFile, `profile acceptance requires a session file: ${JSON.stringify(afterState)}`);
      const selectedEntries = (await rpc.send('get_entries')).entries;
      const selectedMarker = selectedEntries.filter(entry => entry.type === 'custom' && entry.customType === 'pi-subagents-profile').at(-1);
      assert.equal(selectedMarker?.data?.name, name);
      assert.equal(rpc.events.some(event => event.method === 'confirm'), false);
      await inspectActiveProfile(rpc, name, 'selected', selectionStart);
      receipt.switches.push({ command: name, phase: 'selected', events: rpc.events });
      const reloadStart = rpc.events.length;
      await rpc.prompt('/profile-test-reload');
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      await inspectActiveProfile(rpc, name, 'reloaded', reloadStart);
    } finally { await rpc.close(); }
    assert.ok(fs.existsSync(sessionFile), `profile session file was not persisted on shutdown: ${sessionFile}`);
    const resumed = launchRpc(sessionFile);
    try {
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      const resumedState = await resumed.send('get_state');
      assert.equal(resumedState.sessionFile, sessionFile);
      const resumedEntries = (await resumed.send('get_entries')).entries;
      const resumedMarker = resumedEntries.filter(entry => entry.type === 'custom' && entry.customType === 'pi-subagents-profile').at(-1);
      assert.equal(resumedMarker?.data?.name, name);
      await inspectActiveProfile(resumed, name, 'resumed', 0);
      assert.match(await resumed.prompt('/subagents-load-profile missing-profile'), /ENOENT|not found/i);
      await inspectActiveProfile(resumed, name, 'after-invalid-profile', 0);
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      receipt.switches.push({ command: name, phase: 'resumed', events: resumed.events });
    } finally { await resumed.close(); }
  }
  pass('PASS: session-local simple/complex/max switches and resumes preserve exact persistent settings bytes');
  pass('PASS: capable explicit profiles preserve parent defaults without model or thinking ceilings');
  pass('PASS: useful/proactive/comprehensive policies preserve shared role fields and reject invalid models');
  if (deployed) {
    assert.deepEqual(liveSettings.subagents, { ...liveSettings.subagents, ...profiles.max.subagents });
    pass('PASS: live persistent configuration matches max while session choices remain branch-local');
    for (const name of Object.keys(profiles)) assert.deepEqual(readJson(path.join(snapshot, 'profiles/pi-subagents', `${name}.json`)), profiles[name]);
    const captured = readJson(path.join(snapshot, 'settings.json'));
    const portableLive = { ...liveSettings };
    delete portableLive.lastChangelogVersion;
    delete portableLive.trackingId;
    assert.deepEqual(captured, portableLive);
    assert.equal(fs.readFileSync(path.join(snapshot, 'APPEND_SYSTEM.md'), 'utf8'), fs.readFileSync(path.join(live, 'APPEND_SYSTEM.md'), 'utf8'));
    pass('PASS: portable profiles and persistent configuration match captured source');
  }
  for (const session of receipt.sessions) assert.deepEqual(session.terminal, { code: 0, signal: null });
  pass('PASS: actual native role models/thinking and fresh reload status reject wrong expectations; all RPC children shut down cleanly');
  receipt.parent = parent;
  receipt.success = true;
} finally {
  const artifact = path.join(scratch, 'result.json');
  fs.writeFileSync(artifact, JSON.stringify(receipt, null, 2));
  console.log(`Artifact: ${artifact}`);
}
