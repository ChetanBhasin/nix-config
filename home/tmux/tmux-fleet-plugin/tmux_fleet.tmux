#!/usr/bin/env sh

# The detached tmux client executes this helper in its own environment. A
# controller-managed client returns the sentinel; a normal client starts the controller.
tmux set-option -g 'command-alias[220]' 'tmux-fleet-switch=detach-client -E "@tmuxFleetSwitch@"'

# Fixed hook indexes make re-sourcing idempotent without disturbing other plugins.
tmux set-hook -g 'session-created[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'session-closed[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'session-renamed[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'client-attached[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'client-detached[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'client-session-changed[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'session-window-changed[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'window-linked[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
tmux set-hook -g 'window-unlinked[942]' "run-shell -b '@tmuxFleet@ notify >/dev/null 2>&1'"
