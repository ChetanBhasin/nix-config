import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { applyRepairs, digest } from './patcher.mjs';

function fixture(t) {
  const agentDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-preflight-'));
  t.after(() => fs.rmSync(agentDir, { recursive: true, force: true }));
  const patch = { file: 'index.js', beforeHash: digest('before\n'), afterHash: digest('after\n'),
    edits: [{ before: 'before\n', after: 'after\n' }] };
  const manifest = { packages: ['first', 'second'].map(name => ({ name, version: '1.0.0', patches: [patch] })) };
  const root = name => path.join(agentDir, 'npm/node_modules', name);
  const install = (name, version = '1.0.0', source = 'before\n') => {
    fs.mkdirSync(root(name), { recursive: true });
    fs.writeFileSync(path.join(root(name), 'package.json'), JSON.stringify({ name, version }));
    fs.writeFileSync(path.join(root(name), 'index.js'), source);
  };
  return { agentDir, manifest, root, install, run: options => applyRepairs({ agentDir, manifest, ...options }) };
}

test('cold preflight defers absent packages but health checks and post-resolution apply stay strict', (t) => {
  const f = fixture(t);
  assert.deepEqual(f.run({ deferMissing: true }), { checked: 0, repaired: 0,
    deferred: ['first@1.0.0', 'second@1.0.0'], packages: [] });
  assert.throws(() => f.run({}), /ENOENT/);
  assert.throws(() => f.run({ check: true }), /ENOENT/);
  assert.throws(() => f.run({ check: true, deferMissing: true }), /cannot defer/);
});

test('partial package set repairs installed code then completes strictly after normal resolution', (t) => {
  const f = fixture(t); f.install('first');
  const initial = f.run({ deferMissing: true });
  assert.equal(initial.repaired, 1); assert.deepEqual(initial.deferred, ['second@1.0.0']);
  assert.deepEqual(initial.packages, ['first@1.0.0']);
  assert.equal(fs.readFileSync(path.join(f.root('first'), 'index.js'), 'utf8'), 'after\n');
  f.install('second');
  assert.equal(f.run({}).repaired, 1);
  assert.deepEqual(f.run({ check: true }).deferred, []);
});

test('unknown versions/sources still reject the entire plan before any installed file changes', (t) => {
  for (const invalid of ['version', 'source']) {
    const f = fixture(t); f.install('first');
    f.install('second', invalid === 'version' ? '2.0.0' : '1.0.0', invalid === 'source' ? 'local edit\n' : 'before\n');
    assert.throws(() => f.run({ deferMissing: true }), /review compatibility|refusing to overwrite/);
    assert.equal(fs.readFileSync(path.join(f.root('first'), 'index.js'), 'utf8'), 'before\n');
  }
});

test('an existing incomplete directory or dangling package symlink is not an absent install', (t) => {
  for (const dangling of [false, true]) {
    const f = fixture(t); f.install('first');
    if (dangling) fs.symlinkSync(path.join(f.agentDir, 'missing-target'), f.root('second'));
    else fs.mkdirSync(f.root('second'));
    assert.throws(() => f.run({ deferMissing: true }), /ENOENT/);
    assert.equal(fs.readFileSync(path.join(f.root('first'), 'index.js'), 'utf8'), 'before\n');
  }
});
