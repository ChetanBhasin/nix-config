{ config, pkgs, lib, ... }:
with lib;
let python-debug = pkgs.python3.withPackages (p: with p; [ debugpy ]);
in {
  config = {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      # let g:python_debug_home = "${python-debug}"
      extraConfig = ''
        :luafile ~/.config/nvim/lua/init.lua
      '';
    };

    xdg.configFile.nvim = {
      source = ./config;
      recursive = true;
    };
  };
}
