---
description: Preserve a compact, honest handoff at a durable boundary
argument-hint: "[next objective or recipient]"
---
Prepare a handoff for ${@:-the next session or owner}.

1. Read the active contract and actual repository/session state. Distinguish accepted work from partial implementation, failed checks and pending review. Do not mark todos or requirements complete merely because a handoff is needed.
2. Record the objective, exact writable roots, stable requirement IDs, current revision/Jujutsu change IDs, changed files, canonical commands, executed evidence, artifact paths and unresolved decisions. Include the primary metric and any assumptions that must not be silently changed.
3. Enumerate owned processes, sessions and resources needed by the recipient. Do not copy credentials, raw private conversation history or irrelevant prior objectives. Read-only sibling interfaces need their owner and pinned revision, not implied edit authority.
4. Drain mutation work and release this instance's writer lease before transferring ownership. Never transfer a nonce or imply that a revived/forked session inherits ownership. Wait for active children or explicitly retain their ownership/result routes; do not orphan them.
5. If requested/authorized, checkpoint with the repository's existing VCS workflow. Preserve user changes and do not push, publish, delete or reset history as part of handoff.
6. Save genuinely durable project facts with `ctx_memory`; keep current work in its ledger/todos. Pi-native compaction owns the window: use native `/compact` for pressure, and a fresh `/new` session for a genuinely different objective. Do not depend on Magic Context window-management commands or use future notes as a substitute for active task tracking.
7. Return a concise handoff with usage, revision/status, validation, artifacts, residual risks and the next exact action. A display name is not a unique session address; use actual session IDs/paths where needed.
