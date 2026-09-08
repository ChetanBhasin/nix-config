# tmux-fleet

`tmux-fleet` is a local tmux session picker with on-demand SSH targets. It does
not discover, poll, cache, or require connectivity to remote tmux servers.
Selecting an SSH target replaces the current terminal client with a foreground
SSH connection to that host's tmux server, so it never nests tmux clients.

## Use

Inside tmux, press `Prefix s` to open the normal **Sessions** submenu:

- `Prefix s s` opens the combined local-session and SSH-target picker when
  fleet mode is enabled; otherwise it opens tmux's ordinary session tree.
- `Prefix s n`, `Prefix s r`, `Prefix s k`, and `Prefix s d` retain their
  normal new, rename, kill, and detach behavior.

The picker contains current-host sessions, a new-local-session action,
optional configured SSH targets, recently used ad-hoc targets, and **Connect
SSH target**. Enter an OpenSSH destination such as `chetan@192.168.1.170`, an
IPv4/IPv6 address, DNS name, or an `ssh_config` alias. Values with whitespace,
control characters, or a leading `-` are rejected before SSH is started.

SSH is run in the foreground with a forced TTY. It preserves normal
`ssh_config`, `ProxyJump`, host-key confirmation, agents, FIDO/PIN and
passphrase prompts, password authentication, and keyboard-interactive
authentication. tmux-fleet does not override agent forwarding, ControlMaster,
timeout, or authentication policy from `ssh_config`.

The managed remote helper atomically starts tmux and then, in one tmux command
queue, attaches the latest session when one exists or creates a new session.
It preserves the controller-switch (42) status naturally. On a machine with this
module enabled, `Prefix s s` in the remote tmux session exits back through SSH
and reopens the origin picker; select a local row to return to a local session. A
normal remote detach and an SSH failure also return to the origin picker with that
target preselected for retry. On an unmanaged remote machine, the fixed fallback
uses that same one-process `start-server; if-shell` queue after exporting
`TMUX_FLEET_MANAGED=1`. The `Prefix s s` return shortcut is unavailable there.

A normal detach from a **local** managed tmux session exits to the shell, as
usual.
## Home Manager setup

Enable the exported module on the machine where you want the picker. SSH
targets are optional and directional; no peer needs to SSH back to the origin.

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

Enable the module on a remote host too when you want `Prefix s s` there to
return to the originating picker. Home Manager installs a stable helper at
`~/.local/libexec/tmux-fleet`; an ad-hoc remote host without that helper uses
the same atomic `start-server; if-shell` attach-latest-or-new queue.

## State and safety limits

- Recent ad-hoc SSH targets are stored as a bounded, deduplicated list under
  `$XDG_STATE_HOME/tmux-fleet/recent-ssh-targets.json`, or
  `~/.local/state/tmux-fleet/recent-ssh-targets.json` when `XDG_STATE_HOME` is unset.
- Runtime picker files live under the private `/tmp/tmux-fleet-$UID` directory.
- State directories must be user-owned and mode 0700; state files are mode
  0600. State reads and writes have size limits and writes are atomic.
- Malformed or insecure recent-target state is warned about and ignored for the
  picker; writes remain strict and will not replace it.
- Existing local sessions are atomically revalidated by tmux server PID and start
  time, session ID, and creation time before attachment.

## Standalone configuration

Home Manager writes `$XDG_CONFIG_HOME/tmux-fleet/config.json`. Set
`TMUX_FLEET_CONFIG` to use another file. Defaults outside Home Manager are:

```json
{
  "ssh_targets": [],
  "tmux_command": "tmux",
  "fzf_command": "fzf",
  "ssh_command": "ssh"
}
```

`ssh_targets` are optional destinations to display in the picker. They are not
probed until selected. The hidden `attach-latest` command is used by a managed
remote helper; normal users should launch `tmux-fleet` or use `Prefix s s`.

## Troubleshooting

- Test a destination exactly as entered in the picker: `ssh -tt TARGET`.
- If authentication fails, choose the target again: every connection attempt
  is foreground and can show its normal prompts.
- Use `tmux-fleet snapshot` to inspect only the current host's tmux sessions.
- If remote `Prefix s s` opens another picker instead of returning to the
  origin, enable this module on the remote host or use normal detach there.

See [`docs/modules.md`](../../docs/modules.md) for `cb.tmux.fleet.*` options.
