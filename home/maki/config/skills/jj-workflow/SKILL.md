---
name: jj-workflow
description: Use for revision checkpoints, handoffs or change tracking in repositories that already contain .jj. Preserve working files and foreign changes; never introduce Jujutsu into a repository that does not use it.
---
# Jujutsu checkpoints

- Confirm `.jj` exists before using any of this. If it does not, use the
  repository's existing VCS. Do not initialize or migrate a repository merely
  to follow this skill.
- Inspect `jj status`, `jj diff`, the current change and commit IDs, and
  relevant `jj op log` before touching anything. In a colocated repository,
  understand both the Jujutsu and the Git state before going near the index or
  the refs.
- There is no staging area. The working copy is a change; edits land in it
  immediately. `jj describe` names the change you are in, `jj new` starts the
  next one.
- Preserve unrelated and user-owned changes. Never describe a delta you did not
  make as your own. A sibling repository stays read-only unless it was
  separately authorized.
- At an authorized milestone, `jj describe` the change with what it actually
  does and what validated it. Use `jj new` only when a checkpoint or handoff
  calls for starting a fresh change.
- `jj abandon`, `jj undo` and `jj op restore` are blocked in this setup, by
  design: each can silently drop the user's work. If one is genuinely the right
  move, explain what it would discard and ask.
- Changing the revision invalidates acceptance evidence tied to it. Checkpoint
  before the final journey run, or rerun the affected checks afterwards. Record
  both the change ID and the commit ID when both matter.
- Ignore, untrack and delete are distinct. An untracking request does not
  authorize removing working files.
