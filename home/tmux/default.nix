{ config, pkgs, ... }:
let
  catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-catppuccin";
    version = "default";
    src = pkgs.fetchFromGitHub {
      owner = "dreamsofcode-io";
      repo = "catppuccin-tmux";
      rev = "4e48b09a76829edc7b55fbb15467cf0411f07931";
      sha256 = "sha256-ymmCI6VYvf94Ot7h2GAboTRBXPIREP+EB33+px5aaJk=";
    };
  };
in {
  programs.tmux = {
    enable = true;
    clock24 = false;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      catppuccin
      yank
      vim-tmux-navigator
      resurrect
    ];
    keyMode = "vi";
    mouse = true;
    tmuxp.enable = true;
    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
    '';
  };
}
