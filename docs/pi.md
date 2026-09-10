# Pi Track B and Writable Runtime

This configuration installs vanilla Pi Coding Agent 0.84.3 with the Track B composition: Lens code intelligence, Hashline editing, isolated specialist subagents, parent-only Magic Context, native browser automation, Gruvbox Night, native model controls, and separately packaged PI WEB.

The ownership boundary is deliberate:

- **Nix owns executables and fixed policy:** Pi, Node.js, Git, `agent-browser` 0.34.0, ast-grep, Chrome/Chromium, FFmpeg (`ffmpeg` and `ffprobe`), the Nix-patched `web_run` from exact `@howaboua/pi-codex-conversion@3.0.23`, language servers, PI WEB 1.202608.2, wrappers, service definitions, and policy environment variables.
- **The portable projection owns reviewed Pi-native policy:** package pins, prompts, themes, extension policy, and the Codex extras-only configuration under `home/pi/config/`.
- **Pi and the user own mutable evidence:** authentication, trust decisions, sessions, package realizations, browser profiles, caches, indexes, embeddings, SQLite databases, and logs.

Home Manager keeps upstream Pi's live directory at `~/.pi/agent`. Its `settings`, `keybindings`, and `models` module values are empty and `context` is empty. Home Manager never projects those files as store symlinks and does not globally set `PI_CODING_AGENT_DIR` or `PI_CODING_AGENT_SESSION_DIR`. `pi-config` remains the copy-and-reconcile boundary. By default, activation only preflights Pi state; `cb.pi.forceApplyOnActivation` opts into a transactional, flake-authoritative copy after the write boundary. This repository enables that option in `home/pi/default.nix` for all three hosts.

The module exposes only these options:

| Option | Default | Purpose |
|--------|---------|---------|
| `cb.pi.enable` | `false` | Install Pi, Track B policy, and `pi-config` |
| `cb.pi.package` | pinned package | Select Pi; the current package is 0.84.3 |
| `cb.pi.forceApplyOnActivation` | `false` | Run `pi-config apply --force` after the Home Manager write boundary |
| `cb.pi.enableLspTooling` | `true` | Add the curated language-server toolchain to Pi's wrapper |
| `cb.pi.extraPackages` | `[]` | Add more tools to Pi and its shell environment |
| `cb.pi.enableWeb` | `false` | Enable Nix-managed PI WEB services |
| `cb.pi.webPackage` | pinned package | Select standalone PI WEB; currently 1.202608.2 |

The wrapper always includes Node.js, Git, agent-browser, ast-grep, FFmpeg (`ffmpeg` and `ffprobe`), and a Nix-owned browser executable. `ast-grep`, `agent-browser`, `ffmpeg`, `ffprobe`, Pi, and PI WEB are also available interactively after activation. Pi's package commands still realize pinned declarations into its writable npm tree; the mutable npm `.bin` directory is never added to global or service `PATH`.

Links into `/nix/store` created imperatively inside writable realization trees are not garbage-collection roots. Put required executables in `cb.pi.extraPackages` instead; the scoped link allowance keeps Pi-managed package/tool state writable but does not make ad hoc store paths durable.

## Track B policy

The portable package graph contains 13 exact npm pins. PI WEB is intentionally absent because Nix packages and services it independently. `@narumitw/pi-btw@0.55.3` replaces the former Juicesharp BTW package. `pi-footer@0.5.1` owns the statusline; Pi's extension loader supplies its coding-agent and TUI runtime imports from the Nix-owned Pi process, while the existing `@earendil-works/pi-tui@0.84.3` pin remains for Magic Context's peer dependency.

Runtime responsibilities are non-overlapping:

- **Lens** owns symbols, navigation, AST search, repository reports, and explicit diagnostics. Its install, context-injection, autoformat, autofix, read-guard, tests, and mutation hooks are disabled. The wrapper adds Lens-owned hard-disable flags only after the mutable Lens extension exists, so a fresh Pi installation can start before its npm tree is hydrated. It resolves only Nix-provided tools and language servers.
- **Hashline** replaces `read` and `grep`, disables built-in `edit`, and supplies anchored `replace`, `insert`, and undo. The built-in `write` remains available for whole-file creation/overwrite and Hashline returns fresh anchors afterward. Codex `apply_patch`/command adapters and Lens mutation tools remain inactive.
- **Codex conversion** is captured in `pi-codex-conversion.json` as extras-only. It supplies `web_run`, `view_image`, image generation, and voice; structured adapter mode, Code/Notebook Mode, `apply_patch`, heavy prompt replacement, and Responses compaction are disabled.
- **Magic Context** runs only in the parent. Its database, embeddings, model cache, and indexes stay local. Child processes receive `MAGIC_CONTEXT_PI_SUBAGENT=1` and explicit extension allowlists.
- **Subagents** start fresh by default, hand back files rather than transcripts, and allow one writer. The `fork-only` intercom bridge leaves fresh launches without a bridge prompt or `contact_supervisor`; their bounded contracts and file artifacts carry escalation blockers. Only the policy-permitted, actually forked `oracle` has supervisor dialogue when inherited conversation is necessary evidence. The modern workflow operational wave maximum is 8 lanes by advisory policy, with two top-level async slots, 16 per-run admissions, a configured per-session budget of 64, and depth 1. Spawn-budget grants require named necessary lanes and can raise the effective per-session maximum to 128; they do not raise the per-run or wave limits. Legacy concurrency is 8; `globalConcurrencyLimit=8` does not throttle modern `runs.all`. Role mapping is scout=Luna, researcher/worker=Terra, and reviewer/oracle=Sol.
- **Session coordinator** lets one idle long-lived (`tui`/`rpc`) Pi session queue `/after A B -- <prompt>` until exact, explicitly named independent sessions settle. It binds each name to one live instance and activity revision through a private local registry, requires a post-barrier heartbeat before trusting pre-existing settlement evidence, records `/tree` navigation as a new settled revision, and fails on duplicate live PID claims or lost bound processes. Release waits for the dependent session to become idle and for matching `before_agent_start` confirmation; synchronous or unconfirmed submissions remain available for `/after retry` or `/after cancel`. Bounded dependency text is labeled untrusted, incomplete model output is not marked completed, and barriers remain in memory until release/cancellation or waiting-session reload, switch, fork, or exit.
- **Browser automation** uses `pi-agent-browser-native` over exact `agent-browser` 0.34.0 and a Nix-owned Chrome/Chromium executable. It uses neither MCP nor a downloaded browser.
- **Footer** uses `pi-footer` with the checked-in `extensions/pi-footer.json` layout. It owns only Pi's footer, keeps the native header and editor, follows the active theme through Pi semantic colors, and leaves all extension statuses visible on a secondary row.

## Auto Mode

[Auto Mode](../home/pi/config/extensions/auto-mode/README.md) is off for every fresh top-level Pi process. Use `/auto`, `/auto on`, `/auto off`, and `/auto status` to control it.

`researcher` loads Lens only to register inherited Lens flags. Its configured primitive task-tool allowlist is exactly `read` and `web_run`; a fresh launch has no `contact_supervisor` or bridge prompt. Pi may also expose the composition-only `multi_tool_use.parallel` wrapper, which cannot invoke capabilities outside that primitive allowlist. The researcher deliberately has no `pi-agent-browser-native`, `agent_browser`, or `view_image` surface.

## Nix-owned `web_run`

`packages/pi-codex-web-run.nix` fetches the exact `@howaboua/pi-codex-conversion@3.0.23` npm tarball by fixed hash, chooses the matching Darwin/Linux and x86_64/aarch64 helper, and patches only the Linux ELF against declared OpenSSL, libgcc, and glibc libraries. It does not enable `nix-ld` or modify Pi's mutable npm realization. On a supported host, use `nix build .#piCodexWebRun` for a direct helper diagnostic.

Direct flake outputs cover `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. The derivation retains its `x86_64-darwin` binary mapping and metadata for a compatible Nixpkgs, but this flake's pinned Nixpkgs 26.11 deliberately omits that direct output because upstream dropped `x86_64-darwin` support.

The Pi wrapper and PI WEB service environment set `PI_CODEX_WEB_RUN_BIN` to that Nix-owned executable. Foreground Pi and Pi subagent children therefore inherit the same helper while portable JSON remains store-path-free. The normal `researcher` is a stateless one-angle lane: it batches 2–4 high-signal `search_query` entries in one `web_run` call, opens primary sources, cites final URLs, and returns compact evidence. It stops after the first setup, native-helper, or provider failure and never falls back to browser, shell, curl, or search-engine form automation. Browser and `view_image` portability are separate work; this change does not package or repair either one.

After activation, start a **fresh** Pi process before using the lane; `/reload` does not replace an already-started process environment. Before high-fanout research, first pass `pi auth check --provider openai-codex`, then run one fresh `researcher` child with a narrow task requiring one batched `web_run.search_query` call against an official source. Its artifact must contain final official URLs, use only `web_run` (and optional `read`) for task work, and show no `contact_supervisor`, bridge prompt, loader-recovery message, browser, or image capability. A reported `multi_tool_use.parallel` wrapper is harmless because it cannot widen the primitive allowlist. Stop rollout on the first startup, authentication, provider, or throttling failure. A direct helper probe alone is not an end-to-end child smoke test.

## Portable projection

The repository snapshot is `home/pi/config/`. It is an optional projection of Pi-native files, not a replacement agent directory:

```text
home/pi/config/
├── settings.json
├── keybindings.json
├── models.json
├── pi-codex-conversion.json
├── AGENTS.md
├── SYSTEM.md
├── APPEND_SYSTEM.md
├── extensions/
├── skills/
├── prompts/
└── themes/
```

Every listed entry is optional. `pi-config` ignores `.gitkeep` sentinels during comparison and preserves them during capture.

Only the listed names are synchronized. In particular, the projection excludes:

- authentication, credentials, trust decisions, and sessions;
- caches, logs, temporary files, and downloaded tools;
- generated global package trees such as `~/.pi/agent/npm/` and `~/.pi/agent/git/`;
- every project-local `.pi` tree; and
- `~/.agents/skills`.

Package declarations inside `settings.json` are portable and are captured. The generated `npm/` and `git/` contents that realize those declarations remain machine-local.

Portable settings and extension policy must not contain `/nix/store`. Generation-specific paths belong only in wrappers, package outputs, and service definitions. `pi-codex-conversion.json` contains policy and portable voice defaults; it contains no credentials, device path, native helper path, or store reference. Machine-specific audio setup must be reviewed before capture just like any other portable change.

Unmanaged files beside the projection in `~/.pi/agent` or `home/pi/config` are not removed. A deletion within the projection is meaningful, however: if a managed file or top-level managed directory was present in the baseline and is absent from the selected source, synchronization removes that managed target. Managed directories are replaced as whole directories so deleted or stale children cannot survive.

## Commands

Run Pi and `pi-config` as the ordinary user. Exit every Pi process before any synchronization command.

### `pi-config doctor`

`doctor` is read-only. It checks the existing hierarchy at `~/.pi` and `~/.pi/agent`, the current project's `.pi`, `~/.agents/skills`, `TMPDIR`, and the npm cache selected by npm configuration. Optional absent paths are accepted and are not created. Existing Pi, project, and global-skill paths must be owned by the current user and writable. Store links are accepted only for entries below the writable realization roots `~/.pi/agent/bin`, `~/.pi/agent/npm`, `~/.pi/agent/git`, and the current project's `.pi/npm` and `.pi/git`; those roots themselves must remain real directories. All other Pi and project paths linked into `/nix/store` are rejected.

It also reports `PI_CODING_AGENT_DIR`, because synchronization deliberately supports only Pi's default `~/.pi/agent` directory.

### `pi-config status`

`status` is read-only and prints two plans:

- `apply: flake -> runtime`, based primarily on `applied-base`; and
- `capture: runtime -> flake`, based primarily on `capture-base`.

The baselines are independent and live under `~/.local/state/pi-nix-sync/`. When an operation has no baseline for a path, it may use the other direction's baseline only if either the source or target still matches it. Consequently the apply and capture panels can legitimately classify the same path differently.

The command exits 0 when both plans are settled and 1 when a replacement or unresolved change exists.

### `pi-config diff`

`diff` is read-only and produces a normalized unified diff from the snapshot embedded in the installed `pi-config` package to `~/.pi/agent`. JSON object ordering and formatting do not create differences. Directory entries are represented by paths, content hashes, and executable-bit state. It exits 1 when the projections differ.

### `pi-config apply [--take-flake | --force]`

`apply` is the only operation that writes projection entries into `~/.pi/agent`. Its source is the snapshot embedded when the currently installed `pi-config` package was built, so rebuild the flake after recording a capture before applying it.

Without a conflict, a flake-only change is applied automatically. `--take-flake` resolves only two-sided conflicts, including an unsafe first run against a nonempty, differing runtime. It does not override an established runtime-only change; capture or otherwise reconcile that change first.

`--force` makes the embedded flake snapshot authoritative for every unequal managed path, including runtime-only changes, conflicts, first-run differences, and managed deletions. It cannot be combined with `--take-flake`. The normal lock, ownership, validation, transaction, and recovery-backup protections still apply; an already-settled forced apply does not create another backup.

### `pi-config capture [--take-runtime] [--flake-root PATH]`

`capture` writes only projection entries into the working tree's `home/pi/config`. It never commits, pushes, rebuilds, or activates the flake.

With no `--flake-root`, it searches the current directory and its parents for `home/pi/config`. `--flake-root PATH` selects the flake root explicitly. A runtime-only change is captured automatically. `--take-runtime` resolves only two-sided conflicts, including an unsafe first run against a nonempty, differing portable snapshot; it does not override an established flake-only change.

## Three-way synchronization

Each managed path is compared independently against the relevant baseline:

| Relationship to the baseline | State | `apply` behavior | `capture` behavior |
|------------------------------|-------|------------------|--------------------|
| Flake and runtime are equal | `equal` | Do not rewrite the runtime; advance `applied-base` | Do not rewrite the flake; advance `capture-base` |
| Only the flake changed | `flake-only` | Apply automatically | Refuse; the target has the one-sided change |
| Only the runtime changed | `runtime-only` | Refuse; the target has the one-sided change | Capture automatically |
| Both changed to the same result | `equal` | Do not rewrite; advance the baseline | Do not rewrite; advance the baseline |
| Both changed differently | `conflict` | Refuse unless `--take-flake` selects the flake | Refuse unless `--take-runtime` selects the runtime |

A refusal makes no managed mutation. The `--take-*` flags intentionally resolve conflicts only; they are not general force flags for overwriting an established opposite-direction one-sided change. `apply --force` is the explicit exception: it selects the flake for every unequal managed path.

First-run behavior is deliberately conservative:

- First apply to an empty runtime accepts the flake projection and creates `applied-base`.
- First capture into the empty initial projection accepts the runtime and creates `capture-base`.
- With no usable baseline and a nonempty, differing target, the difference is a conflict. Select the source explicitly with the direction's `--take-*` flag or synchronize in the other direction first.

Absence participates in the same matrix, so directional deletions are synchronized. Only the named projection is affected; machine-local files and directories remain untouched.

## Validation and transaction safety

All synchronization commands refuse to run while a directory whose name ends in `.lock` exists anywhere under `~/.pi/agent` or the current project's `.pi`. This applies to `status` and `diff` as well as mutations. Exit Pi before running them. Concurrent `pi-config` mutations are also rejected with a nonblocking CLI lock.

The four JSON files must contain JSON objects. Comparison and capture canonicalize their formatting:

- `settings.json` omits `lastChangelogVersion` and `trackingId` from comparison and capture. Apply replaces every portable setting from the flake while preserving the current runtime values of those two keys. If they are the only remaining settings, the runtime file is retained with just those values.
- `keybindings.json` is compared semantically and captured in canonical form.
- `models.json` is compared semantically and rejects literal values under sensitive API-key, token, authentication, authorization-header, cookie, and related fields. Exact environment references such as `$API_KEY` and `${API_KEY}` are allowed, as are command references beginning with `!`, such as `!security find-generic-password -w`.
- `pi-codex-conversion.json` is compared semantically and captured in canonical form.

Top-level managed files must be regular files, and managed directory trees may contain only real directories and regular files. Symlinks and special files are rejected rather than followed, preventing an escape from the projected tree. Executable bits are preserved in both directions, and installed content is made owner-writable.

Before changing a target, `pi-config` stages and validates the complete desired projection and baseline. It then creates a UTC-dated recovery backup under:

```text
~/.local/state/pi-nix-sync/backups/<timestamp>-<apply-or-capture>-<pid>/
```

The backup records the old versions of every target path being replaced, the old baseline, absent paths, and transaction metadata. The state directory also holds `applied-base/`, `capture-base/`, staging data, `cli.lock`, and the active `transaction.json` journal. Staged data, backups, the journal, installed targets, and baselines are flushed with `fsync`; an ordinary detected failure attempts to roll back the target and baseline and retains the recovery backup.

POSIX rename is atomic for one path, not for a group of managed paths plus a baseline. A crash or filesystem failure can therefore interrupt the multi-path transaction. If `~/.local/state/pi-nix-sync/transaction.json` remains, every synchronization command refuses to proceed; there is no automatic recovery command. Leave Pi stopped, inspect the journal and the referenced backup's `metadata.json`, restore or verify each recorded target path and baseline from that backup, and remove the journal only after the complete state is known to be consistent. Do not merely delete the journal to bypass the check; if the correct recovery is unclear, preserve the journal and backup for manual review.

## Home Manager activation

The module always adds a read-only check before Home Manager's write boundary. If `~/.pi` is absent, the Pi-state check succeeds without creating it; the independent legacy-link checks described below can still stop activation. If `~/.pi` exists, the preflight recursively rejects foreign-owned or unwritable Pi paths. It also rejects `/nix/store` links except for entries below Pi's writable `~/.pi/agent/bin`, `~/.pi/agent/npm`, and `~/.pi/agent/git` realization roots; the roots themselves must remain real directories. `pi-config doctor` performs the broader post-activation check that also covers project state, applies the same scoped policy to project `.pi/npm` and `.pi/git`, and checks global skills, temporary storage, and npm cache.

With `cb.pi.forceApplyOnActivation = false`, activation does not repair, copy, unlink, or delete anything beneath `~/.pi`. When the option is `true`, a second activation step runs `pi-config apply --force` after the write boundary. Home Manager dry-runs print that step without executing it. The repository's shared Pi configuration enables the option for `hugh`, `markus`, and `boris`.

The force step remains transactional: it preserves unmanaged paths and Pi's runtime-only settings keys, records a recovery backup when anything changes, and refuses unsafe ownership, symlinks, a pending journal, or any running Pi process. Exit Pi before activation. Capture runtime-managed edits first if they should survive; otherwise the flake snapshot, including managed absences, wins.

## Build, activate, and reload

Run the focused synchronization policy tests:

```sh
python3 -m unittest discover -s home/pi -p 'test_*.py' -v
```

Build before activation:

```sh
make build-darwin host=hugh
# or: make build-nixos host=boris
```

Apply from an ordinary interactive terminal so sudo/launchd integration can complete:

```sh
make apply-darwin host=hugh
# or: make apply-nixos host=boris
```

On this repository's hosts, activation force-applies the embedded snapshot after Home Manager's write boundary and before PI WEB service setup/reload; the same generation updates Nix packages and wrapper policy. Capture any runtime-managed edits that should survive before running `make apply-*`. External module consumers keep the safer `forceApplyOnActivation = false` default and can run `pi-config apply`, `pi-config apply --take-flake`, or `pi-config apply --force` explicitly.

With forced activation enabled, exit Pi before activation and start a fresh Pi process afterward. Magic Context deliberately refuses a schema migration while an older Pi PID still uses the shared database; do not kill an unrelated harness or bypass the guard. Exit the listed old process and retry `/ctx-status`.

## PI WEB

PI WEB is a standalone Nix package, not a Pi npm package. Its two user services are `com.pi-web.sessiond` and `com.pi-web.web` on Darwin, or `pi-web-sessiond.service` and `pi-web.service` on Linux. Fixed service policy is:

- bind `127.0.0.1:8504`;
- browser-created sessions and subsessions disabled;
- ask-user and environment-facts relays enabled;
- the same Nix-owned Pi, browser, agent-browser, ast-grep, FFmpeg, and LSP paths as the parent wrapper; and
- no mutable `~/.pi/agent/npm/node_modules/.bin` entry in `PATH`.

Upstream Relay auto-install is patched out because its bundled relative source would resolve into the current `/nix/store` generation and pollute portable Pi settings. Install any Relay implementation explicitly instead.

Operational checks:

```sh
pi-web status
pi-web doctor
curl -fsS http://127.0.0.1:8504/api/config | jq
pi-agent-browser-doctor
```

`pi-web install` reports the declarative service status; `pi-web uninstall` and `pi-web update` refuse because Home Manager/Nix owns those operations. Toggle `cb.pi.enableWeb` or update `packages/pi-web.nix`, then apply the configuration.

## Acceptance gate

After activation, synchronization, and reload, run:

```text
/lens-health
/subagents-doctor
/ctx-status
/footer
```

Then, outside Pi:

```sh
pi-agent-browser-doctor
pi-web doctor
pi-web status
pi-config doctor
pi-config status
pi-config diff
```

Expected invariants:

- Lens reports no pipeline crash and does not download tools or servers.
- Active mutation tools exclude built-in `edit`, Codex `apply_patch`/`exec_command`, Notebook Mode, and Lens `ast_grep_replace`; Hashline supplies anchored reads and edits.
- `/subagents-doctor` reports depth 1 policy, two top-level active async slots, 16 per-run admissions, a configured per-session budget of 64, legacy concurrency 8, and an advisory modern-workflow wave maximum of 8. Spawn-budget grants require named necessary lanes and can raise the effective per-session maximum to 128 without raising the per-run or wave limits. Role allowlists are scout=Luna, researcher/worker=Terra, and reviewer/oracle=Sol. `globalConcurrencyLimit=8` does not throttle modern `runs.all`.
- `/ctx-status` opens the production database at migration v81 after every old Pi harness has reloaded.
- `/footer` previews a one-line Nerd Font statusline with project and Git state on the left; model, thinking, context, and token usage on the right; and active extension statuses on a secondary row. Exit without saving unless intentionally changing the checked-in layout.
- browser doctor reports agent-browser 0.34.0 and the smoke test uses Nix Chrome/Chromium.
- PI WEB reports both services current and `/api/config` reports `spawnSessions=false`, `subsessions=false`, `askUser=true`, and `environmentFacts=true`.
- both `pi-config status` panels are `equal`, `pi-config diff` is empty, and neither portable source nor live portable settings contains `/nix/store`.

The Luna/Terra/Sol cycle is matched against authenticated available models. Until `pi auth check --provider openai-codex` is ready, Pi can list the extension-registered models but warns that the scoped patterns have no available matches. Authenticate before treating model acceptance as complete.

The current mutable npm tree reports five high-severity transitive advisories through Magic Context (`adm-zip`, `onnxruntime-node`, `sharp`, and `@huggingface/transformers`), with no npm fix available for the pinned graph. Keep the pins and reassess on package updates; do not run `npm audit fix --force` across Pi's managed tree.

## Rollback

Use normal Nix generation rollback for executables, wrappers, and services. For portable files, leave Pi stopped and restore the relevant UTC backup under `~/.local/state/pi-nix-sync/backups/`, or select a reviewed source through the three-way sync command. The latest apply prints its exact recovery directory.

Roll back one failing package/policy lane at a time. Do not delete Magic Context databases, Hashline anchors, browser profiles, authentication, or sessions as a first response. PI WEB logs live under `~/.pi-web/logs/`; Pi package realizations remain under `~/.pi/agent/npm/` and can be reconciled from the pinned `settings.json` after preserving user state.

No OMP configuration is imported. Any retained `~/.omp` tree is recovery material only.

## Project-local configuration and packages

Project `.pi` directories are intentionally outside global synchronization. Configure project resources and packages with Pi's normal commands, and record the resulting project `.pi` tree in that project's own repository when appropriate. `pi-config` only inspects the current project for writability and active `.lock` directories; it never captures or modifies the tree.

Global settings, credentials, trust decisions, sessions, package installations, extensions, resources, temporary state, and caches also remain writable through Pi's normal interfaces and default locations. Capture only when deliberately updating the portable projection. `~/.agents/skills` remains independently user-managed.

For Pi's upstream behavior, see the official documentation:

- [Settings](https://pi.dev/docs/latest/settings)
- [Packages](https://pi.dev/docs/latest/packages)
- [Environment variables](https://pi.dev/docs/latest/environment-variables)
