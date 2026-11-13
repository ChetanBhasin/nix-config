# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a cross-platform Nix configuration for macOS (nix-darwin) and Linux
(NixOS), organized by feature using the Dendritic pattern.

`flake.nix` declares inputs and bootstraps flake-parts. `import-tree` discovers
Nix files under `modules/`, excluding paths prefixed with `_`. Discovered files
are flake-parts modules; private underscore files can be ordinary modules
imported explicitly by their owner. A feature contributes ordinary NixOS,
Darwin, or Home Manager module values through `flake.modules.<class>.<name>`.
Importing its outer file registers those values; hosts and profiles choose
which lower-level modules to use.

### Layout

- `modules/hosts/{hugh,markus}.nix` and `modules/hosts/boris/default.nix`:
  explicit host outputs and host-local system and Home Manager settings.
  Boris directly imports its private NixOS module `boris/_hardware.nix`.
- `modules/{terminal,tmux,neovim}/`: feature directories with independent personal
  and exportable Home Manager implementations. The personal terminal files merge
  into one `terminal-personal` module, selected once by the home profile.
- `modules/hyprland.nix`, `quickshell.nix`, `karabiner.nix`, `zen.nix`:
  feature definitions, including related platform and user settings together.
- `modules/nixpkgs.nix`: shared package configuration and ordered overlays.
- `modules/nix.nix`, `user.nix`: Nix/Determinate and user/Home Manager integration.
- `modules/system-packages.nix`, `home-profile.nix`, `darwin-desktop.nix`:
  shared packages, personal profile composition, and macOS desktop policy.
- `modules/exports.nix`: the stable `homeManagerModules` public entry points and
  the Darwin host-output option declaration.
- `home/`: shell, Lua, tmux, and Quickshell assets; no Nix module wiring.
- `packages/`: raw package expressions; `theme/gruvbox-night.nix`: palette data.
  These are outside the auto-imported module tree.

Capture flake inputs and the module registry in the outer flake-parts module;
keep `pkgs`, `config`, and `lib` for the inner module's evaluation context. Use
explicit imports from the registry rather than generic host builders. Preserve
private/public differences and opt-in defaults when changing feature wiring.

## Common Commands

**Build and Test**:
```bash
# Build configuration for specific host
make build-darwin host=hugh
nix build .#darwinConfigurations.hugh.system
make build-nixos host=boris
nix build .#nixosConfigurations.boris.config.system.build.toplevel

# Test configuration without applying
nix eval .#darwinConfigurations.hugh.config.system.stateVersion
nix eval .#nixosConfigurations.boris.config.system.stateVersion

# Apply configuration
make apply-darwin host=hugh
make apply-nixos host=boris

# Check flake validity
nix flake check

# Update all inputs
nix flake update
```

**Host Management**:
- Available Darwin hosts: `hugh`, `markus`
- Available Linux hosts: `boris` (NixOS Hyprland workstation)
- Default host in Makefile: `hugh`

## Configuration Guidelines

**Package Placement Rules**:
1. Cross-platform system packages → `modules/system-packages.nix`
2. Darwin-specific system packages → `modules/darwin-desktop.nix` environment.systemPackages
3. User-specific packages → `modules/home-profile.nix` with platform conditionals
4. GUI applications → their feature module, or Homebrew casks in `modules/darwin-desktop.nix` (only if not available in nixpkgs)

**Application State Files**:

Never point a store-sourced `home.file` at a path an application rewrites at
runtime. Home Manager projects those paths as read-only store symlinks, and
`force = true` silently discards whatever was already there. A
`programs.zen-browser` module owning `~/Library/Application Support/zen/profiles.ini`
stripped the `[Install<hash>]` sections Zen uses to locate its profile; Zen
responded by building a fresh empty profile and stranding the real one — on
2026-08-24 and again on 2026-09-14.

1. `force = true` is allowed only on `config.lib.file.mkOutOfStoreSymlink`, where
   the real data lives outside the store.
2. Config an app writes back to is seeded copy-if-absent from an activation
   script, never projected:
   `[[ ! -e "$target" ]] && install -Dm600 "$source" "$target"`.
3. Read-only store projection is fine only for files the app never writes.
4. When an app owns a file this repo therefore cannot manage, snapshot it before
   `linkGeneration` instead — see `home.activation.snapshotZenIni` in
   `modules/zen.nix`.

**Darwin-Specific Features**:
- System preferences and dock configuration in `modules/darwin-desktop.nix`
- Homebrew management with conditional packages based on `enableProf`/`enableExtras` options
- TouchID sudo authentication support
- Extensive font management through Homebrew casks

**Development Workflow**:
- Always test builds with `make build-darwin` before applying
- Use `nix eval` for quick configuration validation
- Check for deprecated Darwin SDK references (avoid `darwin.apple_sdk.frameworks.*`)

## Important Notes

- The configuration is optimized for aarch64-darwin (Apple Silicon)
- Homebrew usage is minimized - prefer nixpkgs when packages have proper aarch64-darwin support
- Home Manager provides user-level package management across platforms
- All hosts use zsh as default shell with starship prompt

## Shell Configuration

The shell setup uses a layered approach:
- `modules/terminal/shell.nix`: Main zsh configuration with plugins (via nixpkgs)
- `home/zsh/sources.sh`: Platform-agnostic shell configuration (symlinked to `~/.sources`)
- `home/zsh/sources_darwin.sh` / `sources_linux.sh`: Platform-specific config (symlinked to `~/.sources_platform`)

Shell plugins are managed via nixpkgs packages for automatic updates:
- `zsh-syntax-highlighting`
- `zsh-fzf-tab`
- `zsh-history-substring-search`

FZF configuration is managed via `programs.fzf` in nix, not shell exports.

## Exportable Home Manager Modules

The repository exports standalone Home Manager modules via `homeManagerModules` for use in other flakes:

**Feature implementation**:
- `modules/neovim/export.nix`: NeoVim IDE (options under `cb.neovim.*`)
- `modules/terminal/export.nix`: Zsh + FZF + Starship + Direnv + Zoxide + Alacritty
  (options under `cb.terminal.*`)
- `modules/tmux/export.nix`: Tmux and optional fleet support (`cb.tmux.*`)
- `modules/exports.nix`: individual public modules and the combined default

Public modules remain self-contained Home Manager modules. Each feature's
`enable` defaults to `false`; consumers do not need flake-parts or import-tree.
Personal implementations live alongside the public modules and intentionally
remain separate where their defaults and behavior differ.
Application assets remain under `home/` and can be shared by both variants.

**Usage by External Flakes**:
```nix
{
  inputs.cb-config.url = "github:chetanbhasin/nix-config";
  outputs = { cb-config, ... }: {
    homeConfigurations.user = {
      modules = [
        cb-config.homeManagerModules.neovim
        { cb.neovim.enable = true; }
      ];
    };
  };
}
```

See `docs/modules.md` for complete option documentation.
