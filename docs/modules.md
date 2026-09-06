# Exportable Home Manager Modules

This repository exports standalone Home Manager modules that can be used in your own Nix flake configurations. These modules provide battle-tested configurations for editors, terminal tools, multiplexers, and the regular Pi coding agent.

## Quick Start

Add this repository as a flake input and import the modules you need:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cb-config.url = "github:chetanbhasin/nix-config";
  };

  outputs = { nixpkgs, home-manager, cb-config, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      modules = [
        cb-config.homeManagerModules.neovim
        cb-config.homeManagerModules.terminal
        cb-config.homeManagerModules.tmux
        cb-config.homeManagerModules.pi
        {
          cb.neovim.enable = true;
          cb.terminal.enable = true;
          cb.tmux.enable = true;
          cb.pi.enable = true;
        }
      ];
    };
  };
}
```

## Available Modules

### `homeManagerModules.neovim`

Full-featured NeoVim IDE with LSP, treesitter, completion, and 50+ curated plugins.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb.neovim.enable` | boolean | `false` | Enable the NeoVim configuration |
| `cb.neovim.defaultEditor` | boolean | `true` | Set NeoVim as the default `$EDITOR` |
| `cb.neovim.withNodeJs` | boolean | `true` | Enable Node.js integration |
| `cb.neovim.withPython3` | boolean | `true` | Enable Python 3 integration |
| `cb.neovim.enableTmuxIntegration` | boolean | `true` | Include vim-tmux-navigator for seamless pane navigation |
| `cb.neovim.extraPackages` | list of packages | `[]` | Additional packages to add to NeoVim's PATH |
| `cb.neovim.extraPlugins` | list of packages | `[]` | Additional NeoVim plugins |
| `cb.neovim.treesitterGrammars` | `"all"` or list of strings | `"all"` | Treesitter grammars to install |

#### Example

```nix
{
  cb.neovim = {
    enable = true;
    defaultEditor = true;
    enableTmuxIntegration = true;

    # Add custom packages available to NeoVim
    extraPackages = with pkgs; [ nodejs_20 ];

    # Add custom plugins
    extraPlugins = with pkgs.vimPlugins; [ vim-surround ];

    # Install only specific treesitter grammars
    treesitterGrammars = [ "rust" "go" "python" "nix" "lua" ];
  };
}
```

#### Included Features

- **LSP**: nvim-lspconfig, mason.nvim for automatic LSP installation
- **Completion**: nvim-cmp with multiple sources (LSP, snippets, buffer, path, git, tmux)
- **Syntax**: Treesitter with 100+ language grammars
- **Navigation**: Telescope, nvim-tree, FZF integration
- **Git**: gitsigns, lazygit, lazyjj integration
- **Languages**: Enhanced support for Rust, Go, Python, Nix, TypeScript
- **Debug**: DAP (Debug Adapter Protocol) for Python
- **Theme**: Custom Gruvbox Night palette with an orange interaction accent and local highlight overrides

---

### `homeManagerModules.terminal`

Complete terminal environment with Zsh, FZF, Starship prompt, and more.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb.terminal.enable` | boolean | `false` | Enable the terminal configuration |
| `cb.terminal.enableZsh` | boolean | `true` | Enable Zsh with plugins |
| `cb.terminal.enableFzf` | boolean | `true` | Enable FZF with custom keybindings |
| `cb.terminal.enableStarship` | boolean | `true` | Enable Starship prompt |
| `cb.terminal.enableDirenv` | boolean | `true` | Enable direnv with nix-direnv |
| `cb.terminal.enableZoxide` | boolean | `true` | Enable zoxide (smart cd) |
| `cb.terminal.enableAlacritty` | boolean | `true` | Enable Alacritty terminal config |
| `cb.terminal.enableDevEnvironment` | boolean | `false` | Enable development env vars (OpenSSL, rdkafka paths) |
| `cb.terminal.viMode` | boolean | `true` | Enable vi mode for Zsh |
| `cb.terminal.historySize` | integer | `50000` | Number of history entries |
| `cb.terminal.extraZshConfig` | string | `""` | Additional Zsh configuration |
| `cb.terminal.extraAliases` | attrs | `{}` | Additional shell aliases |

#### Example

```nix
{
  cb.terminal = {
    enable = true;
    enableZsh = true;
    enableFzf = true;
    enableStarship = true;
    viMode = true;

    # Disable components you don't need
    enableAlacritty = false;  # If using a different terminal

    # Add custom aliases
    extraAliases = {
      ll = "eza -la";
      vim = "nvim";
    };

    # Add custom Zsh configuration
    extraZshConfig = ''
      export MY_VAR="value"
    '';
  };
}
```

#### Included Features

- **Zsh Plugins**: syntax-highlighting, fzf-tab, history-substring-search
- **FZF**: Custom keybindings with vim-style navigation (Alt+j/k)
- **Starship**: Minimal prompt with git, kubernetes, language version indicators
- **Direnv**: Automatic environment switching with nix-direnv
- **Zoxide**: Smart directory jumping
- **Alacritty**: Pre-configured terminal emulator settings
- **Shell Functions**: Kubernetes helpers, git FZF integrations, extract utility

---

### `homeManagerModules.tmux`

Modern tmux configuration with session management, FZF integration, and the Gruvbox Night theme.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb.tmux.enable` | boolean | `false` | Enable the tmux configuration |
| `cb.tmux.package` | package | pinned full-frame tmux build | Override the tmux package; the default tracks upstream PR #5433 and adds rounded pane corners |
| `cb.tmux.prefix` | string | `"C-Space"` | Tmux prefix key |
| `cb.tmux.enableVimIntegration` | boolean | `true` | Enable vim-tmux-navigator |
| `cb.tmux.enableSessionPersistence` | boolean | `true` | Enable resurrect/continuum |
| `cb.tmux.enableFzfIntegration` | boolean | `true` | Enable FZF-powered features |
| `cb.tmux.enableThumbs` | boolean | `true` | Enable tmux-thumbs (vimium-like hints) |
| `cb.tmux.fleet.enable` | boolean | `false` | Enable the local/SSH tmux fleet picker on `Prefix s` |
| `cb.tmux.fleet.remoteHosts` | list of strings | `[]` | OpenSSH aliases for participating peers; omit the current host |
| `cb.tmux.fleet.reconcileSeconds` | integer | `30` | Slow watcher reconciliation interval |
| `cb.tmux.fleet.connectTimeoutSeconds` | integer | `5` | Non-interactive SSH connection timeout |
| `cb.tmux.fleet.serverAliveIntervalSeconds` | integer | `15` | OpenSSH keepalive interval |
| `cb.tmux.fleet.serverAliveCountMax` | integer | `2` | Missed keepalives before a connection is stale |
| `cb.tmux.fleet.controlPersistSeconds` | integer | `600` | ControlMaster idle lifetime |
| `cb.tmux.shell` | string | Nix-managed `zsh` | Default shell executable |
| `cb.tmux.historyLimit` | integer | `50000` | Scrollback buffer size |
| `cb.tmux.extraConfig` | string | `""` | Additional tmux configuration |
| `cb.tmux.extraPlugins` | list of packages | `[]` | Additional tmux plugins |

The default package pins tmux commit `fe8f9ff` from upstream PR [#5433](https://github.com/tmux/tmux/pull/5433) until the feature reaches a release. Set `cb.tmux.package = pkgs.tmux` to stay on stock tmux; the configuration will load normally but use heavy joined pane dividers instead of full rounded frames.

#### Example

```nix
{
  cb.tmux = {
    enable = true;
    prefix = "C-a";  # Use traditional prefix instead of C-Space
    enableVimIntegration = true;
    enableSessionPersistence = true;
    fleet = {
      enable = true;
      remoteHosts = [ "workstation" "server" ]; # OpenSSH host aliases
    };

    # Add custom configuration
    extraConfig = ''
      set -g status-position top
    '';

    # Add custom plugins
    extraPlugins = with pkgs.tmuxPlugins; [ nord ];
  };
}
```

#### Included Features

- **Prefix**: `C-Space` (ergonomic, no conflicts)
- **Navigation**: vim-tmux-navigator for seamless splits
- **Sessions**: resurrect, continuum for automatic save/restore
- **Fleet picker**: Cached local and SSH-hosted sessions with event-driven
  refresh, explicit reauthentication, and no nested tmux UI
- **FZF**: Session switcher, URL picker, content extractor
- **Theme**: Gruvbox Night with an orange-focused custom status line
- **Pane focus**: Rounded four-sided active frame with a slight gutter, using
  the pinned upstream separate-border implementation
- **Which-Key**: Discoverable command palette via `Prefix Space`
- **Thumbs**: Vimium-style hints for text selection

#### Fleet prerequisites and lifecycle

Enable `cb.tmux.fleet` on every participating machine and configure
`remoteHosts` with the other machines' OpenSSH aliases. Each alias must support
public-key authentication and resolve to a host whose Home Manager generation
provides `tmux`, the plugin, and `~/.local/libexec/tmux-fleet`. Discovery uses
noninteractive OpenSSH, disables agent forwarding, and never opens a public
listener.

With fleet mode enabled, `Prefix s` replaces an ordinary tmux client with the
controller and opens the cached picker. Local hooks and remote watcher streams
reload FZF as state changes; a slow full snapshot repairs missed events. Inside
a controller-managed local or remote client, `Prefix s` returns exit code 42
to the existing controller and reopens that picker without nesting tmux. A
normal `Prefix d` detach exits the controller and returns to the shell.

Offline hosts retain their last accepted sessions as stale entries. Choosing
**Reconnect** leaves FZF and runs foreground OpenSSH so private-key
PIN/passphrase, FIDO touch, and host-key prompts can proceed; password and
keyboard-interactive authentication remain disabled. Existing targets are
atomically revalidated by server generation, session ID, and creation time
before attachment.

For protocol details, state paths, standalone configuration, and
troubleshooting, see the
[`tmux-fleet` README](../packages/tmux-fleet/README.md).

#### Key Bindings

`Prefix` below means `C-Space` by default; `cb.tmux.prefix` changes only that
first chord.

| Binding | Action |
|---------|--------|
| `Prefix Space` | Main command palette |
| `Prefix F` | FZF action palette |
| `Prefix P` | Project switcher |
| `Prefix S` | FZF session switcher |
| `Prefix ?` | Show help menu |
| `Prefix s` | Fleet picker when enabled; otherwise sessions menu |
| `Prefix w` | Windows menu |
| `Prefix p` | Panes menu |
| `Prefix g` | Git menu |
| `Prefix f` | Find menu |
| `Alt+1-5` | Quick session switch |
| `Alt+h/l` | Previous/next window |

---

### `homeManagerModules.pi`

Regular Pi Coding Agent in package-only mode. Nix installs the pinned Pi 0.84.3 binary, its wrapper toolchain, and `pi-config`; Pi and the user retain ownership of writable state, while an optional activation step can make the flake snapshot authoritative for managed portable paths.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb.pi.enable` | boolean | `false` | Enable the package-only Pi configuration and install `pi-config` |
| `cb.pi.package` | package | pinned Pi package (0.84.3 currently) | Override the installed Pi package |
| `cb.pi.forceApplyOnActivation` | boolean | `false` | Force the embedded snapshot over managed live Pi paths after the Home Manager write boundary |
| `cb.pi.enableLspTooling` | boolean | `true` | Expose the curated language-server toolchain to Pi |
| `cb.pi.extraPackages` | list of packages | `[]` | Add tools to Pi and its shell environment |

#### Included Features

- Regular Pi at its upstream default `~/.pi/agent` location
- Node.js and Git in Pi's wrapper environment
- Optional curated tooling for Rust, Nix, Python, Go, Lua, TypeScript, web formats, shell, infrastructure, Markdown, TOML, Just, Bazel, and Starlark
- `pi-config capture`, conservative `pi-config apply`, and explicit `pi-config apply --force` synchronization for a writable portable snapshot
- A read-only activation preflight, plus optional transactional forced synchronization after the write boundary

#### Example

```nix
{
  cb.pi = {
    enable = true;
    forceApplyOnActivation = true; # Make the flake snapshot authoritative on activation
    extraPackages = with pkgs; [ kubectl ];
  };
}
```

Pi credentials, sessions, package realizations, and project-local resources remain ordinary writable application state. Managed portable files are also writable between activations, but `forceApplyOnActivation = true` replaces uncaptured edits with the flake snapshot. Run `pi-config doctor` after activation and see the [Pi Configuration Guide](pi.md) for synchronization and recovery details.

---

### `homeManagerModules.default`

Convenience module that imports all exported Home Manager modules.

```nix
{
  imports = [ cb-config.homeManagerModules.default ];

  cb.neovim.enable = true;
  cb.terminal.enable = true;
  cb.tmux.enable = true;
  cb.pi.enable = true;
}
```

## Platform Support

All modules support both macOS (Darwin) and Linux:

- **macOS**: Uses pbcopy for clipboard, includes SDK paths for native compilation
- **Linux**: Uses wl-copy/xclip for clipboard, appropriate paths for Linux

Platform-specific behavior is handled automatically via `pkgs.stdenv.hostPlatform` checks.

## Customization Tips

### Extending NeoVim Plugins

```nix
{
  cb.neovim = {
    enable = true;
    extraPlugins = with pkgs.vimPlugins; [
      vim-surround
      vim-repeat
      targets-vim
    ];
  };
}
```

### Custom Starship Prompt

The terminal module uses starship. To customize further, you can override after importing:

```nix
{
  cb.terminal.enable = true;

  # Override starship settings
  programs.starship.settings.character = {
    success_symbol = "[>](bold green)";
    error_symbol = "[>](bold red)";
  };
}
```

### Using with nix-darwin

```nix
{
  inputs = {
    darwin.url = "github:lnl7/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
    cb-config.url = "github:chetanbhasin/nix-config";
  };

  outputs = { darwin, home-manager, cb-config, ... }: {
    darwinConfigurations.myhost = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        home-manager.darwinModules.home-manager
        {
          home-manager.users.myuser = {
            imports = [
              cb-config.homeManagerModules.neovim
              cb-config.homeManagerModules.terminal
              cb-config.homeManagerModules.tmux
              cb-config.homeManagerModules.pi
            ];
            cb.neovim.enable = true;
            cb.terminal.enable = true;
            cb.tmux.enable = true;
            cb.pi.enable = true;
          };
        }
      ];
    };
  };
}
```

## Troubleshooting

### Module Not Found

Ensure you've added the flake input correctly and are using the right attribute path:

```nix
# Correct
cb-config.homeManagerModules.neovim

# Wrong
cb-config.homeModules.neovim  # Wrong attribute name
```

### Conflicting Options

If you have existing NeoVim/Zsh/Tmux configurations, you may get conflicts. Either:

1. Remove your existing configuration
2. Use `lib.mkForce` to override specific options
3. Don't enable the conflicting module component (e.g., `cb.terminal.enableZsh = false`)

### Missing Dependencies

The modules declare their dependencies, but if you encounter missing packages, ensure your nixpkgs is recent enough. These modules are tested against `nixpkgs-unstable`.
