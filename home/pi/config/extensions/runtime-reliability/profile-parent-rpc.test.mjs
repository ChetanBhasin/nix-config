import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { digest, patchedText } from './patcher.mjs';

const agentDir = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const nativeDir = path.join(agentDir, 'npm/node_modules/pi-subagents');
const packageDir = process.env.PI_TEST_PACKAGE_DIR || path.join(agentDir, 'npm/node_modules/@earendil-works/pi-coding-agent');
const cli = path.join(packageDir, 'dist/cli.js');
const manifest = JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));

// Regression for the parent-model leak only. This is NOT the full execution
// strategy profile acceptance journey and deliberately prints none of its PASS literals.
test('native profile parent-model repair is pinned, idempotent and fail-closed', () => {
  const pkg = manifest.packages.find(item => item.name === 'pi-subagents');
  assert.equal(pkg.version, '0.56.0');
  const patch = pkg.patches.filter(item => item.file === 'src/slash/slash-commands.ts').at(-1);
  const source = fs.readFileSync(path.join(nativeDir, patch.file), 'utf8');
  assert.equal(digest(source), patch.afterHash);
  assert.equal(patchedText(source, patch), source);
  assert.throws(() => patchedText(source + '// unknown edit\n', patch), /Unrecognized source/);
  assert.doesNotMatch(source, /getProfileWorkerModel|pi\.setModel|findModelInfo|toModelInfo/);
});

function launchRpc(root, sessionFile) {
  const env = { ...process.env };
  // Do not inherit the worker role, Auto propagation, parent session or credentials.
  for (const key of Object.keys(env)) {
    if (key.startsWith('PI_') || /(?:API_KEY|TOKEN|SECRET|PASSWORD)$/.test(key)) delete env[key];
  }
  Object.assign(env, {
    HOME: root, PI_CODING_AGENT_DIR: root, PI_OFFLINE: '1',
    TMPDIR: path.join(root, 'tmp'), XDG_CACHE_HOME: path.join(root, 'cache'),
    XDG_CONFIG_HOME: path.join(root, 'config'), XDG_DATA_HOME: path.join(root, 'data'),
  });
  const child = spawn(process.execPath, [cli, '--mode', 'rpc', '--no-extensions',
    '-e', path.join(nativeDir, 'index.ts'), '-e', path.join(root, 'probe.ts'),
    '--session', sessionFile, '--provider', 'profile-fixture', '--model', 'parent', '--thinking', 'high'],
  { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] });
  const pending = new Map();
  const events = [];
  let buffer = '', stderr = '', sequence = 0;
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', text => { stderr = (stderr + text).slice(-8192); });
  const rejectAll = error => {
    for (const request of pending.values()) { clearTimeout(request.timer); request.reject(error); }
    pending.clear();
  };
  child.on('error', rejectAll);
  child.on('close', code => rejectAll(new Error(`Pi exited ${code}: ${stderr}`)));
  child.stdout.on('data', text => {
    buffer += text;
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index).replace(/\r$/, '');
      buffer = buffer.slice(index + 1);
      if (!line) continue;
      let event;
      try { event = JSON.parse(line); }
      catch { rejectAll(new Error(`Non-JSON RPC output: ${line.slice(0, 300)}`)); continue; }
      if (event.type === 'extension_ui_request') {
        // Answer yes so this test catches the historical optional model switch,
        // rather than hiding it by declining a confirmation.
        if (event.method === 'confirm') child.stdin.write(JSON.stringify({
          type: 'extension_ui_response', id: event.id, confirmed: true,
        }) + '\n');
        events.push(event);
      }
      if (event.type === 'extension_error') events.push(event);
      const request = event.type === 'response' ? pending.get(event.id) : undefined;
      if (request) {
        clearTimeout(request.timer);
        pending.delete(event.id);
        if (event.success) request.resolve(event.data);
        else request.reject(new Error(event.error ?? 'RPC command failed'));
      }
    }
  });
  return {
    events,
    request(type, params = {}) {
      return new Promise((resolve, reject) => {
        const id = `profile-${++sequence}`;
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`RPC timeout: ${type}; stderr: ${stderr}`));
        }, 30000);
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(JSON.stringify({ id, type, ...params }) + '\n');
      });
    },
    async close() {
      if (child.exitCode !== null || child.signalCode !== null) return;
      const closed = once(child, 'close');
      child.stdin.end();
      const kill = setTimeout(() => child.kill('SIGKILL'), 5000);
      try { await closed; } finally { clearTimeout(kill); }
    },
  };
}

const parentTuple = state => ({ provider: state.model?.provider, model: state.model?.id, thinking: state.thinkingLevel });

async function branchMarker(rpc) {
  const { entries, leafId } = await rpc.request('get_entries');
  const byId = new Map(entries.map(entry => [entry.id, entry]));
  for (let entry = byId.get(leafId); entry; entry = byId.get(entry.parentId)) {
    if (entry.type === 'custom' && entry.customType === 'pi-subagents-profile') return entry.data.name;
  }
  return undefined;
}

function seed(root) {
  fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
  fs.cpSync(path.join(agentDir, 'profiles/pi-subagents'), path.join(root, 'profiles/pi-subagents'), { recursive: true });
  fs.writeFileSync(path.join(root, 'profiles/pi-subagents/invalid.json'), '{not valid json');
  const max = JSON.parse(fs.readFileSync(path.join(root, 'profiles/pi-subagents/max.json'), 'utf8'));
  fs.writeFileSync(path.join(root, 'settings.json'), JSON.stringify({
    packages: [], defaultProjectTrust: 'yes', defaultProvider: 'profile-fixture',
    defaultModel: 'parent', defaultThinkingLevel: 'high', subagents: max.subagents,
  }, null, 2));
  fs.writeFileSync(path.join(root, 'models.json'), JSON.stringify({ providers: {
    'profile-fixture': { baseUrl: 'http://127.0.0.1:1', api: 'openai-completions', apiKey: 'fixture-not-a-credential',
      models: [{ id: 'parent', name: 'Offline profile parent', reasoning: true, input: ['text'],
        contextWindow: 32768, maxTokens: 4096, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }] },
  } }));
  fs.writeFileSync(path.join(root, 'probe.ts'), `export default function (pi) {
    pi.registerCommand('profile-test-reload', { handler: async (_args, ctx) => { await ctx.reload(); } });
  }\n`);
}

test('real isolated Pi RPC profile load/reload/restore never changes parent or prompts to switch', { timeout: 150000 }, async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'profile-parent-rpc-'));
  seed(root);
  const settingsBefore = fs.readFileSync(path.join(root, 'settings.json'));
  const sessionFile = path.join(root, 'session.jsonl');
  const checks = [];
  let rpc = launchRpc(root, sessionFile);
  try {
    const commands = await rpc.request('get_commands');
    assert.ok(commands.commands.some(command => command.name === 'subagents-load-profile'));
    const before = parentTuple(await rpc.request('get_state'));
    assert.deepEqual(before, { provider: 'profile-fixture', model: 'parent', thinking: 'high' });
    for (const name of ['simple', 'complex', 'max']) {
      await rpc.request('prompt', { message: `/subagents-load-profile ${name}` });
      assert.deepEqual(parentTuple(await rpc.request('get_state')), before);
      assert.equal(await branchMarker(rpc), name);
      await rpc.request('prompt', { message: '/profile-test-reload' });
      assert.deepEqual(parentTuple(await rpc.request('get_state')), before);
      assert.equal(await branchMarker(rpc), name);
      checks.push({ name, parent: before, reload: true, marker: name });
    }
    const from = rpc.events.length;
    await rpc.request('prompt', { message: '/subagents-load-profile invalid' });
    assert.ok(rpc.events.slice(from).some(event => event.method === 'notify' && event.notifyType === 'error'));
    assert.deepEqual(parentTuple(await rpc.request('get_state')), before);
    assert.equal(await branchMarker(rpc), 'max');
    assert.equal(rpc.events.filter(event => event.method === 'confirm').length, 0);
    assert.equal(rpc.events.filter(event => event.type === 'extension_error').length, 0);
    await rpc.close();
    rpc = launchRpc(root, sessionFile);
    assert.deepEqual(parentTuple(await rpc.request('get_state')), before);
    assert.equal(await branchMarker(rpc), 'max');
    assert.deepEqual(fs.readFileSync(path.join(root, 'settings.json')), settingsBefore);
    const reportPath = path.join(root, 'parent-profile-report.json');
    fs.writeFileSync(reportPath, JSON.stringify({
      test: 'native-parent-profile-invariance', interface: 'real Pi CLI RPC',
      provider: 'offline fixture; no provider request or subagent launched', checks,
      invalidRejected: true, restored: true, parentSettingsUnchanged: true,
      scope: 'parent-model repair only; not full execution-strategy acceptance',
    }, null, 2) + '\n');
    console.log(`PASS native parent-profile RPC regression; artifact: ${reportPath}`);
  } finally {
    await rpc.close();
    // Keep isolated lifecycle artifacts for independent review; no live state copied.
  }
});
