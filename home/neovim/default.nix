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
          taplo-cli
          yamllint
          go
          ctags
          stylua
          ruff
          ripgrep
          gzip
          nerd-fonts.hack
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
        vim-closer
        telescope-nvim
        telescope-ui-select-nvim
        legendary-nvim
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
        # FZF integration
        fzf-vim
        # Modern Rust plugin (successor to rust-tools.nvim)
        rustaceanvim
        mini-nvim
        conform-nvim
        nvim-lspconfig
        vim-vsnip
        mason-nvim
        mason-lspconfig-nvim
        nvim-cmp
        cmp-nvim-lsp
        cmp-vsnip
        cmp-nvim-lua
        cmp-buffer
        cmp-path
        cmp-zsh
        cmp-git
        cmp-tmux
        cmp-spell
        cmp-clippy
        cmp-treesitter
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
