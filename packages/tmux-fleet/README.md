# tmux-fleet

`tmux-fleet` presents local and SSH-hosted tmux sessions in one FZF picker. It
switches the terminal between tmux clients instead of nesting one tmux client
inside another, so there is one prefix and one status bar at a time.

The implementation is portable across nix-darwin and NixOS. It deliberately
uses the system OpenSSH client rather than an embedded SSH library, preserving
normal `ssh_config`, `ProxyJump`, host-key verification, agents, hardware keys,
and interactive key-unlock behavior.

## Home Manager setup

Enable the exported tmux module on every participating host and list only the
other hosts by their OpenSSH aliases:

```nix
{
  imports = [ cb-config.homeManagerModules.tmux ];

  cb.tmux = {
    enable = true;
    fleet = {
      enable = true;
      remoteHosts = [ "workstation" "server" ];
    };
  };
}
```

Each alias must work with ordinary OpenSSH and resolve to a machine that also
has this module enabled. Home Manager installs the controller, plugin, FZF,
configuration, and a stable remote helper at
`~/.local/libexec/tmux-fleet`.

The repository's own hosts are configured as peers:

- Hugh: Markus and Boris
- Markus: Hugh and Boris
- Boris: Hugh and Markus

## Using the picker

1. Attach to tmux normally.
2. Press `Prefix s` (`C-Space s` with the default prefix).
3. Choose a local session, remote session, new-session action, or reconnect
   action.

`Prefix s` replaces an ordinary tmux client with `tmux-fleet run`. After the
controller attaches a managed client, pressing `Prefix s` again returns exit
code 42 to that same controller and reopens its picker. This is a client-side
handoff; no tmux server is stopped or replaced.

A normal tmux detach (`Prefix d`) exits the managed client with status 0 and
returns to the shell instead of reopening the picker. A stale session identity
returns to the picker with the previous query selected rather than attaching a
new session that happens to reuse a display name.

Running `tmux-fleet` or `tmux-fleet run` directly from a terminal opens the same
controller. `tmux-fleet snapshot` prints the current local snapshot for
troubleshooting. The hidden `watch`, `notify`, and `attach` commands are plugin
and SSH protocol helpers, not normal user entry points.

## Architecture

- The controller owns FZF, local and remote watcher workers, active tmux/SSH
  children, and the in-memory model.
- A watcher sends an initial snapshot, receives Unix-datagram invalidations
  from indexed tmux hooks, emits heartbeats, and performs a slow reconciliation
  snapshot to recover from missed hooks.
- Hooks cover session create/close/rename, client attach/detach/session changes,
  selected-window changes, and window link/unlink events. Watchers are ordinary
  command processes, not attached tmux control-mode clients, so they do not
  alter `session_attached` or interfere with `destroy-unattached` policies.
- Each remote alias has a supervised noninteractive OpenSSH watcher. Accepted
  events are bounded and coalesced per host; malformed or silent streams are
  disconnected and retried with backoff.
- The picker starts from local state and the last accepted per-host disk cache.
  FZF reloads from the in-memory model when watcher events arrive.
- Before attaching an existing session, one tmux command atomically verifies
  the server generation, session ID, and session creation time. Remote identity
  fields and new-session names are hex encoded across the remote shell boundary.

The controller does not open a public listener, forward an SSH agent, implement
SSH itself, or use tmux control mode.

## Offline hosts and authentication

Background discovery is intentionally noninteractive:

- `BatchMode=yes`
- public-key authentication only
- agent forwarding disabled
- bounded connect attempts and server-alive checks
- one per-alias ControlMaster path in the private runtime directory

When a watcher disconnects, its last accepted sessions remain visible as stale
cache entries. Choose **Reconnect** to leave FZF and run foreground OpenSSH with
`BatchMode=no`. This permits private-key PIN/passphrase prompts, FIDO touch,
host-key confirmation, and other public-key user-presence flows. Password and
keyboard-interactive authentication remain disabled. SSH exit code 255 returns
to the picker with the prior host selected.

## Configuration

Home Manager writes `$XDG_CONFIG_HOME/tmux-fleet/config.json`. Set
`TMUX_FLEET_CONFIG` to use another file. Defaults outside Home Manager are:

```json
{
  "hosts": [],
  "reconcile_seconds": 30,
  "connect_timeout_seconds": 5,
  "server_alive_interval_seconds": 15,
  "server_alive_count_max": 2,
  "control_persist_seconds": 600,
  "tmux_command": "tmux",
  "fzf_command": "fzf",
  "ssh_command": "ssh"
}
```

`hosts` entries are whitespace-free OpenSSH aliases, not commands or shell
fragments. Duplicate aliases are removed in order. The Home Manager options
validate timing ranges before generating this file.

## State and safety limits

- Runtime sockets, FZF files, and ControlMaster sockets live in the private
  `/tmp/tmux-fleet-$UID` directory. Controller-specific files are removed when
  their owner exits; stale watcher sockets are pruned by later notifications.
- Last accepted remote snapshots live under
  `$XDG_CACHE_HOME/tmux-fleet`, or `~/.cache/tmux-fleet` when
  `XDG_CACHE_HOME` is unset.
- Runtime and cache directories must be owned by the current user and are kept
  at mode 0700.
- Tmux output, cache files, protocol lines, field lengths, session counts, and
  pending event queues are bounded before they enter persistent controller
  state.

The cache is an availability aid, not an authority: a target is revalidated by
tmux immediately before attachment. Disconnected hosts are never interpreted
as proof that their sessions were deleted.

## Troubleshooting

- Confirm each alias first with `ssh HOST` and `ssh HOST true`.
- Confirm the helper exists remotely with
  `ssh HOST 'test -x "$HOME/.local/libexec/tmux-fleet"'`.
- Use the picker **Reconnect** row when background discovery reports that user
  authentication is required.
- Use `tmux-fleet snapshot` on the affected host to inspect the local tmux view.
- If a host remains stale after reconnecting, check that its Home Manager
  generation includes both the tmux-fleet plugin and helper.

See [`docs/modules.md`](../../docs/modules.md) for all `cb.tmux.fleet.*` Home
Manager options.
