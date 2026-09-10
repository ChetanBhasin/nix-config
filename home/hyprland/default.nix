{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.home-config-manager;
  theme = import ../../modules/theme/gruvbox-night.nix;
  # Hyprland/hyprlock take colours as rgb(RRGGBB); the palette stores them as #RRGGBB.
  rgb = colour: "rgb(${removePrefix "#" colour})";
  font = "JetBrainsMono Nerd Font";
  terminal = "alacritty";
  arrangeWindow = pkgs.writeShellApplication {
    name = "hyprland-arrange-window";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
    ];
    text = builtins.readFile ./arrange-window.bash;
  };
  quickshell = getExe pkgs.quickshell;
  # A fresh Hyprland install gives no hint that SUPER is the modkey, so one
  # bind prints the map. The body is built here and shell-escaped because a
  # hyprlang `bind =` entry is single-line: real newlines cannot live in it.
  keybindHelp = concatStringsSep "\n" [
    "SUPER + Return      terminal"
    "SUPER + D / Space   launcher"
    "SUPER + N           control center"
    "SUPER + Q           close window"
    "SUPER + M           exit Hyprland"
    "SUPER + H/J/K/L     focus left/down/up/right"
    "SUPER + SHIFT + …   move window"
    "SUPER + CTRL + …    resize window"
    "SUPER + 1..0        workspace"
    "CTRL + Left/Right      previous/next workspace"
    "CTRL + ALT + arrows    align window to screen half"
    "CTRL + ALT + H/J/K/L   same alignment (Vim aliases)"
    "CTRL + ALT + Return/C  maximize/center window"
    "SUPER + SHIFT + 1..0  move to workspace"
    "SUPER + V / F / P   float / fullscreen / pseudo"
    "SUPER + ALT + L     lock screen"
    "Print / SHIFT+Print screenshot screen / region"
  ];
  cheatsheet = pkgs.writeShellScript "hyprland-cheatsheet" ''
    exec ${getExe pkgs.libnotify} -t 15000 -a Hyprland \
      "Hyprland keybinds" ${escapeShellArg keybindHelp}
  '';
in
{
  # Everything here is Linux-only Wayland desktop config. `home/default.nix` is
  # shared with the Darwin hosts, so the whole module stays inert unless a host
  # opts in.
  config = mkIf cfg.enableHyprland {
    # `home/default.nix` is imported by the Darwin hosts too; failing here is
    # far clearer than Linux-only desktop modules failing during evaluation.
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "home-config-manager.enableHyprland is Linux-only; Hyprland has no Darwin support.";
      }
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      # NixOS `programs.hyprland` already provides the compositor wrapper and the
      # portals; installing them again here would shadow the system session.
      package = null;
      portalPackage = null;
      # The default is stateVersion-gated (lua from 26.05, hyprlang before).
      # Pin it so the generated file stays a plain hyprland.conf.
      configType = "hyprlang";

      # Home Manager creates hyprland-session.target; Quickshell, hypridle and
      # the tray applets bind to that session lifecycle.

      settings = {
        "$mod" = "SUPER";
        "$terminal" = terminal;
        "$menu" = "${quickshell} ipc --config gruvbox-night call launcher toggle";

        # The display's native geometry is not known at build time, so let Hyprland pick.
        monitor = [ ",preferred,auto,auto" ];

        input = {
          kb_layout = "us";
          follow_mouse = 1;
          sensitivity = 0;
          touchpad = {
            natural_scroll = true;
            disable_while_typing = true;
            # libinput defaults this off; a laptop user expects a tap to click.
            "tap-to-click" = true;
          };
        };

        general = {
          gaps_in = 4;
          gaps_out = 8;
          border_size = 2;
          "col.active_border" = rgb theme.activeBorder;
          "col.inactive_border" = rgb theme.inactiveBorder;
          layout = "dwindle";
          resize_on_border = true;
        };

        decoration = {
          rounding = 6;
          # Blur and shadow are the two most expensive effects; a laptop keeps
          # more battery and a steadier frame rate without them.
          blur.enabled = false;
          shadow.enabled = false;
        };

        animations = {
          enabled = true;
          bezier = [ "snap, 0.05, 0.9, 0.1, 1.05" ];
          animation = [
            "windows, 1, 3, snap"
            "fade, 1, 3, default"
            "workspaces, 1, 3, default"
          ];
        };

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          # A solid themed background means no wallpaper daemon and no image
          # asset need to be shipped at all.
          background_color = rgb theme.base00;
          force_default_wallpaper = 0;
        };

        dwindle = {
          preserve_split = true;
        };

        # No exec-once: Quickshell and the remaining session daemons are
        # Home Manager services started by hyprland-session.target.

        bind = [
          "$mod, Return, exec, $terminal"
          "$mod, Q, killactive"
          "$mod, M, exit"
          "$mod, V, togglefloating"
          "$mod, F, fullscreen"
          "$mod, P, pseudo"
          "$mod, D, exec, $menu"
          "$mod, SPACE, exec, $menu"
          "$mod, N, exec, ${quickshell} ipc --config gruvbox-night call dashboard toggle"
          "$mod, slash, exec, ${cheatsheet}"

          # $mod+J and $mod+L are taken by vim-style focus movement below, so
          # togglesplit and the lock screen keep their mnemonic letters one
          # modifier over rather than firing alongside a movefocus.
          "$mod ALT, J, layoutmsg, togglesplit"
          "$mod ALT, L, exec, hyprlock"

          # Match macOS Mission Control's default desktop navigation.
          "CTRL, left, workspace, r-1"
          "CTRL, right, workspace, r+1"

          # Mirror Hammerspoon's Ctrl+Option window arrangement layer. The
          # H/J/K/L variants provide the same placements without leaving home row.
          "CTRL ALT, Return, exec, ${arrangeWindow}/bin/hyprland-arrange-window maximize"
          "CTRL ALT, C, exec, ${arrangeWindow}/bin/hyprland-arrange-window center"
          "CTRL ALT, left, exec, ${arrangeWindow}/bin/hyprland-arrange-window left"
          "CTRL ALT, down, exec, ${arrangeWindow}/bin/hyprland-arrange-window down"
          "CTRL ALT, up, exec, ${arrangeWindow}/bin/hyprland-arrange-window up"
          "CTRL ALT, right, exec, ${arrangeWindow}/bin/hyprland-arrange-window right"
          "CTRL ALT, H, exec, ${arrangeWindow}/bin/hyprland-arrange-window left"
          "CTRL ALT, J, exec, ${arrangeWindow}/bin/hyprland-arrange-window down"
          "CTRL ALT, K, exec, ${arrangeWindow}/bin/hyprland-arrange-window up"
          "CTRL ALT, L, exec, ${arrangeWindow}/bin/hyprland-arrange-window right"

          "$mod, H, movefocus, l"
          "$mod, J, movefocus, d"
          "$mod, K, movefocus, u"
          "$mod, L, movefocus, r"
          "$mod, left, movefocus, l"
          "$mod, down, movefocus, d"
          "$mod, up, movefocus, u"
          "$mod, right, movefocus, r"

          "$mod SHIFT, H, movewindow, l"
          "$mod SHIFT, J, movewindow, d"
          "$mod SHIFT, K, movewindow, u"
          "$mod SHIFT, L, movewindow, r"
          "$mod SHIFT, left, movewindow, l"
          "$mod SHIFT, down, movewindow, d"
          "$mod SHIFT, up, movewindow, u"
          "$mod SHIFT, right, movewindow, r"

          "$mod CTRL, H, resizeactive, -40 0"
          "$mod CTRL, J, resizeactive, 0 40"
          "$mod CTRL, K, resizeactive, 0 -40"
          "$mod CTRL, L, resizeactive, 40 0"
          "$mod CTRL, left, resizeactive, -40 0"
          "$mod CTRL, down, resizeactive, 0 40"
          "$mod CTRL, up, resizeactive, 0 -40"
          "$mod CTRL, right, resizeactive, 40 0"

          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod, 0, workspace, 10"

          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
          "$mod SHIFT, 0, movetoworkspace, 10"

          "$mod, S, togglespecialworkspace, magic"
          "$mod SHIFT, S, movetoworkspace, special:magic"

          "$mod, mouse_down, workspace, e+1"
          "$mod, mouse_up, workspace, e-1"

          ", Print, exec, grim - | wl-copy"
          "SHIFT, Print, exec, grim -g \"$(slurp)\" - | wl-copy"
        ];

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # bindel repeats on hold and still fires on the lock screen.
        bindel = [
          ", XF86AudioRaiseVolume, exec, pamixer -i 5"
          ", XF86AudioLowerVolume, exec, pamixer -d 5"
          ", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ];

        # bindl fires on the lock screen but must not repeat.
        bindl = [
          ", XF86AudioMute, exec, pamixer -t"
          ", XF86AudioMicMute, exec, pamixer --default-source -t"
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"
        ];
      };
    };

    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          hide_cursor = true;
          ignore_empty_input = true;
          # A short grace period makes an accidental lock recoverable without
          # a password round trip.
          grace = 2;
        };

        # This host ships no wallpaper asset, so lock onto a solid themed
        # surface instead of an image path.
        background = [
          {
            monitor = "";
            color = rgb theme.base00;
            blur_passes = 0;
          }
        ];

        input-field = [
          {
            monitor = "";
            size = "280, 48";
            position = "0, -60";
            halign = "center";
            valign = "center";
            rounding = 6;
            outline_thickness = 2;
            dots_center = true;
            outer_color = rgb theme.activeBorder;
            inner_color = rgb theme.base01;
            font_color = rgb theme.base05;
            check_color = rgb theme.base0C;
            fail_color = rgb theme.base08;
            placeholder_text = "Password";
          }
        ];

        label = [
          {
            monitor = "";
            text = "cmd[update:1000] date +%H:%M";
            color = rgb theme.base07;
            font_family = font;
            font_size = 64;
            position = "0, 120";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "cmd[update:60000] date +'%A, %d %B'";
            color = rgb theme.base04;
            font_family = font;
            font_size = 18;
            position = "0, 56";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };

    services.hypridle = {
      enable = true;
      settings = {
        general = {
          # Guard against stacking lockers when several triggers coincide.
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 600;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
        ];
      };
    };

    # The GUI polkit agent that 1Password and NetworkManager prompt through.
    services.hyprpolkitagent.enable = true;

    services.network-manager-applet.enable = true;
    services.blueman-applet.enable = true;

    # Only tools no module above already installs.
    home.packages = with pkgs; [
      grim
      slurp
      wl-clipboard
      brightnessctl
      playerctl
      pamixer
      libnotify
      pavucontrol
      adwaita-icon-theme
      # Keep nm-applet's symbolic tray icons in the stable Home Manager profile.
      networkmanagerapplet
    ];
  };
}
