import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { agentDirectory } from './patcher.mjs';
const { cbConvertLegacyMessages: convertMessages } = await import(pathToFileURL(path.join(agentDirectory(), 'npm/node_modules/@cortexkit/pi-magic-context/dist/index-kamc8t8p.js')).href);
import { buildLegacyHistory, isLegacySummary, loadHistoryCatalog, reduceHistory, registerContextBridge } from './context-bridge.mjs';

const temporary = () => fs.mkdtempSync(path.join(os.tmpdir(), 'pi-context-bridge-'));
const message = (id, text, role = 'user') => ({ type: 'message', id, message: { role, content: [{ type: 'text', text }], timestamp: 1 } });
const marker = () => ({ type: 'compaction', id: 'marker', firstKeptEntryId: 'm7', summary: 'Magic Context compacted 2 segments: old titles' });
const branch = () => [...Array.from({ length: 7 }, (_, index) => message(`m${index + 1}`, `RAW_SENTINEL_${index + 1}`, index % 2 ? 'assistant' : 'user')), marker()];
const row = (start, end, text, session = 'parent') => ({ session_id: session, start_message_id: `m${start}`, end_message_id: `m${end}`, title: text, p1: text, content: text });
const catalog = () => ({ source: 'test', rows: [row(1, 2, 'BEFORE_GAP'), row(5, 6, 'AFTER_GAP')], facts: [{ session_id: 'parent', category: 'private', content: 'FOREIGN_AFTER_FORK' }, { session_id: 'child', category: 'decision', content: 'OWN_FACT' }] });
const build = (overrides = {}) => buildLegacyHistory({ sessionId: 'child', entries: branch(), catalog: catalog(), convertMessages, archiveFile: '/private/archive.json', ...overrides });

function database(file) {
  const db = new DatabaseSync(file);
  db.exec('CREATE TABLE compartments (session_id TEXT, sequence INTEGER, start_message_id TEXT, end_message_id TEXT, title TEXT, p1 TEXT, content TEXT); CREATE TABLE session_facts (id INTEGER, session_id TEXT, category TEXT, content TEXT)');
  db.prepare('INSERT INTO compartments VALUES (?,?,?,?,?,?,?)').run('parent', 1, 'm1', 'm2', 'title', 'BEFORE_GAP', 'BEFORE_GAP');
  return db;
}

function harness(directory, overrides = {}) {
  const handlers = new Map();
  const pi = { on: (name, handler) => handlers.set(name, handler), registerCommand() {}, getThinkingLevel: () => 'max' };
  registerContextBridge(pi, { agentDir: directory, database: path.join(directory, 'missing.db'), convertMessages, ...overrides });
  const entries = branch();
  const ctx = { sessionManager: { getBranch: () => entries, getSessionId: () => 'child' }, model: { provider: 'test', id: 'test', contextWindow: 1000000 }, ui: { notify() {} } };
  return { handlers, entries, ctx };
}

test('recognizes all legacy marker shapes but not native summaries', () => {
  for (const value of ['Magic Context compacted prior history.', 'Magic Context compacted: one', 'Magic Context compacted messages 1-7.', 'Magic Context compacted 6 segments: titles']) assert.equal(isLegacySummary(value), true);
  assert.equal(isLegacySummary('Native substantive summary'), false);
  assert.equal(build({ entries: [message('a', 'live')] }), null);
});

test('restores facts before, inside and after gaps using raw history', () => {
  const result = build();
  assert.equal(result.selected, 2);
  assert.deepEqual(result.gaps, [3, 4]);
  for (const sentinel of ['BEFORE_GAP', 'RAW_SENTINEL_3', 'RAW_SENTINEL_4', 'AFTER_GAP', 'OWN_FACT']) assert.ok(result.text.includes(sentinel));
  assert.ok(!result.text.includes('RAW_SENTINEL_7'));
  assert.ok(!result.text.includes('FOREIGN_AFTER_FORK'));
});

test('new-ID import binds by raw entry IDs, not numerical coverage or session ID', () => {
  const source = catalog();
  // Legacy numeric ordinals deliberately conflict with the stable raw entry IDs.
  Object.assign(source.rows[0], { start_message: 8888, end_message: 9999 });
  const result = build({ sessionId: 'brand-new-import', catalog: source });
  assert.equal(result.selected, 2);
  assert.ok(result.text.includes('BEFORE_GAP'));
  assert.equal(result.facts.length, 0);
});

test('ignores foreign and boundary-crossing rows; own summary wins duplicate endpoints', () => {
  const source = catalog();
  source.rows.push(row(1, 2, 'OWN_BOUND_SUMMARY', 'child'), row(6, 7, 'AFTER_NATIVE_BOUNDARY'), row(99, 100, 'UNRELATED_SECRET'));
  const result = build({ catalog: source });
  assert.ok(result.text.includes('OWN_BOUND_SUMMARY'));
  for (const text of ['UNRELATED_SECRET', 'AFTER_NATIVE_BOUNDARY', 'BEFORE_GAP']) assert.ok(!result.text.includes(text));
});

test('synthetic tool boundaries match upstream raw converter without ordinal renumbering', () => {
  const entries = [message('u1', 'goal'), { type: 'message', id: 'tool1', message: { role: 'toolResult', toolCallId: 'call', toolName: 'read', content: [{ type: 'text', text: 'TOOL_GAP_SENTINEL' }] } }, message('a1', 'after tool', 'assistant'), message('keep', 'live'), { ...marker(), firstKeptEntryId: 'keep' }];
  const result = build({ entries, catalog: { source: 'test', rows: [], facts: [] } });
  assert.ok(result.historical.some(item => item.id === 'synth-user-tool1'));
  assert.ok(result.text.includes('TOOL_GAP_SENTINEL'));
  assert.deepEqual(result.gaps, [1, 2, 3]);
});

test('unavailable database uses a private consistent snapshot and otherwise retained raw history', () => {
  const directory = temporary();
  try {
    const dbFile = path.join(directory, 'context.db');
    const cache = path.join(directory, 'catalog.json');
    database(dbFile).close();
    assert.equal(loadHistoryCatalog(dbFile, cache).source, 'database');
    assert.equal(fs.statSync(cache).mode & 0o777, 0o600);
    const offline = loadHistoryCatalog(path.join(directory, 'missing.db'), cache);
    assert.equal(offline.source, 'snapshot');
    assert.equal(offline.rows[0].p1, 'BEFORE_GAP');
    const rawOnly = loadHistoryCatalog(path.join(directory, 'missing.db'), path.join(directory, 'missing-cache'));
    assert.equal(rawOnly.source, 'raw-history');
    assert.ok(build({ catalog: rawOnly }).text.includes('RAW_SENTINEL_1'));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('SQLite exclusive lock falls back to snapshot rather than blocking the window', () => {
  const directory = temporary();
  const file = path.join(directory, 'context.db');
  const db = database(file);
  try {
    const cache = path.join(directory, 'catalog.json');
    loadHistoryCatalog(file, cache);
    db.exec('BEGIN EXCLUSIVE');
    assert.equal(loadHistoryCatalog(file, cache).source, 'snapshot');
  } finally { db.close(); fs.rmSync(directory, { recursive: true, force: true }); }
});

test('context replacement is non-mutating and enriches native manual/threshold/overflow preparations', async () => {
  const directory = temporary();
  try {
    const { handlers, entries, ctx } = harness(directory);
    const original = [{ role: 'compactionSummary', summary: marker().summary, firstKeptEntryId: 'm7', tokensBefore: 123, timestamp: 1 }, { role: 'user', content: 'latest' }];
    const result = await handlers.get('context')({ messages: original }, ctx);
    assert.equal(original[0].summary, marker().summary);
    assert.ok(result.messages[0].summary.includes('RAW_SENTINEL_3'));
    assert.equal(result.messages[1], original[1]);
    for (const reason of ['manual', 'threshold', 'overflow']) {
      const preparation = { previousSummary: marker().summary, messagesToSummarize: [] };
      assert.equal(await handlers.get('session_before_compact')({ preparation, branchEntries: entries, reason }, ctx), undefined);
      assert.ok(preparation.previousSummary.includes('RAW_SENTINEL_3'));
      assert.match(preparation.messagesToSummarize[0].content, /Carry forward/);
      assert.ok(preparation.messagesToSummarize[0].content.length < 200);
    }
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('second native compaction and restart do not reintroduce a title-only marker', async () => {
  const directory = temporary();
  try {
    const first = harness(directory);
    const prep = { previousSummary: marker().summary, messagesToSummarize: [] };
    await first.handlers.get('session_before_compact')({ preparation: prep, branchEntries: first.entries }, first.ctx);
    const retained = 'Native summary retaining RAW_SENTINEL_3';
    const second = harness(directory);
    second.entries.push({ type: 'compaction', id: 'native', firstKeptEntryId: 'm7', summary: retained });
    const next = { previousSummary: retained, messagesToSummarize: [] };
    assert.equal(await second.handlers.get('session_before_compact')({ preparation: next, branchEntries: second.entries }, second.ctx), undefined);
    assert.equal(next.previousSummary, retained);
    assert.equal(next.messagesToSummarize.length, 1);
    assert.match(next.messagesToSummarize[0].content, /Carry forward/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('large-history consolidation resumes completed chunks after provider failure', async () => {
  const directory = temporary();
  try {
    const checkpointFile = path.join(directory, 'chunks.json');
    const text = 'A'.repeat(64000) + 'B'.repeat(64000) + 'C'.repeat(64000);
    let calls = 0;
    await assert.rejects(reduceHistory(text, { maxChars: 1000, checkpointFile, complete: async chunk => { calls += 1; if (chunk[0] === 'B') throw new Error('provider offline'); return `preserved ${chunk[0]}`; } }), /provider offline/);
    assert.equal(calls, 2);
    calls = 0;
    const result = await reduceHistory(text, { maxChars: 1000, checkpointFile, complete: async chunk => { calls += 1; return `preserved ${chunk[0]}`; } });
    assert.equal(calls, 2);
    for (const sentinel of ['preserved A', 'preserved B', 'preserved C']) assert.ok(result.includes(sentinel));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('invalid summaries and abort cannot silently trim retained history', async () => {
  const directory = temporary();
  try {
    const options = { maxChars: 10, checkpointFile: path.join(directory, 'chunks.json'), complete: async () => '' };
    await assert.rejects(reduceHistory('x'.repeat(100), options), /empty or non-shrinking/);
    const controller = new AbortController(); controller.abort();
    await assert.rejects(reduceHistory('x'.repeat(100), { ...options, signal: controller.signal }));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
