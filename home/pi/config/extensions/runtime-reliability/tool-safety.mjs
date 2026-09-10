import path from 'node:path';
import { createHash } from 'node:crypto';
import { agentDirectory } from './patcher.mjs';
import { privateWrite } from './context-bridge.mjs';

const digest = value => createHash('sha256').update(value).digest('hex');
const textOf = content => content.filter(part => part.type === 'text').map(part => part.text).join('\n');
const wrapLines = text => text.split('\n').flatMap(line => line.match(/.{1,4096}/gu) || ['']).join('\n');
const noticeFor = (archive, readable) => `[Output bounded for context safety, not deleted. Full exact result: ${archive}\nPaged text: ${readable}. Use read with offset/limit for remaining details. Do not infer omitted content.]`;

/** Keep complete private artifacts; bound model-visible text, including giant single lines. */
export function boundToolOutput(event, { directory, maxChars = 64000, maxLine = 4096 }) {
  const content = event.content || [];
  const text = textOf(content);
  if (text.length <= maxChars && text.split('\n').every(line => line.length <= maxLine)) {
    const previous = event.details?.runtimeReliabilityArchive;
    if (!previous) return null;
    const notice = noticeFor(previous.archive, previous.readable);
    const oldSuffix = '\n\n' + notice;
    if (!text.endsWith(oldSuffix)) return null;
    // Upgrade already-bounded persisted results before native serialization
    // discards everything after its first 2,000 tool-result characters.
    return { content: [{ type: 'text', text: notice + '\n\n' + text.slice(0, -oldSuffix.length) }, ...content.filter(part => part.type !== 'text')], details: event.details };
  }
  const id = digest(`${event.toolName}:${event.toolCallId}:${JSON.stringify(content)}`);
  const archive = path.join(directory, id + '.json');
  const readable = path.join(directory, id + '.txt');
  privateWrite(archive, JSON.stringify({ toolName: event.toolName, toolCallId: event.toolCallId, content }));
  privateWrite(readable, 'Tool output archive. Long lines are wrapped for paged reading; the JSON sibling preserves exact content.\n\n' + wrapLines(text));
  const suffix = ' … [long line continues in archive]';
  const notice = noticeFor(archive, readable) + '\n\n';
  const available = maxChars - notice.length;
  if (available < 256 || maxLine <= suffix.length) throw new RangeError('Output budget is too small for an archive notice');
  const lines = text.split('\n').map(line => line.length <= maxLine ? line : line.slice(0, maxLine - suffix.length) + suffix);
  let preview = lines.join('\n');
  if (preview.length > available) {
    const separator = '\n… [middle in archive] …\n';
    const budget = available - separator.length;
    const head = Math.floor(budget * 0.8);
    preview = preview.slice(0, head) + separator + preview.slice(-(budget - head));
  }
  return {
    content: [{ type: 'text', text: notice + preview }, ...content.filter(part => part.type !== 'text')],
    details: { ...event.details, runtimeReliabilityArchive: { archive, readable, originalCharacters: text.length } },
  };
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}

const deterministicFailure = event => Boolean(event.isError || event.details?.success === false || event.details?.ok === false) && /Unknown options?:|unrecognized (?:option|argument)|grant exceeds session cap|maximum (?:spawn|delegation)|ENOENT|is not a function|ERR_MODULE_NOT_FOUND|Cannot find (?:module|package)/i.test(textOf(event.content || []));

export function registerToolSafety(pi, { agentDir = agentDirectory(), now = Date.now, maxChars = 64000 } = {}) {
  const directory = path.join(agentDir, 'reliability/tool-results');
  const failures = new Map();
  const inputs = new Map();
  const keyOf = event => digest(`${event.toolName}:${JSON.stringify(canonical(event.input || {}))}`);
  const bounded = event => boundToolOutput(event, { directory, maxChars });
  pi.on('session_start', () => { failures.clear(); inputs.clear(); });
  pi.on('tool_call', event => {
    const key = keyOf(event);
    inputs.set(event.toolCallId, key);
    if (inputs.size > 256) inputs.delete(inputs.keys().next().value);
    const failure = failures.get(key);
    if (failure?.count >= 2 && now() - failure.at < 60000) {
      return { block: true, reason: `The identical request has failed twice with a deterministic runtime error. Repair or gather new evidence before retrying; this is not an authorization to disable the tool. Run /runtime-doctor or inspect the exact failing dependency/configuration. The guard resets after a successful repair tool call or one minute. Last error: ${failure.message}` };
    }
  });
  pi.on('tool_result', event => {
    const key = inputs.get(event.toolCallId);
    inputs.delete(event.toolCallId);
    if (key && deterministicFailure(event)) {
      const previous = failures.get(key);
      failures.set(key, { count: (previous?.count || 0) + 1, at: now(), message: textOf(event.content).slice(0, 1200) });
      if (failures.size > 256) failures.delete(failures.keys().next().value);
    } else if (!event.isError && event.details?.success !== false && event.details?.ok !== false) {
      if (key) failures.delete(key);
      if (['bash', 'write', 'replace', 'insert', 'undo_last_change'].includes(event.toolName)) failures.clear();
    }
    return bounded(event) || undefined;
  });
  pi.on('context', event => {
    let changed = false;
    const messages = event.messages.map(message => {
      if (message.role !== 'toolResult') return message;
      const result = bounded(message);
      if (!result) return message;
      changed = true;
      return { ...message, ...result };
    });
    return changed ? { messages } : undefined;
  });
  pi.on('session_before_compact', event => {
    for (const key of ['messagesToSummarize', 'turnPrefixMessages']) {
      if (!Array.isArray(event.preparation[key])) continue;
      event.preparation[key] = event.preparation[key].map(message => {
        if (message.role !== 'toolResult') return message;
        const result = bounded(message);
        return result ? { ...message, ...result } : message;
      });
    }
  });
}
