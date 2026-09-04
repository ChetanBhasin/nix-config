{ pkgs, ... }:
let
  theme = import ../../modules/theme/luna.nix;

  # Keep escape-sequence keybindings independent of TOML string quoting.
  esc = builtins.fromJSON ''"\u001b"'';

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
        success_symbol = "[➜](bold fg:${theme.base0B})";
        error_symbol = "[➜](bold fg:${theme.base08})";
        vicmd_symbol = "[](bold fg:${theme.base0B})";
      };

      # Directory
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold fg:${theme.base0A}";
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
        style = "bold fg:${theme.base0D}";
        format = "[$symbol$state( \\($name\\))]($style) ";
      };

      # Command duration
      cmd_duration = {
        min_time = 2000;
        show_milliseconds = false;
        style = "bold fg:${theme.base0A}";
        format = "[⏱ $duration]($style) ";
      };

      # Jobs indicator
      jobs = {
        symbol = "✦";
        style = "bold fg:${theme.base0D}";
        threshold = 1;
        format = "[$symbol$number]($style) ";
      };

      # Language-specific modules (compact)
      rust = {
        symbol = "rs ";
        style = "bold fg:${theme.base08}";
        format = "[$symbol$version]($style) ";
      };

      python = {
        symbol = "py ";
        style = "bold fg:${theme.base0A}";
        format = "[$symbol$version]($style) ";
      };

      nodejs = {
        symbol = "node ";
        style = "bold fg:${theme.base0B}";
        format = "[$symbol$version]($style) ";
      };

      golang = {
        symbol = "go ";
        style = "bold fg:${theme.base0C}";
        format = "[$symbol$version]($style) ";
      };

      # Kubernetes context - compact, right-aligned
      kubernetes = {
        disabled = false;
        symbol = "☸ ";
        style = "dimmed fg:${theme.base0D}";
        format = "[$symbol$context]($style) ";
      };

      # AWS - compact, right-aligned
      aws = {
        symbol = "aws:";
        style = "dimmed fg:${theme.base0A}";
        format = "[$symbol$profile]($style) ";
      };

      # Docker
      docker_context = {
        symbol = "docker:";
        style = "bold fg:${theme.base0D}";
        format = "[$symbol$context]($style) ";
      };

      # Time (disabled by default)
      time = {
        disabled = false;
        format = "[$time]($style) ";
        style = "bold dimmed fg:${theme.base03}";
      };
    };
  };

  programs.bat = {
    enable = true;
    config.theme = theme.name;
    themes.${theme.name}.src = pkgs.writeText "${theme.name}.tmTheme" theme.bat;
  };

  # Alacritty terminal emulator, installed and configured via nix/home-manager.
  programs.alacritty = {
    enable = true;
    settings = {
      colors = theme.alacritty;

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
        opacity = 1.0;
        option_as_alt = "OnlyLeft";
      };

      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
        bold_italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold Italic";
        };
        size = 14.0;
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
        # Ctrl+Space: Send CSI u sequence so tmux recognizes it as C-Space (not C-@/NUL)
        # Without this, Ctrl+Space sends NUL (0x00) which tmux sees as C-@
        # \u001b[32;5u = ESC [ 32 ; 5 u = CSI u encoding for Ctrl+Space
        {
          key = "Space";
          mods = "Control";
          chars = "${esc}[32;5u";
        }
        # Standard macOS shortcuts
        {
          key = "K";
          mods = "Command";
          action = "ClearHistory";
        }
        {
          key = "N";
          mods = "Command";
          action = "SpawnNewInstance";
        }
        {
          key = "W";
          mods = "Command";
          action = "Quit";
        }
        {
          key = "C";
          mods = "Command";
          action = "Copy";
        }
        {
          key = "V";
          mods = "Command";
          action = "Paste";
        }
        {
          key = "Plus";
          mods = "Command";
          action = "IncreaseFontSize";
        }
        {
          key = "Minus";
          mods = "Command";
          action = "DecreaseFontSize";
        }
        {
          key = "Key0";
          mods = "Command";
          action = "ResetFontSize";
        }
      ]
      # Direct tab/window navigation: Cmd+1-9 on Darwin, Ctrl+Shift+1-9 elsewhere.
      ++ multiplexerTabBindings;
    };
  };
}
