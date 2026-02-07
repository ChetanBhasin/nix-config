# Standalone NeoVim module for Home Manager
# Can be imported by other flakes via: inputs.nix-config.homeManagerModules.neovim
{ config, pkgs, lib, ... }:

let
  cfg = config.cb.neovim;

  # Path to the neovim lua config directory (relative to this module)
  nvimConfigPath = ../../home/neovim/config;
in {
  options.cb.neovim = {
    enable = lib.mkEnableOption "Chetan's NeoVim configuration";

    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set NeoVim as the default editor";
    };

    withNodeJs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Node.js integration for NeoVim";
    };

    withPython3 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Python 3 integration for NeoVim";
    };

    enableTmuxIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description =
        "Enable vim-tmux-navigator for seamless tmux/vim navigation";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to add to NeoVim's PATH";
    };

    extraPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional NeoVim plugins";
    };

    treesitterGrammars = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "all" ])
        (lib.types.listOf lib.types.str);
      default = "all";
      description =
        "Treesitter grammars to install. Use 'all' for comprehensive language support or a list of specific grammars.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = cfg.defaultEditor;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withNodeJs = cfg.withNodeJs;
      withPython3 = cfg.withPython3;

      extraPackages = with pkgs;
        [
          # Lua ecosystem
          lua
          lua-language-server
          stylua

          # Nix ecosystem
          deadnix
          statix
          nixd
          alejandra

          # Language servers
          terraform-lsp
          taplo
          yamllint
          gopls

          # Languages
          go

          # Utilities
          ctags
          ruff
          ripgrep
          gzip
          nerd-fonts.jetbrains-mono

          # Python debugging
          python3Packages.debugpy

          # Version control TUIs
          lazygit
          lazyjj
        ] ++ (with nodePackages; [
          dockerfile-language-server-nodejs
          typescript-language-server
          yaml-language-server
        ]) ++ cfg.extraPackages;

      plugins = with pkgs.vimPlugins;
        [
          # Core utilities
          plenary-nvim
          vim-cool
          comment-nvim
          vim-smoothie
          nvim-autopairs
          legendary-nvim
          which-key-nvim
          dressing-nvim
          fidget-nvim

          # File navigation
          telescope-nvim
          telescope-ui-select-nvim
          telescope-fzf-native-nvim
          nvim-tree-lua
          nvim-web-devicons

          # UI enhancements
          lualine-nvim
          bufferline-nvim
          catppuccin-nvim
          alpha-nvim
          indent-blankline-nvim
          rainbow-delimiters-nvim
          nvim-colorizer-lua
          lspkind-nvim

          # Productivity
          FTerm-nvim
          undotree
          todo-comments-nvim
          trouble-nvim

          # Version control
          gitsigns-nvim
          lazygit-nvim
          lazyjj-nvim

          # FZF integration
          fzf-vim

          # Rust support
          rustaceanvim

          # Mini plugins
          mini-nvim

          # Formatting
          conform-nvim

          # LSP
          nvim-lspconfig
          mason-nvim
          mason-lspconfig-nvim

          # Snippets
          luasnip
          friendly-snippets

          # Completion
          nvim-cmp
          cmp-nvim-lsp
          cmp_luasnip
          cmp-nvim-lua
          cmp-buffer
          cmp-path
          cmp-zsh
          cmp-git
          cmp-tmux
          cmp-spell
          cmp-clippy
          cmp-treesitter

          # Debug Adapter Protocol
          nvim-dap
          nvim-dap-python
          nvim-dap-ui
        ]
        # Tmux integration (optional)
        ++ lib.optionals cfg.enableTmuxIntegration [
          vim-tmux-navigator
        ]
        # Treesitter with comprehensive language support
        ++ [
          (nvim-treesitter.withPlugins (p:
            if cfg.treesitterGrammars == "all" then
              with p; [
                astro
                awk
                bash
                c
                c_sharp
                cmake
                clojure
                comment
                commonlisp
                cpp
                css
                csv
                cuda
                dart
                dhall
                diff
                dockerfile
                editorconfig
                elixir
                elm
                erlang
                fortran
                git_config
                git_rebase
                gitattributes
                gitcommit
                gitignore
                gleam
                go
                goctl
                godot_resource
                gomod
                gosum
                gotmpl
                gowork
                gpg
                graphql
                haskell
                hcl
                helm
                hjson
                hocon
                html
                http
                hurl
                ini
                ispc
                java
                javascript
                jq
                jsdoc
                json
                json5
                jsonnet
                julia
                kconfig
                kotlin
                latex
                linkerscript
                llvm
                lua
                luadoc
                luap
                luau
                make
                markdown
                markdown_inline
                matlab
                mermaid
                meson
                mlir
                nginx
                nim
                ninja
                nix
                ocaml
                ocaml_interface
                ocamllex
                pem
                php
                phpdoc
                pod
                powershell
                printf
                prisma
                promql
                proto
                puppet
                purescript
                pymanifest
                python
                query
                rasi
                readline
                regex
                requirements
                rescript
                robot
                ruby
                rust
                scala
                scheme
                scss
                slint
                snakemake
                solidity
                ssh_config
                starlark
                strace
                svelte
                swift
                tcl
                templ
                terraform
                textproto
                thrift
                tlaplus
                tmux
                todotxt
                toml
                tsv
                tsx
                twig
                typescript
                typespec
                typoscript
                typst
                v
                vim
                vimdoc
                vue
                wing
                wit
                xml
                yaml
                zig
              ]
            else
              builtins.map (name: p.${name}) cfg.treesitterGrammars))
        ] ++ cfg.extraPlugins;
    };

    # Link the NeoVim lua configuration
    xdg.configFile."nvim".source = nvimConfigPath;
    xdg.configFile."nvim".recursive = true;
  };
}
