import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';

const packageDir = process.env.PI_TEST_PACKAGE_DIR || fileURLToPath(new URL('../../npm/node_modules/@earendil-works/pi-coding-agent/', import.meta.url));

test('Auto Mode loads through Pi without npm-installed core packages beside the extension', async (t) => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-workflow-startup-'));
  const agentDir = path.join(temp, 'agent');
  const extensionDir = path.join(agentDir, 'extensions/auto-mode');
  fs.mkdirSync(extensionDir, { recursive: true });
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = agentDir;
  t.after(() => {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
  });
  for (const file of fs.readdirSync(new URL('.', import.meta.url))) {
    if (file.endsWith('.ts') || file === 'package.json') {
      fs.copyFileSync(new URL(file, import.meta.url), path.join(extensionDir, file));
    }
  }
  assert.equal(fs.existsSync(path.join(agentDir, 'npm')), false);
  for (const variant of ['dist/index.js', 'dist/bundle/index.js']) {
    const { DefaultResourceLoader, SettingsManager } = await import(pathToFileURL(path.join(packageDir, variant)).href);
    const loader = new DefaultResourceLoader({
      cwd: temp, agentDir, settingsManager: SettingsManager.inMemory({ packages: [] }),
      noExtensions: true, additionalExtensionPaths: [path.join(extensionDir, 'index.ts')],
      noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    });
    await loader.reload();
    const result = loader.getExtensions();
    assert.deepEqual(result.errors, [], variant);
    assert.equal(result.extensions.length, 1, variant);
    const extension = result.extensions[0];
    for (const command of ['auto', 'workflow']) assert.ok(extension.commands.has(command), command);
    for (const tool of ['workflow_contract', 'writer_lease']) assert.ok(extension.tools.has(tool), tool);
  }
});
