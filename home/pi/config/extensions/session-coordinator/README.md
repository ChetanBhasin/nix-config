# Pi session coordinator

A global Pi extension for one local Pi session to wait on work running in other independent top-level Pi processes.

It adds one command:

```text
/after [--timeout 30m] <session-name>... -- <dependent prompt>
```

The extension does not start or own the target processes. Each loaded Pi process publishes a small, private heartbeat record. The waiting process binds every requested display name to one exact live instance, waits for the target activity revision observed at binding to settle, and then submits one synthetic user message containing the dependency results plus the dependent prompt.

## Example

Start two independent named sessions:

```bash
pi --name API
pi --name Tests
```

Ask each interactive session to do its work. One-shot `-p` sessions can also be targets, but the waiting barrier must bind them while they are still live; completed closed sessions are not discovered retroactively.

In a third Pi session:

```text
/after API Tests -- Use both findings to implement and verify the fix.
```

The waiting session must be long-lived (`tui` or `rpc` mode). New barriers are rejected in one-shot `print` and `json` modes because those processes exit before asynchronous release. Target sessions may use any mode as long as they are live when bound.

Names containing whitespace or shell-like punctuation can be quoted:

```text
/after --timeout 45m "API research" "Test audit" -- Reconcile the conclusions.
```

Inspect, retry, or cancel the one barrier owned by the current session:

```text
/after status
/after retry
/after cancel
```

## Settlement semantics

- A target becomes `running` at `before_agent_start` (with `agent_start` as a fallback) and `settled` at `agent_settled`.
- `/tree` branch navigation publishes a new immediately settled revision, so future barriers receive evidence from the selected branch rather than stale text from the prior branch.
- A target already idle when `/after` is submitted counts as settled after a post-barrier heartbeat confirms that the publishing process still owns the record.
- A target that registers only after the barrier was created must complete at least one agent activity; an empty newly opened session does not satisfy the barrier.
- Binding is by exact, case-sensitive display name. Once bound, a later rename does not change the selected instance.
- If another live instance acquires the requested name before the whole barrier releases, the barrier fails instead of guessing—even if that dependency had already settled.
- The barrier is snapshot-based. It records evidence for the exact activity revision current at binding; later unrelated work in that target neither replaces that evidence nor extends the barrier.
- `error`, `aborted`, and incomplete outcomes are still settled and passed through as metadata. Only assistant messages ending with `stopReason: "stop"` are labeled `completed`; length-limited output remains `unknown`.
- The dependent prompt includes each target's session ID/file, working directory, last user message, last assistant text/error, outcome, and settlement time. Captured text is bounded and may be marked truncated.

The generated handoff explicitly labels dependency text as untrusted evidence rather than instructions.
Dependency JSON escapes tag-forming characters so captured model text cannot close the handoff delimiter.

## Failure behavior

The dependent prompt is not submitted when:

- two non-closed records whose PIDs remain alive claim the same requested name (including a stale-heartbeat claimant);
- the waiting session names itself as a dependency;
- a bound target closes or its process exits before the required activity settles;
- the timeout expires; or
- `/after cancel` runs before submission.

A stale heartbeat alone is not treated as a crash when the bound PID is still alive; this avoids false failures after machine sleep or event-loop stalls. The barrier remains pending until the process settles, exits, or the timeout expires.
A record cannot be selected until it publishes a heartbeat at or after the barrier creation time. This prevents a dead producer's briefly fresh record from being trusted merely because its PID was reused by an unrelated process.
Failures are reported in the waiting session. The default timeout is 2 hours; accepted timeout units are `ms`, `s`, `m`, `h`, and `d`, with a range of 1 second through 7 days. Settlement timestamps, rather than poll timing, decide the deadline. Dependent prompts are limited to 16,000 characters, and serialized dependency evidence is capped at 48,000 characters with explicit truncation markers.

After the dependencies release, the coordinator waits for the dependent session to be idle and retains the handoff until a matching `before_agent_start` event confirms submission. A synchronous `sendUserMessage` failure returns it to the ready state immediately; an unconfirmed asynchronous attempt returns it after 60 seconds. Use `/after retry` to make a new marked attempt, or `/after cancel` to discard it.

Expired attempts that have not passed Pi's `input` hook are intercepted and discarded if they arrive late. Pi's extension API intentionally returns `void` from `sendUserMessage`, however, so an attempt that passes `input` and then stalls until after the 60-second confirmation timeout cannot be cancelled with certainty. Retrying during that narrow race can submit twice; cancel instead when the first attempt's fate is unclear.

Only one waiting barrier or released handoff can be queued per waiting session. Barriers are intentionally in-memory and are cancelled by `/reload`, `/new`, `/resume`, `/fork`, or process exit.

## Registry and privacy

Records live by default at:

```text
~/.pi/agent/session-coordinator/v2/instances
```

Set `PI_SESSION_COORDINATOR_DIR` to override the directory. Directories are mode `0700`, records are mode `0600`, and publication uses same-directory temporary files plus atomic rename. Gracefully closed, demonstrably dead, malformed, and abandoned temporary records become eligible for pruning after 24 hours; cleanup runs when a coordinator-enabled Pi process starts, so files can remain longer if Pi is not launched.

A live record retains exact settlement outcome/timestamp metadata for the latest 10,000 revisions without time-based pruning, so a suspended waiter can still verify work that settled by its deadline. Full result text is kept only for the newest 32 revisions; older entries preserve revision evidence with an explicit truncation marker. Registry files are capped at 4 MiB. If the history cap discards a revision before a waiter observes it, the barrier fails explicitly instead of substituting newer evidence.

Only explicitly named sessions publish bounded conversation text. Naming a session therefore opts its last user/assistant exchange into this local coordination registry; unnamed sessions publish lifecycle metadata only.

This mechanism is local to one OS account and machine. Pi display names remain ordinary non-unique metadata; the extension detects ambiguity rather than pretending names are globally unique addresses.

Duplicate detection is based on atomic registry snapshots, not a global OS lock. A conflicting instance published after the final release snapshot can therefore race the handoff; use intentionally unique names when coordination correctness matters.

## Development

```bash
nix shell nixpkgs#typescript --command npm test
```

The suite covers parsing, unique binding, post-barrier liveness proof, already-settled/running/late targets, tree navigation, exact revision evidence, deadline ordering, incomplete outcomes, confirmed submission and retry/cancellation, duplicate-name races (including stale live claimants), crash/close behavior, handoff bounds/escaping, registry permissions, lifecycle publication, and privacy.
