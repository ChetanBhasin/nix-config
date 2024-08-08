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
        vim-cool
        comment-nvim
        barbecue-nvim
        vim-smoothie
        vim-closer
        telescope-nvim
        telescope-ui-select-nvim
        legendary-nvim
        nvim-tree-lua
        nvim-web-devicons
        lualine-nvim
        dressing-nvim
        fidget-nvim
        comment-nvim
        catppuccin-nvim
        FTerm-nvim
        undotree
        rust-tools-nvim
        nvim-lspconfig
        vim-vsnip
        mason-nvim
        mason-lspconfig-nvim
        harpoon
        legendary-nvim
        cmp-nvim-lsp
        cmp-vsnip
        cmp-nvim-lua
        cmp-zsh
        cmp-git
        cmp-tmux
        cmp-spell
        cmp-clippy
        cmp-copilot
        cmp-treesitter
        (nvim-treesitter.withPlugins
          (p: with p; [ astro awk bash c c_sharp cmake clojure comment commonlisp cpp css csv cuda dart dhall diff dockerfile editorconfig elixir elm erlang fortran git_config git_rebase gitattributes gitcommit gitignore gleam go goctl godot_resource gomod gosum gotmpl gowork gpg graphql haskell hcl helm hjson hocon html http hurl ini ispc java javascript jq jsdoc json json5 jsonc jsonnet julia just kconfig kotlin latex linkerscript llvm lua luadoc luap luau make markdown markdown_inline matlab mermaid meson mlir nginx nim ninja nix norg ocaml ocaml_interface ocamllex pem php phpdoc pod powershell printf prisma promql proto puppet purescript pymanifest python query rasi readline regex requirements rescript robot robots ruby rust scala scheme scss slint snakemake solidity ssh_config ssh_config starlark strace svelte swift tcl templ terraform textproto thrift tlaplus tmux todotxt toml tsv tsx twig typescript typespec typoscript typst v vim vimdoc vue wing wit xml yaml zig ]))
        copilot-lua
      ];
    };

    xdg.configFile."nvim".source = ./config;
    xdg.configFile."nvim".recursive = true;
  };
}
