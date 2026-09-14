---
description: Preserve a compact, honest handoff at a durable boundary
argument-hint: [next objective or recipient]
---
Prepare a handoff for $ARGUMENTS.

1. Read the current todo list and the actual repository state. Separate
   accepted work from partial implementation, failed checks, and pending
   review. Do not mark a todo complete because a handoff is due.
2. Record: the objective, the exact writable roots, the requirement wording,
   the current revision (and Jujutsu change ID where the repo uses `jj`), the
   changed files, the canonical commands, the evidence actually executed, the
   artifact paths, and the unresolved decisions. Include the primary metric and
   any assumption that must not be silently changed.
3. List the processes, sessions and resources the recipient needs. Leave out
   credentials, raw conversation history, and unrelated prior objectives. A
   read-only sibling interface needs its owner and a pinned revision, not
   implied edit authority.
4. Let in-flight subagents finish, or say explicitly that they are still
   running and who owns their results. Do not orphan them.
5. If a checkpoint was authorized, use the repository's existing VCS workflow.
   Preserve the user's changes; do not push, publish or reset history as part
   of a handoff.
6. Save genuinely durable project facts with `memory`, tagged so a later
   session can find them. Keep the live task state in the todo list. Use
   `/compact` for window pressure and `/new` for a genuinely different
   objective.
7. Return the handoff plus the next exact action.
