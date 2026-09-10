# Workflow acceptance and cooperative writing

These controls load in both parent and child Auto Mode controllers. `/auto` still defaults off and keeps its existing protected-action/confirmation policy. A writer claim is **not permission** for a protected action. No role tool allowlist is expanded: the parent must explicitly make `workflow_contract` and `writer_lease` available to approved writing roles.

## Ledger

- `/workflow` or `/workflow status` shows the active branch's acceptance, requirements, evidence IDs, blockers, input provenance, continuation counters and local lease. Tool status output is capped at 48 KB; full records remain in Pi custom entries.
- Discussion and read-only reconnaissance need no objective or writing contract. A lease alone does not create or accept an objective. For implementation, explicitly call `workflow_contract start` before work. There is no prose classifier that guesses objectives or treats an answer as completion.
- `workflow_contract status` returns the latest genuine `input.id`. `interactive` and `rpc` inputs are recorded separately from extension messages; a child labels its intake `delegated-input`, not direct user authority. RPC is an input transport, **not proof that a human authored it**. Custom/extension continuations never authorize scope changes.
- Define stable IDs, explicit `mandatory` flags, expected **literal observable output**, and a user scenario through the **actual interface** (CLI, app, API, UI). A journey pins its tool and exact arguments **before** execution. Tests or test counts are not a substitute for that scenario. Set `artifactRequired: true` on criteria/journeys that produce load-bearing artifacts.

Example `start` tool arguments (replace absolute paths and input ID):

```json
{
  "action": "start",
  "inputId": "latest-input-id",
  "definition": {
    "objective": "Greet a named user from the shipped CLI",
    "kind": "implementation",
    "roots": ["/absolute/project/src", "/absolute/live/config"],
    "externalInputs": ["/absolute/project/bin/greet", "/absolute/fixture.json"],
    "requirements": [{"id":"greeting", "mandatory":true, "expected":"Hello, Ada!"}],
    "journeys": [{"id":"cli-user", "scenario":"User invokes greet with Ada", "interface":"shipped greet CLI", "tool":"bash", "input":{"command":"/absolute/project/bin/greet Ada"}, "expected":"Hello, Ada!"}]
  }
}
```

`roots` are existing absolute source files or directories (including live config outside cwd); every file under a declared directory, including **untracked and Git-ignored files**, is fingerprinted. Prefer e.g. `src/` plus `Cargo.toml`/`package.json` over the whole repository when build/dependency trees are large. `externalInputs` names additional local files/directories, deployed binaries and fixtures. Symlink targets outside these inputs must be explicit. Only `.git` administration is omitted; root worktree HEAD is included. Scans fail closed above 20,000 entries/128 MiB or on unreadable/unstable inputs. Use narrow roots, not an entire home directory. Put generated logs outside source roots, otherwise their creation changes the revision and requires a rerun. Gitignored build/dependency directories under declared roots are not silently excluded.

When a goal intentionally deletes an input, declare its surviving **parent directory** as the root. A deleted file root can still drain and release its lease through the unchanged parent/worktree, but a missing declared input is not valid acceptance evidence. Identity uncertainty still blocks release.

After an actual tool finishes, call:

```json
{"action":"evidence", "evidence":{"target":"cli-user", "kind":"journey", "expected":"Hello, Ada!", "observed":"Hello, Ada!", "toolCallId":"actual-finalized-id"}}
```

Add criterion evidence with `kind: "requirement"` as well. Supply an absolute `artifact` locator when applicable; it must appear in the tool output and its contents are fingerprinted. Evidence must have a pre/post stable workspace, match the objective revision, match finalized non-error call/result messages **on this branch**, and contain the declared expected/observed output. New attempts of the same interface invalidate old evidence, including failed/unfinalized attempts. Child and ledger reports are attestations, never acceptance evidence. Missing/failed/stale journeys cannot complete. `complete` **throws** on validation failure (Pi ignores an `isError` property returned from `execute`).

A later input requires `confirm` with the current `revision` and `inputId` for unchanged scope. That acknowledgement itself does no filesystem hashing or evidence reset. `revise` can autonomously **add or strengthen** requirements/journeys/artifact checks and add external verification inputs while preserving every existing obligation and the same objective, kind and source roots. It invalidates old evidence but retains continuation budgets. Removals, changed existing outcomes/arguments, weaker mandatory/artifact flags, changed objective/kind or expanded/replaced source roots still require a **genuine input**, not a tool assertion:

```text
workflow-scope {"action":"revise","revision":1,"definition":{...complete new definition...}}
```

Then call `revise` with that exact definition, input ID and revision. Evidence is conservatively invalidated; IDs/flags cannot be silently dropped or downgraded to finish. Replacing **unfinished** work requires a **new** genuine `workflow-scope {"action":"start","definition":{...}}` input. After checked completion, an ordinary new genuine input can start a new objective; same-input and extension-message resets remain forbidden. The former objective's snapshots remain in history. A malformed scope input cannot be acknowledged as unchanged.

Snapshots, provenance and execution receipts are versioned Pi custom entries. Startup/reload and tree navigation restore **only `getBranch()`**, never all entries or compaction summaries. A fork inherits only its copied branch history, not a process lease. An ephemeral session is explicitly reported as non-durable. Bounds: 64 criteria, 16 journeys, 80 selected evidence items, 256 recent receipt lookups; older finalized messages remain in session history.

## Bounded Auto Mode remediation

Only an enabled **owner parent**, for an active actionable incomplete contract, may queue a marked `followUp` from `agent_end`. Pi 0.84.4 drains this before `agent_settled`; the coordinator's transport settlement is deliberately unchanged. Already-streamed answers are never rewritten or retracted. Footer/notifications and non-triggering acceptance warnings report unaccepted work separately.

There are at most **three** automated continuations per objective; two consecutive unchanged progress comparisons stop earlier as blocked/unaccepted. Counts/fingerprints survive reload, compaction and scope revisions. `/auto off` never resets them. Abort, runtime error/length stop, queued input/messages, UI waiting, undrained mutations, explicit blockers and waiting disposition suppress new remediation. An already-queued transport turn cannot be selectively removed through Pi's public API; after `/auto off`, the marked remediation instruction is excluded from model context and no further ledger follow-ups are queued.

Unavailable workflow, writer or planned journey tools produce a visible capability blocker **without spending continuation/no-progress budget or expanding a role allowlist**. Restoring the intended capability allows remediation to resume.

Use `disposition` with `waiting` and reasons before waiting on delegated work; launches also mark waiting conservatively. Explicitly set `actionable` with the resolution reason when work returns, then verify artifacts. Use `blocked` for missing credentials, protected actions or unresolved decisions. Clearing a disposition does **not** reset continuation budgets or accept evidence.

## One-writer protocol

1. `writer_lease {"action":"claim","roots":["/absolute/root", "/absolute/live/config"]}` returns a session/process-bound nonce. Claim roots only after repository/worktree initialization. Parent releases before handing source writing to a child.
2. Direct `write`, `edit`, Hashline `replace`/`insert`/`undo_last_change`, and explicit-path AST rewrites must lie within the lease. If a contract is active, they must also fit its implementation roots. Overlaps, symlink aliases and different subdirectories of the same worktree conflict. Independent worktrees can proceed.
3. **Every shell command**, LSP rename (which may edit references elsewhere), missing/inferred paths, globbed AST rewrites and unknown plugin effects need an exact one-use permit first:
   `writer_lease {"action":"permit","nonce":"...","roots":["/absolute/root"],"tool":"bash","input":{"command":"exact command"}}`.
   The declared roots must cover **all source-writing effects**. No regex guesses whether a shell command writes. Even `cat` needs this permit; dedicated read/search/Lens diagnostics and known coordination/memory/browser tools remain usable without a lease. These tools can persist their own runtime state and artifacts, not source edits: never direct a browser screenshot/download or other artifact output over source files. `runtime_health check` needs no lease; `repair` needs an explicit permit. `!`/`!!` shell is rejected because it has no guarded tool-batch finalization; use the guarded bash tool instead.
4. Do not run detached/background writers. Release with `{"action":"release","nonce":"..."}` in a **later turn**, after the whole mutation batch drains. Release in the same parallel batch throws rather than deadlocking or dropping ownership early. At most eight exact permits can be pending. Permits are lost on release/tree/reload.
5. Shutdown/reload/new/fork release only the instance's matching captured nonce/session/process and only after drain, even when Pi has already changed an in-memory SessionManager ID. Public release still validates the current session. Unknown or undrained ownership is retained, not stolen. A new instance must claim again; an old callback cannot release its successor.

The pinned Node 24.19.0 provides built-in `node:sqlite`. A separate private database at `~/.pi/agent/state/auto-mode/writer-leases.sqlite` uses `BEGIN IMMEDIATE` transactions for acquisition/reclamation. It is **not** the Magic Context database and is outside captured extensions. No native/network dependency is installed. Owner identity binds session, nonce, hostname, PID and OS process birth: Linux boot ID + `/proc/PID/stat` start ticks; Darwin uses PATH-resolved `ps -p PID -o lstart=` under `LC_ALL=C`. Only demonstrated death or a mismatched known birth identity permits reclamation. Live, EPERM, foreign-host and unknown owners block. No TTL stealing, stale-age unlinking or malformed-state age recovery. Malformed/uncertain state needs operator inspection with owners stopped; never delete a live lease to get unstuck.

## Limits and validation

This is **cooperative coordination, not sandbox/security isolation or semantic proof**. The tool/argument/result chain and fingerprints establish execution and material consistency, not that the agent listed every requirement, chose a genuine/sufficient journey, told the truth about a shell's effects, or interpreted the output correctly. Initial criteria and unchanged-scope acknowledgements remain agent-authored interpretations. Independent review must check them. Echoing expected text is not meaningful application verification, even though no general structural checker can prove that distinction.

Fingerprinting is point-in-time, not an atomic filesystem snapshot. Undeclared external services, environment inputs, external editors, hard-link aliases, orphan processes, direct extension filesystem/`pi.exec` calls, tools overridden under a read-only name, later argument-mutating hooks, disabled controllers and hostile same-UID code are outside the guarantee. Preserve existing permission gates. Specify relevant external inputs and review load-bearing tool calls/artifacts. Read-only evidence tooling must actually be read-only. Darwin identity fallback is implemented conservatively but requires deployment qualification on Darwin.

Run `npm test` in this directory. Tests use only isolated `/tmp` state, real competing Node processes, and a deterministic offline provider with actual Pi 0.84.4 `AgentSession`/tool execution. They exercise rejection, real CLI evidence, follow-up-before-settlement ordering, whole-batch lease exclusion, branch persistence and cancellation/off/waiting. No external model, network install, settings change, commit or CI change is involved. Keep **only portable source/tests/docs/config** here: the Pi capture includes every descendant and rejects symlinks. Never put node_modules, SQLite state, build products or logs in this directory.

Optional **billable** qualification: `node workflow-live-check.mjs --live`. It uses exact `openai-codex/gpt-6-astra` at `max`, with no model fallback, through Pi's actual SDK and the workflow controller. Only `/tmp` application/session/lease state is written; normal live auth refresh remains enabled. The real agent must plan, claim, implement, run both pinned success/failure CLI journeys, record four checked receipts, complete and release. The harness independently replays both outcomes, revalidates the saved ledger and reacquires the released root. Its `result.json`/session artifact is under the printed scratch path. This isolates the workflow protocol; it does not replace full-launcher/global-extension deployment checks.
