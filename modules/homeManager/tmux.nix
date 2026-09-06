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

  # Paths to tmux config files (relative to this module)
  tmuxConfigPath = ../../home/tmux;
  renamePopup = pkgs.writeShellScript "tmux-rename-popup" (
    builtins.readFile (tmuxConfigPath + "/rename-popup.bash")
  );
in
{
  options.cb.tmux = {
    enable = lib.mkEnableOption "Chetan's tmux configuration";

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
        ++ cfg.extraPlugins;

      extraConfig = ''
        set -g @cb_tmux_config ${builtins.toJSON "${config.xdg.configHome}/tmux/tmux.conf"}
        set -g @cb_tmux_which_key ${builtins.toJSON "${config.xdg.configHome}/tmux/which-key-init.tmux"}
        set -g @cb_tmux_rename_popup ${builtins.toJSON "${renamePopup}"}
        set -g @cb_tmux_fzf ${if cfg.enableFzfIntegration then "1" else "0"}
        set -g @cb_tmux_thumbs ${if cfg.enableThumbs then "1" else "0"}
        ${builtins.readFile (tmuxConfigPath + "/tmux.conf")}
        ${cfg.extraConfig}
      '';
    };

    # Pre-generated which-key menu configuration
    xdg.configFile."tmux/which-key-init.tmux".source = tmuxConfigPath + "/which-key-init.tmux";

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
      ];
  };
}
