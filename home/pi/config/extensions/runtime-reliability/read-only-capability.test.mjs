import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { digest, patchedText } from './patcher.mjs';

const native = new URL('../../npm/node_modules/pi-subagents/', import.meta.url);
const manifest = JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));
const { createJiti } = await import(new URL('../../npm/node_modules/jiti/lib/jiti.mjs', import.meta.url));
const jiti = createJiti(import.meta.url, { fsCache: false });
const guard = await jiti.import(fileURLToPath(new URL('src/runs/shared/completion-guard.ts', native)));
const output = await jiti.import(fileURLToPath(new URL('src/runs/shared/single-output.ts', native)));
const intent = await jiti.import(fileURLToPath(new URL('src/runs/shared/task-intent.ts', native)));
const tools = ['read', 'grep', 'symbol_search', 'module_report', 'read_symbol', 'web_run'];

test('lookup capability repair is version/hash pinned, idempotent and rejects unknown source', () => {
  const pkg = manifest.packages.find(item => item.name === 'pi-subagents');
  assert.equal(pkg.version, '0.56.0');
  const patches = pkg.patches.filter(item => item.file === 'src/runs/shared/completion-guard.ts');
  const patch = patches.at(-1);
  const source = fs.readFileSync(new URL(patch.file, native), 'utf8');
  assert.equal(digest(source), patch.afterHash);
  assert.equal(patchedText(source, patch), source);
  let before = source;
  for (const step of [...patches].reverse()) {
    for (const edit of [...step.edits].reverse()) before = before.replace(edit.after, edit.before);
    assert.equal(digest(before), step.beforeHash);
  }
  assert.equal(patches.reduce((text, step) => patchedText(text, step), before), source);
  assert.throws(() => patchedText(source + '\n// unknown source\n', patch), /Unrecognized source/);
});

test('native lookup tools use runtime artifact persistence and explicit read-only task intent', () => {
  assert.equal(guard.hasMutationToolCapability(tools), false);
  const task = 'Do not modify any files. Return findings only. Inspect implementation of getBranch; cite primary source and uncertainty.';
  const injected = output.injectSingleOutputInstruction(task, '/tmp/lookup-output.md', { tools });
  assert.match(injected, /Return the complete artifact in your final response/);
  assert.match(injected, /The runtime will persist it/);
  assert.doesNotMatch(injected, /Write your findings/);
  assert.equal(intent.classifyTaskMutationIntent('lookup', injected).kind, 'read-only');
  assert.deepEqual(guard.evaluateCompletionMutationGuard({ agent: 'lookup', task: injected, tools, messages: [] }), {
    expectedMutation: false, attemptedMutation: false, triggered: false, blocked: false,
  });
});
test('lookup extension inventory cannot override its explicit read-only allowlist', () => {
  const configuredExtensions = ['extensions/runtime-reliability/index.ts', 'npm/node_modules/@narumitw/pi-accounts/dist/index.ts', 'npm/node_modules/pi-lens/dist/index.js', 'npm/node_modules/@howaboua/pi-codex-web-run/index.ts'].map(path => fileURLToPath(new URL(`../../${path}`, import.meta.url)));
  const launch = { agent: 'lookup', tools, requestedTools: tools, configuredExtensions, acceptanceRole: 'read-only' };
  assert.match(guard.validateImplementationToolContract({ ...launch, task: 'Implement a fix in counter.mjs.' }), /no mutation-capable tools/);
  assert.equal(guard.validateImplementationToolContract({ ...launch, task: 'Do not modify any files. Return findings only.' }), undefined);
  for (const capability of [{ tools: undefined }, { tools: [...tools, 'unknown_tool'] }, { mcpDirectTools: ['unknown-mcp'] }]) {
    assert.equal(guard.validateImplementationToolContract({ ...launch, ...capability, task: 'Implement a fix in counter.mjs.' }), undefined);
  }
});


test('unknown, mixed-effect, shell and MCP capabilities retain implementation guards', () => {
  for (const tool of ['write', 'bash', 'lsp_navigation', 'unknown_tool', 'web_run_write']) {
    assert.equal(guard.hasMutationToolCapability([...tools, tool]), true, tool);
  }
  assert.equal(guard.hasMutationToolCapability(undefined), true);
  assert.equal(guard.hasMutationToolCapability(tools, ['unknown-mcp']), true);
  assert.equal(guard.evaluateCompletionMutationGuard({ agent: 'worker', task: 'Implement a fix in counter.mjs.', tools: ['write'], messages: [] }).triggered, true);
  assert.match(guard.validateImplementationToolContract({ agent: 'worker', task: 'Implement a fix in counter.mjs.', tools, acceptanceRole: 'writer' }), /no mutation-capable tools/);
});
