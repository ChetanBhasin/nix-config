import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { Rpc, isolatedEnv, assertRoleDetails, assertBuiltinModel, assertFreshProfileStatus, messageText } from './subagent-profiles-runtime.mjs';

const runtimeUrl = new URL('./subagent-profiles-runtime.mjs', import.meta.url).href;
const scratchRoot = '/tmp/execution-strategy-tests/profile-qualification';
fs.mkdirSync(scratchRoot, { recursive: true });
const root = fs.mkdtempSync(path.join(scratchRoot, 'regressions-'));
const agent = path.join(root, 'agent');
const env = isolatedEnv(root, agent);
fs.mkdirSync(env.TMPDIR, { recursive: true });
console.log(`Regression scratch: ${root}`);

// Fixture process receives only synthetic contamination, never real auth/session state.
test('main-process allowlist precedes imported discovery and its inherited subprocess environment', () => {
  const discovery = path.join(root, 'discovery.mjs');
  fs.writeFileSync(discovery, `import { execFileSync } from 'node:child_process';
    export const seen = JSON.parse(execFileSync(process.execPath, ['-e', 'console.log(JSON.stringify(process.env))'], { encoding: 'utf8' }));`);
  const script = `import { isolateProcessEnvironment } from ${JSON.stringify(runtimeUrl)};
    const selector = process.env.PI_TEST_AGENT_DIR;
    const deployed = process.env.PI_PROFILES_CHECK_DEPLOYED;
    isolateProcessEnvironment(${JSON.stringify(root)}, ${JSON.stringify(agent)});
    const { seen } = await import(${JSON.stringify(discovery)});
    console.log(JSON.stringify({ selector, deployed, main: process.env, child: seen }));`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
    cwd: root, env: { ...env, PI_TEST_AGENT_DIR: '/synthetic/selector', PI_PROFILES_CHECK_DEPLOYED: '1',
      ANTHROPIC_API_KEY: 'synthetic-secret', NPM_TOKEN: 'synthetic-secret', AWS_SESSION_TOKEN: 'synthetic-secret',
      PI_SUBAGENT_PARENT_SESSION_ID: 'synthetic-session', PI_SUBAGENT_EXTRA_AGENT_DIRS: '/synthetic/agents',
      HTTPS_PROXY: 'http://synthetic.invalid', npm_config_userconfig: '/synthetic/npmrc',
      PI_OFFLINE: '', JITI_FS_CACHE: 'true' }, encoding: 'utf8', timeout: 10000,
  });
  assert.equal(result.status, 0, result.stderr);
  const observed = JSON.parse(result.stdout);
  assert.equal(observed.selector, '/synthetic/selector');
  assert.equal(observed.deployed, '1');
  assert.deepEqual(observed.main, env);
  assert.deepEqual(observed.child, env);
  assert.doesNotMatch(result.stdout, /synthetic-secret|synthetic-session|synthetic\/agents|synthetic\.invalid/);
  // Lock the harness call-site ordering, not just the standalone helper.
  const source = fs.readFileSync(new URL('./subagent-profiles-check.mjs', import.meta.url), 'utf8');
  assert.ok(source.indexOf('const env = isolateProcessEnvironment(') < source.indexOf("require('jiti')"));
  assert.ok(source.indexOf('const deployed = process.env.PI_PROFILES_CHECK_DEPLOYED') < source.indexOf('const env = isolateProcessEnvironment('));
  assert.doesNotMatch(source, /setSubagentProfileOverlay|createSubagentProfileSessionState/);
});

test('allowlist drops preload, credential and native child selectors', () => {
  assert.deepEqual(isolatedEnv(root, agent, { PATH: env.PATH, NODE_OPTIONS: '--require=evil',
    NODE_PATH: '/evil', OPENAI_API_KEY: 'fake', PI_SUBAGENT_DEPTH: '9', PI_OFFLINE: '0' }), env);
});

const expected = { model: 'openai-codex/gpt-5.6-terra', thinking: 'medium' };
const detail = (model = expected.model, thinking = expected.thinking) => `Agent: worker (builtin)\nPath: /fixture/worker.md\nModel: ${model}\nThinking: ${thinking}\n\nSystem Prompt:\nModel: ${expected.model}\nThinking: ${expected.thinking}`;
const modelOutput = model => `## Subagent result\nBuiltin subagent model\n\nAgent: worker\nEffective model:\n  ${model}\nSource: user override\nAvailable models in this session's registry (copy an exact provider/id when passing model):\n  ${expected.model}`;

test('native role metadata and per-role effective model accept exact settings', () => {
  assert.deepEqual(assertRoleDetails(detail(), 'worker', expected), expected);
  assertBuiltinModel(modelOutput(expected.model), 'worker', expected.model);
});

test('wrong active profile cannot pass via registry or prompt substrings', () => {
  assert.throws(() => assertRoleDetails(detail('openai-codex/gpt-6-astra'), 'worker', expected), /active native settings/);
  assert.throws(() => assertBuiltinModel(modelOutput('openai-codex/gpt-6-astra'), 'worker', expected.model));
  assert.throws(() => assertRoleDetails(detail(), 'reviewer', expected));
  assert.throws(() => assertRoleDetails(detail().replace(`Model: ${expected.model}\n`, ''), 'worker', expected), /one Model/);
});

test('wrong, missing or ambiguous thinking fails independently of correct model', () => {
  assert.throws(() => assertRoleDetails(detail(expected.model, 'high'), 'worker', expected), /active native settings/);
  assert.throws(() => assertRoleDetails(detail().replace('Thinking: medium\n', ''), 'worker', expected), /one Thinking/);
  assert.throws(() => assertRoleDetails(detail().replace('Thinking: medium', 'Thinking: medium\nThinking: high'), 'worker', expected), /one Thinking/);
});

const status = name => ({ type: 'extension_ui_request', method: 'setStatus', statusKey: 'subagents-profile', statusText: `profile: ${name}` });
test('reload requires fresh final status and fresh unique native message', () => {
  const old = status('simple'), fresh = status('simple');
  assert.equal(assertFreshProfileStatus([old, fresh], 1, 'simple'), fresh);
  assert.throws(() => assertFreshProfileStatus([old], 1, 'simple'), /Fresh profile footer/);
  assert.throws(() => assertFreshProfileStatus([old, status('max')], 1, 'simple'), /Fresh profile footer/);
  assert.throws(() => assertFreshProfileStatus([old, fresh, status('max')], 1, 'simple'), /Fresh profile footer/);
  const message = { type: 'message_end', message: { customType: 'subagents-admin', content: detail() } };
  assert.equal(messageText([message], 'subagents-admin'), detail());
  assert.throws(() => messageText([], 'subagents-admin'));
  assert.throws(() => messageText([message, message], 'subagents-admin'));
});
test('native slash initial progress is not a final result or effective-model receipt', () => {
  const event = content => ({ type: 'message_end', message: { customType: 'subagent-slash-result', content } });
  const initial = event('Running subagent...');
  const final = event(modelOutput(expected.model));
  assert.equal(messageText([initial, final], 'subagent-slash-result'), final.message.content);
  assert.throws(() => messageText([initial], 'subagent-slash-result'));
  assert.throws(() => messageText([initial, final, final], 'subagent-slash-result'));
});


function fixture(body, options = {}) {
  const program = `const send = data => process.stdout.write(JSON.stringify(data) + '\\n');
    let buffer = '';
    process.stdin.setEncoding('utf8').on('data', text => {
      buffer += text; let end;
      while ((end = buffer.indexOf('\\n')) !== -1) {
        const request = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
        send({ type: 'response', id: request.id, success: true, data: { ok: true } });
      }
    });
    ${body}`;
  return new Rpc(spawn(process.execPath, ['-e', program], { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] }),
    { timeoutMs: 2000, shutdownMs: 100, killMs: 100, ...options });
}

async function rejectedClose(rpc, pattern) {
  await assert.rejects(rpc.close(), pattern);
  assert.ok(rpc.terminal, 'Child close/stdio must be drained even on failure');
  assert.equal(rpc.child.exitCode !== null || rpc.child.signalCode !== null, true);
  await assert.rejects(rpc.close(), pattern); // no already-exited bypass
}

test('RPC success requires clean unsignalled EOF shutdown; close is idempotent', async () => {
  const rpc = fixture('');
  try {
    assert.deepEqual(await rpc.send('get_state'), { ok: true });
    assert.deepEqual(await rpc.close(), { code: 0, signal: null });
    assert.deepEqual(await rpc.close(), { code: 0, signal: null });
  } finally { await rpc.close(); }
});

test('final response followed by crash fails even when no request is pending', async () => {
  const rpc = fixture("process.stdin.on('end', () => process.exit(7));");
  try { await rpc.send('get_state'); } finally { await rejectedClose(rpc, /7\/null/); }
});

test('a crash after the last response is latched before close is requested', async () => {
  const rpc = fixture("process.stdin.once('data', () => setTimeout(() => process.exit(8), 20));");
  try {
    await rpc.send('get_state');
    await rpc.closed;
  } finally { await rejectedClose(rpc, /8\/null/); }
});

test('already-exited children latch nonzero, signal and even premature zero exits', async () => {
  for (const body of ['process.exit(9);', "process.kill(process.pid, 'SIGTERM');", 'process.exit(0);']) {
    const rpc = fixture(body);
    await rpc.closed;
    await assert.rejects(rpc.send('get_state'), /Pi exited/);
    await assert.rejects(rpc.waitFor(() => true, 0), /Pi exited/);
    await rejectedClose(rpc, /Pi exited/);
  }
});

test('shutdown timeout remains a failure even if SIGTERM exits zero', async () => {
  const rpc = fixture("setInterval(() => {}, 1000); process.on('SIGTERM', () => process.exit(0));");
  try { await rpc.send('get_state'); } finally { await rejectedClose(rpc, /shutdown timeout/); }
  assert.deepEqual(rpc.terminal, { code: 0, signal: null });
});

test('shutdown escalates and drains a child ignoring SIGTERM', async () => {
  const rpc = fixture("setInterval(() => {}, 1000); process.on('SIGTERM', () => {});");
  try { await rpc.send('get_state'); } finally { await rejectedClose(rpc, /shutdown timeout/); }
  assert.equal(rpc.terminal.signal, 'SIGKILL');
});

test('malformed/truncated output and extension load errors cannot qualify', async () => {
  for (const [body, pattern] of [
    ["process.stdin.on('end', () => process.stdout.write('not-json\\n'));", /Unexpected token/],
    ["process.stdin.on('end', () => process.stdout.write('{'));", /Unterminated/],
    ["process.stdin.on('end', () => process.stderr.write('Failed to load extension'));", /Failed to load extension/],
  ]) {
    const rpc = fixture(body);
    try { await rpc.send('get_state'); } finally { await rejectedClose(rpc, pattern); }
  }
});

test('terminal failure rejects active event waiters instead of timing out', async () => {
  const rpc = fixture('');
  await rpc.send('get_state');
  const waiting = assert.rejects(rpc.waitFor(() => false, rpc.events.length), /Pi exited/);
  rpc.child.kill('SIGTERM');
  await waiting;
  await rejectedClose(rpc, /Pi exited/);
});

test('request timeout and forbidden model/dialog events remain terminal faults', async () => {
  const noResponse = new Rpc(spawn(process.execPath, ['-e', 'process.stdin.resume();'],
    { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] }), { timeoutMs: 100, shutdownMs: 100, killMs: 100 });
  try { await assert.rejects(noResponse.send('get_state'), /RPC timeout/); }
  finally { await rejectedClose(noResponse, /RPC timeout/); }
  for (const event of [{ type: 'extension_error', error: 'fixture' },
    { type: 'extension_ui_request', method: 'confirm' }, { type: 'agent_start' }]) {
    const rpc = fixture(`process.stdin.once('data', () => send(${JSON.stringify(event)}));`);
    try {
      await rpc.send('get_state').catch(() => {});
      await rpc.closed;
    } finally { await rejectedClose(rpc, /Unexpected model turn, extension failure or dialog/); }
  }
});

test('spawn failure is latched and drained', async () => {
  const rpc = new Rpc(spawn(path.join(root, 'missing-executable'), [], { cwd: root, env, stdio: ['pipe', 'pipe', 'pipe'] }));
  await rpc.closed;
  await rejectedClose(rpc, /ENOENT/);
});
