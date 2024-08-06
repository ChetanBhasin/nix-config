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
        vim-smoothie
        vim-closer
        telescope-nvim
        telescope-ui-select-nvim
        nvim-tree-lua
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
        nvim-treesitter.withAllGrammars
        copilot-lua
      ];
    };

    xdg.configFile."nvim".source = ./config;
    xdg.configFile."nvim".recursive = true;
  };
}
