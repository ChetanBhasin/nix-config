import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyRepairs, patchedChain, patchedText, digest } from './patcher.mjs';
const { createJiti } = await import(new URL('../../npm/node_modules/jiti/lib/jiti.mjs', import.meta.url));
const jiti = createJiti(import.meta.url);
const npm = fileURLToPath(new URL('../../npm/node_modules/', import.meta.url));
const models = await jiti.import(path.join(npm, 'pi-subagents/src/runs/shared/model-fallback.ts'));
const { LaunchSemaphore } = await jiti.import(path.join(npm, 'pi-subagents/src/runs/shared/launch-semaphore.ts'));
const budgets = await jiti.import(path.join(npm, 'pi-subagents/src/runs/shared/spawn-budget.ts'));
const browser = await import(path.join(npm, 'pi-agent-browser-native/dist/extensions/agent-browser/lib/process-identity.js'));

test('delegate inherits each live parent model and thinking, including off; explicit models remain pinned', () => {
  for (const [id, thinking] of [['gpt-6-astra', 'max'], ['another-parent', 'high'], ['gpt-6-astra', 'off']]) {
    const parent = { provider: 'openai-codex', id, thinking };
    assert.equal(models.resolveEffectiveSubagentModel(undefined, 'inherit', parent, undefined), `openai-codex/${id}:${thinking}`);
    assert.equal(models.resolveEffectiveSubagentModel(undefined, 'openai-codex/gpt-6-astra:max', parent, undefined), 'openai-codex/gpt-6-astra:max');
  }
});

test('200 cumulative admissions with no lifetime quota do not exhaust capacity', () => {
  const state = { currentSessionId: 'isolated-fixture' };
  const config = { maxSubagentSpawnsPerSession: 0 };
  for (let i = 0; i < 200; i++) assert.equal(budgets.reserveSpawnBudget(state, config, state.currentSessionId, 1).error, undefined);
  assert.equal(budgets.getSpawnBudgetSnapshot(state, config).limit, null);
});

test('one shared pool bounds simultaneous roots; cancellation and double release do not leak slots', async () => {
  const pool = new LaunchSemaphore(2);
  let active = 0, peak = 0;
  const work = async () => {
    const release = await pool.acquire();
    try { active++; peak = Math.max(peak, active); await new Promise(r => setTimeout(r, 2)); }
    finally { active--; release(); release(); }
  };
  await Promise.all([Promise.all(Array.from({ length: 10 }, work)), Promise.all(Array.from({ length: 10 }, work))]);
  assert.equal(peak, 2);
  const one = await pool.acquire(), two = await pool.acquire();
  const aborted = new AbortController();
  const pending = pool.acquire(aborted.signal);
  aborted.abort(new Error('cancel queued child'));
  await assert.rejects(pending, /cancel queued child/);
  one(); two();
  (await pool.acquire())();
});

test('browser NixOS PID discovery is real and retains trusted absolute platform paths', async () => {
  const commands = browser.buildProcessStartIdentityCommands(process.pid, 'linux');
  assert.ok(commands.some(c => c.file === '/run/current-system/sw/bin/ps'));
  assert.ok(commands.every(c => path.isAbsolute(c.file)));
  assert.equal(browser.buildProcessStartIdentityCommands(-1).length, 0);
  assert.ok(await browser.readProcessStartIdentity(process.pid));
  assert.equal(await browser.readProcessStartIdentity(2147483647), undefined);
  assert.ok(!browser.buildProcessStartIdentityCommands(process.pid, 'darwin').some(c => c.file.includes('/nix/')));
});

test('repairs are exact, idempotent, and reject changed upstream/local sources', () => {
  const patch = { file: 'src/example.js', beforeHash: digest('before\n'), afterHash: digest('after\n'), edits: [{ before: 'before\n', after: 'after\n' }] };
  assert.equal(patchedText('before\n', patch), 'after\n');
  assert.equal(patchedText('after\n', patch), 'after\n');
  assert.throws(() => patchedText('user edit\n', patch), /refusing to overwrite/);
  const nextPatch = { file: patch.file, beforeHash: patch.afterHash, afterHash: digest('final\n'), edits: [{ before: 'after\n', after: 'final\n' }] };
  assert.equal(patchedChain('before\n', [patch, nextPatch]), 'final\n');
  assert.equal(patchedChain('after\n', [patch, nextPatch]), 'final\n');
  assert.equal(patchedChain('final\n', [patch, nextPatch]), 'final\n');
  assert.throws(() => patchedChain('user edit\n', [patch, nextPatch]), /refusing to overwrite/);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-repair-test-'));
  try {
    const root = path.join(tmp, 'npm/node_modules/fixture');
    fs.mkdirSync(path.join(root, 'src'), { recursive: true });
    fs.writeFileSync(path.join(root, 'package.json'), '{"version":"1.0.0"}');
    fs.writeFileSync(path.join(root, patch.file), 'before\n');
    const manifest = { packages: [{ name: 'fixture', version: '1.0.0', patches: [patch] }] };
    assert.throws(() => applyRepairs({ agentDir: tmp, manifest, check: true }), /Repairs missing/);
    assert.equal(applyRepairs({ agentDir: tmp, manifest }).repaired, 1);
    assert.equal(applyRepairs({ agentDir: tmp, manifest, check: true }).repaired, 0);
    fs.writeFileSync(path.join(root, 'package.json'), '{"version":"2.0.0"}');
    assert.throws(() => applyRepairs({ agentDir: tmp, manifest }), /review compatibility/);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});

test('reviewed terminal repairs reconstruct and apply from their preceding hashes', () => {
  const manifest = JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));
  const packageManifest = manifest.packages.find(entry => entry.name === 'pi-subagents');
  assert.ok(packageManifest);
  for (const file of [
    'src/extension/index.ts',
    'src/runs/foreground/subagent-executor.ts',
    'src/agents/agent-management.ts',
  ]) {
    const current = fs.readFileSync(path.join(npm, 'pi-subagents', file), 'utf8');
    const patch = packageManifest.patches.filter(entry => entry.file === file).at(-1);
    assert.ok(patch, `missing terminal repair for ${file}`);
    assert.equal(digest(current), patch.afterHash, `${file} terminal hash`);
    let previous = current;
    for (const edit of [...patch.edits].reverse()) {
      assert.ok(edit.after, `${file} has a reversible reviewed edit`);
      assert.equal(previous.split(edit.after).length - 1, 1, `${file} reverse edit is exact`);
      previous = previous.replace(edit.after, () => edit.before);
    }
    assert.equal(digest(previous), patch.beforeHash, `${file} preceding hash`);
    assert.equal(patchedText(previous, patch), current, `${file} forward repair`);
  }
});


test('installed repairs match the captured version manifest', () => {
  assert.ok(applyRepairs({ check: true }).checked >= 5);
});
