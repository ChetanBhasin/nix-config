{ config, pkgs, ... }: {
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
        "$directory"
        "$git_branch"
        "$git_status"
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
      right_format = builtins.concatStringsSep "" [
        "$kubernetes"
        "$aws"
      ];

      # Character/prompt
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
        vicmd_symbol = "[](bold green)";
      };

      # Directory
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
      };

      # Git
      git_branch = {
        symbol = " ";
        style = "bold purple";
        format = "[$symbol$branch(:$remote_branch)]($style) ";
      };

      git_status = {
        style = "bold red";
        format = "([$all_status$ahead_behind]($style) )";
        conflicted = "=";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕";
        untracked = "?";
        stashed = "*";
        modified = "!";
        staged = "+";
        renamed = "»";
        deleted = "✘";
      };

      # Nix shell indicator
      nix_shell = {
        symbol = "❄️ ";
        style = "bold blue";
        format = "[$symbol$state( \\($name\\))]($style) ";
      };

      # Command duration
      cmd_duration = {
        min_time = 2000;
        show_milliseconds = false;
        style = "bold yellow";
        format = "[⏱ $duration]($style) ";
      };

      # Jobs indicator
      jobs = {
        symbol = "✦";
        style = "bold blue";
        threshold = 1;
        format = "[$symbol$number]($style) ";
      };

      # Language-specific modules (compact)
      rust = {
        symbol = "rs ";
        style = "bold red";
        format = "[$symbol$version]($style) ";
      };

      python = {
        symbol = "py ";
        style = "bold yellow";
        format = "[$symbol$version]($style) ";
      };

      nodejs = {
        symbol = "node ";
        style = "bold green";
        format = "[$symbol$version]($style) ";
      };

      golang = {
        symbol = "go ";
        style = "bold cyan";
        format = "[$symbol$version]($style) ";
      };

      # Kubernetes context - compact, right-aligned
      kubernetes = {
        disabled = false;
        symbol = "☸ ";
        style = "dimmed blue";
        format = "[$symbol$context]($style) ";
      };

      # AWS - compact, right-aligned
      aws = {
        symbol = "aws:";
        style = "dimmed yellow";
        format = "[$symbol$profile]($style) ";
      };

      # Docker
      docker_context = {
        symbol = "docker:";
        style = "bold blue";
        format = "[$symbol$context]($style) ";
      };

      # Time (disabled by default)
      time = {
        disabled = true;
        format = "[$time]($style) ";
        style = "bold dimmed white";
      };
    };
  };

  xdg.configFile."ghostty/config".source = ./ghostty;

  # Alacritty terminal emulator (alternative to Ghostty)
  # Note: Installed via both Homebrew cask (for macOS app in /Applications)
  # and nixpkgs (for theme/config generation). Use the Homebrew version.
  programs.alacritty = {
    enable = true;
    # Use catppuccin_mocha theme from alacritty-theme package
    theme = "catppuccin_mocha";
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
        { key = "K"; mods = "Command"; action = "ClearHistory"; }
        { key = "N"; mods = "Command"; action = "SpawnNewInstance"; }
        { key = "W"; mods = "Command"; action = "Quit"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "Plus"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Minus"; mods = "Command"; action = "DecreaseFontSize"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
      ];
    };
  };
}
