import assert from 'node:assert/strict';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { join } from 'node:path';

/** LF is the only delimiter; U+2028/U+2029 inside JSON strings remain data. */
export function jsonlReader(onRecord) {
  let buffer = '';
  return {
    push(text) {
      buffer += text;
      let end;
      while ((end = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, end).replace(/\r$/, '');
        buffer = buffer.slice(end + 1);
        assert.ok(line, 'Empty RPC record');
        onRecord(JSON.parse(line));
      }
    },
    end() { assert.equal(buffer, '', 'Unterminated RPC record'); },
  };
}

/** Allowlist, not a blacklist: no inherited session/child/auth/proxy/Node preload state. */
export function isolatedEnv(root) {
  return {
    PATH: process.env.PATH, LANG: 'C.UTF-8', HOME: root,
    TMPDIR: join(root, 'tmp'), XDG_CACHE_HOME: join(root, 'cache'),
    XDG_CONFIG_HOME: join(root, 'config'), XDG_DATA_HOME: join(root, 'data'),
    PI_CODING_AGENT_DIR: join(root, 'agent'), PI_OFFLINE: '1', JITI_FS_CACHE: 'false',
    NO_COLOR: '1', TERM: 'dumb',
  };
}

export function launchRpc(fixture, label = 'parent') {
  const { root, cli, extensions } = fixture;
  const args = [cli, '--mode', 'rpc', '--no-extensions', '--no-skills', '--no-prompt-templates',
    ...extensions.flatMap(file => ['-e', file]), '--session', join(root, `${label}.jsonl`),
    '--provider', 'native-acceptance-fixture', '--model', 'parent-scripted', '--thinking', 'high'];
  const child = spawn(process.execPath, args, { cwd: root, env: isolatedEnv(root), stdio: ['pipe', 'pipe', 'pipe'] });
  const pending = new Map(), waiters = new Set(), events = [];
  let sequence = 0, fault, stderr = '';
  const log = join(root, `${label}-rpc.jsonl`);
  const fail = error => {
    fault ??= error;
    for (const request of pending.values()) { clearTimeout(request.timer); request.reject(error); }
    pending.clear();
    for (const waiter of waiters) waiter.reject(error);
    waiters.clear();
  };
  const reader = jsonlReader(event => {
    events.push(event);
    if (event.type === 'extension_ui_request' && ['confirm', 'select', 'input', 'editor'].includes(event.method)) {
      // Never auto-approve a permit, protected action or unexpected confirmation.
      child.stdin.write(JSON.stringify({ type: 'extension_ui_response', id: event.id, cancelled: true }) + '\n');
    }
    const request = event.type === 'response' && pending.get(event.id);
    if (request) {
      clearTimeout(request.timer); pending.delete(event.id);
      if (event.success) request.resolve(event.data);
      else request.reject(new Error(event.error ?? 'RPC command failed'));
    }
    for (const waiter of [...waiters]) if (waiter.predicate(event)) { waiters.delete(waiter); waiter.resolve(event); }
  });
  child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
  child.stdout.on('data', text => {
    fs.appendFileSync(log, text);
    try { reader.push(text); } catch (error) { fail(error); }
  });
  child.stderr.on('data', text => { stderr += text; fs.appendFileSync(join(root, `${label}-stderr.log`), text); });
  child.on('error', fail);
  child.on('close', code => {
    try { reader.end(); } catch (error) { fail(error); }
    if (pending.size || waiters.size) fail(new Error(`Pi exited ${code}: ${stderr.slice(-8000)}`));
  });
  child.stdin.on('error', fail);
  const rpc = {
    events, pid: child.pid, args, log,
    request(type, params = {}) {
      if (fault) return Promise.reject(fault);
      return new Promise((resolve, reject) => {
        const id = `${label}-${++sequence}`;
        const timer = setTimeout(() => { pending.delete(id); reject(new Error(`RPC timeout ${type}: ${stderr.slice(-8000)}`)); }, 90000);
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(JSON.stringify({ id, type, ...params }) + '\n');
      });
    },
    wait(predicate, from = 0) {
      const found = events.slice(from).find(predicate);
      if (found) return Promise.resolve(found);
      if (fault) return Promise.reject(fault);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { waiters.delete(waiter); reject(new Error(`RPC event timeout: ${stderr.slice(-8000)}`)); }, 90000);
        const waiter = { predicate, resolve: value => { clearTimeout(timer); resolve(value); }, reject: error => { clearTimeout(timer); reject(error); } };
        waiters.add(waiter);
      });
    },
    async call(name, input) {
      const from = events.length;
      await rpc.request('prompt', { message: 'NATIVE_FIXTURE_CALL\n' + JSON.stringify({ name, input, id: `fixture-${randomUUID()}` }) });
      await rpc.wait(event => event.type === 'agent_settled', from);
      const results = events.slice(from).filter(event => event.type === 'tool_execution_end');
      assert.equal(results.length, 1, `Expected exactly one native dispatch: ${JSON.stringify(results)}`);
      assert.equal(results[0].toolName, name);
      return results[0];
    },
    async close() {
      if (child.exitCode !== null || child.signalCode !== null) return;
      // Foreground-only fixture work: first request abort, then drain native cleanup on EOF.
      await rpc.request('abort').catch(() => {});
      const closed = once(child, 'close'); child.stdin.end();
      const kill = setTimeout(() => child.kill('SIGTERM'), 5000);
      const hardKill = setTimeout(() => child.kill('SIGKILL'), 15000);
      try { await closed; } finally { clearTimeout(kill); clearTimeout(hardKill); }
    },
  };
  return rpc;
}

export const textOf = result => (result.content ?? result.result?.content ?? []).filter(row => row.type === 'text').map(row => row.text).join('\n');
export function success(event) {
  assert.equal(event.isError, false, textOf(event));
  return event.result.details;
}
export function rejected(event, pattern) {
  assert.equal(event.isError, true, `Unexpected success: ${JSON.stringify(event)}`);
  assert.match(textOf(event), pattern);
  return textOf(event);
}
export const parentTuple = state => ({ provider: state.model?.provider, model: state.model?.id, thinking: state.thinkingLevel });
export async function branchMarker(rpc) {
  const { entries, leafId } = await rpc.request('get_entries');
  const byId = new Map(entries.map(entry => [entry.id, entry]));
  for (let entry = byId.get(leafId); entry; entry = byId.get(entry.parentId)) {
    if (entry.type === 'custom' && entry.customType === 'pi-subagents-profile') return entry.data.name;
  }
}
