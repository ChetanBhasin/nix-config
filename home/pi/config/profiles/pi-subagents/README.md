# Subagent profiles

Use Pi's existing commands (no extra extension):

```text
/subagents-profiles
/subagents-load-profile simple
/subagents-models
```

Replace `simple` with `complex`, `max`, or any other saved profile name. Loading applies the profile to the current session branch in memory, records the choice in that branch, updates the footer, and never writes `settings.json`. Other sessions are unchanged, while reload/resume restores each branch's choice and already-running children retain their launch contracts. A markerless legacy session infers its current persisted profile once and records that migration. Decline **"Also switch this session to the profile worker model?"** to keep the main session unchanged.

## Tiers

| Role | simple | complex | max (persistent baseline) |
| --- | --- | --- | --- |
| delegate | Luna / low | Terra / high | Inherit parent model and thinking |
| scout | Luna / low | Terra / high | Terra / xhigh |
| researcher | Luna / low | Terra / high | Astra / max |
| worker | Terra / medium | Sol / high | Astra / xhigh |
| reviewer | Terra / medium | Sol / high | Astra / max |
| oracle | Terra / medium | Sol / high | Astra / high (builtin); explicit thinking override remains cleared |
| Thinking ceiling | medium | high | max |

All models use `openai-codex`. `max` is the preserved high-capability configuration, not a command to overwrite every personal thinking choice with `max`. Inspect the resolved roles after reload; in particular an unset thinking override still resolves through the installed builtin/default rules.

Thinking ceilings reject higher effort, including model suffixes such as `:max`. Strict global and per-role model allowlists reject out-of-profile overrides, inherited expensive models and fallbacks. They are budget controls, not model selectors or automatic downgrades. Trusted project settings can override global policy. Ask before escalating profiles; do not silently retry with a stronger model. The main session's model/thinking, concurrency limits and tool permissions are unchanged.

## Editing and portability

The native loader **replaces the entire `agentOverrides` mapping**. Each JSON therefore contains complete role definitions, including tools, extension providers, context, prompts and acceptance roles. It replaces the profile-owned defaults, thinking ceiling and model scope while retaining unrelated subagent settings.

Changes made through `/subagents` affect persistent defaults, not the saved profile JSON files or the current branch's selected in-memory profile. Reselect or reload that branch after updating a profile. Before switching, save any wanted role changes into the applicable profile(s), especially shared tools/prompts; otherwise selecting an older snapshot restores those older role fields. Model profiles do not follow later role edits automatically.

Change live files first, then `pi-config capture`. The updated sync helper manages `profiles/` alongside settings, extensions, skills, prompts and themes. Keep that tree portable: no credentials, dependencies or generated provider catalogs. The optional native catalog-generation commands write `providers/` here; do not run them in this managed tree unless you intend to review and capture their output. These hand-authored profiles need no generator or billable model probes.

Offline acceptance from the nix-config repository:

```sh
node home/pi/subagent-profiles-check.mjs
PI_PROFILES_CHECK_DEPLOYED=1 node home/pi/subagent-profiles-check.mjs
```

The second form also checks that persistent settings match the captured `max` baseline while all three profiles switch and reload session-locally without changing settings bytes. The check uses the installed Pi/subagent packages and public Codex metadata from `models-store.json`, isolated temporary settings and a fixture-only key. It never copies live credentials or asks a model to respond. It exercises native profile commands, in-session reloads, unchanged main-session settings, unknown-profile rejection, role resolution, forbidden model/fallback/inheritance and excessive-thinking rejection. It is not a throughput, billing, provider-authentication or task-quality benchmark.
