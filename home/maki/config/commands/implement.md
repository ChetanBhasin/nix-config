---
description: Deliver one bounded milestone with one writer and real acceptance
argument-hint: <milestone>
---
Implement $ARGUMENTS within the existing objective.

- Re-read the current todo list and the current source. Reconcile genuine user
  corrections without dropping requirements that are still unmet. Confirm the
  writable roots, the success and failure journeys, and the artifact
  obligations before writing anything.
- Use one writer: either this session for a tightly coupled repair, or one
  `strong`-tier `task` with `subagent_type = "general"` for a meaningful
  independent slice. Give it the goal, constraints, roots, relevant files,
  gates and expected output. Keep independent read-only fan-out to two.
- Discover with `index`, then `grep`/`glob`. Edit with `edit_lines`,
  `insert_lines` or `multiedit` against fresh line numbers; re-`index` a file
  whose line numbers you changed before editing it again. Use `write` only for
  a genuinely new file or an intended full-file replacement.
- Preserve the project's existing language and tooling. Do not introduce a new
  runtime to avoid learning the one already there.
- Run the project's own checks for every file you touched. For a material
  change, get one focused fresh-context review from a read-only `task`; fix the
  concrete findings and resume that review once rather than spawning duplicate
  review loops.
- Run the pinned user journey yourself and inspect the artifact. A child's
  summary and a test count are not acceptance evidence.
- Report: what changed, the revision, the checks actually executed with their
  output, absolute artifact paths, and the residual or deployment limits. Do
  not push, publish, or activate a host without being asked.
