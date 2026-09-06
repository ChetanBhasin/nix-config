# Runs inside a tmux popup created by the rename-*-popup command aliases.
set -uo pipefail

kind=${1:-}
pane=${2:-${TMUX_PANE:-}}

if [[ -z "$pane" ]]; then
  printf '\n  Could not determine the originating pane.\n\n  Press Enter to close.'
  IFS= read -r _
  exit 1
fi

case "$kind" in
  pane)
    noun="pane"
    target=$pane
    current=$(tmux display-message -p -t "$pane" '#{pane_title}')
    ;;
  window)
    noun="window"
    target=$(tmux display-message -p -t "$pane" '#{window_id}')
    current=$(tmux display-message -p -t "$pane" '#{window_name}')
    ;;
  session)
    noun="session"
    target=$(tmux display-message -p -t "$pane" '#{session_id}')
    current=$(tmux display-message -p -t "$pane" '#{session_name}')
    ;;
  *)
    printf '\n  Unknown rename target: %s\n\n  Press Enter to close.' "$kind"
    IFS= read -r _
    exit 1
    ;;
esac

printf '\n  Edit the %s name and press Enter.\n\n' "$noun"
if ! IFS= read -r -e -i "$current" -p '  › ' value; then
  printf '\n'
  exit 0
fi

[[ -n "$value" && "$value" != "$current" ]] || exit 0

case "$kind" in
  pane)
    rename_command=(tmux select-pane -t "$target" -T "$value")
    ;;
  window)
    rename_command=(tmux rename-window -t "$target" -- "$value")
    ;;
  session)
    rename_command=(tmux rename-session -t "$target" -- "$value")
    ;;
esac

if ! error=$("${rename_command[@]}" 2>&1); then
  printf '\n  %s\n\n  Press Enter to close.' "$error"
  IFS= read -r _
  exit 1
fi
