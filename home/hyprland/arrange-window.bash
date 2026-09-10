#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s {left|right|up|down|maximize|center}\n' "${0##*/}" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
action=$1
case "$action" in
  left | right | up | down | maximize | center) ;;
  *) usage ;;
esac

active_window=$(hyprctl -j activewindow)
address=$(jq -r '.address // empty' <<<"$active_window")
monitor_id=$(jq -r '.monitor // empty' <<<"$active_window")

# A workspace with no focused window is a normal no-op.
[[ -n "$address" && -n "$monitor_id" ]] || exit 0

# Geometry dispatchers target a floating window. Clear any maximized/fullscreen
# state first so moving from one arrangement to another is deterministic.
hyprctl dispatch focuswindow "address:$address" >/dev/null
hyprctl dispatch fullscreenstate '0 0 set' >/dev/null
hyprctl dispatch setfloating "address:$address" >/dev/null

if [[ "$action" == center ]]; then
  hyprctl dispatch centerwindow 1 >/dev/null
  exit 0
fi

monitor=$(
  hyprctl -j monitors \
    | jq -cer --argjson monitor_id "$monitor_id" \
      '.[] | select(.id == $monitor_id)'
)

target=$(
  jq -er --arg action "$action" '
    (
      if ((.transform // 0) % 2) == 1 then
        { width: (.height / .scale), height: (.width / .scale) }
      else
        { width: (.width / .scale), height: (.height / .scale) }
      end
    ) as $screen
    | (.reserved // [0, 0, 0, 0]) as $reserved
    | (.x + $reserved[0]) as $x
    | (.y + $reserved[1]) as $y
    | ($screen.width - $reserved[0] - $reserved[2] | floor) as $width
    | ($screen.height - $reserved[1] - $reserved[3] | floor) as $height
    | ($width / 2 | floor) as $left_width
    | ($height / 2 | floor) as $top_height
    | if $action == "left" then
        [$x, $y, $left_width, $height]
      elif $action == "right" then
        [$x + $left_width, $y, $width - $left_width, $height]
      elif $action == "up" then
        [$x, $y, $width, $top_height]
      elif $action == "down" then
        [$x, $y + $top_height, $width, $height - $top_height]
      else
        [$x, $y, $width, $height]
      end
    | map(floor)
    | @tsv
  ' <<<"$monitor"
)

IFS=$'\t' read -r x y width height <<<"$target"
hyprctl dispatch resizewindowpixel "exact $width $height,address:$address" >/dev/null
hyprctl dispatch movewindowpixel "exact $x $y,address:$address" >/dev/null
