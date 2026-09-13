import path from "node:path";
import { canonicalPath, contains, fingerprint, sourceWorktrees } from "./workflow-workspace.js";

interface Bindings { roots: string[]; externalInputs: string[] }
export interface RecoveryCoverage {
  version: 1;
  started: boolean;
  retained: string[];
  /** Worktree identities captured before guarded source mutation. */
  trees?: string[];
  baseline?: Bindings & { entries: Record<string, string> };
  diagnostic?: string;
}

/** A failed initial scan is repairable only while no guarded work has begun. */
export function setupCoverage(bindings: Bindings): RecoveryCoverage {
  const entries: Record<string, string> = {};
  try {
    fingerprint(bindings.roots, bindings.externalInputs, entries);
    return { version: 1, started: false, retained: [], baseline: { roots: [...bindings.roots], externalInputs: [...bindings.externalInputs], entries } };
  } catch (error) {
    return { version: 1, started: false, retained: [], diagnostic: String(error) };
  }
}

export function validateCoverage(value: RecoveryCoverage): void {
  const paths = (items: unknown) => Array.isArray(items) && items.length <= 20000 && items.every((p) => typeof p === "string" && path.isAbsolute(p));
  if (!value || value.version !== 1 || typeof value.started !== "boolean" || !paths(value.retained)) throw new Error("Invalid recovery coverage");
  if (value.trees !== undefined && !paths(value.trees)) throw new Error("Invalid recovery worktree coverage");
  if (value.baseline) {
    const b = value.baseline;
    if (!paths(b.roots) || !paths(b.externalInputs) || !b.entries || typeof b.entries !== "object" || Array.isArray(b.entries) ||
        Object.keys(b.entries).length > 20000 || Object.entries(b.entries).some(([p, hash]) => !path.isAbsolute(p) || typeof hash !== "string" || !/^[a-f0-9]{64}$/.test(hash))) {
      throw new Error("Invalid recovery baseline");
    }
  }
}

/** Conservative over-approximation: shell permits retain every declared affected root.
 * Legacy snapshots without tracking cannot prove that narrowing is lossless.
 */
export function priorCoverage(current: Bindings & { recoveryCoverage?: RecoveryCoverage }): RecoveryCoverage {
  return current.recoveryCoverage ?? { version: 1, started: true, retained: [...current.roots, ...current.externalInputs], diagnostic: "Legacy snapshot has no changed-source baseline" };
}

/** Pure preflight: no ledger mutation, even when a replacement or old scan fails. */
export function repairCoverage(current: Bindings & { recoveryCoverage?: RecoveryCoverage }, next: Bindings): { coverage: RecoveryCoverage; revision: string } {
  const entries: Record<string, string> = {};
  let revision: string;
  try { revision = fingerprint(next.roots, next.externalInputs, entries).revision; }
  catch (error) { throw new Error(`Recovery replacement fingerprint failed; nothing adopted. Correct roots/external symlink inputs and retry: ${String(error)}`); }
  const previous = priorCoverage(current);
  validateCoverage(previous);
  const retained = new Set(previous.retained);
  if (previous.baseline) {
    const before = previous.baseline;
    const now: Record<string, string> = {};
    try {
      fingerprint(before.roots, before.externalInputs, now);
      for (const p of new Set([...Object.keys(before.entries), ...Object.keys(now)])) {
        if (before.entries[p] !== now[p]) retained.add(p);
      }
    } catch {
      // An unreadable, removed, oversized or unstable old tree cannot prove a smaller coverage set.
      for (const p of [...before.roots, ...before.externalInputs]) retained.add(p);
    }
  } else if (previous.started) {
    for (const p of [...current.roots, ...current.externalInputs]) retained.add(p);
  }
  const inputs = [...next.roots, ...next.externalInputs];
  const trees = new Set(sourceWorktrees(next.roots));
  const retainedTrees = new Set(previous.trees ?? []);
  for (const p of retained) {
    // Preserve the lexical entry AND its target; separate explicit inputs may cover each.
    const covered = inputs.some((root) => contains(root, p))
      && inputs.some((root) => contains(canonicalPath(root), canonicalPath(p)));
    if (!covered) throw new Error(`Recovery would obscure changed-source coverage: ${p}. Retain it (or a surviving parent for deletions) in roots/externalInputs; scope retirement needs genuine human authorization.`);
    for (const tree of sourceWorktrees([p])) retainedTrees.add(tree);
  }
  for (const tree of retainedTrees) {
    if (!trees.has(tree)) throw new Error(`Recovery must retain worktree HEAD coverage for ${tree} through a source root`);
  }
  if (retained.size > 20000) throw new Error("Recovery coverage exceeds 20,000 entries; retain broader roots instead of repeatedly rebinding");
  return { coverage: { version: 1, started: previous.started, retained: [...retained].sort(), trees: [...retainedTrees].sort(), baseline: { roots: [...next.roots], externalInputs: [...next.externalInputs], entries } }, revision };
}
