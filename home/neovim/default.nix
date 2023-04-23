{ flake, config, pkgs, lib, ... }:
let home = config.home.homeDirectory;
in {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    defaultEditor = true;
    package = pkgs.neovim;
    extraPackages = with pkgs; [
      nodePackages.bash-language-server
      shellcheck

      nodePackages.dockerfile-language-server-nodejs
      nodePackages.vscode-langservers-extracted
      nodePackages.typescript-language-server

      luaformatter
      lua-language-server
      lua54Packages.luacheck

      deadnix
      statix
      nil

      terraform-lsp

      # TOML
      taplo-cli

      nodePackages.yaml-language-server
      yamllint

      (pkgs.writeShellScriptBin "clean-nvim-all" ''
        rm -rf ${config.xdg.dataHome}/nvim
        rm -rf ${config.xdg.cacheHome}/nvim
        rm -rf ${config.xdg.stateHome}/nvim
        rm -rf ${config.xdg.configHome}/nvim
      '')
      (pkgs.writeShellScriptBin "clean-nvim" ''
        rm -rf ${config.xdg.dataHome}/nvim
        rm -rf ${config.xdg.stateHome}/nvim
        rm -rf ${config.xdg.cacheHome}/nvim
      '')
    ];
  };

  xdg.configFile."nvim" = {
    source = config.lib.file.mkOutOfStoreSymlink "${home}/.config/nvim";
    recursive = true;
  };

}
