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

    extraBrews = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Homebrew formulae for this host";
    };

    extraCasks = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Homebrew casks for this host";
    };
  };

  config = {
    system.primaryUser = "chetan";

    programs.nix-index.enable = true;

    # Darwin-specific system packages only (shared packages are in ../systemPackages)
    environment.systemPackages = with pkgs; [ apple-sdk darwin.cctools ];

    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      BROWSER = "firefox";
      TERMINAL = "alacritty";
    };

    programs.zsh.enable = true;

    nix = {
      package = pkgs.nix;
      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
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
        # Appearance
        AppleInterfaceStyle = "Dark";
        AppleShowScrollBars = "WhenScrolling";

        # Locale & Measurement
        AppleMeasurementUnits = "Centimeters";
        AppleMetricUnits = 1;
        AppleTemperatureUnit = "Celsius";

        # Text & Typing
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        ApplePressAndHoldEnabled = false; # Disable accent menu, enable key repeat

        # Keyboard
        InitialKeyRepeat = 15;
        KeyRepeat = 2;

        # System Behavior
        NSDisableAutomaticTermination = true;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        NSWindowResizeTime = 1.0e-3;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;
        _HIHideMenuBar = false;
        AppleScrollerPagingBehavior = true;
        AppleShowAllExtensions = true;

        # Sound
        "com.apple.sound.beep.volume" = 0.0;

        # Trackpad & Mouse
        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.trackpad.enableSecondaryClick" = true;
        "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
      };

      dock = {
        autohide = false; # Keep dock visible
        autohide-delay = 0.0;
        autohide-time-modifier = 0.2;
        expose-animation-duration = 0.1;
        launchanim = false;
        largesize = 128; # Magnification icon size
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
        FXRemoveOldTrashItems = true; # Auto-delete trash after 30 days
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
        TrackpadThreeFingerTapGesture = 0;
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

      # Additional settings via CustomUserPreferences
      CustomUserPreferences = {
        # NSGlobalDomain settings not directly supported by nix-darwin
        NSGlobalDomain = {
          AppleICUForce12HourTime = true;
          AppleReduceDesktopTinting = false;
          AppleMenuBarVisibleInFullscreen = false;
          AppleEnableSwipeNavigateWithScrolls = false;
          AppleMiniaturizeOnDoubleClick = false;
          "com.apple.sound.beep.flash" = 0;
          "com.apple.trackpad.forceClick" = true;
          "com.apple.springing.enabled" = true;
          "com.apple.springing.delay" = 0.5;
        };

        "com.apple.AppleMultitouchTrackpad" = {
          # Gestures
          TrackpadFiveFingerPinchGesture = 2;
          TrackpadFourFingerHorizSwipeGesture = 2;
          TrackpadFourFingerPinchGesture = 2;
          TrackpadFourFingerVertSwipeGesture = 2;
          TrackpadThreeFingerHorizSwipeGesture = 0; # Disabled (using 3-finger drag)
          TrackpadThreeFingerVertSwipeGesture = 0; # Disabled (using 3-finger drag)
          TrackpadTwoFingerDoubleTapGesture = 1;
          TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;

          # Scrolling & Interaction
          TrackpadHandResting = true;
          TrackpadHorizScroll = true;
          TrackpadMomentumScroll = true;
          TrackpadPinch = true;
          TrackpadRotate = true;
          TrackpadScroll = true;

          # Other
          TrackpadCornerSecondaryClick = 0;
          USBMouseStopsTrackpad = false;
          DragLock = false;
          ForceSuppressed = false;
          ActuateDetents = true;
        };

        "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
          # Mirror settings for Bluetooth trackpad
          TrackpadFiveFingerPinchGesture = 2;
          TrackpadFourFingerHorizSwipeGesture = 2;
          TrackpadFourFingerPinchGesture = 2;
          TrackpadFourFingerVertSwipeGesture = 2;
          TrackpadThreeFingerHorizSwipeGesture = 0;
          TrackpadThreeFingerVertSwipeGesture = 0;
          TrackpadTwoFingerDoubleTapGesture = 1;
          TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
          TrackpadHandResting = true;
          TrackpadHorizScroll = true;
          TrackpadMomentumScroll = true;
          TrackpadPinch = true;
          TrackpadRotate = true;
          TrackpadScroll = true;
          TrackpadCornerSecondaryClick = 0;
          USBMouseStopsTrackpad = false;
          DragLock = false;
        };
      };
    };

    homebrew = {
      enable = true;
      user = "chetan";
      onActivation.autoUpdate = true;
      onActivation = { cleanup = "uninstall"; };

      # Base brews (all hosts)
      brews = [ ]
        ++ lib.optionals cfg.enableProf [ "krb5" "docker" "rocksdb" ]
        ++ lib.optionals cfg.enableExtras [ "nodenv" "docker" ]
        ++ cfg.extraBrews;

      # Base casks (all hosts)
      casks = [
        "tailscale-app"
        "codex"
        "postico"
        "lens"
        "alacritty"
        "db-browser-for-sqlite"
        "firefox"
        "fork"
        "hammerspoon"
        "jetbrains-toolbox"
        "vlc"
        "obsidian"
        "slack"
        "zen"
        "utm"
        "logi-options+"
        "google-chrome"
      ] ++ lib.optionals cfg.enableProf [ "thunderbird" ]
        ++ lib.optionals cfg.enableExtras [
          "ticktick"
          "yubico-authenticator"
          "whatsapp@beta"
          "notion-calendar"
          "telegram"
          "signal"
          "protonvpn"
          "proton-drive"
          "proton-pass"
          "figma"
          "discord"
          "spotify"
          "caffeine"
          "monitorcontrol"
          "proton-mail"
          "macfuse"
          "orbstack"
          "oracle-jdk"
          "cursor"
          "chatgpt"
        ]
        ++ cfg.extraCasks;
    };

    fonts.packages = with pkgs; [ recursive nerd-fonts.jetbrains-mono ];

    system.stateVersion = 4;
  };
}
