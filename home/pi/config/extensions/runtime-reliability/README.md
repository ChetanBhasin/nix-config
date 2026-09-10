# Pi runtime reliability

Live-first compatibility support for the pinned Pi 0.84.4 stack. Make changes in `~/.pi/agent`, validate them, then use `pi-config capture` to preserve the portable configuration. Never edit captured configuration and force-apply it over uncaptured live changes.

## Startup and repairs

`patches.json` records exact package versions and before/after SHA-256 hashes. `patcher.mjs` preflights the whole manifest before writing anything, uses atomic per-file replacement, and accepts already-repaired files. Unknown versions, unknown source, incomplete package roots and ambiguous edits fail closed; they are not silently overwritten. Package upgrades require a compatibility review and updated regression evidence.

The Nix launcher uses two phases:

1. Before Pi starts, `--bootstrap` repairs installed packages and explicitly reports wholly absent package roots as deferred. A cold profile can therefore run `pi --version`, and normal Pi package resolution can perform first installation. A partial or dangling package root is not treated as an absent installation.
2. The private preload installs `bootstrap.mjs` on both Pi's source SDK and bundled CLI resource-loader classes. Strict repair runs after package resolution but before pre-trust extension import, and again before the final extension set loads. Reload follows the same gates. The selected bootstrap module must load successfully; losing it cannot silently remove the gate. Private preload variables are removed before ordinary child processes run.

`--check`, ordinary `--apply`, `/runtime-doctor`, and `runtime_health` remain strict. Older profiles without `bootstrap.mjs` retain their strict pre-launch check. Other launchers get an additional check from this extension, but only the repaired Nix launcher guarantees the pre-import boundary. This guards extension imports, not npm lifecycle scripts; the offline test fixtures explicitly disable those scripts. No extensions or capabilities are disabled to make startup pass.

```sh
cd ~/.pi/agent/extensions/runtime-reliability
node patcher.mjs --check
npm test
nix shell nixpkgs#typescript --command tsc --project .
```

`preflight.test.mjs` checks missing/partial/corrupt roots and all-or-nothing validation. `bootstrap.test.mjs` uses real source and bundled Pi resource loaders and offline npm installation from local tarballs; it covers cold/partial installs, pre-trust loading, reload and rejection before any unknown extension executes. `PI_TEST_PACKAGE_DIR` can select a specific installed Pi package. `home/pi/test_pi_launcher.py` additionally exercises the real Nix launcher through version and RPC startup; set `PI_TEST_RELIABILITY_DIR` to this live directory while testing before capture.

## Context and tool output

With `config.json` selecting `pi-native`, Pi owns compaction. The context bridge reconstructs legacy Magic Context gaps from branch-scoped raw history and consistent database snapshots, preserves earlier summaries across repeated compaction, and fails closed on incomplete recovery. Magic Context remains available for memory, notes, search and raw expansion, without a competing window manager. Native checkpoints and abandoned branches have separate recall boundaries.

Tool safety keeps bounded previews and private lossless archives, including giant single-line output. Identical deterministic failures receive a temporary retry guard rather than disabling the tool; successful repair or a new session resets it. These are reliability controls, not a security sandbox or a guarantee that arbitrary tool output contains no sensitive information. Treat archives as private session data.

The runtime tests cover these boundaries. Repository tests `home/pi/native-context-acceptance.test.mjs` and `home/pi/native-auto-context-acceptance.test.mjs` exercise Pi's real runner and manual/automatic compactor. `native-live-check.mjs` is explicit, **billable** Astra/max recovery qualification, not part of `npm test`.

Keep only portable source, configuration, tests and documentation in this directory. The capture includes descendants and rejects symlinks. Put logs, sessions, databases, dependency trees and generated artifacts outside it. Existing Pi processes retain their boot-resolved extensions/settings; validate changes in a fresh process. Building the launcher is not the same as activating it on the host.
