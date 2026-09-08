#!/usr/bin/env sh

# The detached tmux client executes this helper in its own environment. A
# controller-managed client returns the sentinel; a normal client starts the picker.
# Remove hooks installed by older watcher-based releases before setting the alias.
# Fixed indexes make this cleanup safe to repeat without touching other plugins.
tmux set-hook -gu 'session-created[942]'
tmux set-hook -gu 'session-closed[942]'
tmux set-hook -gu 'session-renamed[942]'
tmux set-hook -gu 'client-attached[942]'
tmux set-hook -gu 'client-detached[942]'
tmux set-hook -gu 'client-session-changed[942]'
tmux set-hook -gu 'session-window-changed[942]'
tmux set-hook -gu 'window-linked[942]'
tmux set-hook -gu 'window-unlinked[942]'


tmux set-option -g 'command-alias[220]' 'tmux-fleet-switch=detach-client -E "@tmuxFleetSwitch@"'
