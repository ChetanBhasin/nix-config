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
  quickshell = getExe pkgs.quickshell;
  launcherCommand = "${quickshell} ipc --config gruvbox-night call launcher toggle";
  dashboardCommand = "${quickshell} ipc --config gruvbox-night call dashboard toggle";
  arrangeCommand = action: "${arrangeWindow}/bin/hyprland-arrange-window ${action}";
  # A fresh Hyprland install gives no hint that SUPER is the modkey, so one
  # bind prints the map. The helper passes the complete body as one
  # shell-escaped argument to libnotify.
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
            col = {
              active_border = rgb theme.activeBorder;
              inactive_border = rgb theme.inactiveBorder;
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
          (mkBind "SUPER + M" (dsp "exit" [ ]))
          (mkBind "SUPER + V" (windowDsp "float" [ { action = "toggle"; } ]))
          (mkBind "SUPER + F" (windowDsp "fullscreen" [ ]))
          (mkBind "SUPER + P" (windowDsp "pseudo" [ ]))
          (mkBind "SUPER + D" (execDsp launcherCommand))
          (mkBind "SUPER + SPACE" (execDsp launcherCommand))
          (mkBind "SUPER + N" (execDsp dashboardCommand))
          (mkBind "SUPER + slash" (dsp "exec_cmd" [ "${cheatsheet}" ]))

          # SUPER+J and SUPER+L are taken by Vim-style focus movement below, so
          # togglesplit and the lock screen keep their mnemonic letters one
          # modifier over rather than firing alongside a focus move.
          (mkBind "SUPER + ALT + J" (dsp "layout" [ "togglesplit" ]))
          (mkBind "SUPER + ALT + L" (dsp "exec_cmd" [ "hyprlock" ]))

          # Match macOS Mission Control's default desktop navigation.
          (mkBind "CTRL + left" (dsp "focus" [ { workspace = "r-1"; } ]))
          (mkBind "CTRL + right" (dsp "focus" [ { workspace = "r+1"; } ]))

          # Mirror Hammerspoon's Ctrl+Option window arrangement layer. The
          # H/J/K/L variants provide the same placements without leaving home row.
          (mkBind "CTRL + ALT + Return" (execDsp (arrangeCommand "maximize")))
          (mkBind "CTRL + ALT + C" (execDsp (arrangeCommand "center")))
          (mkBind "CTRL + ALT + left" (execDsp (arrangeCommand "left")))
          (mkBind "CTRL + ALT + down" (execDsp (arrangeCommand "down")))
          (mkBind "CTRL + ALT + up" (execDsp (arrangeCommand "up")))
          (mkBind "CTRL + ALT + right" (execDsp (arrangeCommand "right")))
          (mkBind "CTRL + ALT + H" (execDsp (arrangeCommand "left")))
          (mkBind "CTRL + ALT + J" (execDsp (arrangeCommand "down")))
          (mkBind "CTRL + ALT + K" (execDsp (arrangeCommand "up")))
          (mkBind "CTRL + ALT + L" (execDsp (arrangeCommand "right")))

          (mkBind "SUPER + H" (dsp "focus" [ { direction = "left"; } ]))
          (mkBind "SUPER + J" (dsp "focus" [ { direction = "down"; } ]))
          (mkBind "SUPER + K" (dsp "focus" [ { direction = "up"; } ]))
          (mkBind "SUPER + L" (dsp "focus" [ { direction = "right"; } ]))
          (mkBind "SUPER + left" (dsp "focus" [ { direction = "left"; } ]))
          (mkBind "SUPER + down" (dsp "focus" [ { direction = "down"; } ]))
          (mkBind "SUPER + up" (dsp "focus" [ { direction = "up"; } ]))
          (mkBind "SUPER + right" (dsp "focus" [ { direction = "right"; } ]))

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

          (mkBind "SUPER + S" (dsp "workspace.toggle_special" [ "magic" ]))
          (mkBind "SUPER + SHIFT + S" (windowDsp "move" [ { workspace = "special:magic"; } ]))

          (mkBind "SUPER + mouse_down" (dsp "focus" [ { workspace = "e+1"; } ]))
          (mkBind "SUPER + mouse_up" (dsp "focus" [ { workspace = "e-1"; } ]))

          (mkBind "Print" (dsp "exec_cmd" [ "grim - | wl-copy" ]))
          (mkBind "SHIFT + Print" (dsp "exec_cmd" [ "grim -g \"$(slurp)\" - | wl-copy" ]))

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
