import assert from 'node:assert/strict';
import test from 'node:test';
import { jsonlReader, isolatedEnv, rejected, success } from './rpc.mjs';

// These are helper unit tests, not substitutes for either native acceptance journey.
test('RPC uses LF framing, preserves Unicode separators and fragmented JSON', () => {
  const actual = [];
  const reader = jsonlReader(value => actual.push(value));
  const first = { text: 'one\u2028two\u2029three\nquoted newline' };
  const wire = JSON.stringify(first) + '\r\n' + JSON.stringify({ type: 'response', success: true }) + '\n';
  for (let i = 0; i < wire.length; i += 3) reader.push(wire.slice(i, i + 3));
  reader.end();
  assert.deepEqual(actual, [first, { type: 'response', success: true }]);
});

test('RPC rejects junk, empty records and unterminated final output', () => {
  assert.throws(() => jsonlReader(() => {}).push('not JSON\n'));
  assert.throws(() => jsonlReader(() => {}).push('\n'), /Empty RPC record/);
  const reader = jsonlReader(() => {}); reader.push('{"ok":true}');
  assert.throws(() => reader.end(), /Unterminated RPC record/);
});

test('fixture environment is allowlisted and isolation locations are private-root relative', () => {
  const env = isolatedEnv('/tmp/native-helper-unit');
  assert.equal(env.HOME, '/tmp/native-helper-unit');
  assert.equal(env.PI_CODING_AGENT_DIR, '/tmp/native-helper-unit/agent');
  assert.equal(env.JITI_FS_CACHE, 'false');
  assert.equal(env.PI_OFFLINE, '1');
  for (const key of ['PI_SUBAGENT_CHILD', 'PI_SUBAGENT_PARENT_SESSION', 'PI_SESSION_FILE', 'CB_PI_AUTO_MODE_CONTROL_V1', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'NODE_OPTIONS', 'HTTP_PROXY', 'AWS_PROFILE', 'SSH_AUTH_SOCK']) assert.equal(env[key], undefined);
  assert.deepEqual(Object.keys(env).sort(), ['HOME', 'JITI_FS_CACHE', 'LANG', 'NO_COLOR', 'PATH', 'PI_CODING_AGENT_DIR', 'PI_OFFLINE', 'TERM', 'TMPDIR', 'XDG_CACHE_HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME'].sort());
});

test('native result assertions reject prose success and mismatched failure', () => {
  assert.deepEqual(success({ isError: false, result: { details: { value: 3 } } }), { value: 3 });
  assert.throws(() => success({ isError: true, result: { content: [{ type: 'text', text: 'success claimed' }] } }));
  const failure = { isError: true, result: { content: [{ type: 'text', text: 'unmet dependency' }] } };
  assert.equal(rejected(failure, /unmet dependency/), 'unmet dependency');
  assert.throws(() => rejected(failure, /stale/));
});
