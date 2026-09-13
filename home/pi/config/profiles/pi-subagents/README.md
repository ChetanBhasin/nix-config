# Subagent profiles and execution strategy

Use the existing `/subagents-load-profile simple|complex|max` command, then inspect `/subagents-models`. There is no separate strategy selector. Selection is branch-local; reload, resume and tree navigation restore that branch's profile. Other sessions and already-running child contracts are unchanged. Profile commands never change the parent's provider, model or thinking and never offer a parent-model switch.

| Role | simple | complex | max (persistent baseline) |
| --- | --- | --- | --- |
| lookup | Terra / medium | Terra / medium | Terra / medium |
| delegate | Terra / medium | Terra / high | Astra / max |
| scout | Terra / medium | Terra / high | Terra / xhigh |
| researcher | Terra / medium | Terra / high | Astra / max |
| worker | Terra / medium | Sol / high | Astra / xhigh |
| reviewer | Terra / medium | Sol / high | Astra / max |
| oracle | Terra / medium | Sol / high | Astra / max |
| Delegation strategy | useful scoped transfer | proactive subsystem transfer | comprehensive risk-driven transfer/review |

All models use `openai-codex`. These are explicit capable defaults, not model/thinking ceilings, inheritance from the parent, lane quotas or review-effort budgets. Do not silently override the selected defaults or switch profiles after a provider failure. Diagnose failures and report real blockers.

`subagents.executionStrategy` is consumed by the live execution-strategy extension. It changes active context guidance and enables exact native launch preparation, dependency-aware ownership, authenticated packet consumption, revision-aware review gaps and linked telemetry. Simple keeps trivial work local; complex proactively separates discovery/implementation/review; max emphasizes comprehensive risk-driven depth. Every profile requires complete independent coverage, one writer and parent-owned integration. Native scheduling/permissions and workflow acceptance remain authoritative. Auto Mode changes user availability, not whether autonomous delegation works.

`lookup` is an executable read-only package agent from `extensions/lookup-role`, not merely an override entry. It retains pertinent project constraints and uses a narrow tool set/fresh context; it returns citations, assumptions and uncertainty. Other role definitions keep their existing tools and extension providers.

The native loader replaces the entire `agentOverrides` mapping. Shared builtin role settings therefore appear in each profile; lookup's full definition lives in its package. Changes through `/subagents` affect persistent defaults, not saved profile JSON or the selected branch overlay. Reselect the profile or reload after changing its file; reload after changing installed extension code. Markerless sessions infer and record the persisted profile once.

Change live files first, then validate and use `pi-config capture`. Keep credentials, sessions, provider catalogs, caches and dependencies outside the managed projection. Do not run native profile/catalog generation here unless its output is intentionally reviewed for capture.

Validation: `node home/pi/subagent-profiles-check.mjs` checks native offline selection/restoration and role resolution; `PI_PROFILES_CHECK_DEPLOYED=1` also checks captured equality. The execution-strategy `acceptance.mjs` journeys separately exercise actual native delegation/review/receipts. Offline deterministic fixtures do not establish provider authentication, billing, throughput or task quality; live lookup qualification is reported separately.
