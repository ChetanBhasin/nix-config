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
          nil
          taplo-cli
          yamllint
          go
          ctags
          stylua
          ripgrep
          gzip
          nerdfonts
        ] ++ (with nodePackages; [
          dockerfile-language-server-nodejs
          typescript-language-server
          yaml-language-server
        ]) ++ lib.optionals pkgs.stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
        ];
      plugins = with pkgs.vimPlugins; [
        plenary-nvim
        telescope-nvim
        dressing-nvim
        comment-nvim
        catppuccin-nvim
        FTerm-nvim
        undotree
        rust-tools-nvim
        nvim-lspconfig
        (nvim-treesitter.withPlugins (plugins:
          with plugins; [
            tree-sitter-bash
            tree-sitter-css
            tree-sitter-dart
            tree-sitter-dockerfile
            tree-sitter-eex
            tree-sitter-elixir
            tree-sitter-graphql
            tree-sitter-go
            tree-sitter-hcl
            tree-sitter-html
            tree-sitter-json
            tree-sitter-jsonnet
            tree-sitter-latex
            tree-sitter-lua
            tree-sitter-make
            tree-sitter-markdown
            tree-sitter-nix
            tree-sitter-org-nvim
            tree-sitter-prisma
            tree-sitter-python
            tree-sitter-regex
            tree-sitter-rust
            tree-sitter-scala
            tree-sitter-svelte
            tree-sitter-sql
            tree-sitter-toml
            tree-sitter-tsx
            tree-sitter-typescript
            tree-sitter-vim
            tree-sitter-yaml
          ]))
      ];
    };

    xdg.configFile."nvim".source = ./config;
    xdg.configFile."nvim".recursive = true;
  };
}
