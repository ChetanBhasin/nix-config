{ config, pkgs, ... }: {
  programs.tmux = {
    enable = true;
    clock24 = false;
    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
    '';
  };
}
