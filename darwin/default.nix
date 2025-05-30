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

    fonts = { packages = with pkgs; [ dejavu_fonts hack-font ]; };

    homebrew = {
      enable = true;
      user = "chetan";
      onActivation.autoUpdate = true;
      onActivation = { cleanup = "uninstall"; };
      brews = [ "cloudflared" ]
        ++ lib.optionals cfg.enableProf [ "krb5" "docker" "rocksdb" ]
        ++ lib.optionals cfg.enableExtras [ "flyctl" "nodenv" "docker" ];
      casks = [
        "1password"
        "ghostty"
        "db-browser-for-sqlite"
        "firefox"
        "fork"
        "hammerspoon"
        "jetbrains-toolbox"
        "open-in-code"
        "vlc"
        "obsidian"
        "slack"
        "zen"
        "utm"
        "logi-options+"
      ] ++ lib.optionals cfg.enableProf [ "thunderbird" ]
      ++ lib.optionals cfg.enableExtras [
        "netdownloadhelpercoapp"
        "cloudflare-warp"
        "balenaetcher"
        "ticktick"
        "proton-mail-bridge"
        "yubico-authenticator"
        "whatsapp@beta"
        "notion-calendar"
        "cryptomator"
        "tailscale"
        "tailscale"
        "telegram"
        "signal"
        "remarkable"
        "protonvpn"
        "proton-drive"
        "proton-pass"
        "figma"
        "discord"
        "spotify"
        "caffeine"
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
        "ollama"
        "cursor"
        "chatgpt"
      ];
    };

    # Use Touch ID for sudo
    security.pam.services.sudo_local.touchIdAuth = cfg.enableSudoTouch;

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    system.stateVersion = 4;
  };
}
