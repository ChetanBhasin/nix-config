---
name: jj-workflow
description: Use for revision checkpoints, handoffs or tracking changes in repositories that already contain .jj. Preserve working files and foreign changes; do not introduce Jujutsu into other repositories.
---
# Jujutsu checkpoints

- Read project instructions and confirm `.jj` exists. If absent, use the repository's existing VCS; do not initialize or migrate it merely to follow this skill.
- Inspect `jj status`, `jj diff`, current change/commit IDs and relevant operation history through the required shell permits. In colocated repositories, understand both Jujutsu and Git state before touching the index or refs.
- Claim the authorized repository roots before mutations. Preserve unrelated/user-owned changes and recorded ownership; never describe a foreign delta as your own. A sibling repository remains read-only unless separately authorized.
- At an authorized coherent milestone, describe the actual change and its validation with `jj describe`. Use `jj new` only when the checkpoint/handoff calls for starting a new change. Do not push, rewrite shared history, abandon changes or use undo as cleanup without authority.
- HEAD/revision changes can invalidate acceptance fingerprints. Make the checkpoint before final journey evidence, or rerun the affected checks afterward. Record both change and commit IDs when they matter.
- Ignore, untrack and delete are distinct operations. An untracking request does not authorize removing working files. Never use broad clean/reset/abandon commands to make status look tidy.
- Report the current IDs, actual delta, executed checks, owned outstanding processes and remaining risks. Save only durable facts, not raw session history.

The cooperative lease is not permission for a protected action. For exact tool semantics, read [the workflow protocol](../../extensions/auto-mode/WORKFLOW.md).
