# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a cross-platform Nix configuration supporting both macOS (Darwin) and Linux (NixOS) systems. The configuration uses a unified approach where shared packages and configurations are centralized, while platform-specific settings are isolated.

### Key Architectural Components

**Flake Structure (`flake.nix`)**:
- `darwinConfigurations`: macOS systems using nix-darwin (hugh, markus)  
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
- All hosts use nushell available as a package but zsh as default shell