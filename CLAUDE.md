# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a cross-platform Nix configuration supporting both macOS (Darwin) and Linux (NixOS) systems. The configuration uses a unified approach where shared packages and configurations are centralized, while platform-specific settings are isolated.

### Key Architectural Components

**Flake Structure (`flake.nix`)**:
- `darwinConfigurations`: macOS systems using nix-darwin (hugh, markus)
- `homeManagerModules`: Exportable Home Manager modules for external use (neovim, terminal, tmux)
- `nixosModules` and `darwinModules`: Reusable module functions for platform-specific setups
- Home Manager integration for both platforms with user-specific configurations

**Package Organization**:
- `systemPackages/`: Cross-platform system packages (development tools, languages, databases)
- `darwin/default.nix`: macOS-specific system configuration, Homebrew casks, and system preferences
- `home/default.nix`: User-level packages with platform conditionals (Darwin vs Linux)

**Host Configuration**:
- `hosts/{hostname}/`: Host-specific configurations
- `hosts/{hostname}/configuration.nix`: System-level settings per host
- `hosts/{hostname}/home.nix`: User-level Home Manager configuration per host

**Modularity Strategy**:
- Shared packages are centralized to avoid duplication
- Platform-specific packages use conditional logic (`lib.optionals pkgs.stdenv.isDarwin`)
- Homebrew is minimized - only used when packages lack aarch64-darwin support in nixpkgs

## Common Commands

**Build and Test**:
```bash
# Build configuration for specific host
make build-darwin host=hugh
nix build .#darwinConfigurations.hugh.system

# Test configuration without applying
nix eval .#darwinConfigurations.hugh.config.system.stateVersion

# Apply configuration 
make apply-darwin host=hugh

# Check flake validity
nix flake check

# Update all inputs
nix flake update
```

**Host Management**:
- Available Darwin hosts: `hugh`, `markus`
- Available Linux hosts: `venus` (server configuration)
- Default host in Makefile: `hugh`

## Configuration Guidelines

**Package Placement Rules**:
1. Cross-platform system packages → `systemPackages/default.nix`
2. Darwin-specific system packages → `darwin/default.nix` environment.systemPackages
3. User-specific packages → `home/default.nix` with platform conditionals
4. GUI applications → Homebrew casks in `darwin/default.nix` (only if not available in nixpkgs)

**Darwin-Specific Features**:
- System preferences and dock configuration in `darwin/default.nix`
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
- `home/zsh/default.nix`: Main zsh configuration with plugins (via nixpkgs)
- `home/zsh/sources.sh`: Platform-agnostic shell configuration (symlinked to `~/.sources`)
- `home/zsh/sources_darwin.sh` / `sources_linux.sh`: Platform-specific config (symlinked to `~/.sources_platform`)

Shell plugins are managed via nixpkgs packages for automatic updates:
- `zsh-syntax-highlighting`
- `zsh-fzf-tab`
- `zsh-history-substring-search`

FZF configuration is managed via `programs.fzf` in nix, not shell exports.

## Exportable Home Manager Modules

The repository exports standalone Home Manager modules via `homeManagerModules` for use in other flakes:

**Module Structure (`modules/homeManager/`)**:
- `neovim.nix`: NeoVim IDE with LSP, treesitter, 50+ plugins (options under `cb.neovim.*`)
- `terminal.nix`: Zsh + FZF + Starship + Direnv + Zoxide + Alacritty (options under `cb.terminal.*`)
- `tmux.nix`: Modern tmux with sessions, FZF, Catppuccin theme (options under `cb.tmux.*`)
- `default.nix`: Index that exports all modules

**Design Principles**:
- Modules are self-contained and can be used independently
- Each module has an `enable` option (defaults to `false`) for explicit opt-in
- Config files are referenced via relative paths from the module files
- Platform-specific behavior handled via `pkgs.stdenv.isDarwin` checks

**Relationship with `home/` Directory**:
- `home/` contains the internal configuration used by `darwinConfigurations`
- `modules/homeManager/` contains exportable versions with options
- These are intentionally parallel (some duplication) to:
  - Keep existing configurations stable
  - Allow external modules to evolve independently
  - Avoid breaking changes when adding features

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