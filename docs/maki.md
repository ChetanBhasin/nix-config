# Maki Configuration Guide

[Maki](https://github.com/tontinton/maki) is a Rust TUI coding agent whose design goal is minimal context spend: a single binary, a small fixed prompt, and tools shaped so that what reaches the context window is what the turn actually needs.

Everything here is managed by `modules/homeManager/maki.nix` from the sources in `home/maki/config/`. See [modules.md](modules.md#homemanagermodulesmaki) for the option reference.

## What the configuration gives you

| Capability | How |
|---|---|
| Code intelligence | `index`: tree-sitter skeletons with exact line ranges, no LSP process |
| Anchored edits | `edit_lines` / `insert_lines` / `multiedit` against fresh line numbers |
| Data plumbing | `code_execution`: Python sandbox where every tool is an async function, so filtered output never enters the context window |
| Delegation | `task` tiers natively; named roles through the `roles` plugin |
| One-writer enforcement | a semaphore of one on the single writing role |
| Local code review | `rv` through a Lua plugin: a jj stack review as the agent's task list |
| Bash permissions | tree-sitter parse of the command, so `git diff && rm -rf /` requests `git *` **and** `rm *` |
| Runtime | Single Rust binary, ratatui TUI |

The trade is deliberate: no LSP layer and no workflow ledger. What there is instead is a much cheaper turn.

## First run

```sh
maki auth login openai   # ChatGPT subscription, via the Codex backend
export OPENROUTER_API_KEY=...        # optional, built-in provider
export HETZNER_INFERENCE_API_KEY=... # optional, declared in providers.toml
maki auth status
maki models              # every model the configured providers actually offer
maki                     # TUI
```

Then open `/model` once and assign tiers with `!` strong, `@` medium, `#` weak, `$` compaction. The suggested mapping:

| Tier | Model | Used for |
|---|---|---|
| strong | `openai/gpt-6-astra` | the parent session, `reviewer`, `oracle` and `worker` |
| medium | `openai/gpt-5.6-terra` | `scout` and the other discovery roles |
| weak | `openai/gpt-5.6-luna` | cheap lookups |
| compaction | `openai/gpt-5.6-luna` | summarizing is cheap work |

Tier assignments live in `~/.local/state/maki/model-tiers`, not in this flake, because they are per-machine.

Nothing restricts which models are selectable. An earlier revision of this config pinned a model list in `provider.allowed_models`, which was a mistake: in Maki that list is hard policy, not a picker convenience, and it also blocks delegation, `--model`, and any provider added later. Curate with tiers, which steer cost without locking the door; `provider.excluded_models` is there to ban something specific.

### Providers

| Provider | Setup | Notes |
|---|---|---|
| OpenAI | `maki auth login openai` | ChatGPT subscription via the Codex backend. `/model` lists what your plan actually offers, so a new release needs no config change |
| OpenRouter | `OPENROUTER_API_KEY` | Built in. 300+ models addressed as `openrouter/<vendor>/<model>`, e.g. `openrouter/anthropic/claude-sonnet-4` |
| Hetzner | `HETZNER_INFERENCE_API_KEY` | Declared in `home/maki/config/providers.toml`. Speaks plain OpenAI chat-completions, which is maki's `openai` protocol, so no compatibility flags are needed. `discover_models = true`, so the endpoint's own list is the authority |

`providers.toml` is seeded once and then yours, because `maki auth login` writes plan and base-URL choices back into it.

## What `init.lua` decides, and why

Every setting below is a deliberate choice rather than a default someone liked.

| Maki | Value | Why |
|---|---|---|
| `always_thinking` | `"max"` | Reasoning effort is worth more than it costs on this work; no picker interaction per session |
| `always_yolo` | `false` | Protected actions go through explicit permits; `permissions.toml` carries the allowlist instead |
| `always_workflow` | `false` | `code_execution` calling `task` is unbounded fan-out. Use `/workflow` per session |
| `ui.splash_animation` | `false` | Quiet startup: nothing between invocation and prompt |
| `ui.show_thinking` | `true` | Reasoning stays visible |
| `ui.theme` | `"gruvbox-night"` | The shared palette in `modules/theme/gruvbox-night.nix` |
| `agent.rtk` | `true` | `rtk` is on Maki's PATH through the module; it trims bash output before it is paid for |
| `agent.stale_read_check` | `true` | An anchored edit against a stale read lands silently in the wrong place |
| `agent.compaction_instructions` | requirements, commands, evidence, artifacts | Preserve mandatory requirements, including the failures and the missing evidence |
| `agent.post_compaction_instructions` | re-read instructions, re-`index` before acting | A summary is a lead, not authority over current source |
| `provider.default_model` | `openai/gpt-6-astra` | The strongest model on the subscription; the tier ladder demotes from there |
| `provider.allowed_models` | unset | see above; an allowlist here is policy, not curation |
| `provider.stream_timeout_secs` | `900` | Max-effort turns on astra outrun the 300s default |
| `plugins.bash.timeout_secs` | `600` | Nix evaluations and Bazel builds outrun the 120s default |
| `plugins.edit.insert_lines` | `true` | The `worker` role needs it; upstream leaves it opt-in |
| `agent.max_output_lines` | `3000` | Reviews and build logs run past the 2000 default |
| `plugins.index.max_file_size_mb` | `8` | Generated Rust and vendored TypeScript exceed the 2 MB default |
| `plugins.task.max_concurrent` | `8` | Keeps a fan-out legible and the bill bounded |
| `plugins.task.allow_model` | `false` | "Do not silently override configured models" — the tier ladder is the interface |
| `trust.prompt` / `trust.paths` | `true` / `{}` | Ask before trusting a project. A freshly cloned repo does not get to run its own `.maki/init.lua` |
| `telemetry.enabled` | `false` | No install telemetry |

### The bash guard

`init.lua` wraps the `tool.bash.input` slot and refuses seven commands outright: `git push --force`/`-f` (unless `--force-with-lease`), `git reset --hard`, `git clean -f`, `jj abandon`, `jj undo`, and `jj op restore`.

This is in Lua rather than in `permissions.toml` because permission scopes match a prefix. A deny on `git push --force*` catches `git push --force origin main` and misses `git push origin main --force`. The Lua layer splits each `;`/`&&`/`|` segment into words and checks them order-independently, so both forms are refused and the model reads *why* as the tool result.

It is a guard against an over-eager agent, not a security boundary. Permissions and folder trust are what gate the call. The layer costs the `run` capability, which is why `plugin.toml` grants it and revokes `fs_write`, `net` and `env`.

## Permissions

`~/.config/maki/permissions.toml` is seeded once and then belongs to you: pressing `A` in a permission prompt appends to it, and Home Manager will not overwrite an existing file. Delete it and re-activate to reset.

The seed allows read-only inspection (`rg`, `fd`, `jq`, `ast-grep`, `difft`, read-only `git`/`jj` subcommands) and the build loops worth not interrupting (`cargo`, `just`, `bazel`, `nix eval`/`build`/`flake check`). It denies host activation (`darwin-rebuild`, `nixos-rebuild`, `home-manager`), the irreversible ones (`rm -rf`, `sudo`, `diskutil`, `nix-collect-garbage`), and `tmux kill-server`.

Bare `make *` is deliberately not allowed. `make apply-darwin` shells out to `darwin-rebuild`, and a deny rule cannot see through a Makefile recipe, so only `make build-darwin` and `make build-nixos` are pre-approved.

A deny wins over every allow, over YOLO mode, and over a session grant. Nothing else in the file can undo one.

## Delegation roles

Maki's `task` tool already enforces most of what a role table would otherwise have to spell out. The write tools declare `audiences = { "main", "general_sub", "interpreter" }`, so a `research` subagent cannot see them — read-only enforcement, with no per-role tool allowlist to maintain. And `task` itself is `{ "main", "workflow" }`, so no subagent is offered it: one level of delegation is structural here, not configured.

What the tool cannot supply is the charter per role, and a model and effort to match. `home/maki/config/lua/roles.lua` adds a `role` tool with five:

| Role | Surface | Returns |
|---|---|---|
| `scout` | read-only | a map of unfamiliar code with file:line refs, not an opinion |
| `researcher` | `read` + `websearch` + `webfetch` only | one web question, citing final URLs |
| `reviewer` | read-only | located findings in a change, ranked; fixes nothing |
| `oracle` | read-only | challenges a decision already made, against supplied evidence |
| `worker` | full write access | the only writing role |

`worker` holds a semaphore of one, so two writers cannot overlap. The shape of the tool is the invariant — no lease, ledger, nonce or recovery path, because there is never a second writer to arbitrate with.

`/profile simple|complex|max` swaps the model and effort table each role gets. `max` is the default: strong reasoning roles at maximum effort, medium scouting. A profile entry may pin `spec` instead of `tier`, which is how a cheap role goes to another provider:

```lua
scout = { spec = "hetzner/Qwen3.8-27B", thinking = "high" }
```

`tier` is clamped to the parent's so a role cannot escalate cost on its own; `spec` is exact and deliberately escapes that clamp. `/roles` prints what the active profile gives each one.

Subagents spawned by `role` appear in `/tasks` (Ctrl-X) like any other: the chat window is created inside `maki.agent.session`, which `task` also calls, not by the `task` plugin.

## rv: the review as a task list

[rv](https://github.com/Firaenix/rv) reviews the jj stack on disk — before it is a pull request, or instead of ever becoming one. It is read-only on history (it never opens a jj transaction) and writes only `.review/` plus one line in `.git/info/exclude`.

`packages/rv.nix` builds the tagged release wrapped with `difftastic`, so the structural diff is always available rather than silently degrading. `home/maki/config/lua/rv.lua` is the plugin over its CLI, two tools dispatched on an `action` the way the builtin `memory` tool is:

| Tool | Actions | Wraps |
|---|---|---|
| `rv_review` | `status`, `comments`, `diff` | `rv status/comments/diff --json` |
| `rv_note` | `comment`, `reply`, `resolve`, `abandon` | the matching rv subcommands |

`/rv` flashes the range and counts without spending a turn.

Neither tool declares a permission scope, so neither prompts — the treatment `read` and `grep` get. That is deliberate for rv specifically: it cannot rewrite history, and settling is reversible, so the worst case is bookkeeping noise rather than lost work.

## Goal mode

`/goal <text>` keeps the agent working across turns until it calls the `goal_complete` tool, hits the budget ($2.00) or round cap (12), or the user intervenes — `/goal pause|resume|clear|status` from the menu, interrupting mid-turn, or cancelling the turn, which pauses the goal. While it runs, the status line shows round and spend, the objective is re-injected into every system prompt so it survives auto-compaction, and a reviewer vetoes the `question` tool, so the agent decides autonomously and notes its assumptions instead of asking. State persists as `goal.json` in Maki's state directory, and a restart restores the goal paused — it never resumes spending on its own.

`home/maki/config/lua/goal.lua` is vendored from [Firaenix/maki-plugins](https://github.com/Firaenix/maki-plugins), adapted to our fork's plugin-platform API in two places: cost tracking rides on the real `TurnEnd` autocmd (the upstream `TurnComplete` event does not exist), and the in-flight-queue check reads the `maki.session.read()` snapshot's `queue.count` instead of a `maki.session.queue()` function that does not exist. The plugin also registers the `goal_complete` tool, adding one small definition to every request while `cb.maki.enableGoal` is on — the same standing charge the table below describes.

Beyond the base grants, `home/maki/config/plugin.toml` gives it two more: `reviewers`, because registering the question-veto reviewer is an explicit grant, and `fs_write`, because `maki.fs.write` is guarded unconditionally — the state directory is not exempt by design. Toggled with `cb.maki.enableGoal`.

## What the plugins cost

Tool definitions are sent on every request, so a plugin is a standing charge whether or not it is used. Measured with `maki prompt --tools`, counting compact JSON at four bytes per token:

| | tokens/request |
|---|---|
| Baseline, 21 builtin tools | 5,177 |
| `role` | +336 |
| `rv_review` + `rv_note` | +573 |
| **Total, 24 tools** | **6,152 (+18.8%)** |

The first cut of rv was one tool per subcommand and cost **1,060** — six tools whose descriptions repeated the same range arguments. Collapsing to two action-dispatched tools removed 46% of that for no loss of function.

Registering rv only inside a jj workspace would remove the rest, and is not possible: Luau's sandbox has no synchronous filesystem access at load time. `maki.fs` is async and a loading plugin cannot yield, `io` is not exposed, and `os.rename` is stripped. `cb.maki.enableRv = false` is the lever for a machine that does not use jj.

Definition cost is not where the real spend is, though. Tool definitions sit at the front of the prompt, identical every turn, which is exactly what prompt caching covers: one cache write per session, then cache-rate reads. The standing cost that matters is **attention** — 24 tools instead of 21 is three more chances to reach for the wrong one, which is why maki keeps its own descriptions terse and defers MCP tools behind `tool_search`.

Where the tokens actually go is tool **output**, which is uncached, lands mid-conversation, and is re-sent on every subsequent turn. That is what the shaping in these plugins is for. `rv comments --json` carries a seven-line context array per finding; the plugin keeps the one line the comment is anchored to. On a single finding that is roughly 175 tokens of raw JSON against 30 of shaped text, and it compounds per finding and per turn thereafter. Running `rv ... --json` through `bash` instead would cost several times the plugin's entire standing charge within one review.

## Context layout

Maki charges for the system prompt on every request, so the long-form material is split by how often it is needed:

| Where | Content | Cost |
|---|---|---|
| `~/.config/maki/AGENTS.md` | ~45 lines: discovery funnel, one writer, evidence, delegation, VCS, scope | Every request |
| `~/.config/maki/skills/` | `jj-workflow`, plus the builtin `maki-plugin-dev` | One description line until loaded |
| `~/.config/maki/commands/` | `/user:mission`, `/user:implement`, `/user:accept`, `/user:handoff` | Nothing until typed |
| `memory` tool | Gotchas the agent learns, per project, under the state dir | Tag names only |

One dense block appended to every system prompt would dominate the fixed overhead the agent is built to minimize. The contract is delivered in stages instead: the part that governs every turn in `AGENTS.md`, and the rest behind a description line or a command name until it is actually wanted.

## Known rough edges

- `websearch` needs `EXA_API_KEY`. Without it, switch `plugins.websearch.provider` to `"youcom"`, whose free profile is keyless.
- `rv` needs a jj repository colocated with git (a top-level `.git/`), which is the default for `jj git init` since jj 0.44. Elsewhere `rv_review` and `rv_note` return rv's own error rather than guessing, and still cost their definitions — see [What the plugins cost](#what-the-plugins-cost).
- `role` and `task` both delegate, and both are in context. Replacing `task` outright would net −162 tokens per request and a better surface, but `/tasks` and Ctrl-X come from the bundled task plugin's `picker.lua`, so disabling it drops subagent visibility unless the roles plugin re-registers them. Set `plugins.task = { enabled = false }` in `init.lua` if you want to try it, and check `/tasks` still lists role subagents before keeping it.
- OSC 9 notifications need `set -g allow-passthrough all` in tmux. `home/tmux/tmux.conf` currently sets `on`, which drops the notification once you switch tmux windows — which is exactly when you wanted it.
- A local dev server is behind Maki's private-address guard. Add the exact host to `net.allowed_private_hosts` while you need it, and remove it after.
- `~/.maki/` is a legacy layout Maki prefers over `~/.config/maki`. Activation warns if it exists; run `maki migrate xdg` and remove it.
