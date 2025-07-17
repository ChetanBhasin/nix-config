{ config, pkgs, lib, ... }:
with lib;
let cfg = config.darwin-config-manager;
in {

  imports = [ ../systemPackages ];

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
    system.primaryUser = "chetan";

    programs.nix-index.enable = true;

    # Darwin-specific system packages only (shared packages are in ../systemPackages)
    environment.systemPackages = with pkgs; [
      darwin.apple_sdk.frameworks.SystemConfiguration
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.cctools
    ];

    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      BROWSER = "firefox";
      TERMINAL = "ghostty";
    };

    programs.zsh.enable = true;

    nix = {
      package = pkgs.nix;
      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        experimental-features = [ "nix-command" "flakes" ];
        trusted-users = [ "@admin" "chetan" ];
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };
    };

    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    security.pam.services.sudo_local.touchIdAuth = cfg.enableSudoTouch;

    system.defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleShowScrollBars = "WhenScrolling";
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSDisableAutomaticTermination = true;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        NSWindowResizeTime = 1.0e-3;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;
        _HIHideMenuBar = false;
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
        AppleScrollerPagingBehavior = true;
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
      };

      dock = {
        autohide = false; # Keep dock visible
        autohide-delay = 0.0;
        autohide-time-modifier = 0.2;
        expose-animation-duration = 0.1;
        launchanim = false;
        mineffect = "scale";
        minimize-to-application = true;
        mouse-over-hilite-stack = true;
        mru-spaces = false;
        orientation = "bottom";
        show-process-indicators = true;
        show-recents = false;
        showhidden = true;
        static-only = false; # Allow manually pinned apps
        tilesize = 44;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };

      finder = {
        _FXShowPosixPathInTitle = true;
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "clmv";
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      trackpad = {
        ActuationStrength = 0;
        Clicking = true;
        Dragging = true;
        FirstClickThreshold = 0;
        SecondClickThreshold = 0;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };

      ActivityMonitor = {
        IconType = 2;
        OpenMainWindow = true;
        ShowCategory = 103;
        SortColumn = "CPUUsage";
        SortDirection = 0;
      };

      screencapture = {
        location = "~/Pictures/Screenshots";
        type = "png";
      };
    };

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
        "tailscale-app"
        "ollama-app"
        "arc"
        "postico"
        "granola"
        "lens"
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
        "steam"
        "google-chrome"
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
          "cursor"
          "chatgpt"
        ];
    };

    fonts.packages = with pkgs; [ recursive nerd-fonts.jetbrains-mono ];

    system.stateVersion = 4;
  };
}
