{ config, pkgs, ... }:
let
  tmuxPackage = import ../../packages/tmux-pane-borders.nix { inherit pkgs; };
  renamePopup = pkgs.writeShellScript "tmux-rename-popup" (builtins.readFile ./rename-popup.bash);
in
{
  programs.tmux = {
    enable = true;
    package = tmuxPackage;
    clock24 = true;
    keyMode = "vi";
    mouse = true;
    historyLimit = 50000;

    # Use C-Space as prefix (ergonomic, no conflicts with shell/terminal/neovim)
    prefix = "C-Space";

    # Essential modern plugins
    plugins = with pkgs.tmuxPlugins; [
      # Core functionality
      sensible
      pain-control
      vim-tmux-navigator

      # Session management and persistence
      resurrect
      continuum
      session-wizard

      # Enhanced user experience with FZF
      tmux-fzf
      extrakto
      fzf-tmux-url

      # Visual feedback and status
      battery

      # Clipboard integration
      yank

      # Vimium/easymotion-like hints for quick text selection
      tmux-thumbs

    ];

    # Use an immutable, cross-platform shell path (there is no /bin/zsh on NixOS)
    shell = "${pkgs.zsh}/bin/zsh";

    extraConfig = ''
      set -g @cb_tmux_config ${builtins.toJSON "${config.xdg.configHome}/tmux/tmux.conf"}
      set -g @cb_tmux_which_key ${builtins.toJSON "${config.xdg.configHome}/tmux/which-key-init.tmux"}
      set -g @cb_tmux_rename_popup ${builtins.toJSON "${renamePopup}"}
      ${builtins.readFile ./tmux.conf}
    '';
  };

  # Pre-generated which-key menu (generated from which-key-config.yaml via build.py)
  xdg.configFile."tmux/which-key-init.tmux".source = ./which-key-init.tmux;

  # Install required dependencies
  home.packages = with pkgs; [
    fzf
    ripgrep
    fd
    bat
    jq
    python313
    # Keep Alacritty's TERM entry available on SSH destinations
    alacritty.terminfo
    coreutils
    git
    lazygit
  ];
}
