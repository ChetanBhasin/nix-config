{
  flake.modules.homeManager.terminal-personal =
    { config, pkgs, ... }:
    let

      # Keep escape-sequence keybindings independent of TOML string quoting.
      esc = builtins.fromJSON ''"\u001b"'';
      ctrlC = builtins.fromJSON ''"\u0003"'';
      ctrlV = builtins.fromJSON ''"\u0016"'';
      ctrlK = builtins.fromJSON ''"\u000B"'';
      ctrlW = builtins.fromJSON ''"\u0017"'';
      ctrlN = builtins.fromJSON ''"\u000E"'';

      # Encode the physical platform shortcut with the standard CSI-u protocol.
      # Tmux normalizes Super+number to Alt+number, which would collide with the
      # session shortcuts, so both platforms deliberately emit Ctrl+Shift+number.
      multiplexerTabMod = if pkgs.stdenv.hostPlatform.isDarwin then "Command" else "Control|Shift";
      multiplexerTabBindings = builtins.genList (
        n:
        let
          num = n + 1;
          codepoint = 49 + n;
        in
        {
          key = "Key${toString num}";
          mods = multiplexerTabMod;
          chars = "${esc}[${toString codepoint};6u";
        }
      ) 9;
      # The two logical modifier layers, mapped to physical keys per platform. On
      # macOS these are the physical Command ("Cmd layer") and Control ("Ctrl
      # layer") keys. On Linux the Hyprland XKB swap (ctrl:swap_lwin_lctl) makes
      # the physical Win key send Control and the physical leftmost key send
      # Command/Super, so the same layers land on the same physical keys and macOS
      # muscle memory carries over.
      cmdMod = if pkgs.stdenv.hostPlatform.isDarwin then "Command" else "Control";
      ctrlMod = if pkgs.stdenv.hostPlatform.isDarwin then "Control" else "Command";

      # Linux-only: after the XKB swap the physical leftmost key is logical
      # Command/Super; map it to the classic terminal control bytes. On macOS those
      # physical keys are the Command actions, so this list is empty there.
      ctrlLayerBindings =
        if pkgs.stdenv.hostPlatform.isDarwin then
          [ ]
        else
          [
            {
              key = "C";
              mods = "Command";
              chars = ctrlC; # interrupt
            }
            {
              key = "V";
              mods = "Command";
              chars = ctrlV; # quote insert
            }
            {
              key = "K";
              mods = "Command";
              chars = ctrlK; # kill to end of line
            }
            {
              key = "W";
              mods = "Command";
              chars = ctrlW; # kill to beginning of line
            }
            {
              key = "N";
              mods = "Command";
              chars = ctrlN;
            }
          ];
    in
    {
      programs.direnv.enable = true;
      programs.direnv.enableZshIntegration = true;
      programs.direnv.nix-direnv.enable = true;

      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          # General settings
          add_newline = true;
          scan_timeout = 10;

          # Custom format - directory and git first, then languages
          format = builtins.concatStringsSep "" [
            "$time"
            "$directory"
            "$custom"
            "$nix_shell"
            "$rust"
            "$python"
            "$nodejs"
            "$golang"
            "$docker_context"
            "$jobs"
            "$cmd_duration"
            "$line_break"
            "$character"
          ];

          # Right side - less important context (kubernetes, aws)
          right_format = builtins.concatStringsSep "" [ "$kubernetes" ];

          # Character/prompt
          character = {
            success_symbol = "[➜](bold fg:base0b)";
            error_symbol = "[➜](bold fg:base08)";
            vicmd_symbol = "[](bold fg:base0b)";
          };

          # Directory
          directory = {
            truncation_length = 3;
            truncate_to_repo = true;
            style = "bold fg:${config.lib.stylix.palette.primaryAccent}";
          };

          custom = {
            jj = {
              when = "jj-starship detect";
              shell = [ "jj-starship" ];
              format = "$output ";
            };
          };

          # Nix shell indicator
          nix_shell = {
            symbol = "❄️ ";
            style = "bold fg:base0d";
            format = "[$symbol$state( \\($name\\))]($style) ";
          };

          # Command duration
          cmd_duration = {
            min_time = 2000;
            show_milliseconds = false;
            style = "bold fg:base0a";
            format = "[⏱ $duration]($style) ";
          };

          # Jobs indicator
          jobs = {
            symbol = "✦";
            style = "bold fg:base0d";
            threshold = 1;
            format = "[$symbol$number]($style) ";
          };

          # Language-specific modules (compact)
          rust = {
            symbol = "rs ";
            style = "bold fg:base08";
            format = "[$symbol$version]($style) ";
          };

          python = {
            symbol = "py ";
            style = "bold fg:base0a";
            format = "[$symbol$version]($style) ";
          };

          nodejs = {
            symbol = "node ";
            style = "bold fg:base0b";
            format = "[$symbol$version]($style) ";
          };

          golang = {
            symbol = "go ";
            style = "bold fg:base0c";
            format = "[$symbol$version]($style) ";
          };

          # Kubernetes context - compact, right-aligned
          kubernetes = {
            disabled = false;
            symbol = "☸ ";
            style = "dimmed fg:base0d";
            format = "[$symbol$context]($style) ";
          };

          # AWS - compact, right-aligned
          aws = {
            symbol = "aws:";
            style = "dimmed fg:base0a";
            format = "[$symbol$profile]($style) ";
          };

          # Docker
          docker_context = {
            symbol = "docker:";
            style = "bold fg:base0d";
            format = "[$symbol$context]($style) ";
          };

          # Time (disabled by default)
          time = {
            disabled = false;
            format = "[$time]($style) ";
            style = "bold dimmed fg:base03";
          };
        };
      };

      programs.bat = {
        enable = true;
      };

      # Alacritty terminal emulator, installed and configured via nix/home-manager.
      programs.alacritty = {
        enable = true;
        settings = {

          window = {
            dimensions = {
              columns = 150;
              lines = 100;
            };
            padding = {
              x = 8;
              y = 8;
            };
            dynamic_padding = true;
            decorations = "Buttonless";
            option_as_alt = "OnlyLeft";
          };

          cursor = {
            style = {
              shape = "Block";
              blinking = "Off";
            };
            unfocused_hollow = true;
          };

          selection = {
            save_to_clipboard = true;
          };

          scrolling = {
            history = 10000;
            multiplier = 3;
          };

          keyboard.bindings = [
            # <ctrlMod>+Space: send CSI-u so tmux reads C-Space (not C-@/NUL). On
            # macOS this is the physical Control key (Ctrl+Space); on Linux it is
            # the physical leftmost key (logical Command after the XKB swap).
            {
              key = "Space";
              mods = ctrlMod;
              chars = "${esc}[32;5u";
            }
            # Shift+Enter: preserve a distinct newline key through tmux and SSH via CSI-u.
            {
              key = "Enter";
              mods = "Shift";
              chars = "${esc}[13;2u";
            }
            # Cmd layer: copy/paste/quit/new/clear-history/font size. On macOS the
            # physical Command key; on Linux the physical Win key (logical Control
            # after the XKB swap).
            {
              key = "K";
              mods = cmdMod;
              action = "ClearHistory";
            }
            {
              key = "N";
              mods = cmdMod;
              action = "SpawnNewInstance";
            }
            {
              key = "W";
              mods = cmdMod;
              action = "Quit";
            }
            {
              key = "C";
              mods = cmdMod;
              action = "Copy";
            }
            {
              key = "V";
              mods = cmdMod;
              action = "Paste";
            }
            {
              key = "Plus";
              mods = cmdMod;
              action = "IncreaseFontSize";
            }
            {
              key = "Minus";
              mods = cmdMod;
              action = "DecreaseFontSize";
            }
            {
              key = "Key0";
              mods = cmdMod;
              action = "ResetFontSize";
            }
          ]
          # Linux-only: the Ctrl layer sends classic terminal control bytes to the
          # pty (like macOS Terminal). Empty on macOS, where those physical keys
          # are the Command actions above.
          ++ ctrlLayerBindings
          # Direct tab/window navigation: Cmd+1-9 on Darwin, Ctrl+Shift+1-9 elsewhere.
          ++ multiplexerTabBindings;
        };
      };
    };
}
