---
name: tmux-safe-acceptance
description: Use when validating tmux configuration, popups, fleet/SSH navigation, keybindings, pane layout or remote-session behavior without disturbing the user's live server.
---
# Safe tmux acceptance

- Read the current repository configuration and define the exact user key path and expected result before implementation. Use the existing project test tooling and [workflow evidence/ownership protocol](../../extensions/auto-mode/WORKFLOW.md).
- Create a uniquely named isolated `tmux -L <test-name>` server in temporary state. Direct every test command to that server. Do not run a bare `kill-server`, kill user panes, or reload the user's actual tmux configuration as a test side effect.
- Exercise the real key sequence, not only helper functions. For fleet/picker work, verify placement/centering at representative terminal sizes, focus, search input, shortcut conflicts, local session inventory, naming and return-to-origin behavior.
- Include spaces/punctuation in session names and missing/stale/disconnected targets. Check that popup height/width and selection remain usable, not just that a command exits successfully.
- A real remote-host claim requires an explicitly authorized reachable host and the actual SSH attachment/return path. Local fixtures do not prove remote topology. If no host is available, report remote acceptance as unverified; do not infer permission to discover/login to arbitrary hosts.
- Keep screenshots, captures and logs outside source roots, inspect them, and record server/socket identity plus the relevant revision. Retain only sanitized evidence.
- Clean up only the test server and resources this run owns, after its checks drain. Never use broad process matching or alter the production server to hide a failed isolated test.
- Distinguish implementation, isolated validation, remote qualification and deployment. Applying a new generation or reloading the live server is a separate authorized step.
