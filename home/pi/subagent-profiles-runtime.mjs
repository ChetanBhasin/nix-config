// Shared acceptance mechanics. Only builtins are imported before isolation.
import assert from 'node:assert/strict';
import path from 'node:path';

export function isolatedEnv(root, agentDir, inherited = process.env) {
  return {
    PATH: inherited.PATH ?? '/usr/bin:/bin', LANG: 'C.UTF-8', HOME: root,
    TMPDIR: path.join(root, 'tmp'), XDG_CACHE_HOME: path.join(root, 'cache'),
    XDG_CONFIG_HOME: path.join(root, 'config'), XDG_DATA_HOME: path.join(root, 'data'),
    PI_CODING_AGENT_DIR: agentDir, PI_OFFLINE: '1', PI_SKIP_VERSION_CHECK: '1',
    JITI_FS_CACHE: 'false', NO_COLOR: '1', TERM: 'dumb',
  };
}

export function isolateProcessEnvironment(root, agentDir) {
  const env = isolatedEnv(root, agentDir);
  for (const key of Object.keys(process.env)) delete process.env[key];
  Object.assign(process.env, env);
  return env;
}

export function assertFreshProfileStatus(events, start, name) {
  assert.ok(Number.isInteger(start) && start >= 0 && start <= events.length, 'Status cursor required');
  const status = events.slice(start).filter(event => event.type === 'extension_ui_request'
    && event.method === 'setStatus' && event.statusKey === 'subagents-profile').at(-1);
  assert.equal(status?.statusText, `profile: ${name}`, 'Fresh profile footer required');
  return status;
}

export function messageText(events, customType) {
  const messages = events.filter(event => event.type === 'message_end' && event.message?.customType === customType
    && (customType !== 'subagent-slash-result' || event.message.content?.startsWith('## Subagent result\n')));
  assert.equal(messages.length, 1, `Expected one fresh ${customType} message`);
  const text = messages[0].message.content;
  assert.equal(typeof text, 'string');
  return text;
}

// Inspect only native metadata, never prompt text or the available-model catalog.
export function assertRoleDetails(text, role, configured) {
  const metadata = text.split('\n\nSystem Prompt:')[0].split('\n');
  assert.match(metadata[0], new RegExp(`^Agent: ${role} \\(builtin\\)$|^Agent: ${role} \\(user\\)$`));
  const field = name => {
    const lines = metadata.filter(line => line.startsWith(`${name}: `));
    assert.equal(lines.length, 1, `${role}: exactly one ${name} field required`);
    return lines[0].slice(name.length + 2);
  };
  const observed = { model: field('Model'), thinking: field('Thinking') };
  assert.deepEqual(observed, { model: configured.model, thinking: configured.thinking }, `${role}: active native settings`);
  return observed;
}

export function assertBuiltinModel(text, role, expected) {
  const lines = text.split('\n');
  const heading = lines.indexOf('Builtin subagent model');
  assert.ok(heading >= 0, 'Native per-role effective-model result required');
  assert.deepEqual(lines.slice(heading + 1, heading + 5), ['', `Agent: ${role}`, 'Effective model:', `  ${expected}`]);
}

/** Strict foreground JSONL transport: faults outlive requests and shutdown drains stdio. */
export class Rpc {
  constructor(child, { timeoutMs = 30000, shutdownMs = 2000, killMs = 2000 } = {}) {
    this.child = child;
    this.timeoutMs = timeoutMs;
    this.shutdownMs = shutdownMs;
    this.killMs = killMs;
    this.events = [];
    this.pending = new Map();
    this.waiters = new Set();
    this.counter = 0;
    this.stderr = '';
    this.buffer = '';
    this.fault = undefined;
    this.closing = false;
    this.exited = false;
    this.closed = new Promise(resolve => {
      child.on('close', (code, signal) => {
        if (this.buffer) this.fail(new Error('Unterminated RPC record'));
        if (code !== 0 || signal !== null) this.fail(new Error(`Pi shutdown failed: ${code}/${signal}: ${this.stderr}`));
        if (!this.closing || this.pending.size || this.waiters.size) this.fail(new Error(`Pi closed before shutdown: ${code}/${signal}`));
        this.terminal = { code, signal };
        resolve(this.terminal);
      });
    });
    child.stderr.setEncoding('utf8').on('data', text => { this.stderr += text; });
    child.stdout.setEncoding('utf8').on('data', text => {
      this.buffer += text;
      try {
        let end;
        while ((end = this.buffer.indexOf('\n')) !== -1) {
          const line = this.buffer.slice(0, end).replace(/\r$/, '');
          this.buffer = this.buffer.slice(end + 1);
          assert.ok(line, 'Empty RPC record');
          this.receive(JSON.parse(line));
        }
      } catch (error) { this.fail(error); child.kill('SIGTERM'); }
    });
    for (const emitter of [child, child.stdin, child.stdout, child.stderr]) emitter.on('error', error => this.fail(error));
    child.on('exit', (code, signal) => {
      this.exited = true;
      if (!this.closing || code !== 0 || signal !== null || this.pending.size || this.waiters.size) {
        this.fail(new Error(`Pi exited: ${code}/${signal}: ${this.stderr}`));
      }
    });
  }

  fail(error) {
    this.fault ??= error;
    for (const request of this.pending.values()) request.reject(this.fault);
    this.pending.clear();
    for (const waiter of this.waiters) waiter.reject(this.fault);
    this.waiters.clear();
  }

  assertRunning() {
    if (this.fault) throw this.fault;
    assert.ok(!this.closing && !this.exited && !this.terminal, 'RPC is not running');
  }

  receive(event) {
    this.events.push(event);
    if (event.type === 'extension_error'
      || (event.type === 'extension_ui_request' && ['confirm', 'select', 'input', 'editor'].includes(event.method))
      || event.type === 'agent_start' || (event.type === 'message_start' && event.message?.role === 'assistant')) {
      this.fail(new Error(`Unexpected model turn, extension failure or dialog: ${JSON.stringify(event)}`));
      this.child.kill('SIGTERM');
      return;
    }
    if (event.type === 'response') {
      const request = this.pending.get(event.id);
      if (request) {
        this.pending.delete(event.id);
        if (event.success) request.resolve(event.data);
        else request.reject(new Error(event.error));
      }
    }
    for (const waiter of this.waiters) if (waiter.predicate(event)) waiter.resolve(event);
  }

  async send(type, fields = {}) {
    this.assertRunning();
    const id = String(++this.counter);
    let timer;
    try {
      return await new Promise((resolve, reject) => {
        this.pending.set(id, { resolve, reject });
        timer = setTimeout(() => this.fail(new Error(`RPC timeout: ${type}: ${this.stderr}`)), this.timeoutMs);
        this.child.stdin.write(JSON.stringify({ ...fields, id, type }) + '\n');
      });
    } finally { clearTimeout(timer); this.pending.delete(id); }
  }

  async waitFor(predicate, start) {
    this.assertRunning();
    const found = this.events.slice(start).find(predicate);
    if (found) return found;
    let timer, waiter;
    try {
      return await new Promise((resolve, reject) => {
        waiter = { predicate, resolve, reject };
        this.waiters.add(waiter);
        timer = setTimeout(() => this.fail(new Error(`Slash result timeout: ${this.stderr}`)), this.timeoutMs);
      });
    } finally { clearTimeout(timer); this.waiters.delete(waiter); }
  }

  async prompt(message) {
    const before = this.events.length;
    await this.send('prompt', { message });
    let customType;
    if (message.startsWith('/subagents ')) customType = 'subagents-admin';
    else if (message.startsWith('/run ') || message.startsWith('/subagents-models')) customType = 'subagent-slash-result';
    if (customType) await this.waitFor(event => event.type === 'message_end' && event.message?.customType === customType
      && (customType !== 'subagent-slash-result' || event.message.content?.startsWith('## Subagent result\n')), before);
    this.assertRunning();
    return JSON.stringify(this.events.slice(before));
  }

  close() {
    this.closePromise ??= this.drain();
    return this.closePromise;
  }

  async drain() {
    this.closing = true;
    let timer, hardKill;
    try {
      if (!this.terminal) {
        if (!this.exited) this.child.stdin.end();
        timer = setTimeout(() => {
          this.fail(new Error('RPC shutdown timeout; terminating child'));
          this.child.kill('SIGTERM');
          hardKill = setTimeout(() => this.child.kill('SIGKILL'), this.killMs);
        }, this.shutdownMs);
      }
      const terminal = await this.closed;
      if (/Failed to load extension/.test(this.stderr)) this.fail(new Error(this.stderr));
      if (this.fault) throw this.fault;
      assert.deepEqual(terminal, { code: 0, signal: null }, 'Clean unsignalled shutdown required');
      return terminal;
    } finally { clearTimeout(timer); clearTimeout(hardKill); }
  }
}
