{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.home-config-manager;
  theme = import ../../modules/theme/luna.nix;
  # Hyprland/hyprlock take colours as rgb(RRGGBB); the palette stores them as #RRGGBB.
  rgb = colour: "rgb(${removePrefix "#" colour})";
  font = "JetBrainsMono Nerd Font";
  terminal = "alacritty";
  # A fresh Hyprland install gives no hint that SUPER is the modkey, so one
  # bind prints the map. The body is built here and shell-escaped because a
  # hyprlang `bind =` entry is single-line: real newlines cannot live in it.
  keybindHelp = concatStringsSep "\n" [
    "SUPER + Return      terminal"
    "SUPER + D / Space   launcher"
    "SUPER + Q           close window"
    "SUPER + M           exit Hyprland"
    "SUPER + H/J/K/L     focus left/down/up/right"
    "SUPER + SHIFT + …   move window"
    "SUPER + CTRL + …    resize window"
    "SUPER + 1..0        workspace"
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
    # far clearer than mako/tofi erroring out as unsupported packages.
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

      # systemd.enable is left at its default: it creates hyprland-session.target,
      # which BindsTo graphical-session.target and is what autostarts waybar,
      # mako, hypridle and the tray applets below.

      settings = {
        "$mod" = "SUPER";
        "$terminal" = terminal;
        "$menu" = "tofi-drun --drun-launch=true";

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
            tap_to_click = true;
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
          pseudotile = true;
          preserve_split = true;
        };

        # No exec-once: waybar, mako, hypridle, hyprpolkitagent and the tray
        # applets are all home-manager user services started by
        # hyprland-session.target. Launching them here would double-start them.

        bind = [
          "$mod, Return, exec, $terminal"
          "$mod, Q, killactive"
          "$mod, M, exit"
          "$mod, V, togglefloating"
          "$mod, F, fullscreen"
          "$mod, P, pseudo"
          "$mod, D, exec, $menu"
          "$mod, SPACE, exec, $menu"
          "$mod, slash, exec, ${cheatsheet}"

          # $mod+J and $mod+L are taken by vim-style focus movement below, so
          # togglesplit and the lock screen keep their mnemonic letters one
          # modifier over rather than firing alongside a movefocus.
          "$mod ALT, J, togglesplit"
          "$mod ALT, L, exec, hyprlock"

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

    programs.waybar = {
      enable = true;
      # systemd.targets is left at its default ([ graphical-session.target ]),
      # which hyprland-session.target binds to.
      systemd.enable = true;

      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 34;

        modules-left = [
          "hyprland/workspaces"
        ];
        modules-center = [ "hyprland/window" ];
        modules-right = [
          "pulseaudio"
          "backlight"
          "battery"
          "network"
          "tray"
          "clock"
        ];

        "hyprland/workspaces" = {
          format = "{name}";
          on-click = "activate";
          sort-by-number = true;
        };

        "hyprland/window" = {
          format = "{title}";
          max-length = 80;
          separate-outputs = true;
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟";
          format-icons.default = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
          scroll-step = 5;
          on-click = "pavucontrol";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
          on-scroll-up = "brightnessctl set 5%+";
          on-scroll-down = "brightnessctl set 5%-";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󰚥 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁼"
            "󰁾"
            "󰂀"
            "󰂂"
            "󰁹"
          ];
          tooltip-format = "{timeTo} ({power} W)";
        };

        network = {
          format-wifi = "󰖩 {essid}";
          format-ethernet = "󰈀 {ifname}";
          format-disconnected = "󰖪";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
        };

        tray = {
          icon-size = 16;
          spacing = 8;
        };

        clock = {
          format = "󰃰 {:%a %d %b  %H:%M}";
          format-alt = "{:%Y-%m-%d %H:%M:%S}";
          tooltip-format = "<tt>{calendar}</tt>";
        };
      };

      style = ''
        * {
          border: none;
          border-radius: 0;
          font-family: "${font}";
          font-size: 13px;
          min-height: 0;
        }

        window#waybar {
          background-color: ${theme.base00};
          color: ${theme.base05};
        }

        #workspaces button {
          padding: 0 8px;
          background-color: transparent;
          color: ${theme.base03};
        }

        #workspaces button.active {
          color: ${theme.primaryAccent};
          box-shadow: inset 0 -2px ${theme.primaryAccent};
        }

        #workspaces button.urgent {
          color: ${theme.base08};
        }

        #window {
          padding: 0 8px;
          color: ${theme.base04};
        }

        #pulseaudio,
        #backlight,
        #battery,
        #network,
        #tray,
        #clock {
          padding: 0 10px;
          color: ${theme.base05};
        }

        #clock {
          color: ${theme.base0D};
        }
        #pulseaudio.muted {
          color: ${theme.base03};
        }

        #network.disconnected {
          color: ${theme.base08};
        }


        #battery.good,
        #battery.charging,
        #battery.plugged {
          color: ${theme.base0B};
        }

        #battery.warning {
          color: ${theme.warning};
        }

        #battery.critical {
          color: ${theme.base08};
        }
      '';
    };

    programs.tofi = {
      enable = true;
      settings = {
        font = font;
        font-size = 13;
        anchor = "center";
        width = 620;
        height = 340;
        num-results = 8;
        result-spacing = 4;
        border-width = 2;
        border-color = theme.activeBorder;
        outline-width = 0;
        outline-color = theme.base00;
        corner-radius = 6;
        padding-top = 12;
        padding-bottom = 12;
        padding-left = 16;
        padding-right = 16;
        background-color = theme.base00;
        text-color = theme.base05;
        selection-color = theme.primaryAccent;
        prompt-color = theme.primaryAccent;
        # tofi trims value whitespace, so the separating space lives here.
        prompt-text = "run:";
      };
    };

    services.mako = {
      enable = true;
      settings = {
        font = "${font} 11";
        anchor = "top-right";
        layer = "overlay";
        width = 380;
        height = 140;
        margin = 10;
        padding = "10,14";
        border-size = 2;
        border-radius = 6;
        background-color = theme.base01;
        text-color = theme.base05;
        border-color = theme.activeBorder;
        progress-color = "over ${theme.base02}";
        default-timeout = 6000;
        icons = true;
        max-icon-size = 32;
        markup = true;
        actions = true;
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
    ];
  };
}
