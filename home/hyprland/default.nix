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
  # Hyprlang parses alpha colours only as rgba(RRGGBBAA), alpha last.
  rgba = alpha: colour: "rgba(${removePrefix "#" colour}${alpha})";
  font = "JetBrainsMono Nerd Font";
  terminal = "alacritty";
  toLua = generators.toLua { };
  luaCall = name: args: generators.mkLuaInline "${name}(${concatMapStringsSep ", " toLua args})";
  dsp = name: args: luaCall "hl.dsp.${name}" args;
  windowDsp = name: args: dsp "window.${name}" args;
  execDsp = command: dsp "exec_cmd" [ command ];
  resizeDsp =
    x: y:
    windowDsp "resize" [
      {
        inherit x y;
        relative = true;
      }
    ];
  lockedOptions = {
    locked = true;
  };
  repeatingLockedOptions = lockedOptions // {
    repeating = true;
  };
  mkBind = keys: dispatcher: {
    _args = [
      keys
      dispatcher
    ];
  };
  mkBindWith = keys: dispatcher: options: {
    _args = [
      keys
      dispatcher
      options
    ];
  };
  lockedBind = keys: command: mkBindWith keys (execDsp command) lockedOptions;
  repeatingLockedBind = keys: command: mkBindWith keys (execDsp command) repeatingLockedOptions;
  arrangeWindow = pkgs.writeShellApplication {
    name = "hyprland-arrange-window";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
    ];
    text = builtins.readFile ./arrange-window.bash;
  };
  # Focus the first window whose class matches the pattern; only spawn the
  # command when no such window exists (the launcher layer is focus-or-open).
  focusOrOpen = pkgs.writeShellApplication {
    name = "hyprland-focus-or-open";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
    ];
    text = ''
      #!/usr/bin/env bash
      # usage: hyprland-focus-or-open <class-pattern> <command...>
      # Focus the first window whose class matches <class-pattern> (unanchored
      # regex); only spawn <command...> when no such window exists.
      set -euo pipefail
      pattern=$1; shift
      if hyprctl -j clients | jq -e --arg p "$pattern" '.[] | select(.class | test("(?i)" + $p))' >/dev/null; then
        hyprctl dispatch "hl.dsp.focus({ window = \"class:$pattern\" })" >/dev/null
      else
        exec "$@"
      fi
    '';
  };
  quickshell = getExe pkgs.quickshell;
  launcherCommand = "${quickshell} ipc --config gruvbox-night call launcher toggle";
  dashboardCommand = "${quickshell} ipc --config gruvbox-night call dashboard toggle";
  arrangeCommand = action: "${arrangeWindow}/bin/hyprland-arrange-window ${action}";
  # The XKB swap hides both modifier layers from a fresh Hyprland install
  # (Win key = Cmd in apps, leftmost key = Ctrl for window ops), so one
  # bind prints the map. The helper passes the complete body as one
  # shell-escaped argument to libnotify.
  keybindHelp = concatStringsSep "\n" [
    "Mac layout: Win key = Cmd (app shortcuts), leftmost key = Ctrl (window ops)"
    "Cmd + Space            launcher"
    "Cmd + Option + B/T/F/E/S/G/N/Z/V/L   launch apps (focus or open)"
    "Cmd + Option + J       toggle split"
    "Cmd + Shift + 3/4      screenshot screen / region"
    "Ctrl + Option + arrows align window to screen half"
    "Ctrl + Option + H/J/K  same alignment (Vim aliases)"
    "Ctrl + Option + Return/C maximize/center window"
    "Ctrl + Option + L      lock screen"
    "Ctrl + Left/Right      previous/next workspace"
    "Ctrl + 1..0            workspace"
    "Ctrl + Shift + 1..0    move to workspace"
    "Ctrl + H/J/K/L         focus window"
    "Ctrl + Shift + ...     move window"
    "Ctrl + Cmd + ...       resize window"
    "Ctrl + Return          terminal"
    "Ctrl + Q / V           close window / float"
    "Ctrl + Cmd + F / P / N / M  fullscreen / pseudo / control center / exit"
    "Print / SHIFT+Print    screenshot screen / region"
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
      # Hyprland 0.55 deprecated Hyprlang and 0.57 removes it. Use Home
      # Manager's native Lua renderer so compositor upgrades remain safe.
      configType = "lua";
      # Curves must be registered before animations that reference them.
      importantPrefixes = [
        "curve"
        "monitor"
        "config"
      ];

      # Home Manager creates hyprland-session.target; Quickshell, hypridle and
      # the tray applets bind to that session lifecycle.

      settings = {
        # The display's native geometry is not known at build time, so let Hyprland pick.
        monitor = [
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = "auto";
          }
        ];

        config = {
          input = {
            kb_layout = "us";
            # XKB swap makes the physical Win key send Ctrl (macOS-Cmd behavior
            # in apps) and the physical leftmost key send Super (the WM layer).
            kb_options = "ctrl:swap_lwin_lctl,ctrl:swap_rwin_rctl";
            follow_mouse = 1;
            sensitivity = 0;
            # macOS "natural scroll" inverts mouse-wheel scrolling too; the
            # touchpad-only setting left the mouse wheel in the wrong direction.
            natural_scroll = true;
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
            # Local overrides rather than theme roles: `activeBorder`/
            # `inactiveBorder` are shared by quickshell, fzf, bat, maki
            # and hyprlock, so window borders pick their own colours here.
            # Orange marks focus, blue marks unfocused, and neither is the
            # amber (#c9a257) that tmux paints its focused pane frame in.
            col = {
              active_border = rgb theme.base09;
              inactive_border = rgb theme.base0D;
            };
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

          animations.enabled = true;

          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            # A solid themed background means no wallpaper daemon and no image
            # asset need to be shipped at all.
            background_color = rgb theme.base00;
            force_default_wallpaper = 0;
          };

          dwindle.preserve_split = true;
        };

        curve = [
          {
            _args = [
              "snap"
              {
                type = "bezier";
                points = [
                  [
                    0.05
                    0.9
                  ]
                  [
                    0.1
                    1.05
                  ]
                ];
              }
            ];
          }
        ];

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 3;
            bezier = "snap";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 3;
            bezier = "default";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 3;
            bezier = "default";
          }
        ];

        # No startup hook: Quickshell and the remaining session daemons are Home
        # Manager services started by hyprland-session.target.
        bind = [
          (mkBind "SUPER + Return" (dsp "exec_cmd" [ terminal ]))
          (mkBind "SUPER + Q" (windowDsp "close" [ ]))
          (mkBind "SUPER + CTRL + M" (dsp "exit" [ ]))
          (mkBind "SUPER + V" (windowDsp "float" [ { action = "toggle"; } ]))
          (mkBind "SUPER + CTRL + F" (windowDsp "fullscreen" [ ]))
          (mkBind "SUPER + CTRL + P" (windowDsp "pseudo" [ ]))
          (mkBind "CTRL + SPACE" (execDsp launcherCommand))
          (mkBind "SUPER + CTRL + N" (execDsp dashboardCommand))
          (mkBind "SUPER + slash" (dsp "exec_cmd" [ "${cheatsheet}" ]))

          # SUPER+J and SUPER+L are taken by Vim-style focus movement below, so
          # togglesplit keeps its mnemonic letter one modifier over rather than
          # firing alongside a focus move. The lock screen sits on the SUPER+ALT
          # (Ctrl+Option) layer: CTRL+ALT is the app launcher layer, where L
          # opens Slack.
          (mkBind "CTRL + ALT + J" (dsp "layout" [ "togglesplit" ]))
          (mkBind "SUPER + ALT + L" (dsp "exec_cmd" [ "hyprlock" ]))

          # Match macOS Mission Control's default desktop navigation.
          (mkBind "SUPER + left" (dsp "focus" [ { workspace = "r-1"; } ]))
          (mkBind "SUPER + right" (dsp "focus" [ { workspace = "r+1"; } ]))

          # Mirror Hammerspoon's Ctrl+Option window arrangement layer. The
          # H/J/K/L variants provide the same placements without leaving home row.
          (mkBind "SUPER + ALT + Return" (execDsp (arrangeCommand "maximize")))
          (mkBind "SUPER + ALT + C" (execDsp (arrangeCommand "center")))
          (mkBind "SUPER + ALT + left" (execDsp (arrangeCommand "left")))
          (mkBind "SUPER + ALT + down" (execDsp (arrangeCommand "down")))
          (mkBind "SUPER + ALT + up" (execDsp (arrangeCommand "up")))
          (mkBind "SUPER + ALT + right" (execDsp (arrangeCommand "right")))
          (mkBind "SUPER + ALT + H" (execDsp (arrangeCommand "left")))
          (mkBind "SUPER + ALT + J" (execDsp (arrangeCommand "down")))
          (mkBind "SUPER + ALT + K" (execDsp (arrangeCommand "up")))

          # Mirror Hammerspoon's Cmd+Option app launcher layer: on the Mac the
          # hyper combo is Cmd+Option, which lands on the Win+Alt keys here.
          # Each combo focuses the app when a window with the matching class
          # already exists and only opens a new instance otherwise.
          (mkBind "CTRL + ALT + B" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open zen zen"))
          (mkBind "CTRL + ALT + T" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open Alacritty ${terminal}"))
          (mkBind "CTRL + ALT + F" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open figma figma-linux"))
          (mkBind "CTRL + ALT + E" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open signal signal-desktop"))
          (mkBind "CTRL + ALT + S" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open spotify spotify"))
          (mkBind "CTRL + ALT + G" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open Discord Discord"))
          (mkBind "CTRL + ALT + N" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open obsidian obsidian"))
          (mkBind "CTRL + ALT + Z" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open zoom zoom"))
          (mkBind "CTRL + ALT + V" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open protonvpn protonvpn-app"))
          (mkBind "CTRL + ALT + L" (execDsp "${focusOrOpen}/bin/hyprland-focus-or-open slack slack"))

          (mkBind "SUPER + H" (dsp "focus" [ { direction = "left"; } ]))
          (mkBind "SUPER + J" (dsp "focus" [ { direction = "down"; } ]))
          (mkBind "SUPER + K" (dsp "focus" [ { direction = "up"; } ]))
          (mkBind "SUPER + L" (dsp "focus" [ { direction = "right"; } ]))
          (mkBind "SUPER + down" (dsp "focus" [ { direction = "down"; } ]))
          (mkBind "SUPER + up" (dsp "focus" [ { direction = "up"; } ]))

          (mkBind "SUPER + SHIFT + H" (windowDsp "move" [ { direction = "left"; } ]))
          (mkBind "SUPER + SHIFT + J" (windowDsp "move" [ { direction = "down"; } ]))
          (mkBind "SUPER + SHIFT + K" (windowDsp "move" [ { direction = "up"; } ]))
          (mkBind "SUPER + SHIFT + L" (windowDsp "move" [ { direction = "right"; } ]))
          (mkBind "SUPER + SHIFT + left" (windowDsp "move" [ { direction = "left"; } ]))
          (mkBind "SUPER + SHIFT + down" (windowDsp "move" [ { direction = "down"; } ]))
          (mkBind "SUPER + SHIFT + up" (windowDsp "move" [ { direction = "up"; } ]))
          (mkBind "SUPER + SHIFT + right" (windowDsp "move" [ { direction = "right"; } ]))

          (mkBind "SUPER + CTRL + H" (resizeDsp (-40) 0))
          (mkBind "SUPER + CTRL + J" (resizeDsp 0 40))
          (mkBind "SUPER + CTRL + K" (resizeDsp 0 (-40)))
          (mkBind "SUPER + CTRL + L" (resizeDsp 40 0))
          (mkBind "SUPER + CTRL + left" (resizeDsp (-40) 0))
          (mkBind "SUPER + CTRL + down" (resizeDsp 0 40))
          (mkBind "SUPER + CTRL + up" (resizeDsp 0 (-40)))
          (mkBind "SUPER + CTRL + right" (resizeDsp 40 0))

          (mkBind "SUPER + 1" (dsp "focus" [ { workspace = "1"; } ]))
          (mkBind "SUPER + 2" (dsp "focus" [ { workspace = "2"; } ]))
          (mkBind "SUPER + 3" (dsp "focus" [ { workspace = "3"; } ]))
          (mkBind "SUPER + 4" (dsp "focus" [ { workspace = "4"; } ]))
          (mkBind "SUPER + 5" (dsp "focus" [ { workspace = "5"; } ]))
          (mkBind "SUPER + 6" (dsp "focus" [ { workspace = "6"; } ]))
          (mkBind "SUPER + 7" (dsp "focus" [ { workspace = "7"; } ]))
          (mkBind "SUPER + 8" (dsp "focus" [ { workspace = "8"; } ]))
          (mkBind "SUPER + 9" (dsp "focus" [ { workspace = "9"; } ]))
          (mkBind "SUPER + 0" (dsp "focus" [ { workspace = "10"; } ]))

          (mkBind "SUPER + SHIFT + 1" (windowDsp "move" [ { workspace = "1"; } ]))
          (mkBind "SUPER + SHIFT + 2" (windowDsp "move" [ { workspace = "2"; } ]))
          (mkBind "SUPER + SHIFT + 3" (windowDsp "move" [ { workspace = "3"; } ]))
          (mkBind "SUPER + SHIFT + 4" (windowDsp "move" [ { workspace = "4"; } ]))
          (mkBind "SUPER + SHIFT + 5" (windowDsp "move" [ { workspace = "5"; } ]))
          (mkBind "SUPER + SHIFT + 6" (windowDsp "move" [ { workspace = "6"; } ]))
          (mkBind "SUPER + SHIFT + 7" (windowDsp "move" [ { workspace = "7"; } ]))
          (mkBind "SUPER + SHIFT + 8" (windowDsp "move" [ { workspace = "8"; } ]))
          (mkBind "SUPER + SHIFT + 9" (windowDsp "move" [ { workspace = "9"; } ]))
          (mkBind "SUPER + SHIFT + 0" (windowDsp "move" [ { workspace = "10"; } ]))

          (mkBind "SUPER + CTRL + S" (dsp "workspace.toggle_special" [ "magic" ]))
          (mkBind "SUPER + CTRL + SHIFT + S" (windowDsp "move" [ { workspace = "special:magic"; } ]))

          # Print/SHIFT+Print plus the macOS Cmd+Shift+3/4 positions.
          (mkBind "Print" (dsp "exec_cmd" [ "grim - | wl-copy" ]))
          (mkBind "SHIFT + Print" (dsp "exec_cmd" [ "grim -g \"$(slurp)\" - | wl-copy" ]))
          (mkBind "CTRL + SHIFT + 3" (dsp "exec_cmd" [ "grim - | wl-copy" ]))
          (mkBind "CTRL + SHIFT + 4" (dsp "exec_cmd" [ "grim -g \"$(slurp)\" - | wl-copy" ]))

          (mkBindWith "SUPER + mouse:272" (windowDsp "drag" [ ]) { mouse = true; })
          (mkBindWith "SUPER + mouse:273" (windowDsp "resize" [ ]) { mouse = true; })

          # These bindings repeat on hold and remain active on the lock screen.
          (repeatingLockedBind "XF86AudioRaiseVolume" "pamixer -i 5")
          (repeatingLockedBind "XF86AudioLowerVolume" "pamixer -d 5")
          (repeatingLockedBind "XF86MonBrightnessUp" "brightnessctl set 5%+")
          (repeatingLockedBind "XF86MonBrightnessDown" "brightnessctl set 5%-")

          # These remain active on the lock screen but must not repeat.
          (lockedBind "XF86AudioMute" "pamixer -t")
          (lockedBind "XF86AudioMicMute" "pamixer --default-source -t")
          (lockedBind "XF86AudioPlay" "playerctl play-pause")
          (lockedBind "XF86AudioNext" "playerctl next")
          (lockedBind "XF86AudioPrev" "playerctl previous")
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

        # A live screencopy of the desktop, blurred and dimmed toward base00,
        # reads as a layered veil over the session. The semi-transparent
        # base00 colour stands in when screencopy is unavailable.
        background = [
          {
            monitor = "";
            path = "screenshot";
            blur_size = 25;
            blur_passes = 2;
            brightness = 0.45;
            contrast = 0.8;
            vibrancy = 0.1;
            color = rgba "cc" theme.base00;
          }
        ];

        input-field = [
          {
            monitor = "";
            # hyprlock sizes the field font from its height, so the taller
            # field gives the larger type.
            size = "300, 56";
            position = "0, 58";
            halign = "center";
            valign = "center";
            rounding = 14;
            outline_thickness = 2;
            dots_center = true;
            outer_color = rgb theme.inactiveBorder;
            inner_color = rgba "66" theme.base01;
            font_color = rgb theme.base05;
            check_color = rgb theme.base0C;
            fail_color = rgb theme.base08;
            placeholder_text = "Password";
          }
        ];

        # A centered vertical stack: account, clock, date, field, hint.
        label = [
          {
            monitor = "";
            text = "cmd[update:0] whoami";
            color = rgb theme.dimNeutral;
            font_family = font;
            font_size = 16;
            position = "0, -124";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "cmd[update:1000] date +%H:%M";
            color = rgb theme.base07;
            font_family = font;
            font_size = 64;
            position = "0, -62";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "cmd[update:60000] date +'%A, %d %B'";
            color = rgb theme.base04;
            font_family = font;
            font_size = 18;
            position = "0, -6";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Press Enter to unlock";
            color = rgb theme.hint;
            font_family = font;
            font_size = 15;
            position = "0, 112";
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
          # flock is atomic where a pidof check is not: a trigger that
          # coincides with a manual lock leaves exactly one hyprlock running.
          lock_cmd = "flock -n ~/.cache/hyprlock.lock hyprlock";
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
