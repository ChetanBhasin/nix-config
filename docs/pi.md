# Regular Pi and Writable Configuration

This configuration installs regular Pi Coding Agent 0.84.2 without making Pi's live state declarative. Nix owns the Pi binary, its wrapper toolchain, and the `pi-config` synchronization command. Pi and the user own every live path under `~/.pi`, every project-local `.pi` directory, and `~/.agents/skills`.

Home Manager runs Pi in package-only mode. Its `settings`, `keybindings`, and `models` values are empty, `context` is empty, and `configDir` is left at Pi's upstream default. It does not create, link, copy, delete, or redirect anything under those live paths, and it does not set `PI_CODING_AGENT_DIR` or `PI_CODING_AGENT_SESSION_DIR`.

The module exposes only these options:

| Option | Default | Purpose |
|--------|---------|---------|
| `cb.pi.enable` | `false` | Install regular Pi and `pi-config` |
| `cb.pi.package` | `pkgs.pi-coding-agent` | Select the Pi package; the current lock provides 0.84.2 |
| `cb.pi.enableLspTooling` | `true` | Add the curated language-server toolchain to Pi's wrapper |
| `cb.pi.extraPackages` | `[]` | Add more tools to Pi and its shell environment |

The wrapper always includes Node.js and Git. Pi's own configuration and package commands continue to operate against its normal writable locations. Pi binary upgrades happen through the flake.

## Portable projection

The repository snapshot is `home/pi/config/`. It is an optional projection of Pi-native files, not a replacement agent directory:

```text
home/pi/config/
├── settings.json
├── keybindings.json
├── models.json
├── AGENTS.md
├── SYSTEM.md
├── APPEND_SYSTEM.md
├── extensions/
├── skills/
├── prompts/
└── themes/
```

Every listed entry is optional. The initial snapshot contains only `.gitkeep`; `pi-config` ignores that sentinel during comparison and preserves it during capture.

Only the listed names are synchronized. In particular, the projection excludes:

- authentication, credentials, trust decisions, and sessions;
- caches, logs, temporary files, and downloaded tools;
- generated global package trees such as `~/.pi/agent/npm/` and `~/.pi/agent/git/`;
- every project-local `.pi` tree; and
- `~/.agents/skills`.

Package declarations inside `settings.json` are portable and are captured. The generated `npm/` and `git/` contents that realize those declarations remain machine-local.

Unmanaged files beside the projection in `~/.pi/agent` or `home/pi/config` are not removed. A deletion within the projection is meaningful, however: if a managed file or top-level managed directory was present in the baseline and is absent from the selected source, synchronization removes that managed target. Managed directories are replaced as whole directories so deleted or stale children cannot survive.

## Commands

Run Pi and `pi-config` as the ordinary user. Exit every Pi process before any synchronization command.

### `pi-config doctor`

`doctor` is read-only. It checks the existing hierarchy at `~/.pi` and `~/.pi/agent`, the current project's `.pi`, `~/.agents/skills`, `TMPDIR`, and the npm cache selected by npm configuration. Optional absent paths are accepted and are not created. Existing Pi, project, and global-skill paths must be owned by the current user and writable; managed paths linked into `/nix/store` are rejected.

It also reports `PI_CODING_AGENT_DIR`, because synchronization deliberately supports only Pi's default `~/.pi/agent` directory.

### `pi-config status`

`status` is read-only and prints two plans:

- `apply: flake -> runtime`, based primarily on `applied-base`; and
- `capture: runtime -> flake`, based primarily on `capture-base`.

The baselines are independent and live under `~/.local/state/pi-nix-sync/`. When an operation has no baseline for a path, it may use the other direction's baseline only if either the source or target still matches it. Consequently the apply and capture panels can legitimately classify the same path differently.

The command exits 0 when both plans are settled and 1 when a replacement or unresolved change exists.

### `pi-config diff`

`diff` is read-only and produces a normalized unified diff from the snapshot embedded in the installed `pi-config` package to `~/.pi/agent`. JSON object ordering and formatting do not create differences. Directory entries are represented by paths, content hashes, and executable-bit state. It exits 1 when the projections differ.

### `pi-config apply [--take-flake]`

`apply` is the only operation that writes projection entries into `~/.pi/agent`. Its source is the snapshot embedded when the currently installed `pi-config` package was built, so rebuild the flake after recording a capture before applying it.

Without a conflict, a flake-only change is applied automatically. `--take-flake` resolves only two-sided conflicts, including an unsafe first run against a nonempty, differing runtime. It does not override an established runtime-only change; capture or otherwise reconcile that change first.

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

A refusal makes no managed mutation. The `--take-*` flags intentionally resolve conflicts only; they are not general force flags for overwriting an established opposite-direction one-sided change.

First-run behavior is deliberately conservative:

- First apply to an empty runtime accepts the flake projection and creates `applied-base`.
- First capture into the empty initial projection accepts the runtime and creates `capture-base`.
- With no usable baseline and a nonempty, differing target, the difference is a conflict. Select the source explicitly with the direction's `--take-*` flag or synchronize in the other direction first.

Absence participates in the same matrix, so directional deletions are synchronized. Only the named projection is affected; machine-local files and directories remain untouched.

## Validation and transaction safety

All synchronization commands refuse to run while a directory whose name ends in `.lock` exists anywhere under `~/.pi/agent` or the current project's `.pi`. This applies to `status` and `diff` as well as mutations. Exit Pi before running them. Concurrent `pi-config` mutations are also rejected with a nonblocking CLI lock.

The three JSON files must contain JSON objects. Comparison and capture canonicalize their formatting:

- `settings.json` omits `lastChangelogVersion` and `trackingId` from comparison and capture. Apply replaces every portable setting from the flake while preserving the current runtime values of those two keys. If they are the only remaining settings, the runtime file is retained with just those values.
- `keybindings.json` is compared semantically and captured in canonical form.
- `models.json` is compared semantically and rejects literal values under sensitive API-key, token, authentication, authorization-header, cookie, and related fields. Exact environment references such as `$API_KEY` and `${API_KEY}` are allowed, as are command references beginning with `!`, such as `!security find-generic-password -w`.

Top-level managed files must be regular files, and managed directory trees may contain only real directories and regular files. Symlinks and special files are rejected rather than followed, preventing an escape from the projected tree. Executable bits are preserved in both directions, and installed content is made owner-writable.

Before changing a target, `pi-config` stages and validates the complete desired projection and baseline. It then creates a UTC-dated recovery backup under:

```text
~/.local/state/pi-nix-sync/backups/<timestamp>-<apply-or-capture>-<pid>/
```

The backup records the old versions of every target path being replaced, the old baseline, absent paths, and transaction metadata. The state directory also holds `applied-base/`, `capture-base/`, staging data, `cli.lock`, and the active `transaction.json` journal. Staged data, backups, the journal, installed targets, and baselines are flushed with `fsync`; an ordinary detected failure attempts to roll back the target and baseline and retains the recovery backup.

POSIX rename is atomic for one path, not for a group of managed paths plus a baseline. A crash or filesystem failure can therefore interrupt the multi-path transaction. If `~/.local/state/pi-nix-sync/transaction.json` remains, every synchronization command refuses to proceed; there is no automatic recovery command. Leave Pi stopped, inspect the journal and the referenced backup's `metadata.json`, restore or verify each recorded target path and baseline from that backup, and remove the journal only after the complete state is known to be consistent. Do not merely delete the journal to bypass the check; if the correct recovery is unclear, preserve the journal and backup for manual review.

## Home Manager activation preflight

The module adds one read-only check before Home Manager's write boundary. If `~/.pi` is absent, the Pi-state check succeeds without creating it; the independent legacy-link checks described below can still stop activation. If `~/.pi` exists, the preflight recursively rejects foreign-owned, unwritable, or `/nix/store`-linked Pi paths and prints remediation. Repeated activation does not create or change anything beneath `~/.pi`.

This preflight reads live state but does not repair, copy, unlink, or delete it. `pi-config doctor` performs the broader post-activation check that also covers project state, global skills, temporary storage, and npm cache.

## Migration from OMP

No OMP settings, instructions, theme, approvals, credentials, or other configuration are imported into Pi. The existing `~/.omp` tree is retained as recovery material.

At the time this migration change was prepared, no new Home Manager generation had been activated. On the current machine, `~/.pi` was still owned by `root:staff`, so the first new activation is expected to stop in the read-only preflight. It prints this narrowly scoped ownership repair:

```sh
sudo chown -R "$(id -un):$(id -gn)" "$HOME/.pi"
```

Run that command manually. It changes ownership without replacing the existing Pi settings, authentication, or session files.

The same preflight also stops because the previous Home Manager generation still owns three OMP store links that would otherwise be removed:

```text
~/.omp/agent/APPEND_SYSTEM.md
~/.omp/agent/lsp.json
~/.omp/agent/themes/gruvbox-night.json
```

For each path, follow the complete `dereference manually: ...` command emitted by the preflight. Each emitted command uses `mktemp` beside that exact file, `cp -pL` to copy the linked content and metadata, and `mv` to replace only that link with the ordinary file. This is a manual content-preservation step; Home Manager does not copy or delete these files for the migration. The preserved OMP files remain under `~/.omp` and are not imported into Pi.

After the ownership repair, all three dereferences, and a successful activation, use this workflow exactly:

```sh
pi-config doctor
pi
pi-config capture --flake-root "$(jj root)"
jj diff -- home/pi/config
jj status
```

The first capture sees the `.gitkeep`-only portable snapshot as empty and accepts the current Pi runtime as its baseline. Review and record the captured files through the normal `jj` workflow, rebuild the flake so the installed `pi-config` embeds that snapshot, and run `pi-config apply` on other machines.

A first apply to a machine with an empty Pi projection is safe. A first apply to a machine with differing existing Pi configuration refuses until that machine's runtime is captured or the user explicitly selects `pi-config apply --take-flake` for the first-run conflict.

## Project-local configuration and packages

Project `.pi` directories are intentionally outside global synchronization. Configure project resources and packages with Pi's normal commands, and record the resulting project `.pi` tree in that project's own repository when appropriate. `pi-config` only inspects the current project for writability and active `.lock` directories; it never captures or modifies the tree.

Global settings, credentials, trust decisions, sessions, package installations, extensions, resources, temporary state, and caches also remain writable through Pi's normal interfaces and default locations. Capture only when deliberately updating the portable projection. `~/.agents/skills` remains independently user-managed.

For Pi's upstream behavior, see the official documentation:

- [Settings](https://pi.dev/docs/latest/settings)
- [Packages](https://pi.dev/docs/latest/packages)
- [Environment variables](https://pi.dev/docs/latest/environment-variables)
