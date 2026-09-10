import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { boundToolOutput, registerToolSafety } from './tool-safety.mjs';

const temporary = () => fs.mkdtempSync(path.join(os.tmpdir(), 'pi-tool-safety-'));
const text = value => ({ type: 'text', text: value });

test('large multiline output is bounded, losslessly archived and idempotent', () => {
  const directory = temporary();
  try {
    const original = { toolName: 'module_report', toolCallId: 'large', content: [text(('FULL_SENTINEL\n' + 'x'.repeat(300) + '\n').repeat(1000))], details: { preserved: true } };
    const bounded = boundToolOutput(original, { directory });
    assert.ok(bounded.content[0].text.length <= 64000);
    assert.equal(bounded.details.preserved, true);
    const archive = bounded.details.runtimeReliabilityArchive;
    assert.deepEqual(JSON.parse(fs.readFileSync(archive.archive, 'utf8')).content, original.content);
    assert.equal(fs.statSync(archive.archive).mode & 0o777, 0o600);
    assert.equal(boundToolOutput({ ...original, ...bounded }, { directory }), null);
    assert.ok(fs.readFileSync(archive.readable, 'utf8').includes('FULL_SENTINEL'));
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('a giant single line remains recoverable through bounded archive pages', () => {
  const directory = temporary();
  try {
    const original = { toolName: 'read', toolCallId: 'one-line', content: [text('α'.repeat(400000) + 'FINAL_SENTINEL')] };
    const bounded = boundToolOutput(original, { directory });
    assert.ok(bounded.content[0].text.length <= 64000);
    const readable = fs.readFileSync(bounded.details.runtimeReliabilityArchive.readable, 'utf8');
    assert.ok(readable.split('\n').every(line => line.length <= 4096));
    assert.ok(readable.endsWith('FINAL_SENTINEL'));
    assert.equal(boundToolOutput({ ...original, ...bounded }, { directory }), null);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('images and short output are not suppressed', () => {
  const directory = temporary();
  try {
    const image = { type: 'image', data: 'test-image', mimeType: 'image/png' };
    assert.equal(boundToolOutput({ content: [text('short'), image] }, { directory }), null);
    const bounded = boundToolOutput({ toolName: 'browser', content: [text('x'.repeat(200000)), image] }, { directory });
    assert.equal(bounded.content[1], image);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

function harness(agentDir) {
  const handlers = new Map();
  let clock = 0;
  registerToolSafety({ on: (event, handler) => handlers.set(event, handler) }, { agentDir, now: () => clock });
  const call = (id, input = { agent: 'researcher', task: 'read only' }, toolName = 'subagent') => handlers.get('tool_call')({ toolName, toolCallId: id, input });
  const fail = id => handlers.get('tool_result')({ toolName: 'subagent', toolCallId: id, isError: true, content: [text('Unknown options: --no-tests')] });
  return { handlers, call, fail, advance: () => { clock += 60001; } };
}

test('identical deterministic failures trip a temporary circuit, not a disabled role', () => {
  const directory = temporary();
  try {
    const h = harness(directory);
    h.call('1'); h.fail('1'); h.call('2'); h.fail('2');
    assert.equal(h.call('3').block, true);
    assert.equal(h.call('4', { task: 'new diagnostic evidence', agent: 'researcher' }), undefined);
    h.advance();
    assert.equal(h.call('5'), undefined);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('successful repair and new sessions reset deterministic retry guards', () => {
  const directory = temporary();
  try {
    const h = harness(directory);
    for (const id of ['1', '2']) { h.call(id); h.fail(id); }
    assert.equal(h.call('blocked').block, true);
    h.call('repair', { path: 'configuration' }, 'replace');
    h.handlers.get('tool_result')({ toolName: 'replace', toolCallId: 'repair', content: [text('repaired')] });
    assert.equal(h.call('allowed'), undefined);
    for (const id of ['3', '4']) { h.call(id); h.fail(id); }
    h.handlers.get('session_start')();
    assert.equal(h.call('new-session'), undefined);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('source text mentioning errors and transient provider errors are not circuit failures', () => {
  const directory = temporary();
  try {
    const h = harness(directory);
    for (const id of ['1', '2', '3']) {
      assert.equal(h.call(id), undefined);
      h.handlers.get('tool_result')({ toolName: 'subagent', toolCallId: id, content: [text('Source says Unknown options: --no-tests')] });
    }
    for (const id of ['4', '5', '6']) {
      assert.equal(h.call(id), undefined);
      h.handlers.get('tool_result')({ toolName: 'subagent', toolCallId: id, isError: true, content: [text('HTTP 503 retryable')] });
    }
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('legacy tool results are bounded in both context and native compaction without rewriting the session', () => {
  const directory = temporary();
  try {
    const h = harness(directory);
    const original = { role: 'toolResult', toolName: 'read', toolCallId: 'old', content: [text('x'.repeat(500000))], isError: false };
    const context = h.handlers.get('context')({ messages: [original] });
    assert.ok(context.messages[0].content[0].text.length <= 64000);
    assert.equal(original.content[0].text.length, 500000);
    const preparation = { messagesToSummarize: [original], turnPrefixMessages: [original] };
    h.handlers.get('session_before_compact')({ preparation });
    for (const key of ['messagesToSummarize', 'turnPrefixMessages']) assert.ok(preparation[key][0].content[0].text.length <= 64000);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
