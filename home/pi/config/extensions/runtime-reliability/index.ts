import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import fs from 'node:fs';
import { Type } from 'typebox';
import { registerContextBridge } from './context-bridge.mjs';
import { registerToolSafety } from './tool-safety.mjs';
import { applyRepairs } from './patcher.mjs';

// The Nix launcher runs this preflight before Pi loads any extension. Keeping
// this package first provides an additional startup check for other launchers.
const health = applyRepairs();
const config = JSON.parse(fs.readFileSync(new URL('./config.json', import.meta.url), 'utf8'));

export default function runtimeReliability(pi: ExtensionAPI) {
  if (config.contextOwner === 'pi-native') registerContextBridge(pi);
  if (config.toolSafety) registerToolSafety(pi);
  pi.registerTool({
    name: 'runtime_health',
    label: 'Runtime health',
    description: 'Check pinned runtime repairs or idempotently restore the exact reviewed repairs. Unknown versions or source changes are rejected, never overwritten.',
    parameters: Type.Object({ action: Type.Optional(Type.Union([Type.Literal('check'), Type.Literal('repair')])) }),
    execute: async (_callId, params) => {
      const report = applyRepairs({ check: params.action !== 'repair' });
      return { content: [{ type: 'text', text: JSON.stringify({ ...report, contextOwner: config.contextOwner, toolSafety: config.toolSafety }) }], details: report };
    },
  });
  pi.registerCommand('runtime-doctor', {
    description: 'Verify version-checked runtime compatibility repairs',
    handler: async (_args, ctx) => {
      const report = applyRepairs({ check: true });
      ctx.ui.notify(JSON.stringify(report), 'info');
    },
  });
  pi.on('session_start', (_event, ctx) => {
    if (health.repaired) ctx.ui.notify(`Applied ${health.repaired} verified compatibility repairs`, 'info');
  });
}
