#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d "$repo_root/home/tmux/.tmp-shift-return.XXXXXX")
declare -a sockets=()
cleanup() {
  local socket
  for socket in "${sockets[@]}"; do
    [[ $socket == "$tmp/"* ]] || continue
    tmux -S "$socket" kill-server 2>/dev/null || true
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

tmux_config="$repo_root/home/tmux/tmux.conf"
for directive in \
  'set-option -g default-terminal "tmux-256color"' \
  "set -g terminal-features[100] 'alacritty*:RGB:clipboard:extkeys:focus:title'" \
  'set-option -s escape-time 50' \
  'set -s extended-keys on' \
  'set -s extended-keys-format csi-u'
do
  grep -Fqx "$directive" "$tmux_config" || {
    printf 'Missing tmux transport directive: %s\n' "$directive" >&2
    exit 1
  }
done

cat >"$tmp/tmux.conf" <<'TMUX'
set-option -g default-terminal "tmux-256color"
set -g status off
set -g terminal-features[100] 'alacritty*:RGB:clipboard:extkeys:focus:title'
set-option -s escape-time 50
set -s extended-keys on
set -s extended-keys-format csi-u
TMUX

cat >"$tmp/capture.py" <<'PY'
import os
import pathlib
import sys
import termios
import tty

output = pathlib.Path(sys.argv[1])
old = termios.tcgetattr(0)
try:
    tty.setraw(0)
    os.write(1, b"\x1b[>4;2m")
    output.with_suffix(".ready").write_text("ready")
    output.write_bytes(os.read(0, 32))
finally:
    termios.tcsetattr(0, termios.TCSADRAIN, old)
PY

cat >"$tmp/client.py" <<'PY'
import os
import pathlib
import pty
import sys
import time

socket, target, output, payload_hex = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, TERM="alacritty")
    env.pop("TMUX", None)
    os.execvpe("tmux", ["tmux", "-S", socket, "attach-session", "-t", target], env)

os.set_blocking(fd, False)
transcript = bytearray()
ready_deadline = time.monotonic() + 1
while time.monotonic() < ready_deadline:
    try:
        transcript.extend(os.read(fd, 65536))
    except BlockingIOError:
        pass
    child, status = os.waitpid(pid, os.WNOHANG)
    if child:
        raise SystemExit(f"tmux client exited before input ({status}): {transcript!r}")
    time.sleep(0.05)

terminal_replies = (
    b"\x1b[?62;4c"
    b"\x1b[>0;15;0c"
    b"\x1bP>|Alacritty 0.15.1\x1b\\"
    b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"
    b"\x1b]11;rgb:0000/0000/0000\x1b\\"
    b"\x1b[?997;1n"
)
os.write(fd, terminal_replies)
time.sleep(5.5)
try:
    transcript.extend(os.read(fd, 65536))
except BlockingIOError:
    pass

os.write(fd, bytes.fromhex(payload_hex))
path = pathlib.Path(output)
deadline = time.monotonic() + 5
while time.monotonic() < deadline and not path.exists():
    time.sleep(0.05)
if not path.exists():
    try:
        transcript.extend(os.read(fd, 65536))
    except BlockingIOError:
        pass
    raise SystemExit(f"capture timed out; tmux client output={transcript!r}")
os.waitpid(pid, 0)
PY

run_case() {
  local name=$1
  local payload=$2
  local expected=$3
  local depth=$4
  local case_dir="$tmp/$name"
  local outer_socket="$case_dir/outer.sock"
  local captured="$case_dir/captured.bin"
  local capture_cmd
  mkdir -p "$case_dir"
  sockets+=("$outer_socket")
  capture_cmd="python3 '$tmp/capture.py' '$captured'"

  if [[ $depth == nested ]]; then
    local inner_socket="$case_dir/inner.sock"
    local inner_attach
    sockets+=("$inner_socket")
    env -u TMUX tmux -S "$inner_socket" -f "$tmp/tmux.conf" \
      new-session -d -s inner "$capture_cmd"
    inner_attach="env -u TMUX tmux -S '$inner_socket' attach-session -t inner"
    env -u TMUX tmux -S "$outer_socket" -f "$tmp/tmux.conf" \
      new-session -d -s outer "$inner_attach"
  else
    env -u TMUX tmux -S "$outer_socket" -f "$tmp/tmux.conf" \
      new-session -d -s outer "$capture_cmd"
  fi

  python3 "$tmp/client.py" "$outer_socket" outer "$captured" "$payload"
  local actual
  actual=$(od -An -tx1 -v "$captured" | tr -d ' \n')
  if [[ $actual != "$expected" ]]; then
    printf '%s transport mismatch: expected=%s actual=%s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
  printf '%s: sent=%s received=%s\n' "$name" "$payload" "$actual"
}

run_case plain-return 0d 0d single
run_case shift-single 1b5b31333b3275 1b5b31333b3275 single
run_case shift-nested 1b5b31333b3275 1b5b31333b3275 nested
printf 'Shift+Return transport acceptance passed\n'
