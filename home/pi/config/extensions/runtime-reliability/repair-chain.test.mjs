import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { after, before, test } from 'node:test';
import { applyRepairs, digest, patchedChain, patchedText } from './patcher.mjs';

const manifest = JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));
const pkg = manifest.packages.find(entry => entry.name === 'pi-subagents');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-release-repair-'));
after(() => fs.rmSync(temp, { recursive: true, force: true }));
const release = path.join(temp, 'package');

before(() => {
  assert.equal(pkg.version, '0.56.0');
  let archive = process.env.PI_TEST_SUBAGENTS_TARBALL;
  if (!archive) {
    // Exercise the published source, not a reverse patch of an already-repaired
    // installation. Cache misses fail explicitly; never install or go online.
    const packed = JSON.parse(execFileSync(process.env.PI_TEST_NPM || 'npm', [
      'pack', 'pi-subagents@0.56.0', '--offline', '--ignore-scripts', '--json',
      '--pack-destination', temp,
    ], { cwd: temp, encoding: 'utf8' }));
    archive = path.join(temp, packed[0].filename);
  }
  execFileSync('tar', ['-xzf', path.resolve(archive), '-C', temp]);
  assert.equal(JSON.parse(fs.readFileSync(path.join(release, 'package.json'), 'utf8')).version, pkg.version);
  for (const [file, expected] of [
    ['src/profiles/profiles.ts', 'ffb56588e7074718ca295308e8be1334743b5b0834d13cfe74e17fc90421923b'],
    ['src/extension/index.ts', '00c761903589186f9f38841b291e65aeb143029557ca8e1086e2167a845bc6b2'],
  ]) {
    assert.equal(digest(fs.readFileSync(path.join(release, file), 'utf8')), expected, `${file} published source`);
  }
});

test('all native repairs apply to the pristine npm release and remain idempotent', () => {
  const agentDir = path.join(temp, 'agent');
  const root = path.join(agentDir, 'npm/node_modules', pkg.name);
  fs.cpSync(release, root, { recursive: true });
  const nativeManifest = { packages: [pkg] };
  assert.throws(() => applyRepairs({ agentDir, manifest: nativeManifest, check: true }), /Repairs missing/);
  const files = [...new Set(pkg.patches.map(patch => patch.file))];
  assert.equal(applyRepairs({ agentDir, manifest: nativeManifest }).repaired, files.length);
  for (const file of files) {
    const final = pkg.patches.filter(patch => patch.file === file).at(-1);
    assert.equal(digest(fs.readFileSync(path.join(root, file), 'utf8')), final.afterHash, file);
  }
  assert.equal(applyRepairs({ agentDir, manifest: nativeManifest, check: true }).repaired, 0);
  assert.equal(applyRepairs({ agentDir, manifest: nativeManifest }).repaired, 0);
});

test('profile and entrypoint repairs accept every prior stage and reject unknown edits', () => {
  for (const file of ['src/profiles/profiles.ts', 'src/extension/index.ts']) {
    const patches = pkg.patches.filter(patch => patch.file === file);
    let current = fs.readFileSync(path.join(release, file), 'utf8');
    const stages = [current];
    for (const patch of patches) {
      current = patchedText(current, patch);
      stages.push(current);
    }
    for (const [index, stage] of stages.entries()) {
      assert.equal(patchedChain(stage, patches), current, `${file} from stage ${index}`);
      assert.throws(() => patchedChain(stage + '\n// local edit\n', patches), /Unrecognized source/);
    }
  }
});
