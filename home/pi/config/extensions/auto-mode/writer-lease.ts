import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { canonicalPath, canonicalRoots, contains, digest, worktree } from "./workflow-workspace.js";

export interface Owner {
  session: string;
  pid: number;
  birth: string;
  host: string;
  nonce: string;
}
export interface Lease {
  version: 1;
  owner: Owner;
  roots: string[];
  worktrees: string[];
  inFlight: string[];
}
export interface ProcessProbe { state: "alive" | "dead" | "unknown"; birth?: string }
export type Probe = (pid: number) => ProcessProbe;

export function processProbe(pid: number): ProcessProbe {
  try { process.kill(pid, 0); } catch (error) {
    return { state: (error as NodeJS.ErrnoException).code === "ESRCH" ? "dead" : "unknown" };
  }
  try {
    if (process.platform === "linux") {
      const stat = fs.readFileSync(`/proc/${pid}/stat`, "utf8");
      const start = stat.slice(stat.lastIndexOf(")") + 2).split(" ")[19];
      const boot = fs.readFileSync("/proc/sys/kernel/random/boot_id", "utf8").trim();
      if (!start || !/^\d+$/.test(start) || !boot) return { state: "unknown" };
      return { state: "alive", birth: `linux:${boot}:${start}` };
    }
    if (process.platform === "darwin") {
      // Resolve ps through PATH (Nix/macOS); never assume /bin/ps exists.
      const birth = execFileSync("ps", ["-p", String(pid), "-o", "lstart="], {
        encoding: "utf8", timeout: 2000, env: { ...process.env, LC_ALL: "C" },
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      return birth ? { state: "alive", birth: `darwin:${birth}` } : { state: "unknown" };
    }
  } catch { /* Missing or unreadable birth identity is not proof of death. */ }
  return { state: "unknown" };
}

export function demonstratedDead(owner: Owner, probe: Probe = processProbe): boolean {
  if (owner.host !== os.hostname()) return false;
  const current = probe(owner.pid);
  return current.state === "dead" || (current.state === "alive" && !!current.birth && current.birth !== owner.birth);
}

function decodeLease(raw: string): Lease {
  const lease = JSON.parse(raw) as Lease;
  const owner = lease?.owner;
  if (lease?.version !== 1 || !owner || !Number.isSafeInteger(owner.pid) || owner.pid < 1 ||
      ![owner.session, owner.birth, owner.host, owner.nonce].every((v) => typeof v === "string" && v.length > 0) ||
      !Array.isArray(lease.roots) || !lease.roots.length || !lease.roots.every((v) => typeof v === "string" && path.isAbsolute(v)) ||
      !Array.isArray(lease.worktrees) || !lease.worktrees.every((v) => typeof v === "string" && path.isAbsolute(v)) ||
      !Array.isArray(lease.inFlight) || !lease.inFlight.every((v) => typeof v === "string")) {
    throw new Error("Malformed writer lease; no age-based recovery. Inspect private lease DB while all owners are stopped.");
  }
  return lease;
}

export function defaultLeaseDatabase(): string {
  return path.join(os.homedir(), ".pi", "agent", "state", "auto-mode", "writer-leases.sqlite");
}

/** Cooperative cross-process exclusion, NOT a sandbox. No TTL and no filesystem unlink reclamation. */
export class WriterLeaseStore {
  private db: DatabaseSync;
  constructor(filename = defaultLeaseDatabase(), private probe: Probe = processProbe) {
    const directory = path.dirname(filename);
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    const directoryStat = fs.lstatSync(directory);
    if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink() || (directoryStat.mode & 0o077) !== 0 ||
        (process.getuid && directoryStat.uid !== process.getuid())) throw new Error("Writer state directory must be private and owned");
    try { fs.closeSync(fs.openSync(filename, "wx", 0o600)); } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
    }
    const stat = fs.lstatSync(filename);
    if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0 ||
        (process.getuid && stat.uid !== process.getuid())) throw new Error("Writer database must be a private owned regular file");
    this.db = new DatabaseSync(filename);
    this.db.exec("PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS leases (nonce TEXT PRIMARY KEY, data TEXT NOT NULL)");
  }
  private transaction<T>(action: () => T): T {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = action();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
  private records(): Lease[] {
    return this.db.prepare("SELECT nonce, data FROM leases").all().map((row) => {
      const lease = decodeLease(String(row.data));
      if (row.nonce !== lease.owner.nonce) throw new Error("Writer nonce mismatch in database");
      return lease;
    });
  }
  private save(lease: Lease): void {
    this.db.prepare("INSERT OR REPLACE INTO leases (nonce, data) VALUES (?, ?)").run(lease.owner.nonce, JSON.stringify(lease));
  }
  claim(session: string, values: string[]): Lease {
    if (!session) throw new Error("Session ownership unavailable");
    const identity = this.probe(process.pid);
    if (identity.state !== "alive" || !identity.birth) throw new Error("Process birth identity unavailable; writer claim denied");
    const roots = canonicalRoots(values);
    const trees = [...new Set(roots.map(worktree).filter((v): v is string => !!v))];
    return this.transaction(() => {
      for (const held of this.records()) {
        if (demonstratedDead(held.owner, this.probe)) {
          this.db.prepare("DELETE FROM leases WHERE nonce = ?").run(held.owner.nonce);
          continue;
        }
        this.stableRoots(held);
        if (held.roots.some((a) => roots.some((b) => contains(a, b) || contains(b, a))) ||
            held.worktrees.some((tree) => trees.includes(tree))) {
          throw new Error(`Writer conflict: session ${held.owner.session}, pid ${held.owner.pid}; live/unknown owners cannot be stolen`);
        }
      }
      const lease: Lease = {
        version: 1, roots, worktrees: trees, inFlight: [],
        owner: { session, pid: process.pid, birth: identity.birth!, host: os.hostname(), nonce: randomUUID() },
      };
      this.save(lease);
      return lease;
    });
  }
  private stableRoots(held: Lease): void {
    if (held.roots.some((root) => canonicalPath(root) !== root)) throw new Error("Writer root identity changed");
    const currentTrees = [...new Set(held.roots.map(worktree).filter((v): v is string => !!v))].sort();
    if (digest(currentTrees) !== digest([...held.worktrees].sort())) throw new Error("Writer worktree identity changed; ownership uncertain");
  }
  private matching(owner: Owner): Lease {
    const held = this.records().find((lease) => lease.owner.nonce === owner.nonce);
    if (!held || digest(held.owner) !== digest(owner) || owner.pid !== process.pid || owner.host !== os.hostname()) {
      throw new Error("Writer ownership/token mismatch");
    }
    const current = this.probe(owner.pid);
    if (current.state !== "alive" || current.birth !== owner.birth) throw new Error("Writer process ownership uncertain");
    this.stableRoots(held);
    return held;
  }
  check(owner: Owner): Lease { return this.transaction(() => this.matching(owner)); }
  reserve(owner: Owner, callId: string, targets: string[]): void {
    this.transaction(() => {
      const held = this.matching(owner);
      if (!callId || held.inFlight.includes(callId)) throw new Error("Duplicate or missing mutation call ID");
      if (!targets.length || targets.some((target) => !held.roots.some((root) => contains(root, canonicalPath(target))))) {
        throw new Error("Mutation lies outside explicitly claimed roots");
      }
      held.inFlight.push(callId);
      this.save(held);
    });
  }
  drain(owner: Owner, finalized: string[]): void {
    this.transaction(() => {
      const held = this.matching(owner);
      held.inFlight = held.inFlight.filter((id) => !finalized.includes(id));
      this.save(held);
    });
  }
  release(owner: Owner): void {
    this.transaction(() => {
      const held = this.matching(owner);
      if (held.inFlight.length) throw new Error("Writer batch has not drained; release in a later turn");
      this.db.prepare("DELETE FROM leases WHERE nonce = ?").run(owner.nonce);
    });
  }
  close(): void { this.db.close(); }
}

// Known source-inspection, coordination and browser tools may persist their own
// runtime state/artifacts. They are not source editors; never use artifact paths to overwrite source.
const NON_SOURCE_TOOLS = new Set([
  "read", "grep", "find", "ls", "project_report", "module_report", "read_symbol", "read_enclosing", "symbol_search",
  "lens_diagnostics", "lsp_diagnostics", "ast_grep_search", "ast_grep_outline", "ast_grep_dump", "pi_lens_activate_tools",
  "ask_user_question", "subagent", "contact_supervisor", "workflow_contract", "writer_lease", "web_run", "view_image",
  "todo", "ctx_search", "ctx_expand", "ctx_memory", "ctx_note", "ctx_reduce",
  "subagent_wait", "subagent_supervisor", "agent_browser",
]);
const FILE_MUTATIONS = new Set(["write", "edit", "replace", "insert", "undo_last_change"]);
const LSP_READ_ONLY = new Set(["definition", "references", "implementation", "hover", "symbols", "callHierarchy", "incomingCalls", "outgoingCalls"]);

/** Unknown tools and ALL shell commands need an exact, one-use, explicitly scoped permit.
 * This deliberately does not attempt to parse shell write effects with regexes.
 */
export function mutationTargets(tool: string, input: Record<string, unknown>, cwd: string): string[] | "permit" | undefined {
  if (NON_SOURCE_TOOLS.has(tool)) return undefined;
  if (tool === "runtime_health" && (input.action === undefined || input.action === "check")) return undefined;
  if (tool === "lsp_navigation" && typeof input.action === "string" && LSP_READ_ONLY.has(input.action)) return undefined;
  if (tool === "lens_diagnostic_mark" && ["false-positive", "defer", "flagged"].includes(String(input.disposition))) return undefined;
  if (FILE_MUTATIONS.has(tool)) {
    return typeof input.path === "string" ? [canonicalPath(input.path, cwd)] : "permit";
  }
  if (tool === "ast_grep_replace" && Array.isArray(input.paths) && input.paths.length &&
      input.paths.every((p) => typeof p === "string" && !/[?*{[!]/.test(p))) {
    return input.paths.map((p) => canonicalPath(p, cwd));
  }
  // LSP rename can mutate references beyond its starting file: require declared affected roots.
  return "permit";
}
