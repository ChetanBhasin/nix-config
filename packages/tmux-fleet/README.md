# tmux-fleet

`tmux-fleet` presents local and SSH-backed tmux sessions in one searchable
picker. A per-user daemon owns one dedicated OpenSSH control master for each
connected destination and refreshes its remote tmux inventory in the
background. Opening the picker reads that cache immediately; it never waits for
every host to connect.

Connectivity is directional. Only the machine running the picker needs to reach
a destination, and destinations do not need to reach each other or connect back
to the origin.

## Use

Inside tmux, press `Prefix S` (`C-Space S` in this repository). The FZF dialog
is centered and lists:

- every local tmux session;
- every session cached from each connected SSH destination;
- one **new session** action for the local host and for each ready remote host;
- one **reconnect** action for each known but disconnected destination; and
- **connect another SSH host** for an ad-hoc `[user@]host` or address.

Start typing to fuzzy-filter the visible host, session, state, and action text.
Enter attaches or runs the selected action; Escape closes the manager.

Lowercase `Prefix s` remains the normal **Sessions** submenu. Its
`Prefix s n`, `Prefix s r`, `Prefix s k`, and `Prefix s d` chords retain their
new, rename, kill, and detach behavior.

### SSH lifecycle

Configured and remembered destinations initially appear as disconnected rows.
Selecting **reconnect** (or entering a new destination) runs ordinary OpenSSH in
the foreground, so host-key confirmation, passwords, FIDO/PIN prompts, agents,
`ProxyJump`, and other `ssh_config` behavior remain available. A successful
login becomes a daemon-owned control master and the picker then shows all tmux
sessions on that host.

The connection remains available across picker invocations and local session
switches. The Home Manager user service closes its masters when it stops or the
user session logs out. A failed master becomes one explicit reconnect row; it
never blocks healthy hosts from appearing.

Every participating remote host must install the tmux-fleet helper at
`~/.local/libexec/tmux-fleet`. A connected host without a compatible helper is
shown as **unsupported** instead of silently falling back to different attach
semantics.

Selecting a remote session opens a foreground `ssh -tt` slave over the daemon's
existing master. It attaches the exact cached tmux session after atomically
revalidating the remote server and session identity. Remote detach returns to
the origin picker. On a managed remote, `Prefix S` emits the switch sentinel and
also returns to the origin picker. No nested tmux client or second status bar is
created.

A normal detach from a **local** managed session exits to the shell, as usual.

## Home Manager setup

Enable the exported module on every host whose sessions should be listed:

```nix
{
  imports = [ cb-config.homeManagerModules.tmux ];

  cb.tmux = {
    enable = true;
    fleet = {
      enable = true;
      sshTargets = [
        "chetan@192.168.1.170"
        "workstation"
      ];
    };
  };
}
```

`sshTargets` is optional. Entries may be OpenSSH aliases, DNS names, IPv4/IPv6
addresses, or `[user@]host` destinations. Whitespace, control characters, and a
leading `-` are rejected before SSH starts. Ad-hoc destinations entered through
the picker are remembered locally in a bounded recent list.

Home Manager installs and starts the `tmux-fleet` per-user service on Linux
(systemd) and macOS (launchd), writes the configuration, installs the helper,
and binds `Prefix S`. After activating a new generation, reload an already
running tmux server:

```bash
tmux source-file ~/.config/tmux/tmux.conf
```

## Connection and safety model

- The daemon is the sole owner of dedicated control masters and their random,
  host-independent socket names.
- Background inventory and attach operations are `BatchMode` slaves that must
  use the existing socket. A fail-closed `ProxyCommand` prevents an accidental
  second connection or authentication prompt.
- SSH forwarding is cleared for bootstrap, inventory, and attach operations.
- Remote inventories refresh independently about every two seconds with bounded
  output, timeouts, protocol validation, and per-host error states.
- A host's connection ID and epoch are checked before every attach. The remote
  helper then atomically validates tmux server PID/start time, session ID, and
  session creation time.
- The daemon IPC socket, registry, and control sockets live in the private
  `/tmp/tmux-fleet-$UID` directory. IPC peers must have the same effective UID.
- Recent targets live at
  `$XDG_STATE_HOME/tmux-fleet/recent-ssh-targets.json`, or
  `~/.local/state/tmux-fleet/recent-ssh-targets.json` when
  `XDG_STATE_HOME` is unset.
- Runtime/state directories and files are owner-checked, symlink-resistant,
  size-bounded, and written atomically with modes 0700 and 0600.

## Standalone configuration

Home Manager writes `$XDG_CONFIG_HOME/tmux-fleet/config.json`. Set
`TMUX_FLEET_CONFIG` to use another file. Defaults outside Home Manager are:

```json
{
  "ssh_targets": [],
  "tmux_command": "tmux",
  "fzf_command": "fzf",
  "ssh_command": "ssh",
  "false_command": "false"
}
```

Start the daemon once for the user session, then run the picker:

```bash
tmux-fleet daemon
tmux-fleet run
```

Only one daemon can hold the per-user lock. The hidden `attach-existing` and
`attach-new` commands are protocol surfaces used by a managed remote helper.

## Troubleshooting

- Verify interactive access with `ssh -tt TARGET true`.
- If a host shows **disconnected**, select its single reconnect row and complete
  authentication in the foreground.
- If it shows **unsupported**, deploy the same tmux-fleet generation on that
  host and confirm `~/.local/libexec/tmux-fleet snapshot` works there.
- `tmux-fleet snapshot` prints the current host's validated tmux snapshot.
- On Linux, inspect service failures with
  `systemctl --user status tmux-fleet.service` and
  `journalctl --user -u tmux-fleet.service`.
- If `Prefix S` still invokes an older binding after deployment, reload
  `~/.config/tmux/tmux.conf` as shown above.

See [`docs/modules.md`](../../docs/modules.md) for `cb.tmux.fleet.*` options.
