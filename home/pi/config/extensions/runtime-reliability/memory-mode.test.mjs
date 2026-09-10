import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { agentDirectory } from './patcher.mjs';

const mc = await import(pathToFileURL(path.join(agentDirectory(), 'npm/node_modules/@cortexkit/pi-magic-context/dist/index-kamc8t8p.js')).href);
const text = result => result.content.filter(part => part.type === 'text').map(part => part.text).join('\n');

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-memory-mode-'));
  const db = mc.openDatabase(path.join(directory, 'context.db'));
  const tools = new Map();
  mc.registerMagicContextTools({ registerTool: tool => tools.set(tool.name, tool) }, {
    db,
    compactionOff: true,
    memoryEnabled: true,
    embeddingEnabled: false,
    gitCommitsEnabled: false,
    todowriteEnabled: false,
    resolveProjectIdentity: () => directory,
    promptSurfaceRuntime: { resolveRegistration: () => ({ descriptionFor: (_name, description) => description }) },
  });
  const entry = (id, value) => ({ type: 'message', id, message: { role: 'user', content: value, timestamp: 1 } });
  const entries = [entry('before', 'HIDDEN_NATIVE_SENTINEL preserve this decision'), entry('after', 'VISIBLE_NATIVE_SENTINEL current task'), { type: 'compaction', id: 'native', firstKeptEntryId: 'after', summary: 'A substantive native summary' }];
  const ctx = { cwd: directory, sessionManager: { getSessionId: () => 'native-test', getBranch: () => entries } };
  return { directory, db, tools, entries, ctx, run: (name, params) => tools.get(name).execute('test', params, new AbortController().signal, undefined, ctx), close: () => { db.close(); fs.rmSync(directory, { recursive: true, force: true }); } };
}

test('native mode keeps memory, notes, search and raw expansion without a second compactor', async () => {
  const f = fixture();
  try {
    for (const name of ['ctx_memory', 'ctx_note', 'ctx_search', 'ctx_expand']) assert.ok(f.tools.has(name), name);
    assert.equal(f.tools.has('ctx_reduce'), false);
    const expanded = await f.run('ctx_expand', { start: 1, end: 1 });
    assert.match(text(expanded), /HIDDEN_NATIVE_SENTINEL/);
    const note = await f.run('ctx_note', { action: 'write', content: 'NATIVE_NOTE_SENTINEL retained durable reminder' });
    assert.notEqual(note.isError, true, text(note));
    assert.match(text(await f.run('ctx_note', { action: 'read' })), /NATIVE_NOTE_SENTINEL/);
    const memory = await f.run('ctx_memory', { action: 'write', category: 'ARCHITECTURE', content: 'NATIVE_MEMORY_SENTINEL a durable project fact' });
    assert.notEqual(memory.isError, true, text(memory));
    assert.match(text(await f.run('ctx_search', { query: 'NATIVE_MEMORY_SENTINEL', sources: ['memory'] })), /NATIVE_MEMORY_SENTINEL/);
  } finally { f.close(); }
});

test('native-only compactions are searchable without MC compartments or prior message indexing', async () => {
  const f = fixture();
  try {
    assert.match(text(await f.run('ctx_search', { query: 'HIDDEN_NATIVE_SENTINEL', sources: ['message'] })), /HIDDEN_NATIVE_SENTINEL preserve this decision/);
    const visible = text(await f.run('ctx_search', { query: 'VISIBLE_NATIVE_SENTINEL', sources: ['message'] }));
    assert.doesNotMatch(visible, /VISIBLE_NATIVE_SENTINEL current task/);
  } finally { f.close(); }
});

for (const query of ['branchscopeterm', 'BRANCH_SCOPE_SENTINEL']) {
  test(`native search excludes abandoned branches before result limiting: ${query}`, async () => {
    const f = fixture();
    try {
      for (let i = 0; i < 100; i++) {
        f.entries[0] = { type: 'message', id: `abandoned-${i}`, message: { role: 'user', content: `${query} abandoned fact ${query} ${query}`, timestamp: 1 } };
        await f.run('ctx_search', { query, sources: ['message'], limit: 1 });
      }
      f.entries[0] = { type: 'message', id: 'current', message: { role: 'user', content: `${query} current fact`, timestamp: 1 } };
      const result = text(await f.run('ctx_search', { query, sources: ['message'], limit: 1 }));
      assert.match(result, new RegExp(`${query} current fact`));
      assert.doesNotMatch(result, /abandoned fact/);
      assert.match(text(await f.run('ctx_expand', { message: 1 })), new RegExp(`${query} current fact`));
      // Returning to an earlier branch reuses its raw identity, not stale ordinals.
      f.entries[0] = { type: 'message', id: 'abandoned-0', message: { role: 'user', content: `${query} abandoned fact ${query} ${query}`, timestamp: 1 } };
      const earlier = text(await f.run('ctx_search', { query, sources: ['message'], limit: 1 }));
      assert.match(earlier, /abandoned fact/);
      assert.doesNotMatch(earlier, /current fact/);
    } finally { f.close(); }
  });
}
