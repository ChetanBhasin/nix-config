{ config, pkgs, ... }: {
  programs.tmux = {
    enable = true;
    clock24 = false;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      nord
      pain-control
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
