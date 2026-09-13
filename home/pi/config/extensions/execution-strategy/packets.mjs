import { check, digest, object, text, unique } from './workspace.mjs';

export const PACKET_GUIDE = `Return one fenced execution-packet JSON object (not a file path): {version:1, attempt:<given>, lane:<given>, role:<given>, conclusion:"...", action:"...", decisions:[], assumptions:[], changes:[], validation:[], evidence:[{id:"e1",link:"tool:<child tool call ID> or artifact:<path>#<revision>",revision:"...",observation:"literal outcome"}], blockers:[], coverage:[{obligation:"...",snapshot:<given hash>,verdict:"pass|fail|partial",evidence:["e1"]}], findings:[{id:"...",obligation:"...",severity:"blocker|non-blocking",issue:"...",evidence:["e1"]}], resolutions:[{finding:<global finding ID from brief>,evidence:["e1"],explanation:"..."}]}. Keep arrays explicit. Only report independently examined evidence. No edits for reviewers. Do not call subagent or execution_strategy planning. Native run identity is supplied by runtime, never self-attested. Missing evidence/coverage is a gap.`;

/** Parse only the final output supplied by a correlated native result. No model-facing packet/path setter exists. */
export function parsePacket(output, attempt, lane) {
  check(typeof output === 'string' && Buffer.byteLength(output) <= 128 * 1024, 'missing/oversized native child output');
  const matches = [...output.matchAll(/```execution-packet\s*\n([\s\S]*?)\n```/g)];
  check(matches.length === 1, 'exactly one native execution-packet fence required');
  const packet = JSON.parse(matches[0][1]);
  check(object(packet) && packet.version === 1 && packet.attempt === attempt.id && packet.lane === lane.id && packet.role === lane.role, 'packet identity mismatch');
  text(packet.conclusion, 'conclusion'); text(packet.action, 'action');
  for (const field of ['decisions', 'assumptions', 'changes', 'validation', 'blockers']) unique(packet[field], field).forEach(s => text(s, field));
  for (const field of ['evidence', 'coverage', 'findings', 'resolutions']) check(Array.isArray(packet[field]), `packet ${field} array required`);
  unique(packet.evidence.map(e => e.id), 'evidence IDs');
  for (const e of packet.evidence) {
    text(e.id, 'evidence ID'); text(e.link, 'evidence link'); text(e.revision, 'evidence revision'); text(e.observation, 'evidence observation');
    check(/^(tool:|artifact:|https?:)/.test(e.link), 'evidence link must be a tool/artifact/URL locator');
  }
  function refs(values) {
    check(unique(values, 'evidence references').length > 0, 'evidence references required');
    values.forEach(key => check(packet.evidence.some(e => e.id === key), `missing evidence ${key}`));
  }
  unique(packet.coverage.map(c => c.obligation), 'coverage IDs');
  for (const coverage of packet.coverage) {
    check(lane.role === 'reviewer', 'only reviewer packets may assert coverage');
    check(lane.obligations.includes(coverage.obligation), 'coverage outside assigned obligations');
    check(coverage.snapshot === attempt.snapshots[coverage.obligation], 'review snapshot mismatch');
    check(['pass', 'fail', 'partial'].includes(coverage.verdict), 'invalid coverage verdict'); refs(coverage.evidence);
  }
  unique(packet.findings.map(f => f.id), 'finding IDs');
  for (const finding of packet.findings) {
    text(finding.id, 'finding ID'); text(finding.issue, 'finding issue');
    check(lane.obligations.includes(finding.obligation), 'finding outside assigned obligations');
    check(['blocker', 'non-blocking'].includes(finding.severity), 'invalid finding severity'); refs(finding.evidence);
  }
  for (const resolution of packet.resolutions) { text(resolution.finding, 'finding reference'); text(resolution.explanation, 'resolution'); refs(resolution.evidence); }
  check(packet.evidence.length > 0, 'packet requires evidence');
  return { packet, hash: digest(packet), outputHash: digest(output) };
}
export function observedUsage(value) {
  if (!object(value)) return { value: null, provenance: 'unknown: native result omitted usage' };
  const fields = ['input', 'output', 'cacheRead', 'cacheWrite', 'totalTokens', 'turns'];
  const normalized = Object.fromEntries(fields.map(k => [k, Number.isFinite(value[k]) && value[k] >= 0 ? value[k] : null]));
  const cost = typeof value.cost === 'number' ? value.cost : value.cost?.total;
  normalized.cost = Number.isFinite(cost) && cost >= 0 ? cost : null;
  return { value: normalized, provenance: 'native returned usage; null fields unknown' };
}
