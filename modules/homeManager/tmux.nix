# Standalone Tmux module for Home Manager
# Can be imported by other flakes via: inputs.nix-config.homeManagerModules.tmux
{ config, pkgs, lib, ... }:

let
  cfg = config.cb.tmux;

  # Paths to tmux config files (relative to this module)
  tmuxConfigPath = ../../home/tmux;

  # Custom catppuccin plugin (not yet in nixpkgs or using different version)
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
      default = "/bin/zsh";
      description = "Default shell to use in tmux";
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

      plugins = with pkgs.tmuxPlugins;
        [
          # Core functionality
          sensible
          pain-control

          # Visual feedback
          prefix-highlight
          battery
          cpu

          # Clipboard
          yank

          # Theme
          catppuccin
        ]
        # Vim integration
        ++ lib.optionals cfg.enableVimIntegration [ vim-tmux-navigator ]
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
        ${builtins.readFile (tmuxConfigPath + "/tmux.conf")}
        ${cfg.extraConfig}
      '';
    };

    # Pre-generated which-key menu configuration
    home.file.".config/tmux/which-key-init.tmux".source = tmuxConfigPath + "/which-key-init.tmux";

    # Required packages for tmux features
    home.packages = with pkgs;
      [
        coreutils
      ]
      ++ lib.optionals cfg.enableFzfIntegration [
        fzf
        ripgrep
        fd
        bat
        jq
        python3
      ];
  };
}
