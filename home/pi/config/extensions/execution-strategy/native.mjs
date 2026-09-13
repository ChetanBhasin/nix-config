import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import { check, digest } from './workspace.mjs';
import { join } from 'node:path';

export function ownedStatus(attempt) {
  check(typeof attempt.asyncDir === 'string', 'native async locator unavailable');
  const path = join(attempt.asyncDir, 'status.json');
  check(lstatSync(path).isFile() && lstatSync(path).size <= 4 * 1024 * 1024, 'invalid native status file');
  const status = JSON.parse(readFileSync(path, 'utf8'));
  check(status.runId === attempt.runId && status.sessionId === attempt.parentSession, 'native status ownership mismatch');
  const steps = (status.steps ?? []).filter(s => s.workflowKey === attempt.lane);
  check(steps.length === 1 && steps[0].agent === attempt.agent && typeof steps[0].runId === 'string', 'native status child identity missing/ambiguous');
  return { status, step: steps[0], path };
}
export function ownedForeground(attempt) {
  check(typeof attempt.foregroundHistory === 'string' && typeof attempt.childRunId === 'string', 'native foreground locator unavailable');
  const path = attempt.foregroundHistory;
  check(lstatSync(path).isFile() && lstatSync(path).size <= 8 * 1024 * 1024, 'invalid native foreground history');
  const history = JSON.parse(readFileSync(path, 'utf8'));
  check(history.version === 1 && Array.isArray(history.runs), 'invalid native foreground history version');
  const runs = history.runs.filter(run => run.runId === attempt.childRunId && run.sessionId === attempt.parentSession);
  check(runs.length === 1 && runs[0].mode === 'single' && runs[0].children?.length === 1, 'native foreground ownership missing/ambiguous');
  const child = runs[0].children[0];
  check(child.index === 0 && child.agent === attempt.agent && typeof child.sessionFile === 'string'
    && (!attempt.actual?.sessionFile || child.sessionFile === attempt.actual.sessionFile)
    && (!attempt.actual?.launchContractDigest || child.launchContractDigest === attempt.actual.launchContractDigest), 'native foreground child identity mismatch');
  return { child: { ...child, runId: runs[0].runId }, path };
}
export function enrichNativeRow(row, attempt) {
  if (!attempt.asyncDir) return row;
  try {
    const { step, path } = ownedStatus(attempt);
    check(step.runId === row.runId, 'native returned/status child run mismatch');
    return { ...row, model: row.model ?? step.model, thinking: row.thinking ?? step.thinking, sessionFile: row.sessionFile ?? step.sessionFile, metadataProvenance: `verified owned status: ${path}` };
  } catch (error) { return { ...row, metadataGap: String(error) }; }
}

const contentText = content => typeof content === 'string' ? content : (content ?? []).filter(c => c.type === 'text').map(c => c.text).join('\n');
/** Follow the persisted leaf's ancestry, not abandoned sibling branches. */
export function activeMessages(entries) {
  const nodes = entries.slice(1);
  const byId = new Map();
  for (const entry of nodes) {
    check(typeof entry.id === 'string' && !byId.has(entry.id), 'missing/duplicate native entry ID');
    byId.set(entry.id, entry);
  }
  const branch = [], seen = new Set();
  let key = nodes.at(-1)?.id ?? null;
  while (key !== null) {
    check(typeof key === 'string' && byId.has(key) && !seen.has(key), 'invalid native branch ancestry');
    seen.add(key); const entry = byId.get(key); branch.push(entry); key = entry.parentId;
  }
  return branch.reverse().filter(e => e.type === 'message').map(e => e.message);
}

export function nativeMaterial(row, parentSession) {
  let messages = row.messages;
  let transcriptHash = null;
  if (!Array.isArray(messages) && (row.sessionFile || row.sessionPath)) {
    const path = realpathSync(row.sessionFile ?? row.sessionPath);
    check(path.endsWith('.jsonl') && lstatSync(path).size <= 16 * 1024 * 1024, 'invalid/oversized native child transcript');
    const raw = readFileSync(path, 'utf8');
    const entries = raw.trim().split('\n').map(line => JSON.parse(line));
    const header = entries[0];
    check(header.type === 'session' && typeof header.id === 'string' && header.id !== parentSession, 'native child session identity invalid');
    messages = activeMessages(entries);
    transcriptHash = digest(raw);
  }
  const final = messages?.findLast(m => m.role === 'assistant' && m.stopReason !== 'toolUse');
  const inline = row.finalOutput ?? row.output;
  const reference = row.outputMode === 'file-only' || row.outputReference || (typeof inline === 'string' && inline.startsWith('Output saved to: '));
  let output = reference ? (final ? contentText(final.content) : undefined) : inline ?? (final ? contentText(final.content) : undefined);
  if (reference && !output?.includes('```execution-packet')) {
    const path = row.savedOutputPath ?? row.artifactPaths?.outputPath;
    check(typeof path === 'string', 'native file-only packet artifact unavailable');
    check(lstatSync(path).isFile() && lstatSync(path).size <= 128 * 1024, 'invalid native file-only packet artifact');
    output = readFileSync(path, 'utf8');
  }
  return { output, messages: messages ?? [], transcriptHash, provenance: transcriptHash ? 'native-owned child session locator' : Array.isArray(row.messages) ? 'native returned child messages' : 'native returned output only (tool evidence unavailable)' };
}
export function bindPacketEvidence(packet, material) {
  const verified = new Map();
  for (const evidence of packet.evidence) {
    const toolId = evidence.link.startsWith('tool:') ? evidence.link.slice(5) : null;
    const result = material.messages.find(m => m.role === 'toolResult' && m.toolCallId === toolId && m.isError === false);
    const valid = Boolean(result && contentText(result.content).includes(evidence.observation));
    verified.set(evidence.id, valid);
    evidence.proof = valid ? { toolCallId: toolId, resultHash: digest(result.content), transcriptHash: material.transcriptHash, provenance: material.provenance } : null;
  }
  for (const item of [...packet.coverage, ...packet.findings, ...packet.resolutions]) {
    check(item.evidence.every(key => verified.get(key)), 'independent review evidence must cite successful native child tool results with literal observations; transcript/links missing');
  }
}
