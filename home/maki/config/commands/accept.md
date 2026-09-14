---
description: Verify the shipped journey and artifacts, not the implementation summary
argument-hint: [acceptance target]
---
Verify $ARGUMENTS against the accepted requirements, not against a summary of
what was implemented.

- Re-read the requirements and the declared inputs. A missing capability or an
  unmet criterion is a blocker to acceptance, not grounds to quietly call the
  work done.
- Climb the spend ladder in order: the project's focused checks, then an
  isolated end-to-end run, then the smallest authorized live qualification.
  Never substitute a source reader, a test count, echoed output, or a
  subagent's report for a real CLI/API/UI journey.
- Execute both the pinned success case and the relevant failure case. Check
  the `skill` tool for a playbook covering this kind of work and load it first.
- In a Jujutsu repository, `rv status --check` is the gate: no acceptance
  claim stands while `rv_comments` still lists an open finding.
- Inspect the artifact itself, not its existence or the generator's exit code.
- Keep acceptance output outside source roots and record its absolute path.
- Attach the literal observed output to each requirement. Evidence must be
  current on this revision; rerun anything invalidated by a later change. List
  the environments you could not reach and the scenarios you did not run.
- Report exactly what is implemented, tested, and applied, with the revision,
  the artifacts and the residual risks. Do not retract or rewrite an earlier
  claim to make the result look complete.
