import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { digest, patchedText } from './patcher.mjs';

const native = new URL('../../npm/node_modules/pi-subagents/', import.meta.url);
const manifest = JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));
const { createJiti } = await import(new URL('../../npm/node_modules/jiti/lib/jiti.mjs', import.meta.url));
const jiti = createJiti(import.meta.url, { fsCache: false });
const { createToolResultFinalizer, finalizeToolResult } = await jiti.import(fileURLToPath(new URL('src/extension/tool-result.ts', native)));

// Unit hook callbacks exercise correlation; acceptance.mjs receipts exercises real Pi RPC.
function boundary() {
  const hooks = new Map();
  const finalize = createToolResultFinalizer({ on(name, handler) { hooks.set(name, handler); } });
  return { finalize, result: event => hooks.get('tool_result')(event), shutdown: () => hooks.get('session_shutdown')() };
}
const failed = id => ({ isError: true, content: [{ type: 'text', text: 'Native child failed' }], details: { runId: id, results: [{ runId: `${id}-child`, agent: 'worker', exitCode: 1 }] } });

test('logical error receipt repair is pinned and reproducible through every earlier repair', () => {
  const pkg = manifest.packages.find(p => p.name === 'pi-subagents');
  assert.equal(pkg.version, '0.56.0');
  for (const file of ['tool-result', 'index', 'fanout-child']) {
    const patches = pkg.patches.filter(p => p.file === `src/extension/${file}.ts`);
    const last = patches.at(-1), source = fs.readFileSync(new URL(last.file, native), 'utf8');
    assert.equal(digest(source), last.afterHash);
    assert.equal(patchedText(source, last), source);
    let before = source;
    for (const patch of [...patches].reverse()) {
      for (const edit of [...patch.edits].reverse()) before = before.replace(edit.after, edit.before);
      assert.equal(digest(before), patch.beforeHash, file);
    }
    assert.equal(patches.reduce((text, patch) => patchedText(text, patch), before), source);
    assert.throws(() => patchedText(source + '\n// unreviewed upgrade\n', last), /Unrecognized source/);
    if (file !== 'tool-result') {
      assert.match(source, /const finalizeToolResult = createToolResultFinalizer\(pi\)/);
      assert.match(source, /return finalizeToolResult\(await .*ctx\), id\);/);
    }
  }
});

test('native logical failures retain original details and canonical error status exactly once', () => {
  const api = boundary(), result = failed('root');
  assert.equal(api.finalize(result, 'call'), result);
  assert.equal(api.result({ toolName: 'read', toolCallId: 'call' }), undefined);
  assert.equal(api.result({ toolName: 'subagent', toolCallId: 'foreign', details: result.details }), undefined);
  assert.deepEqual(api.result({ toolName: 'subagent', toolCallId: 'call', details: {} }), { isError: true, details: result.details });
  assert.equal(api.result({ toolName: 'subagent', toolCallId: 'call' }), undefined);
  assert.equal(result.details.runId, 'root'); assert.equal(result.details.results[0].exitCode, 1);
});

test('bridge state is runtime-local, success clears stale IDs, shutdown drains markers, fallback still throws', () => {
  const a = boundary(), b = boundary(), result = failed('root');
  a.finalize(result, 'same');
  assert.equal(b.result({ toolName: 'subagent', toolCallId: 'same' }), undefined);
  const success = { content: [], details: { runId: 'successful' } };
  assert.equal(a.finalize(success, 'same'), success);
  assert.equal(a.result({ toolName: 'subagent', toolCallId: 'same' }), undefined);
  a.finalize(result, 'pending'); a.shutdown();
  assert.equal(a.result({ toolName: 'subagent', toolCallId: 'pending' }), undefined);
  assert.throws(() => a.finalize(result, ''), /Native child failed/);
  assert.throws(() => finalizeToolResult(result), /Native child failed/);
});
