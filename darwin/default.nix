{ config, pkgs, lib, ... }:
with lib;
let cfg = config.darwin-config-manager;
in
{
  options.darwin-config-manager = {
    enableSudoTouch = lib.mkEnableOption "sudo touch id";
    enableExtras = lib.mkEnableOption "enable extra macOS applications";
    enableProf = lib.mkEnableOption "enable professional macOS applications";

    theme = lib.mkOption {
      type = types.str;
      default = "nord";
      description = ''
        Theme to apply
      '';
    };
  };

  config = {

    services.nix-daemon.enable = true;
    programs.nix-index.enable = true;

    nix = {
      package = pkgs.nixStable;
      # Add cache for nix-community, used mainly for neovim nightly
      settings = {
        substituters = [ "https://nix-community.cachix.org" ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
      # Enable Flakes
      extraOptions = "experimental-features = nix-command flakes";
    };

    fonts = {
      packages = with pkgs; [ dejavu_fonts hack-font ];
    };

    homebrew = {
      enable = true;
      onActivation.autoUpdate = true;
      onActivation = { cleanup = "uninstall"; };
      brews = [ "cloudflared" ] ++ lib.optionals cfg.enableProf [ "krb5" "docker" "rocksdb" ]
        ++ lib.optionals cfg.enableExtras [ "flyctl" "nodenv" "docker" ];
      casks = [
        "1password"
        "alacritty"
        "db-browser-for-sqlite"
        "firefox"
        "fork"
        "hammerspoon"
        "jetbrains-toolbox"
        "postico"
        "open-in-code"
        "vlc"
        "obsidian"
        "slack"
        "arc"
        "utm"
      ] ++ lib.optionals cfg.enableProf [ "thunderbird" ]
      ++ lib.optionals cfg.enableExtras [
        "ticktick"
        "yubico-authenticator"
        "whatsapp"
        "tradingview"
        "notion-calendar"
        "cryptomator"
        "tailscale"
        "tailscale"
        "telegram"
        "signal"
        "remarkable"
        "protonvpn"
        "proton-drive"
        "protonmail-bridge"
        "figma"
        "discord"
        "spotify"
        "deepl"
        "caffeine"
        "raycast"
        "monitorcontrol"
        "shureplus-motiv"
        "insta360-studio"
        "screen-studio"
        "proton-mail"
        "macfuse"
        "orbstack"
        "notion"
        "zoom"
        "oracle-jdk"
      ];
    };

    # Use Touch ID for sudo
    security.pam.enableSudoTouchIdAuth = cfg.enableSudoTouch;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    system.stateVersion = 4;
  };
}
