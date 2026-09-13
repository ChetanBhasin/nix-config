#!/usr/bin/env node
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { seedFixture, protectedSnapshot, writeJson } from './tests/native/fixture.mjs';
import { profiles, delegation } from './tests/native/journeys.mjs';
import { review } from './tests/native/review.mjs';
import { receipts } from './tests/native/receipts.mjs';

const modes = {
  profiles: { run: profiles, line: 'PASS journey switch-profiles: actual Pi RPC profile selection and reload preserve the parent and change child strategy' },
  delegation: { run: delegation, line: 'PASS journey delegate-normal: real normal-mode delegation transfers owned work and respects dependency and writer barriers' },
  review: { run: review, line: 'PASS journey review-revisions: actual review interface invalidates affected evidence, retains unrelated coverage and rejects gaps' },
  receipts: { run: receipts, line: 'PASS journey failure-telemetry: real child success and failure receipts preserve identity, configuration, usage provenance and explicit gaps' },
};
const mode = modes[process.argv[2]];
if (!mode || process.argv.length !== 3) {
  console.error('Usage: node acceptance.mjs profiles|delegation|review|receipts');
  process.exitCode = 2;
} else {
  const before = protectedSnapshot();
  const fixture = seedFixture(process.argv[2]);
  const artifact = join(fixture.root, 'acceptance.json');
  const report = { mode: process.argv[2], status: 'running', fixtureRoot: fixture.root, startedAt: new Date().toISOString() };
  try {
    await mode.run(fixture, report);
    assert.deepEqual(protectedSnapshot(), before, 'Live source/profile/settings changed during acceptance');
    report.protectedFilesUnchanged = true;
    report.status = 'passed'; report.passLine = mode.line;
  } catch (error) {
    report.status = 'failed'; report.error = error.stack ?? String(error);
    report.protectedFilesUnchanged = JSON.stringify(protectedSnapshot()) === JSON.stringify(before);
    process.exitCode = 1;
  } finally {
    report.finishedAt = new Date().toISOString();
    writeJson(artifact, report);
    console.log(`JSON artifact: ${artifact}`);
  }
  if (report.status === 'passed') console.log(mode.line);
  else console.error(`Native ${process.argv[2]} acceptance failed: ${report.error}`);
}
