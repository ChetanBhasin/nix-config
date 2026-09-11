# Pi runtime repair validation

Validated on x86_64 Linux against Pi 0.84.4, 2026-09-10. Changes were made live under `~/.pi/agent`, then captured with `pi-config capture`. The existing Codex configuration and unrelated desktop changes were preserved. No CI/CD or sibling-repository implementation changes were made.

## Subsequent profile update — 2026-09-11

The Astra/max role baseline below is historical. The current live configuration selects **complex** from the new [simple/complex/max profiles](pi.md#subagent-profiles); the main model is unchanged. `max` preserves the user's later role tweaks rather than restoring the older universal Astra/max policy. The cleared oracle override resolves to builtin `high` in Pi Subagents 0.56.0.

Profile qualification uses `node home/pi/subagent-profiles-check.mjs`: actual native RPC/slash switching, fresh-process reloads, unchanged parent settings, missing-profile rejection, role model/fallback/inheritance policy and thinking ceilings. `PI_PROFILES_TEST_PARENT_MODEL=gpt-5.6-terra` covers a cheaper parent; `PI_PROFILES_CHECK_DEPLOYED=1` also checks active complex settings and the captured projection. These are offline checks using public cached model metadata and fixture-only auth, not billable task-quality or provider-access probes.

Independent review `a78d5091-ddba-40c8-8602-65fa48ed27f7` verified the genuine interface receipt and identified a test-only assumption that inheritance always meant an expensive parent. The assertion now uses an explicit Astra parent for forbidden inheritance and accepts allowed cheaper inheritance. Startup thinking is compared with the actual pre-switch state, including model presets.

Synchronization now includes `profiles/`. The focused Python run passed 14 tests, including profile capture/apply/deletion and symlink rejection; 30 unrelated launcher tests were skipped, not requalified. The new `pi-config` builds at `/nix/store/v6pb4akqs6w0hpkvkc9rxjbxjcsw2b2z-pi-config`. No host generation was activated or existing Pi session restarted for this profile update.

## Delivered

- **Startup and tools:** version/source-checked repairs for browser process discovery, standalone Web Run, Magic Context and subagents. The Nix launcher applies Lens policy to Pi's resolved extensions rather than guessing trust, and supports cold npm installation followed by strict repair before extension import. Private preload state does not leak into ordinary children.
- **Context:** Pi-native compaction owns the window; Magic Context retains memory, notes, branch-scoped search and raw history expansion. Legacy gaps and previous summaries survive recovery/compaction. Tool output has bounded previews backed by private lossless archives; deterministic failures get temporary retry guards, not disabled capabilities.
- **Autonomy:** substantive roles and the main default use Astra/max; delegates inherit the actual parent model/thinking. Lifetime spawn exhaustion is removed while simultaneous/per-run limits remain. The accepted requirement/evidence ledger, cooperative writer leases and bounded Auto Mode continuation preserve unfinished obligations and require real interface evidence.
- **Workflow resources:** `/mission`, `/implement-milestone`, `/experiment`, `/acceptance`, `/handoff`, `/artifact-audit`; six progressively disclosed skills for Jujutsu, Kraken experiments, tmux acceptance, browser evidence, cross-repository handoff and Nix validation. These recipes are opt-in, not permission to mutate sibling repositories or perform protected actions.

See [runtime support](../home/pi/config/extensions/runtime-reliability/README.md) and [the workflow protocol](../home/pi/config/extensions/auto-mode/WORKFLOW.md).

## Verification

| Gate | Result |
| --- | --- |
| Runtime repair/context/tool suite | 42 tests pass, including 10 real-loader bootstrap cases |
| Workflow suite | 42 tests pass; existing Auto Mode child-propagation/parent-contract checks also pass |
| Actual Pi runner/manual/automatic compaction | 33 tests pass against captured helpers |
| Launcher | 30 tests pass against both the launcher source and built Nix executable, using captured repair helpers |
| Prompt/skill discovery and expansion | 12 tests pass against captured files; fresh global RPC loads all 12 without command collisions |
| Pi configuration tests | 7 tests pass |
| Typechecking | Runtime extension project passes; Auto Mode source passes with third-party declaration rechecking excluded (`--skipLibCheck`) |
| Live Astra/max context gate | Legacy recovery, native compaction and restored recall pass |
| Live Astra/max workflow gate | Success/failure CLI journeys have checked evidence, independent replay and lease release |
| Capture | All portable entries compare equal against live state; transaction recovery backups retained |
| Nix | Boris system derivation evaluates; Pi and pi-config packages build; built Git-snapshot pi-config reports every portable entry equal to live state |

Live gate receipts remain local at `/tmp/pi-native-live-xue223/result.json` and `/tmp/pi-workflow-live-l6ehEF/result.json`. Test logs are `/tmp/pi-{runtime,workflow,native,launcher,config}-final-tests.log`; fresh RPC evidence is `/tmp/pi-workflow-recipes-rpc.jsonl`. These temporary artifacts may expire; the regression sources and explicit billable live-check scripts are captured. The cold-bootstrap independent review found no issues for Pi 0.84.4.

## Repeat the offline checks

From the repository root, after the live packages have been resolved/repaired:

```sh
raw=$(nix eval --raw .#nixosConfigurations.boris.config.home-manager.users.chetan.cb.pi.package.outPath)
wrapper=$(nix build --no-link --print-out-paths .#nixosConfigurations.boris.config.home-manager.users.chetan.programs.pi-coding-agent.package)
export PI_TEST_PACKAGE_DIR="$raw/lib/node_modules/pi-monorepo"

npm --prefix ~/.pi/agent/extensions/runtime-reliability test
npm --prefix ~/.pi/agent/extensions/auto-mode test
PI_NATIVE_CONTEXT_HELPERS_DIR="$PWD/home/pi/config/extensions/runtime-reliability" \
  node --test home/pi/native-auto-context-acceptance.test.mjs
PI_TEST_WRAPPER="$wrapper/bin/pi" \
  python3 -m unittest discover -s home/pi -p test_pi_launcher.py -v
node --test home/pi/workflow-resources.test.mjs
python3 -m unittest discover -s home/pi -p test_pi_config.py -q

nix shell nixpkgs#typescript --command tsc -p ~/.pi/agent/extensions/runtime-reliability
nix shell nixpkgs#typescript --command tsc -p ~/.pi/agent/extensions/auto-mode --skipLibCheck
PI_CONFIG_SNAPSHOT="$PWD/home/pi/config" python3 home/pi/pi_config.py status
```

The automatic-compaction test imports the manual suite; running that companion already covers both, without counting the manual tests twice. Launcher tests require `PI_TEST_PACKAGE_DIR`; do not count a skipped run as validation. The installed `pi-config status` compares the **embedded installed snapshot**, not the working tree; until activation it correctly reports old-generation drift.

## Deployment boundary and remaining limitations

- **Not activated on the host.** The tested launcher is `/nix/store/dwywh8kwvqls66r4lnw3189g8fqdy9fx-pi-coding-agent-policy-0.84.4/bin/pi`. The system still selects the previous launcher. Current Pi processes also retain boot-resolved settings. A safe host activation and fresh Pi process are required to deploy the launcher everywhere; no running sessions or databases were killed/deleted to force this boundary.
- A Pi package build and Boris derivation evaluation are not a full host build/activation. Darwin execution and live GUI/SSH/product workflows were not qualified by this Pi repair pass.
- The pre-import hook uses private Pi loader ordering. Requalify when changing the pinned core/package versions. It guards extension imports, **not npm lifecycle scripts**; offline installation fixtures explicitly disable those scripts.
- Writer/evidence controls are cooperative, not a sandbox. A command's claimed purpose is not proof of its effects, and no lease grants protected-action permission. Tool archives remain private data, not a universal secret-redaction guarantee.
- Lens reports no blocking errors, but retains inferred-project/dependency warnings on installed package sources and temporary probes. Explicit extension typechecks and real startup/regression checks are the authoritative evidence here. Boris evaluation emits two Nix string-context warnings (`options.json`, `append-initrd-secrets`), outside this Pi-focused repair.
- Dedicated cross-session efficiency analytics were not added. Runtime health, requirement/evidence state and bounded recovery are present; they are not a claim that every future autonomous task will finish without a real blocker.
