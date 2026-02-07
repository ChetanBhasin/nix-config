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
    clock24 = true;
    keyMode = "vi";
    mouse = true;

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
      prefix-highlight
      battery
      cpu

      # Clipboard integration
      yank

      # Vimium/easymotion-like hints for quick text selection
      tmux-thumbs

      # Theme
      catppuccin
    ];

    # Shell integration - use system zsh which is in /etc/shells
    shell = "/bin/zsh";

    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
    '';
  };

  # Pre-generated which-key menu (generated from which-key-config.yaml via build.py)
  home.file.".config/tmux/which-key-init.tmux".source = ./which-key-init.tmux;

  # Install required dependencies
  home.packages = with pkgs; [ fzf ripgrep fd bat jq python3 coreutils ];
}
