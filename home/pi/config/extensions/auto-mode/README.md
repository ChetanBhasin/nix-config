# Pi Auto Mode

Runtime-toggleable unattended mode for long-running Pi tasks. Every top-level Pi process starts **off**; descendant Pi agents inherit their parent's runtime state.

## Commands

- `/auto on` — enable unattended behavior immediately
- `/auto off` — restore interactive behavior immediately
- `/auto status` — show the current state
- `/auto` — toggle the current state

The footer/status area shows `AUTO` while the mode is enabled.

## Behavior while enabled

- Removes `ask_user_question` from the active tool set and blocks any in-flight call that still reaches it.
- Tells the active model to resolve ambiguity itself, prefer the safest reversible choice, and report assumptions.
- Automatically accepts only pi-subagents' exact **spawn-budget increase** confirmation.
- Denies other confirmation dialogs rather than broadening unattended approval.
- Publishes an Ed25519-signed, monotonic control record through an inherited environment descriptor and runtime control file, so already-running child agents observe `/auto on` and `/auto off` at their next extension event.
- Rejects tampered records and records older than the child's last authenticated revision, retaining that last state when the control file is unavailable.
- Keeps the existing model policy against purchases, production control, destructive/irreversible actions, and account/security/privacy changes. This is advisory for tools such as unrestricted `bash`; Auto Mode itself is not a sandbox or permission system.

## Parent and child delegation policy

The owner parent remains the orchestrator and final authority. It delegates useful non-trivial independent or context-heavy lanes, keeps only genuinely tiny deterministic work local, inspects executable agents first, and uses one `async: true` workflow per wave. Waves normally contain 4–8 distinct useful lanes and never exceed 8 active lanes.

Every child contract names its goal, scope, cwd/worktree, authority, evidence, acceptance, validation, stop conditions, and output artifact. Fresh context is the default and deliberately has no intercom bridge or `contact_supervisor`; its bounded task contract and output artifact are the escalation path. Only the policy-permitted, actually forked `oracle` receives inherited-conversation supervisor dialogue when that history is necessary evidence. One writer owns a cwd/worktree, fan-out is read-only, and handoffs are artifacts rather than transcripts. After wide fan-out, an aggregation delegate returns synthesis plus load-bearing evidence; the parent consumes artifacts at dependency barriers without polling, rejects cloned prompts, reserves capacity for implementation/fixes/review, grants budget only for named necessary lanes, and verifies final source, diff, and tests before responding.

An inherited child is a bounded executor, not an orchestrator: it completes only its assigned contract, neither calls nor proposes subagents, honors read-only or sole-writer authority, resolves routine details safely, records unapproved product/API/scope/architecture/authority/protected decisions as artifact blockers, and returns a concise evidence/changes/commands/blockers/risks artifact.

## Owner-only async promotion and limits

For an enabled owner parent, a no-action launch with an `agent` or `workflowScript` receives outer `async: true` only when `async` is omitted and `foregroundOnly` is not explicitly `true`. Explicit `async` values, child calls, OFF mode, management/schedule/resume/steer actions, `extensionBindings`, and workflow source bytes are preserved. Signed child controls remain appended to eligible launch, steer, and resume task text.

The configured boundary keeps `asyncByDefault=false`, `forceTopLevelAsync=false`, `artifactDir=session`, and depth 1. It allows two top-level async runs, 16 per-run spawn admissions, and a configured per-session budget of 64. A spawn-budget grant for named necessary lanes can raise the effective per-session maximum to 128; it does not raise the 16 per-run admission limit or the advisory 8-lane wave limit. `globalConcurrencyLimit`, legacy `parallel.concurrency`, and legacy `parallel.maxTasks` are 8; the 8-lane wave policy is advisory, and `globalConcurrencyLimit` does not itself throttle modern `runs.all`.

Turning the mode off restores the question tool to its prior active-tool position and injects a one-turn instruction that normal interactive behavior has resumed.

## Trust boundary

The signed control record authenticates parent-produced state and rejects ordinary corruption, forged markers, and revisions older than a child has already observed. The delegation policy and its limits are advisory coordination instructions, not a permission boundary or isolation from a malicious same-UID child: subagents that can run unrestricted shell commands can delete or withhold the shared file, alter inherited environment for processes they launch directly, or modify the extension itself. Use OS sandboxing or a Pi permission extension if hostile child code is in scope.

## Installation

`~/.pi/agent/settings.json` loads `./extensions/auto-mode`. Built-in pi-subagents agent overrides also include `~/.pi/agent/extensions/auto-mode/index.ts`, because subagents launch with ambient extensions disabled.

Custom/package/project agents that declare their own `extensions` bypass pi-subagents' `defaultExtensions`; add the Auto Mode path to that declaration or to an `agentOverrides.<name>.subagentOnlyExtensions` entry before relying on propagation.

The fresh `researcher` role explicitly loads Pi Lens only to register inherited Lens CLI flags. Its configured primitive task tools are exactly `read` and `web_run`; fresh resolution adds no `contact_supervisor`. Pi may also expose the composition-only `multi_tool_use.parallel` wrapper, which can invoke only tools already allowed by the role. The researcher does not load `pi-agent-browser-native` or expose `agent_browser` or `view_image`.

## Researcher web lane

`web_run` is a Nix-owned helper taken from the exact `@howaboua/pi-codex-conversion@3.0.23` npm tarball. The Pi wrapper and PI WEB service environment export `PI_CODEX_WEB_RUN_BIN`, so foreground Pi and its subagent children select the patched store helper without putting a store path in portable JSON. On Linux, Nix patches the selected native ELF against its declared OpenSSL, libgcc, and glibc libraries; it does not enable `nix-ld` or repair the mutable npm tree.

`researcher` is a stateless one-angle evidence lane. It batches 2–4 high-signal `search_query` entries in one `web_run` call, opens primary sources, cites final URLs, and returns compact evidence. It never falls back to browser, shell, curl, or search-engine form automation. After the first setup, native-helper, or provider failure, it stops and reports that failure rather than retrying into another surface.

### Smoke gate after activation/restart

After an activation, start a **fresh** Pi process so it inherits the wrapper environment; `/reload` alone does not replace an already-started process environment. Before high-fanout research, run `pi auth check --provider openai-codex`, then launch exactly one fresh `researcher` task that makes one batched `web_run.search_query` call against an official source. Accept the lane only when the child returns compact evidence with final official URLs, uses only `web_run` (and optional `read`) for task work, and has no `contact_supervisor`, bridge prompt, loader-recovery message, browser, or image capability. A reported `multi_tool_use.parallel` wrapper is harmless because it cannot widen the primitive allowlist. Stop rollout on the first startup, authentication, provider, or throttling failure; a direct helper probe is not a substitute for this child smoke gate.

After changing the extension in an already-running Pi process, use `/reload`. A new Pi process loads it automatically.

## Test

```bash
cd ~/.pi/agent/extensions/auto-mode
npm test
```
