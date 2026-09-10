---
description: Verify the shipped user journey and required artifacts
argument-hint: "[acceptance target]"
---
Verify ${@:-the active objective} against its accepted requirements, not against an implementation summary.

- Read `workflow_contract` status, project instructions and the declared source/external inputs. Check that mandatory deliverables and the primary metric reflect the user's request. Missing capability or criteria are blockers to acceptance, not grounds to silently mark work complete.
- Follow the spend ladder: diagnostics and focused regressions, isolated end-to-end checks, then the smallest authorized live qualification. Never substitute source readers, test counts, echo output or a child's report for a real CLI/API/UI journey.
- Execute the pinned success and relevant failure cases. Use `browser-evidence` for web work, `tmux-safe-acceptance` for the exact tmux key path, or `nix-host-validation` for host configuration. Inspect the real artifact, not just its file existence or exit code.
- Preserve one-writer ownership and exact shell permits, including validation commands that generate files. Keep artifacts outside source roots and record their absolute locations. Do not kill unrelated processes or apply host changes merely to make a test pass.
- Attach real finalized tool-call IDs, literal observed outputs and required artifact fingerprints to the corresponding requirement/journey IDs. Evidence must be current on this branch and revision; rerun after material changes. List unavailable environments and unexecuted scenarios explicitly.
- Obtain targeted independent review for material changes and resolve concrete findings. Invoke `workflow_contract complete` only when every mandatory check passes. Report exactly what is implemented, tested and applied, with revision, artifacts and residual risks. Do not rewrite or retract a previously streamed answer to hide incomplete acceptance.
