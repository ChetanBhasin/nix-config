---
name: cross-repo-handoff
description: Use when work consumes sibling repository APIs or transfers implementation/validation ownership across repositories, worktrees or Pi sessions.
---
# Cross-repository ownership and handoff

1. Map the owner, absolute repository/worktree root, current revision, consumed interface and expected output for each participant. A path under the same parent directory does not imply shared edit authority.
2. Keep sibling repositories read-only unless the user has authorized that repository and its writer roots are explicitly claimed. Record revision-pinned consumption and interface assumptions; do not opportunistically fix another owner's API during consumer work.
3. Use one writer per repository/worktree. Release after mutation drain before a child/next session claims it. Nonces and ownership do not transfer through fork, reload, display name or a handoff document. Preserve unknown/live leases; never remove one to get unstuck.
4. Delegate with fresh context and a bounded contract: target cwd, exact writable/read-only roots, source seams, expected artifact, checks and stop conditions. Use Astra/max for substantive work, inherited model/thinking for small delegates, and no nested orchestration unless explicitly assigned and supported.
5. Mark the active objective as waiting while depending on another owner. Consume its actual result/artifact before resuming; child attestations do not establish acceptance. Verify interface compatibility and the user journey in the consuming repository yourself.
6. Handoff accepted requirement IDs, relevant revision IDs, artifact paths, canonical commands, actual validation outcomes, owned processes and unresolved risks. Keep credentials and unrelated conversation history out of the packet.
7. Do not reinterpret ignore/untrack as deletion, or clean/reset foreign changes to manufacture a clean checkout. Checkpoint only with the repository's existing VCS and corresponding authority; publishing/merging remains separately protected.

Read [the workflow protocol](../../extensions/auto-mode/WORKFLOW.md) for exact ledger, permit, waiting and release semantics. These are cooperative controls, not a sandbox or permission grant.
