// Uses Pi's actual source and bundled loaders AND real npm, strictly offline.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { digest } from './patcher.mjs';

const packageDir = process.env.PI_TEST_PACKAGE_DIR || fileURLToPath(new URL('../../npm/node_modules/@earendil-works/pi-coding-agent/', import.meta.url));
const variants = [
  ['source', await import(pathToFileURL(path.join(packageDir, 'dist/index.js')).href)],
  ['bundle', await import(pathToFileURL(path.join(packageDir, 'dist/bundle/index.js')).href)],
];

async function fixture(t, sdk, scenario) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-cold-bootstrap-'));
  const agentDir = path.join(temp, 'agent'), cwd = path.join(temp, 'project');
  const repairDir = path.join(temp, 'repair'), trace = path.join(temp, 'imports.jsonl');
  for (const dir of [agentDir, cwd, repairDir]) fs.mkdirSync(dir);
  const prior = { offline: process.env.PI_OFFLINE, prefix: process.env.npm_config_prefix };
  // PI_OFFLINE disables installation entirely, including local archives. Instead
  // constrain the real npm executable with --offline and disable lifecycle hooks.
  delete process.env.PI_OFFLINE;
  process.env.npm_config_prefix = path.join(temp, 'npm-global');
  t.after(() => {
    if (prior.offline === undefined) delete process.env.PI_OFFLINE; else process.env.PI_OFFLINE = prior.offline;
    if (prior.prefix === undefined) delete process.env.npm_config_prefix; else process.env.npm_config_prefix = prior.prefix;
    fs.rmSync(temp, { recursive: true, force: true });
  });
  const count = scenario === 'partial' ? 2 : 1;
  const packages = [], specs = [];
  for (let i = 0; i < count; i++) {
    const name = `fixture-${path.basename(temp).toLowerCase()}-${i}`;
    const directory = path.join(temp, `archive-${i}`), pkg = path.join(directory, 'package');
    fs.mkdirSync(pkg, { recursive: true });
    const version = scenario === 'version' ? '2.0.0' : '1.0.0';
    fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name, version, type: 'module', pi: { extensions: ['./extension.js'] } }));
    const before = [
      "import fs from 'node:fs';", 'const repaired = false;',
      `const record = kind => fs.appendFileSync(${JSON.stringify(trace)}, JSON.stringify({ kind, name: ${JSON.stringify(name)}, repaired }) + '\\n');`,
      "record('import');", "if (!repaired) throw new Error('Extension imported before repair');",
      "export default function () { record('factory'); }", '',
    ].join('\n');
    const after = before.replace('const repaired = false;', 'const repaired = true;');
    fs.writeFileSync(path.join(pkg, 'extension.js'), scenario === 'source' ? before + '// unknown source\n' : before);
    const archive = path.join(temp, `${name}.tgz`);
    execFileSync('tar', ['-czf', archive, '-C', directory, 'package']);
    specs.push(`npm:${name}@file:${archive}`);
    packages.push({ name, version: '1.0.0', patches: [{ file: 'extension.js', beforeHash: digest(before), afterHash: digest(after),
      edits: [{ before: 'const repaired = false;', after: 'const repaired = true;' }] }] });
  }
  for (const file of ['bootstrap.mjs', 'patcher.mjs']) fs.copyFileSync(new URL(file, import.meta.url), path.join(repairDir, file));
  fs.writeFileSync(path.join(repairDir, 'patches.json'), JSON.stringify({ packages }));
  const { applyRepairs } = await import(pathToFileURL(path.join(repairDir, 'patcher.mjs')).href);
  const { installBootstrapRepairs } = await import(pathToFileURL(path.join(repairDir, 'bootstrap.mjs')).href);
  class IsolatedLoader extends sdk.DefaultResourceLoader {}
  installBootstrapRepairs(IsolatedLoader); installBootstrapRepairs(IsolatedLoader);
  const settingsManager = sdk.SettingsManager.inMemory({ packages: specs,
    npmCommand: [process.env.PI_TEST_NPM || 'npm', '--offline', '--ignore-scripts', '--no-audit', '--no-fund', '--cache', path.join(temp, 'npm-cache')] });
  const loader = new IsolatedLoader({ cwd, agentDir, settingsManager,
    noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true });
  const records = () => fs.existsSync(trace) ? fs.readFileSync(trace, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
  const packageRoot = name => path.join(agentDir, 'npm/node_modules', name);
  if (scenario === 'partial') {
    // Public real installer, not a copied/faked preinstalled package tree.
    await loader.packageManager.install(specs[0]);
    assert.ok(fs.existsSync(path.join(packageRoot(packages[0].name), 'package.json')));
    assert.ok(!fs.existsSync(packageRoot(packages[1].name)));
  } else assert.ok(!fs.existsSync(path.join(agentDir, 'npm')));
  const initial = applyRepairs({ agentDir, deferMissing: true });
  assert.equal(initial.deferred.length, scenario === 'partial' ? 1 : count);
  assert.deepEqual(records(), []);
  return { loader, agentDir, packages, records, applyRepairs };
}

for (const [name, sdk] of variants) {
  for (const scenario of ['cold', 'trust', 'partial', 'version', 'source']) {
    test(`${name}: real offline npm ${scenario} bootstrap before any extension evaluation`, async (t) => {
      const f = await fixture(t, sdk, scenario);
      const useTrust = scenario !== 'cold' && scenario !== 'source';
      let trustCalls = 0;
      const options = useTrust ? { resolveProjectTrust: async ({ extensionsResult }) => {
        trustCalls++;
        assert.deepEqual(extensionsResult.errors, []);
        assert.equal(f.records().filter(record => record.kind === 'import').length, f.packages.length);
        assert.ok(f.records().every(record => record.repaired));
        return false;
      } } : undefined;
      if (scenario === 'version' || scenario === 'source') {
        await assert.rejects(() => f.loader.reload(options), /review compatibility|Unrecognized source/);
        assert.deepEqual(f.records(), [], 'Must reject before top-level code, not merely collect extension errors');
        assert.equal(trustCalls, 0);
        return;
      }
      await f.loader.reload(options);
      assert.equal(trustCalls, useTrust ? 1 : 0);
      assert.deepEqual(f.loader.getExtensions().errors, []);
      assert.equal(f.records().length, f.packages.length * 2, 'One top-level import and one factory per package');
      assert.ok(f.records().every(record => record.repaired));
      assert.deepEqual(f.applyRepairs({ agentDir: f.agentDir, check: true }).deferred, []);
      const targets = f.packages.map(pkg => path.join(f.agentDir, 'npm/node_modules', pkg.name, 'extension.js'));
      for (const target of targets) {
        fs.writeFileSync(target, fs.readFileSync(target, 'utf8').replace('const repaired = true;', 'const repaired = false;'));
      }
      await f.loader.reload();
      assert.deepEqual(f.loader.getExtensions().errors, []);
      // Native JS modules remain cached; Pi invokes their factory again on reload.
      assert.equal(f.records().filter(record => record.kind === 'factory').length, f.packages.length * 2);
      assert.ok(f.records().every(record => record.repaired));
      assert.equal(f.applyRepairs({ agentDir: f.agentDir, check: true }).repaired, 0, 'Reload repaired reinstalled known source');
      const prior = f.records();
      fs.appendFileSync(targets[0], '// unreviewed change\n');
      await assert.rejects(() => f.loader.reload(), /Unrecognized source/);
      assert.deepEqual(f.records(), prior, 'Cached factories must not run after source integrity changes');
      assert.ok(fs.readFileSync(targets[0], 'utf8').endsWith('// unreviewed change\n'));
    });
  }
}
