{
  flake.modules.darwin.karabiner = {
    homebrew.casks = [ "karabiner-elements" ];
  };
  flake.modules.homeManager.karabiner =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      terminalBundleIdentifiers = [
        "^com\\.apple\\.Terminal$"
        "^com\\.github\\.wez\\.wezterm$"
        "^com\\.googlecode\\.iterm2$"
        "^net\\.kovidgoyal\\.kitty$"
        "^org\\.alacritty$"
      ];

      # These have the same conventional meaning on Linux with Ctrl and macOS
      # with Cmd. Mapping keys instead of the whole modifier preserves native
      # Ctrl+Tab and terminal control sequences.
      linuxShortcutKeys = lib.stringToCharacters "acdfgklnopqrstvwxz0" ++ [
        "equal_sign"
        "hyphen"
      ];

      linuxShortcut = key: {
        type = "basic";
        from = {
          key_code = key;
          modifiers = {
            mandatory = [ "control" ];
            # Cmd+Shift+Q logs out, so only plain Ctrl+Q aliases Quit.
            optional = [ "caps_lock" ] ++ lib.optional (key != "q") "shift";
          };
        };
        to = [
          {
            key_code = key;
            modifiers = [ "command" ];
          }
        ];
        conditions = [
          {
            type = "frontmost_application_unless";
            bundle_identifiers = terminalBundleIdentifiers;
          }
        ];
      };

      textNavigation =
        from: to:
        let
          lineBoundary = builtins.elem from [
            "home"
            "end"
          ];
        in
        {
          type = "basic";
          from = {
            key_code = from;
            modifiers = {
              mandatory = lib.optional (!lineBoundary) "control";
              optional = [ "caps_lock" ] ++ lib.optional (from != "delete_or_backspace") "shift";
            };
          };
          to = [
            {
              key_code = to;
              modifiers = [ (if lineBoundary then "command" else "option") ];
            }
          ];
          conditions = [
            {
              type = "frontmost_application_unless";
              bundle_identifiers = terminalBundleIdentifiers;
            }
          ];
        };

      windowAction = from: to: {
        type = "basic";
        from = {
          key_code = from;
          modifiers = {
            mandatory = [
              "control"
              "option"
            ];
            optional = [ "caps_lock" ];
          };
        };
        to = [
          {
            key_code = to;
            modifiers = [
              "fn"
              "control"
            ];
          }
        ];
      };

      appLauncher = key: app: {
        type = "basic";
        from = {
          key_code = key;
          modifiers = {
            mandatory = [
              "command"
              "option"
            ];
            optional = [ "caps_lock" ];
          };
        };
        to = [ { shell_command = "/usr/bin/open -a '${app}'"; } ];
      };

      rules = [
        {
          description = "Use Linux Ctrl shortcuts in macOS apps";
          manipulators = map linuxShortcut linuxShortcutKeys;
        }
        {
          description = "Use Linux text navigation in macOS apps";
          manipulators = lib.mapAttrsToList textNavigation {
            delete_or_backspace = "delete_or_backspace";
            home = "left_arrow";
            end = "right_arrow";
          };
        }
        {
          description = "Copy and paste in terminals with Ctrl+Shift+C/V";
          manipulators =
            map
              (key: {
                type = "basic";
                from = {
                  key_code = key;
                  modifiers = {
                    mandatory = [
                      "control"
                      "shift"
                    ];
                    optional = [ "caps_lock" ];
                  };
                };
                to = [
                  {
                    key_code = key;
                    modifiers = [ "command" ];
                  }
                ];
                conditions = [
                  {
                    type = "frontmost_application_if";
                    bundle_identifiers = terminalBundleIdentifiers;
                  }
                ];
              })
              [
                "c"
                "v"
              ];
        }
        {
          description = "Switch applications with Alt+Tab";
          manipulators =
            map
              (side: {
                type = "basic";
                from = {
                  key_code = "${side}_option";
                  modifiers.optional = [
                    "shift"
                    "caps_lock"
                  ];
                };
                to = [ { key_code = "${side}_option"; } ];
                to_if_other_key_pressed = [
                  {
                    other_keys = [
                      {
                        key_code = "tab";
                        modifiers.optional = [
                          "option"
                          "shift"
                          "caps_lock"
                        ];
                      }
                    ];
                    to = [ { key_code = "${side}_command"; } ];
                  }
                ];
              })
              [
                "left"
                "right"
              ];
        }
        {
          description = "Arrange windows with Ctrl+Option";
          manipulators = lib.mapAttrsToList windowAction {
            return_or_enter = "f";
            c = "c";
            left_arrow = "left_arrow";
            right_arrow = "right_arrow";
            up_arrow = "up_arrow";
            down_arrow = "down_arrow";
          };
        }
        {
          description = "Open applications with Cmd+Option";
          manipulators = lib.mapAttrsToList appLauncher {
            b = "Zen";
            t = "Alacritty";
            f = "Figma";
            e = "Signal";
            s = "Spotify";
            m = "Mail";
            o = "Messages";
            w = "WhatsApp";
            g = "Discord";
            x = "Xcode";
            l = "Slack";
            z = "zoom.us";
            n = "Obsidian";
            h = "IBKR Desktop";
            v = "ProtonVPN";
          };
        }
        {
          description = "Switch workspaces with mouse side buttons";
          manipulators =
            lib.mapAttrsToList
              (button: arrow: {
                type = "basic";
                from.pointing_button = button;
                to = [
                  {
                    key_code = arrow;
                    modifiers = [ "control" ];
                    repeat = false;
                  }
                ];
              })
              {
                # Preserve the existing OpenLogi directions.
                button4 = "right_arrow";
                button5 = "left_arrow";
              };
        }
      ];
      karabinerConfig = pkgs.writeText "karabiner.json" (
        builtins.toJSON {
          profiles = [
            {
              name = "Linux shortcuts";
              selected = true;
              complex_modifications = { inherit rules; };
            }
          ];
        }
      );
      configFile = "${config.xdg.configHome}/karabiner/karabiner.json";
    in
    {
      config = lib.mkIf config.home-config-manager.isDarwin {
        xdg.configFile."karabiner/assets/complex_modifications/nix-config.json".text = builtins.toJSON {
          title = "nix-config keyboard shortcuts";
          inherit rules;
        };

        # Reserve Ctrl+Space for tmux. Merge just this entry to preserve other
        # keyboard shortcuts, then refresh the running macOS settings.
        home.activation.disableInputSourceShortcut = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
            -dict-add 60 '<dict><key>enabled</key><false/></dict>'
          run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
        '';

        # Keep Karabiner's file writable, refreshing only our profile's rule groups.
        home.activation.syncKarabiner = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ ! -e ${lib.escapeShellArg configFile} ]]; then
            run install -Dm600 ${karabinerConfig} ${lib.escapeShellArg configFile}
          elif [[ ! -v DRY_RUN ]]; then
            (
              target=${lib.escapeShellArg configFile}
              tmp=$(mktemp "$target.XXXXXX")
              trap 'rm -f "$tmp"' EXIT
              cp -p "$target" "$tmp"
              ${pkgs.jq}/bin/jq --slurpfile generated ${karabinerConfig} '
                $generated[0].profiles[0] as $managed
                | $managed.complex_modifications.rules as $rules
                | . as $before
                | .profiles |= map(
                    if .name == $managed.name then
                      .complex_modifications.rules |= (
                        (. // []) as $existing
                        | [$existing[] | .description as $description
                           | ($rules | map(select(.description == $description)) | .[0]) // .]
                          + [$rules[] | .description as $description
                             | select($existing | all(.description != $description))]
                      )
                    else . end
                  )
                | select(. != $before)
              ' "$target" > "$tmp"
              if [[ -s "$tmp" ]]; then
                mv "$tmp" "$target"
              fi
            )
          fi
        '';
      };
    };
}
