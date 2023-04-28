{ config, pkgs, ... }:
let
  catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "catppuccin";
    version = "default";
    src = pkgs.fetchFromGitHub {
      owner = "Millrocious";
      repo = "tmux";
      rev = "f71e781b56a45c97dfaa6519bc2914837a9b5f78";
      sha256 = "sha256-fJlQYstWEk3y1kJxoY+ylJ8vU9zTeidDr/vIp9ZtubM=";
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
