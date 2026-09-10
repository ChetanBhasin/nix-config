import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export function digest(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function canonicalPath(value: string, cwd = process.cwd()): string {
  const unprefixed = value.startsWith("@") ? value.slice(1) : value;
  const expanded = unprefixed === "~" || unprefixed.startsWith("~/") ? path.join(os.homedir(), unprefixed.slice(1)) : unprefixed;
  const absolute = path.resolve(cwd, expanded);
  try {
    return fs.realpathSync(absolute);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    // ENOENT from realpath can mean a dangling symlink, not an absent entry.
    // Apply this at every missing ancestor so nonexistent descendants cannot escape.
    if (fs.lstatSync(absolute, { throwIfNoEntry: false })) throw new Error(`Unresolved path identity for existing entry: ${absolute}`);
    const parent = path.dirname(absolute);
    if (parent === absolute) throw error;
    return path.join(canonicalPath(parent), path.basename(absolute));
  }
}

export function contains(root: string, target: string): boolean {
  const relative = path.relative(root, target);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

export function canonicalRoots(values: string[], cwd = process.cwd()): string[] {
  if (!Array.isArray(values) || values.length < 1 || values.length > 16) throw new Error("Declare 1–16 explicit roots");
  const roots = [...new Set(values.map((value) => {
    if (typeof value !== "string" || !value.trim() || !path.isAbsolute(value)) throw new Error("Roots must be absolute paths");
    const root = canonicalPath(value, cwd);
    const stat = fs.statSync(root);
    if (!stat.isDirectory() && !stat.isFile()) throw new Error(`Root must be an existing file or directory: ${root}`);
    return root;
  }))].sort();
  return roots;
}

export function worktree(root: string): string | undefined {
  // A declared file may legitimately be deleted while its batch is reserved.
  // Ownership follows the unchanged parent/worktree; evidence still rejects missing inputs.
  let start = canonicalPath(root);
  while (true) {
    try {
      const entry = fs.lstatSync(start);
      if (entry.isSymbolicLink()) throw new Error(`Worktree root identity changed to symlink: ${start}`);
      if (!entry.isDirectory()) start = path.dirname(start);
      break;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      const parent = path.dirname(start);
      if (parent === start) throw error;
      start = parent;
    }
  }
  try {
    return canonicalPath(execFileSync("git", ["-C", start, "rev-parse", "--show-toplevel"], {
      encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 2000,
    }).trim());
  } catch {
    // A Git marker plus an unsuccessful resolver is uncertainty, not an independent workspace.
    for (let directory = start; ; directory = path.dirname(directory)) {
      try {
        fs.lstatSync(path.join(directory, ".git"));
        throw new Error(`Cannot resolve worktree identity for ${root}`);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      }
      if (directory === path.dirname(directory)) return undefined;
    }
  }
}

export interface WorkspaceStamp {
  revision: string;
  files: number;
  bytes: number;
}

/** All root contents, including untracked/ignored files; only Git's administrative .git is omitted.
 * Symlink targets outside the declared inputs must be named explicitly. Bounds fail closed.
 */
export function fingerprint(roots: string[], externalInputs: string[]): WorkspaceStamp {
  const inputs = [...new Set([...roots, ...externalInputs].map((p) => path.resolve(p)))].sort();
  const allowed = inputs.map((p) => canonicalPath(p));
  const hash = createHash("sha256");
  let files = 0;
  let bytes = 0;
  const visiting = new Set<string>();
  const add = (value: unknown) => hash.update(JSON.stringify(value) + "\n");
  const visit = (filename: string): void => {
    if (++files > 20000) throw new Error("Fingerprint exceeds 20,000 entries; narrow explicit roots");
    const stat = fs.lstatSync(filename, { bigint: true });
    add([filename, String(stat.mode)]);
    if (stat.isSymbolicLink()) {
      const target = fs.realpathSync(filename);
      if (!allowed.some((root) => contains(root, target))) throw new Error(`Declare external symlink input: ${target}`);
      add(["symlink", fs.readlinkSync(filename), target]);
      if (visiting.has(target)) throw new Error(`Cyclic input: ${target}`);
      visit(target);
    } else if (stat.isDirectory()) {
      if (visiting.has(filename)) throw new Error(`Cyclic input: ${filename}`);
      visiting.add(filename);
      for (const name of fs.readdirSync(filename).sort()) {
        if (name !== ".git") visit(path.join(filename, name));
      }
      const after = fs.lstatSync(filename, { bigint: true });
      if (stat.ino !== after.ino || stat.mtimeNs !== after.mtimeNs || stat.ctimeNs !== after.ctimeNs) throw new Error(`Directory changed during fingerprint: ${filename}`);
      visiting.delete(filename);
    } else if (stat.isFile()) {
      bytes += Number(stat.size);
      if (bytes > 128 * 1024 * 1024) throw new Error("Fingerprint exceeds 128 MiB; narrow explicit roots");
      const content = fs.readFileSync(filename);
      const after = fs.lstatSync(filename, { bigint: true });
      if (stat.ino !== after.ino || stat.size !== after.size || stat.mtimeNs !== after.mtimeNs || stat.ctimeNs !== after.ctimeNs) {
        throw new Error(`Input changed during fingerprint: ${filename}`);
      }
      add(["file", createHash("sha256").update(content).digest("hex")]);
    } else {
      throw new Error(`Unsupported input (not a regular file/directory): ${filename}`);
    }
  };
  for (const input of inputs) visit(input);
  for (const root of roots) {
    const tree = worktree(root);
    if (!tree) continue;
    try {
      add([tree, execFileSync("git", ["-C", tree, "rev-parse", "HEAD"], {
        encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 2000,
      }).trim()]);
    } catch {
      add([tree, "unborn"]);
    }
  }
  return { revision: hash.digest("hex"), files, bytes };
}
