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
- Propagates the mode to new, resumed, steered, workflow, and nested Pi subagents without modifying pi-subagents `extensionBindings`.
- Publishes an Ed25519-signed, monotonic control record through an inherited environment descriptor and runtime control file, so already-running child agents observe `/auto on` and `/auto off` at their next extension event.
- Rejects tampered records and records older than the child's last authenticated revision, retaining that last state when the control file is unavailable.
- Keeps the existing model policy against purchases, production control, destructive/irreversible actions, and account/security/privacy changes. This is advisory for tools such as unrestricted `bash`; Auto Mode itself is not a sandbox or permission system.

Turning the mode off restores the question tool to its prior active-tool position and injects a one-turn instruction that normal interactive behavior has resumed.

## Trust boundary

The signed control record authenticates parent-produced state and rejects ordinary corruption, forged markers, and revisions older than a child has already observed. It is a coordination safeguard, not isolation from a malicious same-UID child: subagents that can run unrestricted shell commands can delete or withhold the shared file, alter inherited environment for processes they launch directly, or modify the extension itself. Use OS sandboxing or a Pi permission extension if hostile child code is in scope.

## Installation

`~/.pi/agent/settings.json` loads `./extensions/auto-mode`. Built-in pi-subagents agent overrides also include `~/.pi/agent/extensions/auto-mode/index.ts`, because subagents launch with ambient extensions disabled.

Custom/package/project agents that declare their own `extensions` bypass pi-subagents' `defaultExtensions`; add the Auto Mode path to that declaration or to an `agentOverrides.<name>.subagentOnlyExtensions` entry before relying on propagation.

After changing the extension in an already-running Pi process, use `/reload`. A new Pi process loads it automatically.

## Test

```bash
cd ~/.pi/agent/extensions/auto-mode
npm test
```
