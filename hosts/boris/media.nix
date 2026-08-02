{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  allowedBigscreenApplications = [
    "VacuumTube"
    "apple-tv-bigscreen"
    "org.jellyfin.JellyfinDesktop"
    "netflix-bigscreen"
    "prime-video-bigscreen"
    "spotify-bigscreen"
    "steam"
  ];
  allowedBigscreenApplicationsPattern = lib.concatStringsSep "|" allowedBigscreenApplications;
  jellyfinServerUrl = "https://media.cbopt.com/web/";
  jellyfinDesktopProfileId = "6a73f1e1f79a4b0a9db71aefc8f64e42";
  jellyfinDesktopProfileName = "Boris";
  jellyfinDesktopProfilesJson = builtins.toJSON {
    defaultProfile = jellyfinDesktopProfileId;
    profiles = [
      {
        id = jellyfinDesktopProfileId;
        name = jellyfinDesktopProfileName;
        url = jellyfinServerUrl;
        created = "2026-08-02T00:00:00";
      }
    ];
  };
  jellyfinDesktopProfileJson = builtins.toJSON {
    name = jellyfinDesktopProfileName;
    url = jellyfinServerUrl;
  };
  jellyfinDesktopConfigJson = builtins.toJSON {
    version = 7;
    sections = {
      main = {
        fullscreen = true;
        layout = "tv";
        webMode = "tv";
      };
      path = {
        startupurl_desktop = jellyfinServerUrl;
        startupurl_extension = "bundled";
      };
    };
  };

  mkBigscreenWebApplication =
    {
      name,
      url,
    }:
    pkgs.writeShellApplication {
      name = "bigscreen-${name}";
      text = ''
        profile_directory="$HOME/.local/share/bigscreen-web-applications/${name}"
        mkdir -p "$profile_directory"

        exec ${lib.getExe pkgs.google-chrome} \
          --app=${lib.escapeShellArg url} \
          --start-fullscreen \
          --no-first-run \
          --no-default-browser-check \
          --disable-default-apps \
          --disable-session-crashed-bubble \
          --password-store=basic \
          --user-data-dir="$profile_directory" \
          "$@"
      '';
    };

  appleTvBigscreen = mkBigscreenWebApplication {
    name = "apple-tv";
    url = "https://tv.apple.com/";
  };
  spotifyBigscreen = mkBigscreenWebApplication {
    name = "spotify";
    url = "https://open.spotify.com/";
  };
  netflixBigscreen = mkBigscreenWebApplication {
    name = "netflix";
    url = "https://www.netflix.com/";
  };
  primeVideoBigscreen = mkBigscreenWebApplication {
    name = "prime-video";
    url = "https://www.primevideo.com/";
  };
  ensureBluetoothPowered = pkgs.writeShellApplication {
    name = "ensure-bluetooth-powered";
    runtimeInputs = [
      pkgs.bluez
      pkgs.gawk
      pkgs.kdePackages.kconfig
    ];
    text = ''
      while IFS= read -r adapter; do
        [[ -n "$adapter" ]] || continue
        kwriteconfig6 \
          --file "$HOME/.config/bluedevilglobalrc" \
          --group Adapters \
          --key "''${adapter}_powered" \
          --type bool \
          true
      done < <(bluetoothctl list | awk '{ print $2 }')

      bluetoothctl power on
    '';
  };
in
{
  home = {
    username = "media";
    homeDirectory = "/home/media";
    stateVersion = "23.05";

    # Bigscreen has a native application blacklist but no allowlist. Generate
    # the blacklist from the active profiles so its launcher stays limited to
    # the TV applications declared here.
    activation.bigscreenApplicationAllowlist = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_directory="$HOME/.config"
      mkdir -p "$config_directory"
      temporary_file="$(${pkgs.coreutils}/bin/mktemp "$config_directory/.applications-blacklistrc.XXXXXX")"
      trap '${pkgs.coreutils}/bin/rm -f "$temporary_file"' EXIT

      blacklist_csv="$(
        {
          for applications_directory in \
            "$HOME/.local/share/applications" \
            "/etc/profiles/per-user/media/share/applications" \
            "/run/current-system/sw/share/applications"
          do
            if [[ -d "$applications_directory" ]]; then
              ${pkgs.findutils}/bin/find \
                "$applications_directory" \
                -name '*.desktop' -print
            fi
          done
        } \
          | while IFS= read -r desktop_file; do
              application_id="$(${pkgs.coreutils}/bin/basename "$desktop_file" .desktop)"
              case "$application_id" in
                ${allowedBigscreenApplicationsPattern}) ;;
                *) printf '%s\n' "$application_id" ;;
              esac
            done \
          | ${pkgs.coreutils}/bin/sort -u \
          | ${pkgs.coreutils}/bin/paste -sd, -
      )"

      {
        printf '%s\n' '[Applications]'
        printf 'blacklist=%s\n' "$blacklist_csv"
      } > "$temporary_file"
      ${pkgs.coreutils}/bin/chmod 0644 "$temporary_file"
      ${pkgs.coreutils}/bin/mv "$temporary_file" "$config_directory/applications-blacklistrc"
      trap - EXIT
    '';

    activation.jellyfinDesktopRemoteServer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      jellyfin_desktop_data_dir="$HOME/.local/share/jellyfin-desktop"
      jellyfin_desktop_profile_dir="$jellyfin_desktop_data_dir/profiles/${jellyfinDesktopProfileId}"
      ${pkgs.coreutils}/bin/mkdir -p "$jellyfin_desktop_profile_dir/logs"

      printf '%s\n' ${lib.escapeShellArg jellyfinDesktopProfilesJson} > "$jellyfin_desktop_data_dir/profiles.json"
      printf '%s\n' ${lib.escapeShellArg jellyfinDesktopProfileJson} > "$jellyfin_desktop_profile_dir/profile.json"
      printf '%s\n' ${lib.escapeShellArg jellyfinDesktopConfigJson} > "$jellyfin_desktop_profile_dir/jellyfin-desktop.conf"

      ${pkgs.coreutils}/bin/chmod 0644 \
        "$jellyfin_desktop_data_dir/profiles.json" \
        "$jellyfin_desktop_profile_dir/profile.json" \
        "$jellyfin_desktop_profile_dir/jellyfin-desktop.conf"
    '';
  };

  systemd.user = {
    services.ensure-bluetooth-powered = {
      Unit = {
        Description = "Keep Bluetooth enabled for the Boris media session";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe ensureBluetoothPowered;
      };
    };

    timers.ensure-bluetooth-powered = {
      Unit = {
        Description = "Enable Bluetooth after Plasma restores its saved state";
        PartOf = [ "graphical-session.target" ];
      };
      Timer = {
        OnActiveSec = "5s";
        AccuracySec = "1s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.desktopEntries = {
    VacuumTube = {
      name = "VacuumTube";
      comment = "Watch YouTube in TV mode";
      exec = "${lib.getExe pkgs.vacuum-tube} --fullscreen --no-window-decorations";
      icon = "${pkgs.vacuum-tube.src}/assets/icon.svg";
      categories = [
        "AudioVideo"
        "Video"
        "TV"
      ];
      settings.StartupWMClass = "VacuumTube";
    };

    apple-tv-bigscreen = {
      name = "Apple TV";
      comment = "Watch Apple TV in fullscreen";
      exec = lib.getExe appleTvBigscreen;
      icon = "applications-multimedia";
      categories = [
        "AudioVideo"
        "Video"
        "TV"
      ];
    };

    "org.jellyfin.JellyfinDesktop" = {
      name = "Jellyfin";
      comment = "Watch Jellyfin in TV mode";
      exec = "${pkgs.jellyfin-desktop}/bin/jellyfin-desktop --fullscreen --tv";
      icon = "${pkgs.jellyfin-desktop.src}/resources/images/icon.svg";
      categories = [
        "AudioVideo"
        "Video"
        "TV"
      ];
      settings.StartupWMClass = "org.jellyfin.JellyfinDesktop";
    };

    spotify-bigscreen = {
      name = "Spotify";
      comment = "Listen to Spotify in fullscreen";
      exec = lib.getExe spotifyBigscreen;
      icon = "audio-headphones";
      categories = [
        "AudioVideo"
        "Audio"
        "Music"
      ];
    };

    netflix-bigscreen = {
      name = "Netflix";
      comment = "Watch Netflix in fullscreen";
      exec = lib.getExe netflixBigscreen;
      icon = "applications-multimedia";
      categories = [
        "AudioVideo"
        "Video"
        "TV"
      ];
    };

    prime-video-bigscreen = {
      name = "Prime Video";
      comment = "Watch Prime Video in fullscreen";
      exec = lib.getExe primeVideoBigscreen;
      icon = "applications-multimedia";
      categories = [
        "AudioVideo"
        "Video"
        "TV"
      ];
    };

    steam = {
      name = "Steam";
      comment = "Play games in Steam Gamepad UI";
      exec = "${osConfig.programs.steam.package}/bin/steam -gamepadui %U";
      icon = "steam";
      categories = [ "Game" ];
      settings.StartupWMClass = "Steam";
    };
  };
}
