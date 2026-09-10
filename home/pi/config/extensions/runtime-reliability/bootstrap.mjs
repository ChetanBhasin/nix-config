import { applyRepairs } from './patcher.mjs';

const installed = new WeakSet();
const resolvers = new WeakSet();

// Called by the Nix preload for BOTH the bundled CLI and source SDK loaders.
// Pi resolves/installs packages before importing their extensions. Its pre-trust
// pass also imports global/CLI extensions, so a final-reload-only hook is too late.
export function installBootstrapRepairs(ResourceLoader) {
  const prototype = ResourceLoader?.prototype;
  if (!prototype || typeof prototype.loadCurrentExtensionSet !== 'function' ||
      typeof prototype.loadFinalExtensionSet !== 'function') {
    throw new Error('Runtime repairs: incompatible Pi resource loader');
  }
  if (installed.has(prototype)) return;
  const current = prototype.loadCurrentExtensionSet;
  const final = prototype.loadFinalExtensionSet;

  prototype.loadCurrentExtensionSet = function (...args) {
    const manager = this.packageManager;
    if (!manager || typeof manager.resolveExtensionSources !== 'function' || typeof this.agentDir !== 'string') {
      throw new Error('Runtime repairs: incompatible Pi package resolver');
    }
    if (!resolvers.has(manager)) {
      const resolve = manager.resolveExtensionSources;
      const agentDir = this.agentDir;
      manager.resolveExtensionSources = async function (...sources) {
        const result = await resolve.apply(this, sources);
        // Do not defer here: the normal package resolver has now had its chance
        // to install configured dependencies. Abort before ANY extension import
        // on absent/incomplete packages, unknown versions, or unknown source.
        applyRepairs({ agentDir });
        return result;
      };
      resolvers.add(manager);
    }
    return current.apply(this, args);
  };
  prototype.loadFinalExtensionSet = function (...args) {
    // Covers reload without a pre-trust pass, and verifies fresh installs even
    // when the earlier trust pass has already loaded a cached extension set.
    if (typeof this.agentDir !== 'string') throw new Error('Runtime repairs: missing Pi agent directory');
    applyRepairs({ agentDir: this.agentDir });
    return final.apply(this, args);
  };
  installed.add(prototype);
}
