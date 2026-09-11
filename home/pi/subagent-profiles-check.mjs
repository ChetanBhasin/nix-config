// Offline acceptance through Pi's real RPC/slash interface; no model requests.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const live = path.resolve(process.env.PI_TEST_AGENT_DIR ?? path.join(os.homedir(), '.pi/agent'));
const packageDir = process.env.PI_TEST_PACKAGE_DIR ?? path.join(live, 'npm/node_modules/@earendil-works/pi-coding-agent');
const subagentsDir = process.env.PI_TEST_SUBAGENTS_DIR ?? path.join(live, 'npm/node_modules/pi-subagents');
const source = path.join(live, 'profiles/pi-subagents');
const snapshot = fileURLToPath(new URL('./config', import.meta.url));
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (cause) { throw new Error(`Cannot read JSON: ${file}`, { cause }); }
}
const profiles = Object.fromEntries(['simple', 'complex', 'max'].map(name => [name, readJson(path.join(source, `${name}.json`))]));
const liveSettings = readJson(path.join(live, 'settings.json'));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-subagent-profiles-'));
const agentDir = path.join(scratch, '.pi/agent');
fs.mkdirSync(path.join(agentDir, 'profiles/pi-subagents'), { recursive: true });
fs.cpSync(source, path.join(agentDir, 'profiles/pi-subagents'), { recursive: true });
const initial = { ...liveSettings, packages: [], extensions: [], skills: [], prompts: [] };
if (process.env.PI_PROFILES_TEST_PARENT_MODEL) initial.defaultModel = process.env.PI_PROFILES_TEST_PARENT_MODEL;
fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify(initial));
// Fixture-only key exposes registry models without reading/refreshing real auth.
fs.writeFileSync(path.join(agentDir, 'auth.json'), JSON.stringify({ 'openai-codex': { type: 'api_key', key: 'fixture-no-network' } }));
// Pi 0.84.4's dynamic catalog is separate from credentials. Reuse only its
// public Codex model metadata for offline lookup, never live auth or tokens.
const catalog = readJson(path.join(live, 'models-store.json'))['openai-codex'];
assert.ok(catalog?.models?.length, 'A previously resolved Codex model catalog is required');
fs.writeFileSync(path.join(agentDir, 'models-store.json'), JSON.stringify({ 'openai-codex': catalog }));
fs.writeFileSync(path.join(agentDir, 'models.json'), JSON.stringify({ providers: { 'openai-codex': { apiKey: 'fixture-no-network' } } }));
const env = { ...process.env, HOME: scratch, PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1', PI_SKIP_VERSION_CHECK: '1', JITI_FS_CACHE: '0' };
for (const key of Object.keys(env)) {
  if (key.startsWith('PI_SUBAGENT') || key === 'NODE_OPTIONS' || /^(OPENAI|ANTHROPIC|OPENROUTER|GEMINI|GOOGLE)_.*KEY$/.test(key)) delete env[key];
}
process.env.HOME = scratch;
process.env.PI_CODING_AGENT_DIR = agentDir;
process.env.PI_SUBAGENT_EXTRA_AGENT_DIRS = '';
const require = createRequire(path.join(subagentsDir, 'package.json'));
const { createJiti } = require('jiti');
const jiti = createJiti(import.meta.url, { fsCache: false });
const { discoverAgents } = await jiti.import(path.join(subagentsDir, 'src/agents/agents.ts'));
const { clearSubagentProfileOverlay, createSubagentProfileSessionState, setSubagentProfileOverlay } = await jiti.import(path.join(subagentsDir, 'src/profiles/session-profile.ts'));
const profileSession = createSubagentProfileSessionState();
const { resolveModelScopesForAgent } = await jiti.import(path.join(subagentsDir, 'src/runs/shared/model-scope.ts'));
const { resolveEffectiveSubagentModel, buildModelCandidates } = await jiti.import(path.join(subagentsDir, 'src/runs/shared/model-fallback.ts'));
const { assertThinkingWithinCeiling } = await jiti.import(path.join(subagentsDir, 'src/shared/thinking-ceiling.ts'));
const { toModelInfo, resolveEffectiveThinking, getSupportedThinkingLevels } = await jiti.import(path.join(subagentsDir, 'src/shared/model-info.ts'));
const parent = { provider: initial.defaultProvider, id: initial.defaultModel, thinking: initial.defaultThinkingLevel };
const expensiveParent = { provider: 'openai-codex', id: 'gpt-6-astra', thinking: 'max' };
const receipt = { scratch, packageDir, subagentsDir, switches: [], policy: [], checks: [] };

class Rpc {
  constructor(sessionPath) {
    this.events = [];
    this.pending = new Map();
    this.counter = 0;
    this.stderr = '';
    const sessionArgs = sessionPath ? ['--session', sessionPath] : ['--session-id', randomUUID()];
    this.child = spawn(process.execPath, [path.join(packageDir, 'dist/cli.js'), '--offline', '--mode', 'rpc', ...sessionArgs, '--no-extensions', '--no-skills', '--no-prompt-templates', '-e', path.join(subagentsDir, 'index.ts')], { cwd: scratch, env, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stderr.setEncoding('utf8').on('data', text => { this.stderr += text; });
    let buffer = '';
    this.child.stdout.setEncoding('utf8').on('data', text => {
      buffer += text;
      let end;
      while ((end = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, end).replace(/\r$/, '');
        buffer = buffer.slice(end + 1);
        try { if (line) this.receive(JSON.parse(line)); }
        catch (error) { this.fail(error); this.child.kill('SIGTERM'); return; }
      }
    });
    this.child.on('error', error => this.fail(error));
    this.child.on('exit', (code, signal) => this.fail(new Error(`Pi exited: ${code}/${signal}: ${this.stderr}`)));
  }
  fail(error) {
    for (const request of this.pending.values()) request.reject(error);
    this.pending.clear();
  }
  receive(event) {
    this.events.push(event);
    this.child.emit('rpc-event', event);
    if (event.type === 'extension_ui_request' && event.method === 'confirm') {
      assert.match(event.message, /Also switch this session/);
      this.child.stdin.write(JSON.stringify({ type: 'extension_ui_response', id: event.id, confirmed: false }) + '\n');
    }
    if (event.type === 'response') {
      const request = this.pending.get(event.id);
      if (!request) return;
      this.pending.delete(event.id);
      if (event.success) request.resolve(event.data);
      else request.reject(new Error(event.error));
    }
  }
  async send(type, fields = {}) {
    const id = String(++this.counter);
    let timer;
    try {
      return await new Promise((resolve, reject) => {
        timer = setTimeout(() => {
          this.pending.delete(id);
          reject(new Error(`RPC timeout: ${type}: ${this.stderr}`));
        }, 30000);
        this.pending.set(id, { resolve, reject });
        this.child.stdin.write(JSON.stringify({ id, type, ...fields }) + '\n');
      });
    } finally { clearTimeout(timer); }
  }
  async waitFor(predicate, start) {
    if (this.events.slice(start).some(predicate)) return;
    let timer;
    let listener;
    try {
      await new Promise((resolve, reject) => {
        listener = event => { if (predicate(event)) resolve(); };
        this.child.on('rpc-event', listener);
        timer = setTimeout(() => reject(new Error(`Slash result timeout: ${this.stderr}`)), 30000);
      });
    } finally {
      clearTimeout(timer);
      this.child.off('rpc-event', listener);
    }
  }
  async prompt(message) {
    const before = this.events.length;
    await this.send('prompt', { message });
    if (message.startsWith('/run ') || message === '/subagents-models') {
      await this.waitFor(event => event.type === 'message_end' && event.message?.customType === 'subagent-slash-result' && event.message?.content?.startsWith('## Subagent result'), before);
    }
    return JSON.stringify(this.events.slice(before));
  }
  async close() {
    if (this.child.exitCode !== null || this.child.signalCode !== null) return;
    const closed = once(this.child, 'close');
    this.child.stdin.end();
    const timer = setTimeout(() => this.child.kill('SIGTERM'), 2000);
    try { await closed; } finally { clearTimeout(timer); }
    assert.doesNotMatch(this.stderr, /Failed to load extension/);
  }
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
  assert.equal(maximum.scout.model, 'openai-codex/gpt-5.6-terra');
  assert.equal(maximum.scout.thinking, 'xhigh');
  assert.equal(maximum.worker.model, 'openai-codex/gpt-6-astra');
  assert.equal(maximum.worker.thinking, 'xhigh');
  assert.equal(Object.hasOwn(maximum.oracle, 'thinking'), false);
  assert.equal(maximum.delegate.model, 'inherit');
  for (const profile of Object.values(profiles)) {
    assert.deepEqual(Object.keys(profile.subagents.agentOverrides).sort(), Object.keys(maximum).sort());
    for (const [name, role] of Object.entries(profile.subagents.agentOverrides)) {
      assert.deepEqual(withoutModelFields(role), withoutModelFields(maximum[name]), name);
    }
  }
}

async function inspectActiveProfile(rpc, name, phase) {
  const state = await rpc.send('get_state');
  assert.equal(`${state.model.provider}/${state.model.id}`, `${parent.provider}/${parent.id}`);
  assert.equal(state.thinkingLevel, parent.thinking);
  const models = (await rpc.send('get_available_models')).models.map(toModelInfo);
  const roles = {};
  setSubagentProfileOverlay(profileSession, name, profiles[name].subagents);
  try {
    const discovered = discoverAgents(scratch, 'user', profileSession);
    assert.deepEqual(discovered.agentDiagnostics, []);
    for (const [role, configured] of Object.entries(profiles[name].subagents.agentOverrides)) {
      const agent = discovered.agents.find(entry => entry.name === role);
      assert.ok(agent, role);
      const scope = resolveModelScopesForAgent(discovered.modelScope, role, parent);
      const model = resolveEffectiveSubagentModel(undefined, agent.model, parent, models, agent.modelProvider, { scope });
      const thinking = resolveEffectiveThinking(model, agent.thinking);
      const info = models.find(entry => entry.fullId === model.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, ''));
      assert.ok(info, model);
      assert.ok(getSupportedThinkingLevels(info).includes(thinking), `${role}: ${model}/${thinking}`);
      assert.equal(agent.model, configured.model);
      assert.equal(agent.maxThinking, profiles[name].subagents.maxThinking);
      assertThinkingWithinCeiling({ model, configThinking: agent.thinking, ceiling: agent.maxThinking, agent: role });
      roles[role] = { model, thinking };
      if (name !== 'max') {
        for (const requested of ['openai-codex/gpt-6-astra', 'inherit']) {
          assert.throws(() => resolveEffectiveSubagentModel(requested, agent.model, expensiveParent, models, agent.modelProvider, { scope }), /scope/i);
        }
        const allowedParent = { provider: 'openai-codex', id: agent.model.slice('openai-codex/'.length), thinking: 'low' };
        assert.equal(resolveEffectiveSubagentModel('inherit', agent.model, allowedParent, models, agent.modelProvider, { scope }), `${agent.model}:low`);
        assert.throws(() => buildModelCandidates(model, ['openai-codex/gpt-6-astra'], models, agent.modelProvider, { scope }), /scope/i);
        for (const requested of ['xhigh', 'max', ...(name === 'simple' ? ['high'] : [])]) {
          assert.throws(() => assertThinkingWithinCeiling({ model, configThinking: requested, ceiling: agent.maxThinking, agent: role }), /exceeds configured maximum/);
          assert.throws(() => assertThinkingWithinCeiling({ model: `${agent.model}:${requested}`, configThinking: 'low', ceiling: agent.maxThinking, agent: role }), /exceeds configured maximum/);
        }
      }
    }
  } finally {
    clearSubagentProfileOverlay(profileSession);
  }
  assert.ok(
    rpc.events.some(event =>
      event.method === 'setStatus' &&
      event.statusKey === 'subagents-profile' &&
      event.statusText === `profile: ${name}`,
    ),
    `${phase} footer status must show profile: ${name}`,
  );
  const modelsOutput = await rpc.prompt('/subagents-models');
  assert.match(modelsOutput, /Builtin subagent models/);
  for (const resolved of Object.values(roles)) {
    assert.ok(modelsOutput.includes(resolved.model.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, '')));
  }
  if (name !== 'max') {
    const deniedModel = await rpc.prompt('/run reviewer[model=openai-codex/gpt-6-astra] "Read-only budget check; must reject before launch"');
    assert.match(deniedModel, /scope/i);
    const model = profiles[name].subagents.agentOverrides.reviewer.model;
    const deniedThinking = await rpc.prompt(`/run reviewer[model=${model}:max] "Read-only thinking check; must reject before launch"`);
    assert.match(deniedThinking, /exceeds configured maximum/);
    receipt.policy.push({ name, phase, deniedModel, deniedThinking });
  }
  assert.equal(rpc.events.some(event => event.type === 'message_start' && event.message?.role === 'assistant'), false, 'No billable model turn is allowed');
  receipt.switches.push({ name, phase, roles, events: rpc.events });
}

try {
  assertPreserved();
  const persistedSettings = fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8');
  for (const name of ['simple', 'complex', 'max', 'simple', 'complex']) {
    let sessionFile;
    const rpc = new Rpc();
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
      assert.ok(rpc.events.some(event => event.method === 'confirm'));
      await inspectActiveProfile(rpc, name, 'selected');
      receipt.switches.push({ command: name, phase: 'selected', events: rpc.events });
    } finally { await rpc.close(); }
    assert.ok(fs.existsSync(sessionFile), `profile session file was not persisted on shutdown: ${sessionFile}`);
    const resumed = new Rpc(sessionFile);
    try {
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      const resumedState = await resumed.send('get_state');
      assert.equal(resumedState.sessionFile, sessionFile);
      const resumedEntries = (await resumed.send('get_entries')).entries;
      const resumedMarker = resumedEntries.filter(entry => entry.type === 'custom' && entry.customType === 'pi-subagents-profile').at(-1);
      assert.equal(resumedMarker?.data?.name, name);
      await inspectActiveProfile(resumed, name, 'resumed');
      assert.match(await resumed.prompt('/subagents-load-profile missing-profile'), /ENOENT|not found/i);
      assert.equal(fs.readFileSync(path.join(agentDir, 'settings.json'), 'utf8'), persistedSettings);
      receipt.switches.push({ command: name, phase: 'resumed', events: resumed.events });
    } finally { await resumed.close(); }
  }
  pass('PASS: session-local simple/complex/max switches and resumes preserve exact persistent settings bytes');
  pass('PASS: max preserves previous roles; all profiles preserve non-model role fields and parent defaults');
  pass('PASS: simple and complex reject Astra and excessive thinking');
  if (process.env.PI_PROFILES_CHECK_DEPLOYED === '1') {
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
} finally {
  const artifact = path.join(scratch, 'result.json');
  fs.writeFileSync(artifact, JSON.stringify(receipt, null, 2));
  console.log(`Artifact: ${artifact}`);
}
