{ config, pkgs, ... }:
let
  catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "catppuccin";
    version = "default";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "tmux";
      rev = "10d1b1f7c3e235dfe0bb0082970cb559615bdb25";
      sha256 = "sha256-Csvw9JLe6Djs5svYpW20Lh3pJ/og4WHtghwaISnK2dI=";
    };
  };
in {
  programs.tmux = {
    enable = true;
    clock24 = false;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      nord
      pain-control
      vim-tmux-navigator
      resurrect
      catppuccin
    ];
    keyMode = "vi";
    mouse = true;
    tmuxp.enable = true;
    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
    '';
  };
}
