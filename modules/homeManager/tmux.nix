# Standalone Tmux module for Home Manager
# Can be imported by other flakes via: inputs.nix-config.homeManagerModules.tmux
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.cb.tmux;
  tmuxPackage = import ../../packages/tmux-pane-borders.nix { inherit pkgs; };

  # Paths to tmux config files (relative to this module)
  tmuxConfigPath = ../../home/tmux;
  renamePopup = pkgs.writeShellScript "tmux-rename-popup" (
    builtins.readFile (tmuxConfigPath + "/rename-popup.bash")
  );

  tmuxFleet = pkgs.callPackage ../../packages/tmux-fleet.nix { };
  tmuxFleetPlugin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-fleet";
    version = "0.1.0";
    src = tmuxConfigPath + "/tmux-fleet-plugin";
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
  options.cb.tmux = {
    enable = lib.mkEnableOption "Chetan's tmux configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = tmuxPackage;
      defaultText = lib.literalExpression "tmuxPackage";
      description = ''
        Tmux package to install. The default pins upstream PR #5433 for full
        per-pane frames and carries a small rounded-corner patch.
      '';
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "C-Space";
      description = "Tmux prefix key";
    };

    enableVimIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable vim-tmux-navigator for seamless navigation between vim and tmux";
    };

    enableSessionPersistence = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable tmux-resurrect and tmux-continuum for session persistence";
    };

    enableFzfIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable FZF-powered features (session switching, URL opening, etc.)";
    };

    enableThumbs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable tmux-thumbs for vimium-like text selection hints";
    };

    fleet = {
      enable = lib.mkEnableOption "the local and SSH tmux fleet controller";

      remoteHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "workstation"
          "laptop"
        ];
        description = ''
          SSH host aliases whose tmux sessions should appear beside local sessions.
          Configure public-key authentication for each alias in ssh_config.
          Omit the current machine; enable fleet mode on every listed peer.
        '';
      };

      reconcileSeconds = lib.mkOption {
        type = lib.types.ints.between 1 3600;
        default = 30;
        description = "Background full-snapshot interval for missed tmux events";
      };

      connectTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.between 1 300;
        default = 5;
        description = "Timeout for each background SSH connection attempt";
      };

      serverAliveIntervalSeconds = lib.mkOption {
        type = lib.types.ints.between 1 3600;
        default = 15;
        description = "Interval between OpenSSH keepalive messages";
      };

      serverAliveCountMax = lib.mkOption {
        type = lib.types.ints.between 1 100;
        default = 2;
        description = "Unanswered OpenSSH keepalives allowed before reconnecting";
      };

      controlPersistSeconds = lib.mkOption {
        type = lib.types.ints.between 1 86400;
        default = 600;
        description = "Lifetime of an idle shared OpenSSH control connection";
      };
    };
    shell = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.zsh}/bin/zsh";
      description = "Default shell executable to use in tmux";
    };

    historyLimit = lib.mkOption {
      type = lib.types.int;
      default = 50000;
      description = "Scrollback buffer history limit";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra tmux configuration to append";
    };

    extraPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional tmux plugins";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      package = cfg.package;
      clock24 = true;
      keyMode = "vi";
      mouse = true;
      prefix = cfg.prefix;
      shell = cfg.shell;
      historyLimit = cfg.historyLimit;

      plugins =
        with pkgs.tmuxPlugins;
        [
          # Core functionality
          sensible
          pain-control

          # Visual feedback
          battery

          # Clipboard
          yank

        ]
        # Vim integration
        ++ lib.optionals cfg.enableVimIntegration [
          vim-tmux-navigator
        ]
        # Session persistence
        ++ lib.optionals cfg.enableSessionPersistence [
          resurrect
          continuum
          session-wizard
        ]
        # FZF integration
        ++ lib.optionals cfg.enableFzfIntegration [
          tmux-fzf
          extrakto
          fzf-tmux-url
        ]
        # Thumbs (vimium-like hints)
        ++ lib.optionals cfg.enableThumbs [ tmux-thumbs ]
        ++ lib.optionals cfg.fleet.enable [ tmuxFleetPlugin ]
        ++ cfg.extraPlugins;

      extraConfig = ''
        set -g @cb_tmux_config ${builtins.toJSON "${config.xdg.configHome}/tmux/tmux.conf"}
        set -g @cb_tmux_which_key ${builtins.toJSON "${config.xdg.configHome}/tmux/which-key-init.tmux"}
        set -g @cb_tmux_rename_popup ${builtins.toJSON "${renamePopup}"}
        set -g @cb_tmux_fzf ${if cfg.enableFzfIntegration then "1" else "0"}
        set -g @cb_tmux_thumbs ${if cfg.enableThumbs then "1" else "0"}
        set -g @cb_tmux_fleet ${if cfg.fleet.enable then "1" else "0"}
        ${builtins.readFile (tmuxConfigPath + "/tmux.conf")}
        ${cfg.extraConfig}
      '';
    };

    # Pre-generated which-key menu configuration
    xdg.configFile."tmux/which-key-init.tmux".source = tmuxConfigPath + "/which-key-init.tmux";

    xdg.configFile."tmux-fleet/config.json" = lib.mkIf cfg.fleet.enable {
      text =
        builtins.toJSON {
          hosts = cfg.fleet.remoteHosts;
          reconcile_seconds = cfg.fleet.reconcileSeconds;
          connect_timeout_seconds = cfg.fleet.connectTimeoutSeconds;
          server_alive_interval_seconds = cfg.fleet.serverAliveIntervalSeconds;
          server_alive_count_max = cfg.fleet.serverAliveCountMax;
          control_persist_seconds = cfg.fleet.controlPersistSeconds;
          tmux_command = "${cfg.package}/bin/tmux";
          fzf_command = "${pkgs.fzf}/bin/fzf";
          ssh_command = sshCommand;
        }
        + "\n";
    };

    # Stable path used by noninteractive SSH commands across profile layouts.
    home.file.".local/libexec/tmux-fleet" = lib.mkIf cfg.fleet.enable {
      source = "${tmuxFleet}/bin/tmux-fleet";
    };

    # Required packages for tmux features
    home.packages =
      with pkgs;
      [
        # Keep Alacritty's TERM entry available on SSH destinations
        alacritty.terminfo
        coreutils
        git
        lazygit
      ]
      ++ lib.optionals cfg.enableFzfIntegration [
        fzf
        ripgrep
        fd
        bat
        jq
        python313
      ]
      ++ lib.optionals cfg.fleet.enable [ tmuxFleet ];
  };
}
