import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const agentDir = path.resolve(process.env.PI_TEST_AGENT_DIR ?? fileURLToPath(new URL('./config', import.meta.url)));
const packageDir = process.env.PI_TEST_PACKAGE_DIR ?? path.join(os.homedir(), '.pi/agent/npm/node_modules/@earendil-works/pi-coding-agent');
const { loadPromptTemplates, expandPromptTemplate } = await import(pathToFileURL(path.join(packageDir, 'dist/core/prompt-templates.js')).href);
const { loadSkillsFromDir, formatSkillsForPrompt } = await import(pathToFileURL(path.join(packageDir, 'dist/core/skills.js')).href);
const promptNames = ['mission', 'implement-milestone', 'experiment', 'acceptance', 'handoff', 'artifact-audit'];
const skillNames = ['jj-workflow', 'kraken-experiment-contract', 'tmux-safe-acceptance', 'browser-evidence', 'cross-repo-handoff', 'nix-host-validation'];
const templates = loadPromptTemplates({ cwd: agentDir, agentDir, includeDefaults: false, promptPaths: [path.join(agentDir, 'prompts')] });
const result = loadSkillsFromDir({ dir: path.join(agentDir, 'skills'), source: 'user' });

for (const name of promptNames) {
  test(`Pi discovers /${name} and expands default and explicit arguments`, () => {
    const matches = templates.filter(template => template.name === name);
    assert.equal(matches.length, 1, `Expected exactly one ${name} template`);
    assert.ok(matches[0].description.length > 10);
    const expanded = expandPromptTemplate(`/${name} "repair the local CLI"`, templates);
    assert.ok(expanded.includes('repair the local CLI'));
    assert.doesNotMatch(expanded, /\$\{(?:@|ARGUMENTS)/);
    const defaults = expandPromptTemplate(`/${name}`, templates);
    assert.notEqual(defaults, `/${name}`);
    assert.doesNotMatch(defaults, /\$\{(?:@|ARGUMENTS)/);
    assert.ok(defaults.length > 500);
  });
}

for (const name of skillNames) {
  test(`Pi validates ${name}, exposes its description and resolves local references`, () => {
    const matches = result.skills.filter(skill => skill.name === name);
    assert.equal(matches.length, 1, `Expected exactly one ${name} skill`);
    const skill = matches[0];
    assert.deepEqual(result.diagnostics.filter(diagnostic => diagnostic.path === skill.filePath), []);
    assert.equal(skill.disableModelInvocation, false);
    const body = fs.readFileSync(skill.filePath, 'utf8');
    const links = [...body.matchAll(/\]\(([^)]+\.md)\)/g)];
    assert.ok(links.length > 0, 'The concrete workflow protocol must be reachable');
    for (const [, relative] of links) {
      assert.ok(fs.statSync(path.resolve(skill.baseDir, relative)).isFile(), relative);
    }
    const summary = formatSkillsForPrompt([skill]);
    assert.ok(summary.includes(skill.name));
    const description = skill.description.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
    assert.ok(summary.includes(`<description>${description}</description>`));
    assert.ok(summary.includes(skill.filePath));
    assert.ok(!summary.includes(body.split('\n').find(line => line.startsWith('# '))), 'Full instructions must remain progressively disclosed');
  });
}
