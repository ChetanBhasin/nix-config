# Chetan's Nix Configuration

[![Built with Nix](https://img.shields.io/badge/Built_With-Nix-5277C3.svg?logo=nixos&labelColor=73C3D5)](https://nixos.org)
[![macOS](https://img.shields.io/badge/macOS-Monterey+-000000?logo=apple)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A comprehensive Nix configuration for reproducible development environments across macOS and Linux systems. This repository includes configurations for commonly used systems including personal laptops and server setups.

## 📋 Table of Contents

- [Chetan's Nix Configuration](#chetans-nix-configuration)
  - [📋 Table of Contents](#-table-of-contents)
  - [✨ Features](#-features)
  - [🚀 Quick Start](#-quick-start)
  - [📖 Documentation](#-documentation)
    - [Development](#development)
  - [📜 License](#-license)
  - [🙏 Credits](#-credits)

## ✨ Features

- 🚀 **Modern Terminal Setup**: Zsh + FZF + Alacritty with enhanced productivity workflows
- 🧠 **Powerful IDE**: Neovim with LSP, type annotations, smart navigation, and Claude AI integration
- 🎯 **Tmux Configuration**: C-Space prefix, command palette, session management, and persistence
- 📦 **Package Management**: Nix + Home Manager for reproducible environments
- 🔧 **Cross-Platform**: macOS (Darwin) and Linux (NixOS) support
- 🎨 **Consistent Theming**: Gruvbox dark theme across all applications
- ⚡ **Performance Optimized**: Fast startup times and efficient resource usage
- 🔐 **Security Focused**: Proper SSH configurations and secure defaults


## 🚀 Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/nix-config.git
   cd nix-config
   ```

2. **Choose your installation method**:
   - For macOS: [macOS Installation](#macos-installation)
   - For Linux: [Linux Installation](#linux-installation)

3. **Apply configuration**:
   ```bash
   make apply-darwin host=hugh  # Replace 'hugh' with your preferred host
   ```

4. **Enjoy your new environment!** 🎉

## 🔌 Using as a Flake Input

You can use the NeoVim, Terminal, and Tmux configurations in your own flake without adopting the entire configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";

    # Add this config as an input
    cb-config.url = "github:chetanbhasin/nix-config";
  };

  outputs = { nixpkgs, home-manager, cb-config, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
      modules = [
        # Import individual modules
        cb-config.homeManagerModules.neovim
        cb-config.homeManagerModules.terminal
        cb-config.homeManagerModules.tmux

        # Or import all at once
        # cb-config.homeManagerModules.default

        # Configure the modules
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

### Available Modules

| Module | Description | Options |
|--------|-------------|---------|
| `neovim` | Full NeoVim IDE with LSP, treesitter, and 50+ plugins | `cb.neovim.enable`, `cb.neovim.enableTmuxIntegration`, `cb.neovim.treesitterGrammars` |
| `terminal` | Zsh + FZF + Starship + Direnv + Zoxide + Alacritty | `cb.terminal.enable`, `cb.terminal.enableFzf`, `cb.terminal.enableStarship`, `cb.terminal.viMode` |
| `tmux` | Modern tmux with sessions, FZF, and Gruvbox dark theme | `cb.tmux.enable`, `cb.tmux.enableVimIntegration`, `cb.tmux.enableSessionPersistence` |
| `default` | All modules combined | All options from above |

See [Module Options Documentation](docs/modules.md) for complete configuration options.

## 📖 Documentation

📖 **[IDE Setup Guide](docs/ide.md)** - Comprehensive guide to the powerful Neovim IDE configuration with language servers, type annotations, keyboard shortcuts, Claude AI integration, and development workflows.

🚀 **[Terminal Configuration Guide](docs/terminal.md)** - Complete guide to the modern terminal setup with Zsh, FZF, tmux, and Alacritty for enhanced productivity and development workflows.

📦 **[Module Options](docs/modules.md)** - Complete reference for all exportable Home Manager module options.

### Development

```bash
# Test configuration without applying
nix build .#darwinConfigurations.hugh.system

# Check flake
nix flake check

# Update inputs
nix flake update
```

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Credits

Special thanks to:

- **[Frank](https://github.com/fmoda3/nix-configs)** for sharing his Nix configuration, which served as an excellent learning resource
- **The Nix Community** for maintaining an incredible ecosystem
- **Plugin Authors** for creating the amazing tools that make this configuration possible
- **Contributors** who help improve this configuration
