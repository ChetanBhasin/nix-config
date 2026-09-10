// Normalize launcher paths, or preload policy into the wrapped Pi itself.
// No extension code is evaluated in a separate discovery process. Policy is
// applied to Pi's actual extension set, after trust handlers/prompts and reloads.
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const POLICY_FLAGS = [
  "no-tests", "no-opengrep", "no-read-guard", "no-autoformat",
  "no-autofix", "no-lens-context", "lens-compact-tool-line",
];

function applyPolicy(result) {
  for (const extension of result.extensions) {
    // Match Lens's flag interface rather than filenames: symlinks, hardlinks,
    // explicit sources and project-local installations all use the same policy.
    if (!extension.flags.has("no-lens-context") &&
        !extension.flags.has("lens-compact-tool-line")) continue;
    const missing = POLICY_FLAGS.filter((name) => extension.flags.get(name)?.type !== "boolean");
    if (missing.length) throw new Error(`pi launcher: incompatible Lens flags in ${extension.path}: ${missing.join(", ")}`);
    for (const name of POLICY_FLAGS) result.runtime.flagValues.set(name, true);
  }
  return result;
}

const fromPi = (directory, file) => import(pathToFileURL(`${directory}/dist/${file}`).href);
const packageDir = process.env.PI_LAUNCHER_POLICY_PACKAGE;
if (packageDir) {
  // The preload belongs only to this Pi process, not npm, language servers or
  // Node programs launched by its tools. Preserve the caller's NODE_OPTIONS.
  const suffix = ` --import=${import.meta.url}`;
  const options = process.env.NODE_OPTIONS ?? "";
  if (!options.endsWith(suffix)) throw new Error("pi launcher: malformed policy preload");
  const original = options.slice(0, -suffix.length);
  if (original) process.env.NODE_OPTIONS = original;
  else delete process.env.NODE_OPTIONS;
  delete process.env.PI_LAUNCHER_POLICY_PACKAGE;
  const repairBootstrap = process.env.PI_LAUNCHER_REPAIR_BOOTSTRAP;
  delete process.env.PI_LAUNCHER_REPAIR_BOOTSTRAP;
  const repairModule = repairBootstrap ? await import(pathToFileURL(repairBootstrap).href) : undefined;
  if (repairModule && typeof repairModule.installBootstrapRepairs !== "function") {
    throw new Error("pi launcher: incompatible runtime repair bootstrap");
  }

  // Nix's executable uses the bundled CLI; SDK consumers use the source modules.
  // They export distinct classes. Cover both rather than validating only the SDK.
  const modules = await Promise.all([
    fromPi(packageDir, "core/resource-loader.js"),
    fromPi(packageDir, "bundle/index.js"),
  ]);
  for (const { DefaultResourceLoader } of modules) {
    repairModule?.installBootstrapRepairs(DefaultResourceLoader);
    const getExtensions = DefaultResourceLoader.prototype.getExtensions;
    if (typeof getExtensions !== "function") throw new Error("pi launcher: incompatible Pi resource loader");
    DefaultResourceLoader.prototype.getExtensions = function () {
      return applyPolicy(getExtensions.call(this));
    };
  }
} else if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const [directory, agentPath, action] = process.argv.slice(2);
  if (action === "--resolve-agent-dir") {
    const { resolvePath } = await fromPi(directory, "utils/paths.js");
    process.stdout.write(`${resolvePath(agentPath)}\n`);
  } else if (action === "--preload-url") {
    process.stdout.write(`${import.meta.url}\n`);
  } else {
    throw new Error("pi launcher: unknown helper action");
  }
}
