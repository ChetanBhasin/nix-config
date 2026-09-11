import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const liveAgentDir = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-profile-session-'));
const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
process.env.PI_CODING_AGENT_DIR = scratch;
fs.mkdirSync(path.join(scratch, 'profiles'), { recursive: true });
fs.cpSync(path.join(liveAgentDir, 'profiles/pi-subagents'), path.join(scratch, 'profiles/pi-subagents'), { recursive: true });
const complex = JSON.parse(fs.readFileSync(path.join(scratch, 'profiles/pi-subagents/complex.json'), 'utf8'));
const customName = 'custom-fast';
const custom = structuredClone(complex);
custom.subagents.agentOverrides.worker.model = 'openai-codex/gpt-5.6-terra';
custom.subagents.modelScope.agents.worker.allow = ['openai-codex/gpt-5.6-terra'];
fs.writeFileSync(path.join(scratch, `profiles/pi-subagents/${customName}.json`), JSON.stringify(custom, null, 2) + '\n');
const settingsPath = path.join(scratch, 'settings.json');
fs.writeFileSync(settingsPath, JSON.stringify({ packages: ['unchanged-package'], subagents: { sentinel: { exact: false }, ...complex.subagents } }, null, 2) + '\n');
const persistedBytes = fs.readFileSync(settingsPath);

const { createJiti } = await import(new URL('../../npm/node_modules/jiti/lib/jiti.mjs', import.meta.url));
const jiti = createJiti(import.meta.url);
const npm = path.join(liveAgentDir, 'npm/node_modules/pi-subagents/src');
const profiles = await jiti.import(path.join(npm, 'profiles/profiles.ts'));
const session = await jiti.import(path.join(npm, 'profiles/session-profile.ts'));
const agents = await jiti.import(path.join(npm, 'agents/agents.ts'));

const management = await jiti.import(path.join(npm, 'agents/agent-management.ts'));
const primarySession = session.createSubagentProfileSessionState();
const secondarySession = session.createSubagentProfileSessionState();
const worker = (profileSession = primarySession) => agents.discoverAgents(scratch, 'user', profileSession).agents.find(agent => agent.name === 'worker');

test('session-only profile overlay drives every discoverAgents call without changing persisted bytes', () => {
  assert.equal(profiles.inferPersistedSubagentProfile(), 'complex');
  for (const [name, model] of [['simple', 'openai-codex/gpt-5.6-terra'], ['complex', 'openai-codex/gpt-5.6-sol'], ['max', 'openai-codex/gpt-6-astra']]) {
    const result = profiles.applySubagentProfile(primarySession, name);
    assert.equal(result.profileName, name);
    assert.equal(worker().model, model);
    assert.deepEqual(fs.readFileSync(settingsPath), persistedBytes);
  }
  const customResult = profiles.applySubagentProfile(primarySession, `${customName}.json`);
  assert.equal(customResult.profileName, customName);
  assert.equal(worker().model, 'openai-codex/gpt-5.6-terra');
  assert.deepEqual(fs.readFileSync(settingsPath), persistedBytes);
  const overlay = session.getSubagentSettingsOverlay(settingsPath, primarySession);
  assert.deepEqual(overlay.sentinel, { exact: false });
  assert.deepEqual(overlay.agentOverrides, custom.subagents.agentOverrides);
  assert.deepEqual(JSON.parse(fs.readFileSync(settingsPath)).packages, ['unchanged-package']);
});

test('profile overlays are isolated across concurrent session states and independent cleanup', () => {
  profiles.applySubagentProfile(primarySession, 'simple');
  profiles.applySubagentProfile(secondarySession, 'max');
  assert.equal(worker(primarySession).model, 'openai-codex/gpt-5.6-terra');
  assert.equal(worker(secondarySession).model, 'openai-codex/gpt-6-astra');
  profiles.clearSubagentProfileSession(primarySession);
  assert.equal(worker(primarySession).model, 'openai-codex/gpt-5.6-sol');
  assert.equal(worker(secondarySession).model, 'openai-codex/gpt-6-astra');
  profiles.applySubagentProfile(primarySession, 'complex');
});

test('foreground management mutations use session discovery and report profile-masked persistence', () => {
  profiles.applySubagentProfile(primarySession, 'complex');
  let discoveryCalls = 0;
  const ctx = {
    cwd: scratch,
    modelRegistry: { getAvailable: () => [] },
    discoverAgentsAll: cwd => {
      discoveryCalls += 1;
      return agents.discoverAgentsAll(cwd, primarySession);
    },
    activeProfileName: session.getActiveSubagentProfileName(primarySession),
  };
  const invoke = (action, params) => {
    const before = discoveryCalls;
    const outcome = management.handleManagementAction(action, params, ctx);
    assert.ok(discoveryCalls > before, `${action} must use injected session discovery`);
    return outcome;
  };
  const text = outcome => outcome.content.map(part => part.text ?? '').join('\n');

  try {
    assert.equal(invoke('create', { config: { name: 'management-session-probe', description: 'probe', scope: 'user' } }).isError, false);
    assert.equal(invoke('update', { agent: 'management-session-probe', agentScope: 'user', config: { description: 'updated probe' } }).isError, false);
    assert.equal(invoke('delete', { agent: 'management-session-probe', agentScope: 'user' }).isError, false);
    for (const [action, params] of [
      ['update', { agent: 'missing-session-probe', agentScope: 'user', config: { description: 'missing' } }],
      ['delete', { agent: 'missing-session-probe', agentScope: 'user' }],
    ]) {
      const before = discoveryCalls;
      const missing = management.handleManagementAction(action, params, ctx);
      assert.equal(missing.isError, true);
      assert.match(text(missing), /not found/);
      assert.ok(discoveryCalls - before >= 2, `${action} not-found fallback must reuse injected session discovery`);
    }
    assert.equal(invoke('eject', { agent: 'reviewer', agentScope: 'user' }).isError, false);
    const reset = invoke('reset', { agent: 'reviewer', agentScope: 'user' });
    assert.equal(reset.isError, false);
    assert.match(text(reset), /Active session profile 'complex' remains authoritative/);

    const disabled = invoke('disable', { agent: 'worker', agentScope: 'user' });
    assert.equal(disabled.isError, true);
    assert.match(text(disabled), /active session profile 'complex'/);
    assert.match(text(disabled), /persistent change is saved but does not affect this active profile/);
    assert.notEqual(worker().disabled, true);
    assert.equal(JSON.parse(fs.readFileSync(settingsPath, 'utf8')).subagents.agentOverrides.worker.disabled, true);
    const disabledProfile = structuredClone(complex.subagents);
    disabledProfile.agentOverrides.worker = { ...disabledProfile.agentOverrides.worker, disabled: true };
    session.setSubagentProfileOverlay(primarySession, 'complex-disabled', disabledProfile);
    ctx.activeProfileName = session.getActiveSubagentProfileName(primarySession);
    const enabled = invoke('enable', { agent: 'worker', agentScope: 'user' });
    assert.equal(enabled.isError, true);
    assert.match(text(enabled), /active session profile 'complex-disabled' still disables 'worker'/);
    assert.match(text(enabled), /persistent change does not affect this active profile/);
    assert.equal(JSON.parse(fs.readFileSync(settingsPath, 'utf8')).subagents.agentOverrides.worker.disabled, undefined);
    profiles.applySubagentProfile(primarySession, 'complex');
    ctx.activeProfileName = session.getActiveSubagentProfileName(primarySession);
  } finally {
    fs.rmSync(path.join(scratch, 'agents'), { recursive: true, force: true });
    fs.writeFileSync(settingsPath, persistedBytes);
    profiles.applySubagentProfile(primarySession, 'complex');
  }
  assert.deepEqual(fs.readFileSync(settingsPath), persistedBytes);
});

test('branch markers restore custom profiles and expose migration and repair decisions safely', () => {
  const marker = { type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data: { version: 1, name: 'complex' } };
  assert.deepEqual(profiles.restoreSubagentProfileSession(primarySession, [marker]), {
    name: 'complex',
    source: 'marker',
    shouldAppendMarker: false,
  });
  assert.equal(worker().model, 'openai-codex/gpt-5.6-sol');

  const customMarker = { type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data: { version: 1, name: customName } };
  assert.deepEqual(profiles.restoreSubagentProfileSession(primarySession, [customMarker]), {
    name: customName,
    source: 'marker',
    shouldAppendMarker: false,
  });
  assert.equal(worker().model, 'openai-codex/gpt-5.6-terra');

  const simple = { type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data: { version: 1, name: 'simple' } };
  const max = { type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data: { version: 1, name: 'max' } };
  assert.deepEqual(profiles.restoreSubagentProfileSession(primarySession, [simple, marker, max]), {
    name: 'max',
    source: 'marker',
    shouldAppendMarker: false,
  });
  assert.equal(worker().model, 'openai-codex/gpt-6-astra');

  const malformed = { type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data: null };
  assert.deepEqual(profiles.restoreSubagentProfileSession(primarySession, [simple, marker, malformed]), {
    name: 'complex',
    source: 'marker',
    shouldAppendMarker: true,
    warning: 'malformed profile marker',
  });
  assert.equal(worker().model, 'openai-codex/gpt-5.6-sol');

  assert.deepEqual(profiles.restoreSubagentProfileSession(primarySession, []), {
    name: 'complex',
    source: 'persisted',
    shouldAppendMarker: true,
  });
  for (const data of [null, { version: 1, name: 'unknown' }, { version: 1, name: '../unsafe' }, { version: 2, name: 'complex' }]) {
    const restored = profiles.restoreSubagentProfileSession(primarySession, [{ type: 'custom', customType: profiles.SUBAGENT_PROFILE_ENTRY_TYPE, data }]);
    assert.equal(restored.name, 'complex');
    assert.equal(restored.source, 'persisted');
    assert.equal(restored.shouldAppendMarker, true);
    assert.match(restored.warning, /marker/);
  }
  assert.deepEqual(fs.readFileSync(settingsPath), persistedBytes);
});

test('markerless activation appends one branch marker and always publishes stable footer status', () => {
  const branch = [];
  const calls = [];
  const warnings = [];
  const appended = [];
  const pi = {
    appendEntry: (customType, data) => {
      appended.push([customType, data]);
      branch.push({ type: 'custom', customType, data });
    },
  };
  const ctx = {
    hasUI: true,
    sessionManager: { getBranch: () => branch },
    ui: {
      notify: (...args) => warnings.push(args),
      setStatus: (...args) => calls.push(args),
    },
  };

  assert.equal(profiles.activateSubagentProfileSession(primarySession, pi, ctx).source, 'persisted');
  assert.deepEqual(appended, [[profiles.SUBAGENT_PROFILE_ENTRY_TYPE, { version: 1, name: 'complex' }]]);
  assert.equal(profiles.activateSubagentProfileSession(primarySession, pi, ctx).source, 'marker');
  assert.equal(appended.length, 1);
  assert.deepEqual(warnings, []);
  profiles.clearSubagentProfileSession(primarySession, ctx);
  assert.deepEqual(calls, [
    ['subagents-profile', 'profile: complex'],
    ['subagents-profile', 'profile: complex'],
    ['subagents-profile', undefined],
  ]);
});

test.after(() => {
  profiles.clearSubagentProfileSession(primarySession);
	profiles.clearSubagentProfileSession(secondarySession);
  if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
  else process.env.PI_CODING_AGENT_DIR = previousAgentDir;
  fs.rmSync(scratch, { recursive: true, force: true });
});
