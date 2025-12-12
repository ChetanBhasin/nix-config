{ config, pkgs, lib, ... }:
with lib; {
  config = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withNodeJs = true;
      withPython3 = true;
      extraPackages = with pkgs;
        [
          lua
          lua-language-server
          terraform-lsp
          deadnix
          statix
          nixd
          alejandra # Nix formatter for nixd
          taplo
          yamllint
          go
          gopls # Go language server
          ctags
          stylua
          ruff
          ripgrep
          gzip
          nerd-fonts.hack
          # Python debugging
          python3Packages.debugpy
          # Version control TUIs
          lazygit
          lazyjj
        ] ++ (with nodePackages; [
          dockerfile-language-server-nodejs
          typescript-language-server
          yaml-language-server
        ]);
      plugins = with pkgs.vimPlugins; [
        plenary-nvim
        vim-cool
        comment-nvim
        vim-smoothie
        nvim-autopairs # Replaced vim-closer with treesitter-aware autopairs
        vim-tmux-navigator # Seamless navigation between tmux panes and vim splits
        telescope-nvim
        telescope-ui-select-nvim
        telescope-fzf-native-nvim # Fast fuzzy finding
        legendary-nvim
        which-key-nvim # Keybinding hints
        nvim-tree-lua
        nvim-web-devicons
        lualine-nvim
        bufferline-nvim
        dressing-nvim
        fidget-nvim
        catppuccin-nvim
        FTerm-nvim
        undotree
        # Visual enhancement plugins
        alpha-nvim
        indent-blankline-nvim
        rainbow-delimiters-nvim
        nvim-colorizer-lua
        lspkind-nvim
        todo-comments-nvim # Highlight TODO/FIXME/etc
        trouble-nvim # Better diagnostics UI
        # Version control integration
        gitsigns-nvim # Git/jj diff signs in gutter
        lazygit-nvim # Lazygit floating window
        lazyjj-nvim # Lazyjj floating window (for jj VCS)
        # FZF integration
        fzf-vim
        # Modern Rust plugin (successor to rust-tools.nvim)
        rustaceanvim
        mini-nvim
        conform-nvim
        nvim-lspconfig
        # Snippet engine (replaced vim-vsnip with LuaSnip)
        luasnip
        friendly-snippets
        mason-nvim
        mason-lspconfig-nvim
        nvim-cmp
        cmp-nvim-lsp
        cmp_luasnip # LuaSnip completion source
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
        (nvim-treesitter.withPlugins (p:
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
            jsonc
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
            robots
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
          ]))
      ];
    };

    xdg.configFile."nvim".source = ./config;
    xdg.configFile."nvim".recursive = true;
  };
}
