# Exportable Home Manager Modules

This repository exports standalone Home Manager modules that can be used in your own Nix flake configurations. These modules provide battle-tested configurations for NeoVim, terminal tools, and tmux.

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
        {
          cb.neovim.enable = true;
          cb.terminal.enable = true;
          cb.tmux.enable = true;
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
- **Theme**: Catppuccin with transparency support

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
| `cb.terminal.enableGhostty` | boolean | `true` | Enable Ghostty terminal config |
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
    enableGhostty = false;  # If using a different terminal

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
- **Ghostty**: Pre-configured terminal emulator settings
- **Shell Functions**: Kubernetes helpers, git FZF integrations, extract utility

---

### `homeManagerModules.tmux`

Modern tmux configuration with session management, FZF integration, and Catppuccin theme.

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cb.tmux.enable` | boolean | `false` | Enable the tmux configuration |
| `cb.tmux.prefix` | string | `"C-Space"` | Tmux prefix key |
| `cb.tmux.enableVimIntegration` | boolean | `true` | Enable vim-tmux-navigator |
| `cb.tmux.enableSessionPersistence` | boolean | `true` | Enable resurrect/continuum |
| `cb.tmux.enableFzfIntegration` | boolean | `true` | Enable FZF-powered features |
| `cb.tmux.enableThumbs` | boolean | `true` | Enable tmux-thumbs (vimium-like hints) |
| `cb.tmux.shell` | string | `"/bin/zsh"` | Default shell |
| `cb.tmux.historyLimit` | integer | `50000` | Scrollback buffer size |
| `cb.tmux.extraConfig` | string | `""` | Additional tmux configuration |
| `cb.tmux.extraPlugins` | list of packages | `[]` | Additional tmux plugins |

#### Example

```nix
{
  cb.tmux = {
    enable = true;
    prefix = "C-a";  # Use traditional prefix instead of C-Space
    enableVimIntegration = true;
    enableSessionPersistence = true;

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
- **FZF**: Session switcher, URL picker, content extractor
- **Theme**: Catppuccin Macchiato with custom status line
- **Which-Key**: Discoverable keybindings via `?`
- **Thumbs**: Vimium-style hints for text selection

#### Key Bindings

| Binding | Action |
|---------|--------|
| `C-Space ?` | Show help menu |
| `C-Space s` | Sessions menu |
| `C-Space w` | Windows menu |
| `C-Space p` | Panes menu |
| `C-Space g` | Git menu |
| `C-Space f` | Find menu |
| `Alt+1-5` | Quick session switch |
| `Alt+h/l` | Previous/next window |

---

### `homeManagerModules.default`

Convenience module that imports all three modules (neovim, terminal, tmux).

```nix
{
  imports = [ cb-config.homeManagerModules.default ];

  cb.neovim.enable = true;
  cb.terminal.enable = true;
  cb.tmux.enable = true;
}
```

## Platform Support

All modules support both macOS (Darwin) and Linux:

- **macOS**: Uses pbcopy for clipboard, includes SDK paths for native compilation
- **Linux**: Uses wl-copy/xclip for clipboard, appropriate paths for Linux

Platform-specific behavior is handled automatically via `pkgs.stdenv.isDarwin` checks.

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
            ];
            cb.neovim.enable = true;
            cb.terminal.enable = true;
            cb.tmux.enable = true;
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
