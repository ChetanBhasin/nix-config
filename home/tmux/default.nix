{ config, pkgs, ... }: {
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
      {
        plugin = gruvbox;
        extraConfig = ''
          set -g @tmux-gruvbox 'dark'
          set -g @tmux-gruvbox-statusbar-alpha 'true'
        '';
      }
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
