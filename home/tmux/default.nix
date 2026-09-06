{ config, pkgs, ... }:
let
  tmuxPackage = import ../../packages/tmux-pane-borders.nix { inherit pkgs; };
  renamePopup = pkgs.writeShellScript "tmux-rename-popup" (builtins.readFile ./rename-popup.bash);
  tmuxFleet = pkgs.callPackage ../../packages/tmux-fleet.nix { };
  tmuxFleetPlugin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-fleet";
    version = "0.1.0";
    src = ./tmux-fleet-plugin;
    postInstall = ''
      substituteInPlace "$target/tmux_fleet.tmux" \
        --replace-fail '@tmuxFleet@' '${tmuxFleet}/bin/tmux-fleet' \
        --replace-fail '@tmuxFleetSwitch@' "$target/tmux_fleet_switch"
      substituteInPlace "$target/tmux_fleet_switch" \
        --replace-fail '@tmuxFleet@' '${tmuxFleet}/bin/tmux-fleet'
      chmod +x "$target/tmux_fleet.tmux" "$target/tmux_fleet_switch"
    '';
  };
  sshCommand =
    if pkgs.stdenv.hostPlatform.isDarwin then "/usr/bin/ssh" else "${pkgs.openssh}/bin/ssh";
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

      tmuxFleetPlugin
    ];

    # Use an immutable, cross-platform shell path (there is no /bin/zsh on NixOS)
    shell = "${pkgs.zsh}/bin/zsh";

    extraConfig = ''
      set -g @cb_tmux_config ${builtins.toJSON "${config.xdg.configHome}/tmux/tmux.conf"}
      set -g @cb_tmux_which_key ${builtins.toJSON "${config.xdg.configHome}/tmux/which-key-init.tmux"}
      set -g @cb_tmux_rename_popup ${builtins.toJSON "${renamePopup}"}
      set -g @cb_tmux_fleet 1
      ${builtins.readFile ./tmux.conf}
    '';
  };

  # Pre-generated which-key menu (generated from which-key-config.yaml via build.py)
  xdg.configFile."tmux/which-key-init.tmux".source = ./which-key-init.tmux;

  xdg.configFile."tmux-fleet/config.json".text =
    builtins.toJSON {
      hosts = config.home-config-manager.tmuxFleetRemoteHosts;
      reconcile_seconds = 30;
      connect_timeout_seconds = 5;
      server_alive_interval_seconds = 15;
      server_alive_count_max = 2;
      control_persist_seconds = 600;
      tmux_command = "${tmuxPackage}/bin/tmux";
      fzf_command = "${pkgs.fzf}/bin/fzf";
      ssh_command = sshCommand;
    }
    + "\n";

  # Stable path used by noninteractive SSH commands across Darwin and NixOS profiles.
  home.file.".local/libexec/tmux-fleet".source = "${tmuxFleet}/bin/tmux-fleet";
  # Install required dependencies
  home.packages = with pkgs; [
    tmuxFleet
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
