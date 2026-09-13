# Execution strategy substrate (v1)

Live Pi extension, not a scheduler, launcher, native runtime replacement or acceptance authority. `index.ts` registers **execution_strategy** and context/event policy. It never invokes `pi.exec`, a native tool's `execute`, RPC spawn, model/thinking setters, source writes, lease grants or workflow completion. Existing native `subagent`, writer leases, protected actions and workflow_contract remain authoritative.

## Profile integration (parent-owned)

The latest **current-branch** `pi-subagents-profile` custom entry must be `{version:1,name:"complex"}` (native `/subagents-profile` owns these entries). The extension reads `${getAgentDir()}/profiles/pi-subagents/<name>.json`, not settings and not a second strategy selector. Put metadata inside the existing profile's `subagents` object:

```json
{
  "subagents": {
    "agentOverrides": {},
    "executionStrategy": {
      "version": 1,
      "delegation": "proactive",
      "reviewers": ["reviewer"]
    }
  }
}
```

Recommended parent configuration: **simple → useful**, **complex → proactive**, **max → comprehensive**. All three support useful autonomous transfer, one writer, dependency barriers, comprehensive requirement/risk review and affected-only re-review. The metadata only changes guidance, not model/provider/thinking, lane quotas, model ceilings or review budgets. `reviewers` names the trusted *canonical native agent identities* allowed to provide independent coverage. Inspect native executable roles/configuration before choosing them; this field does not grant tools or create agents.

Unknown metadata keys, bad versions, missing files/metadata and malformed latest markers yield `effective:false` with an **ineffective configuration** reason. No inferred success or fallback to an older marker. Native overlay readiness and effective child model/config remain separate facts; planned profile metadata is not reported as actual launch configuration. Policy refreshes at start/reload, tree navigation, resources discovery, each tool event and each provider context; selection changes therefore apply before the next call. Genuine child markers (`PI_SUBAGENT_CHILD`, a foreign parent-session ID or nonzero/invalid depth) disable orchestration. Native permission forwarding that points to the current session itself does not demote the parent. Child planning/preparation and native launch/resume/project/schedule-start calls are rejected.

`../auto-mode/execution-strategy-handoff.ts` is imported directly. Owner async promotion works independently of `/auto`, only with effective metadata, and preserves explicit `async`. `prepare` translates `foregroundOnly:true` to supported `foregroundOnly:true, async:false`; conflicting async true fails. There is no availability toggle here. The guard classifies `execution_strategy` as pure session bookkeeping, not a source editor or real-interface acceptance receipt; unknown tools and source mutations still require ownership/permits.

## Tool API

All calls use the one session tool. Action-specific missing arguments throw native Pi tool errors. Root unknown fields are schema-rejected: there is **no packet, coverage, run-ID or artifact-path upload field**.

| Action | Arguments | Meaning |
|---|---|---|
| `status` | none | Policy, plan, attempts, actual config/unknowns, parent work/discovery, findings, review gaps. |
| `plan` | `plan` | Establish one workflow with stable IDs. |
| `extend` | `plan` | Same workflow/goal, **new** inputs/obligations/lanes only; cannot remove or redefine old obligations. |
| `prepare` | `lane`, optional `async`, `foregroundOnly` | Return exact `{attempt,tool:"subagent",input,snapshots}`. Does not launch or acquire a lease. |
| `cancel` | `attempt` | Cancel only an unused preparation. Native runtime owns live stop. |
| `consume` | `attempt` | Consume a successful authentic native child packet already observed by the extension. |
| `parent` | `lane`, `conclusion`, `evidence:string[]` | Parent integration attestation only; never independent review. |
| `input` | `input` (stable ID), `value` | Revise an existing declared contract/dependency/assumption value; invalidates dependents. |
| `gate` | none | Explicit `pass`, coverage and gaps, **always `workflowAcceptance:false`**. |

### Exact planning example

Replace the example absolute source path with the real source path before calling. Arrays are explicit (empty is allowed except where noted). Fields under `plan`:

```js
execution_strategy({
  action: "plan",
  plan: {
    workflow: "auth-refresh",
    goal: "Repair auth refresh and independently review it",
    inputs: [{id:"api",kind:"contract",paths:["/project/src/auth.ts"],value:"refresh-contract-v1"}],
    obligations: [
      {id:"refresh",kind:"requirement",description:"Refresh preserves the caller contract",scopes:["/project/src/auth.ts"],inputs:["api"],dependsOn:[]},
      {id:"race",kind:"risk",description:"Concurrent refresh cannot lose credentials",scopes:["/project/src/auth.ts"],inputs:["api"],dependsOn:[]}
    ],
    lanes: [
      {id:"implement",role:"writer",owner:"child",agent:"worker",access:"write",goal:"Repair auth refresh",constraints:["Do not stage or commit"],scopes:["/project/src/auth.ts"],dependsOn:[],obligations:["refresh","race"],inputs:["api"]},
      {id:"review",role:"reviewer",owner:"child",agent:"reviewer",access:"read",goal:"Independently review both requirement and race risk",constraints:["No edits"],scopes:["/project/src/auth.ts"],dependsOn:["implement"],obligations:["refresh","race"],inputs:["api"]}
    ]
  }
});
execution_strategy({action:"prepare",lane:"implement"});
```

Copy the returned **input object unchanged** into the normal model-visible `subagent` tool call. Its exact shape is `{workflowScript:'return runs.run("implement", {"agent":"worker","task":"<complete generated brief>"})',context:"fresh"}`; the actual returned string includes the unique attempt ID, scoped brief, snapshot hashes, evidence links and packet instructions. Do not truncate/reconstruct it, add strategy fields to native arguments, or launch from extension code. One preparation = one keyed native workflow/leaf. Independent lanes can be prepared/called concurrently as separate ordinary native tool calls. Dependency waves are deliberately separate: returned packets must be consumed before preparing their dependents.

```js
execution_strategy({action:"consume",attempt:"<exact returned attempt UUID>"});
execution_strategy({action:"prepare",lane:"review",async:false});
// Call native subagent with this new exact returned input, then consume its attempt.
execution_strategy({action:"gate"});
```

Roles: `discovery`, `writer`, `reviewer`, `integration`. Integration is always parent-owned; other roles are child-owned in normal use. Read-only reviewer/discovery lanes cannot declare writes. All lanes declare goal, constraints, absolute owned source scopes, explicit `dependsOn`, obligations and inputs. Inputs have stable ID, kind (`dependency|contract|assumption`), absolute file/directory paths and a nonempty value/revision (paths may be empty for semantic assumptions). Obligations have stable ID, kind (`requirement|risk`), description, nonempty source scopes, inputs and obligation dependencies. At least one requirement is required. Every write scope must be covered by an obligation.

Duplicate IDs, cycles, unknown references, unreviewed write scopes and unsafe overlapping scopes fail. Overlap involving a writer needs a dependency ordering; independent readers can overlap. At most one prepared/live child writer exists, even on disjoint paths. Preparing and observing a launch both recheck barriers; prepared snapshots/profile hashes cannot silently go stale. Dependencies require consumed successful, current packets (or explicit parent integration). The one-writer check is bookkeeping, not a cross-process lease substitute.

Paused, detached, stopping and identity/termination-uncertain attempts retain ownership. A tool failure alone does not prove the child process stopped. Later authoritative terminal reconciliation can settle the same attempt; do not launch a replacement writer while it remains uncertain.

## Compact packet schema and independent review

Child final output must contain exactly one `execution-packet` fenced JSON object, ≤128 KiB:

```json
{
  "version": 1,
  "attempt": "UUID from brief",
  "lane": "review",
  "role": "reviewer",
  "conclusion": "The scoped behavior is correct",
  "action": "Integrate",
  "decisions": [],
  "assumptions": [],
  "changes": [],
  "validation": ["Inspected the relevant paths"],
  "evidence": [{"id":"e1","link":"tool:actual-child-read-call-id","revision":"source revision","observation":"literal text in the successful child tool result"}],
  "blockers": [],
  "coverage": [{"obligation":"refresh","snapshot":"exact obligation hash from brief","verdict":"pass","evidence":["e1"]}],
  "findings": [],
  "resolutions": []
}
```

Coverage verdict is `pass|fail|partial`. Each finding is `{id,obligation,severity:"blocker|non-blocking",issue,evidence:[evidence IDs]}`. Its durable global ID becomes `<attempt>/<finding.id>`. Resolution: `{finding:<global ID>,evidence:[IDs],explanation}`. A resolution must come from an actual independent reviewer run with current passing coverage of that obligation and verified child-tool observations. Parent-authored findings/resolution uploads are not supported. Non-review packets cannot grant coverage or resolve review findings.

Verified findings from every packet role remain visible to the gate, including writer/discovery blockers. Native transcript evidence follows the persisted leaf's validated ancestry; abandoned sibling tool results cannot substantiate the selected branch's packet.

Evidence may retain `artifact:` and HTTP links for context, but **coverage/findings/resolutions require every cited evidence row to reference a successful actual native child `toolResult` and a literal matching observation**. The extension adds proof hashes/provenance. This prevents a parent's forged path/coverage claim or a reviewer's invented tool ID from passing. It does not semantically prove a reviewer's reasoning; a real independent reviewer still decides that. Reviewer role comes from the planned read-only role + profile-trusted canonical agent matched against the native returned child; run identity is taken from native keyed trace/result/status, never the packet. A known writer run cannot be counted as its reviewer.

Substantive inline `finalOutput`/`output` from correlated native results is preferred. Native file-only display references are not packets: use the verified child transcript, or its explicit native-owned regular output artifact (bounded to 128 KiB), never a pathname parsed from display text. For async projections lacking session/config fields, the extension reads only `status.json` beneath the **native-returned** async directory, validates exact parent-session/run identity, keyed child agent/run, and follows that verified child session locator. It does not accept a caller-supplied status or packet path. Missing metadata, output, transcript/tool evidence, malformed packets, failed children, stale snapshots or partial coverage remain explicit gaps. Merely pointing at a file never grants review.

`status`, `gate` and other tool calls reconcile recorded async status/child sessions to recover missed completion events (including reload). Foreground detachment uses the already-owned leaf ID for terminal-event correlation. At native launch the extension binds the actual runtime's exported foreground-history location; status exposes this native locator and its parent-session binding. Restoration checks that history's parent session, leaf ID, single-child identity, observed session path/launch digest and terminal exit evidence. A session path first supplied at exit may be learned from this verified history, but cannot replace an already observed identity. Reload deliberately drops stale runtime event routing; native wait returning nothing is not terminal proof. Missing or stale history retains the barrier, and terminal process evidence alone never supplies a valid packet or review. Foreground exit/history lacks final usage, which remains explicitly unknown. The strategy extension has no timers, scheduling, polling loops, detached writers or replacement launches. Unsupported native shapes fail closed with provenance gaps; use real native status/diagnostics and a fresh affected review, not a fabricated packet.

## Revision and dependency invalidation

Content hashes cover exact declared source trees (including additions/deletions, file modes and missing files), declared input paths/values, obligation dependencies and explicit lane dependency scopes/inputs. Changes are checked at prepare, launch, completion, consume and gate. Unrelated current coverage is retained. Broad declared dependencies conservatively invalidate their dependents; split obligations/lanes to express genuinely independent checks. `extend` cannot retire old obligations.

Reviewer source/input snapshots must stay stable while the reviewer runs; stale completion cannot be consumed. Later changes invalidate affected coverage without deleting audit history. Outstanding blockers remain open until an evidence-backed current resolution; an unrelated re-review does not resolve them. `gate` requires all declared requirements/risks to have current passing independent coverage, no unresolved blockers, completed/consumed latest lanes and no unresolved live/unknown attempts. It is not workflow completion.

A still-current resolution survives a later reviewer covering the same unchanged snapshot; repeating the resolution is unnecessary. Once its source/dependency/assumption snapshot becomes stale, the finding returns in the next assigned review brief and must receive fresh independent resolution evidence. The native logical-error repair retains original error details via a private per-runtime tool-call map and Pi's supported `tool_result` hook, preserving canonical error status without inventing identity or termination. Both root and child-safe native registrations use that boundary.

Hashing is fail-closed at 20,000 entries / 64 MiB per scope and rejects nested symlinks/special files; narrow declared scopes rather than hashing giant home/cache trees. These are resource safety limits, not review/lane budgets. Canonical root aliases are resolved; no gitignore exclusion silently omits source.

## Correlation, persistence and telemetry

- `tool_call` recognizes only the exact prepared workflow string + permitted native arguments. Calls with modified prepared payloads fail; unrelated launches are recorded **unowned**, not retroactively assigned.
- Native tool provenance is resolved from Pi `sourceInfo` to a `pi-subagents` package. A custom SDK tool merely named `subagent` does not receive independent-review authority.
- `tool_result` records receipt observation; `tool_execution_end` binds finalized native results/errors. Async completion/lifecycle events only attach to owned returned run IDs. Events alone cannot create ownership.
- Branch-local `execution-strategy:v1` custom entries store append/index patches, not repeated whole histories. Tree navigation replays only the selected branch. Different session IDs (including child forks) cannot inherit parent run ownership.
- SDK append exceptions latch **persistence uncertainty**, including telemetry exceptions. No later strategy mutation, native launch or passing gate is allowed until authoritative branch restoration. Append can persist before a subscriber throws; never retry the old live state. Deduplication hashes advance only after successful appends.
- `execution-strategy:telemetry:v1` records parent session, workflow, branch leaf, tool IDs, native workflow/child IDs, policy changes, lifecycle/failures, packet consumption and coverage changes. Status shows planned role/profile separately from native effective fields.
- Parent assistant usage has native-message provenance. Child usage has native-result provenance; missing model/thinking/usage/cost fields are `null` (unknown), never zero or borrowed from the parent. Verified status can supply effective child model/thinking/session; absent usage remains unknown. No fabricated sum of overlapping parent/child totals.
- Parent discovery tool calls record overlapping child scopes, including discovery before transfer. Shell/index-only unknown scopes remain unknown. Savings are always unmeasured (`null`); prepared plans or eventual children do not prove avoided duplicate work.
- Tool text is capped at 48 KiB/1,900 lines with an explicit truncation notice; complete data remains in native result details and branch entries.

Trust boundary: trusted installed Pi/extensions and native-owned metadata, not a sandbox against malicious same-UID code editing runtime files. Caller declarations still determine relevant scopes; guard policies must separately prevent undeclared writes. Packet evidence is structural/literal proof, not semantic review proof. Full native launch/runtime and profile integration acceptance remains with the parent.

## Validation

```sh
nix shell nixpkgs#typescript --command tsc --project ./tsconfig.json
JITI_FS_CACHE=false node --test ./tests/*.test.mjs
JITI_FS_CACHE=false node ./tests/sdk.mjs
```

SDK resolution defaults to the regular package under `~/.pi/agent/npm`; set `PI_SDK_ROOT` to the installed pi-coding-agent package root for another installation. No runtime npm dependency installation is needed by this extension: Pi supplies TypeBox/pi-ai/coding-agent imports; pure modules use Node built-ins.

Unit tests explicitly use **native-shaped fixtures**, not native delegation acceptance. The SDK test uses an actual isolated Pi `AgentSession.prompt`, native tool dispatch and deterministic provider; verifies success/error interface, malformed profile refresh, unchanged parent configuration, native telemetry and real post-persistence subscriber failures followed by authoritative disk restoration. It **does not launch any child** and is not full native delegation acceptance. Models, persisted test sessions, caches and evidence live only beneath `/tmp/execution-strategy-tests`; credentials are in memory, model network is disabled and `JITI_FS_CACHE=false`. The strict TypeScript project resolves the existing live `../../npm/node_modules` installation without installing or capturing dependencies.
