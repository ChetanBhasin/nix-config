import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const strategyDir = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const agentDir = resolve(strategyDir, '../..');
export const nativeDir = join(agentDir, 'npm/node_modules/pi-subagents');
export const piDir = join(agentDir, 'npm/node_modules/@earendil-works/pi-coding-agent');
export const sha256 = data => createHash('sha256').update(data).digest('hex');
export const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
export const writeJson = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');

function filesBelow(root) {
  return fs.readdirSync(root, { withFileTypes: true }).flatMap(entry => {
    const file = join(root, entry.name);
    if (entry.name === 'node_modules' || entry.name === '.git') return [];
    return entry.isDirectory() ? filesBelow(file) : entry.isFile() ? [file] : [];
  });
}

/** Hash code/config only. Never enumerate or read credentials or live sessions. */
export function protectedSnapshot() {
  const files = [join(agentDir, 'settings.json'),
    ...filesBelow(join(agentDir, 'profiles/pi-subagents')),
    ...filesBelow(join(agentDir, 'extensions/auto-mode')),
    ...filesBelow(join(nativeDir, 'src')), join(nativeDir, 'package.json'), join(nativeDir, 'index.ts'),
    ...filesBelow(strategyDir).filter(file => file !== join(strategyDir, 'acceptance.mjs') && !file.startsWith(join(strategyDir, 'tests/native/'))),
  ];
  return Object.fromEntries(files.sort().map(file => [file, sha256(fs.readFileSync(file))]));
}

export function seedFixture(mode) {
  assert.ok(['profiles', 'delegation', 'review', 'receipts'].includes(mode));
  assert.equal(readJson(join(piDir, 'package.json')).version, '0.84.4');
  assert.equal(readJson(join(nativeDir, 'package.json')).version, '0.56.0');
  fs.mkdirSync('/tmp/execution-strategy-tests', { recursive: true, mode: 0o700 });
  const root = fs.mkdtempSync(`/tmp/execution-strategy-tests/native-${mode}-`);
  fs.chmodSync(root, 0o700);
  const agent = join(root, 'agent'), profiles = join(agent, 'profiles/pi-subagents');
  for (const dir of [agent, profiles, join(root, 'tmp'), join(root, 'work')]) fs.mkdirSync(dir, { recursive: true });
  const originals = {};
  for (const name of ['simple', 'complex', 'max']) {
    const source = join(agentDir, 'profiles/pi-subagents', `${name}.json`);
    fs.copyFileSync(source, join(profiles, `${name}.json`));
    originals[name] = readJson(source);
  }
  fs.writeFileSync(join(profiles, 'invalid.json'), '{not valid JSON');
  const provider = join(root, 'fixture-provider.ts');
  fs.copyFileSync(new URL('./provider.ts', import.meta.url), provider);
  const guard = join(agentDir, 'extensions/auto-mode/index.ts');
  const extensions = [join(nativeDir, 'index.ts'), guard, join(strategyDir, 'index.ts'), provider];
  // Native discovery needs the actual custom lookup definition as well as builtin roles.
  fs.mkdirSync(join(agent, 'agents'), { recursive: true });
  fs.copyFileSync(join(agentDir, 'extensions/lookup-role/agents/lookup.md'), join(agent, 'agents/lookup.md'));
  const fixtureOverrides = {};
  if (mode !== 'profiles') {
    for (const [role, model, tools] of [
      ['worker', 'child-writer-scripted', ['workflow_contract', 'writer_lease', 'read', 'write', 'bash']],
      ['reviewer', 'child-reviewer-scripted', ['read']],
    ]) {
      fixtureOverrides[role] = {
        model: `native-acceptance-fixture/${model}`, fallbackModels: [], thinking: 'high',
        tools, extensions: [provider, guard], subagentOnlyExtensions: [],
        inheritProjectContext: false, inheritSkills: false, defaultContext: 'fresh',
        systemPrompt: 'Explicitly scripted offline acceptance fixture. Work only the supplied execution-strategy assignment. Native guard and native acceptance remain enabled.',
        systemPromptMode: 'replace', output: false, outputMode: 'inline',
        acceptanceRole: role === 'worker' ? 'writer' : 'read-only',
      };
    }
    if (mode === 'receipts') {
      // Keep the real lookup role's read-only tools, prompt and file-only output contract.
      // Only its provider/dependency wiring is isolated; this is NOT a Terra qualification.
      fixtureOverrides.lookup = {
        model: 'native-acceptance-fixture/child-lookup-scripted', fallbackModels: [], thinking: 'medium',
        extensions: [provider, join(agentDir, 'npm/node_modules/pi-lens/dist/index.js'), join(agentDir, 'npm/node_modules/@howaboua/pi-codex-web-run/index.ts')],
        subagentOnlyExtensions: [guard],
      };
      // User-scope native definitions outrank profile overrides in get/discovery. Isolate
      // those same transport fields in the copied definition too; never touch the live role.
      const lookupPath = join(agent, 'agents/lookup.md');
      const lookup = fs.readFileSync(lookupPath, 'utf8');
      fs.writeFileSync(lookupPath, lookup
        .replace(/^model: .+$/m, 'model: native-acceptance-fixture/child-lookup-scripted')
        .replace(/^description: .+$/m, 'description: Offline deterministic fixture wiring of the real lookup role, not Terra qualification')
        .replace(/^extensions: .+$/m, `extensions: ${fixtureOverrides.lookup.extensions.join(', ')}`)
        .replace(/^subagentOnlyExtensions: .+$/m, `subagentOnlyExtensions: ${guard}`));
    }
    const selected = structuredClone(originals.max);
    Object.assign(selected.subagents.agentOverrides, fixtureOverrides);
    writeJson(join(profiles, 'max.json'), selected);
  }
  const subagents = readJson(join(profiles, 'max.json')).subagents;
  writeJson(join(agent, 'settings.json'), {
    packages: [], defaultProjectTrust: 'yes', defaultProvider: 'native-acceptance-fixture',
    defaultModel: 'parent-scripted', defaultThinkingLevel: 'high', subagents,
    compaction: { enabled: false }, retry: { enabled: false },
  });
  writeJson(join(agent, 'models.json'), { providers: {} });
  writeJson(join(root, 'fixture-identity.json'), {
    mode, boundary: 'Deterministic provider only; native Pi CLI, dispatch, pi-subagents and child processes. No real provider requests.',
    pi: { version: '0.84.4', root: piDir, cliHash: sha256(fs.readFileSync(join(piDir, 'dist/cli.js'))) },
    subagents: { version: '0.56.0', root: nativeDir, sourceHash: sha256(fs.readFileSync(join(nativeDir, 'src/extension/index.ts'))) },
    fixtureOverrides, originalProfileHashes: Object.fromEntries(Object.keys(originals).map(name => [name, sha256(fs.readFileSync(join(agentDir, 'profiles/pi-subagents', `${name}.json`)))])),
  });
  return { root, agent, profiles, originals, cli: join(piDir, 'dist/cli.js'), extensions, fixtureOverrides };
}
