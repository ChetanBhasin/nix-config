import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const digest = text => createHash('sha256').update(text).digest('hex');
export const agentDirectory = () => process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi/agent');

export function patchedText(current, patch) {
  if (current !== null && digest(current) === patch.afterHash) return current;
  if ((current === null ? null : digest(current)) !== patch.beforeHash) {
    throw new Error(`Unrecognized source for ${patch.file}; refusing to overwrite an upgrade or local change`);
  }
  let result = current ?? '';
  if (patch.beforeHash === null) result = patch.content;
  else for (const edit of patch.edits) {
    if (!edit.before || result.split(edit.before).length !== 2) throw new Error(`Ambiguous repair for ${patch.file}`);
    result = result.replace(edit.before, () => edit.after);
  }
  if (digest(result) !== patch.afterHash) throw new Error(`Repair checksum failed for ${patch.file}`);
  return result;
}

export function applyRepairs({ agentDir = agentDirectory(), check = false, deferMissing = false, manifest } = {}) {
  manifest ??= JSON.parse(fs.readFileSync(new URL('./patches.json', import.meta.url), 'utf8'));
  const npmRoot = path.join(agentDir, 'npm/node_modules');
  const plans = [];
  if (check && deferMissing) throw new Error('A health check cannot defer missing packages');
  const deferred = [];
  for (const pkg of manifest.packages) {
    const root = path.resolve(npmRoot, pkg.name);
    if (!root.startsWith(path.resolve(npmRoot) + path.sep)) throw new Error('Invalid package path');
    // First-start resolution installs absent packages. Existing but incomplete
    // directories, dangling package symlinks and unknown sources still fail closed.
    if (deferMissing && !fs.lstatSync(root, { throwIfNoEntry: false })) {
      deferred.push(`${pkg.name}@${pkg.version}`);
      continue;
    }
    const installed = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    if (installed.version !== pkg.version) throw new Error(`${pkg.name}: tested ${pkg.version}, found ${installed.version}; review compatibility before upgrading`);
    for (const patch of pkg.patches) {
      const target = path.resolve(root, patch.file);
      if (!target.startsWith(root + path.sep)) throw new Error('Invalid repair path');
      const parent = fs.realpathSync(path.dirname(target));
      const realRoot = fs.realpathSync(root);
      if (parent !== realRoot && !parent.startsWith(realRoot + path.sep)) throw new Error('Repair target escapes package');
      if (fs.existsSync(target) && fs.lstatSync(target).isSymbolicLink()) throw new Error('Refusing symlink repair target');
      const current = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : null;
      const next = patchedText(current, patch);
      plans.push({ target, current, next, name: `${pkg.name}/${patch.file}` });
    }
  }
  // Preflight the entire manifest before any mutation. Atomic per-file rename;
  // concurrent fresh starts compute identical content and cannot partially write.
  const changed = plans.filter(plan => plan.current !== plan.next);
  if (check && changed.length) throw new Error(`Repairs missing: ${changed.map(p => p.name).join(', ')}`);
  for (const plan of check ? [] : changed) {
    const temporary = `${plan.target}.${randomUUID()}.tmp`;
    try {
      fs.writeFileSync(temporary, plan.next, { flag: 'wx', mode: 0o600 });
      const now = fs.existsSync(plan.target) ? fs.readFileSync(plan.target, 'utf8') : null;
      if (now !== plan.current && now !== plan.next) throw new Error(`Concurrent modification: ${plan.name}`);
      fs.renameSync(temporary, plan.target);
    } finally {
      fs.rmSync(temporary, { force: true });
    }
  }
  return { checked: plans.length, repaired: changed.length, deferred,
    packages: manifest.packages.map(p => `${p.name}@${p.version}`).filter(p => !deferred.includes(p)) };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const explicitAgentDir = process.argv.slice(2).find(arg => !arg.startsWith('--'));
  console.log(JSON.stringify(applyRepairs({ agentDir: explicitAgentDir || agentDirectory(),
    check: process.argv.includes('--check'), deferMissing: process.argv.includes('--bootstrap') }), null, 2));
}
