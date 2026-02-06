# Standalone Terminal module for Home Manager
# Combines: zsh, fzf, starship, direnv, zoxide, alacritty
# Can be imported by other flakes via: inputs.nix-config.homeManagerModules.terminal
{ config, pkgs, lib, ... }:

let
  cfg = config.cb.terminal;

  # Paths to shell scripts (relative to this module)
  shellScriptsPath = ../../home/zsh;

  # Platform-agnostic "Super" key modifier
  # macOS: Command (Cmd), Linux: Control+Shift (Ctrl+number doesn't produce unique keycodes)
  superMod = if pkgs.stdenv.isDarwin then "Command" else "Control|Shift";

  # Generate tmux window switching keybindings (Super+1-9)
  # Sends escape sequences that tmux binds to select-window
  # Note: \u001b is ESC in TOML (TOML doesn't support \x escapes)
  tmuxWindowBindings = builtins.genList (n:
    let num = n + 1;
    in { key = "Key${toString num}"; mods = superMod; chars = "\\u001b[${toString num};3P"; }
  ) 9;
in
{
  options.cb.terminal = {
    enable = lib.mkEnableOption "Chetan's terminal configuration";

    enableZsh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zsh configuration with plugins";
    };

    enableFzf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable fzf with custom configuration";
    };

    enableStarship = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable starship prompt";
    };

    enableDirenv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable direnv with nix-direnv integration";
    };

    enableZoxide = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zoxide (smart cd)";
    };

    enableAlacritty = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable alacritty terminal configuration";
    };

    enableDevEnvironment = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable development environment variables for building native extensions.
        Sets paths for OpenSSL, rdkafka, libiconv, leptonica, tesseract, poppler.
        Only enable if you need to build packages that depend on these libraries.
      '';
    };

    viMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable vi mode for zsh";
    };

    historySize = lib.mkOption {
      type = lib.types.int;
      default = 50000;
      description = "Number of history entries to keep";
    };

    extraZshConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra zsh configuration to add to initContent";
    };

    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra shell aliases to add";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Zsh configuration
    (lib.mkIf cfg.enableZsh {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        defaultKeymap = if cfg.viMode then "viins" else "emacs";

        history = {
          extended = true;
          size = cfg.historySize;
          save = cfg.historySize;
          share = true;
          ignoreDups = true;
          ignoreSpace = true;
          expireDuplicatesFirst = true;
        };

        shellAliases = {
          c = "z";
        } // cfg.extraAliases;

        sessionVariables = {
          EDITOR = "nvim";
        } // lib.optionalAttrs cfg.enableDevEnvironment {
          OPENSSL_NO_VENDOR = "1";
          OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
          OPENSSL_DIR = "${pkgs.openssl.dev}";
          PKG_CONFIG_LIBDIR = "${pkgs.rdkafka}/lib/pkgconfig";
          LIBRARY_PATH = lib.makeLibraryPath (
            [ pkgs.libiconv pkgs.poppler ]
            ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.libcxx ]
          );
          PKG_CONFIG_PATH =
            "$PKG_CONFIG_PATH:${pkgs.rdkafka}/lib/pkgconfig:${pkgs.libiconv}/lib/pkgconfig:${pkgs.leptonica}/lib/pkgconfig/:${pkgs.tesseract}/lib/pkgconfig";
        };

        initContent = ''
          # Source main configuration
          [[ -f ~/.sources ]] && source ~/.sources
          ${cfg.extraZshConfig}
        '';

        plugins = [
          {
            name = "zsh-syntax-highlighting";
            src = pkgs.zsh-syntax-highlighting;
            file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
          }
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
          {
            name = "zsh-history-substring-search";
            src = pkgs.zsh-history-substring-search;
            file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
          }
        ];
      };

      # Symlink shell configuration files
      home.file.".sources".source = shellScriptsPath + "/sources.sh";
      home.file.".sources_platform".source =
        if pkgs.stdenv.isDarwin
        then shellScriptsPath + "/sources_darwin.sh"
        else shellScriptsPath + "/sources_linux.sh";
    })

    # FZF configuration
    (lib.mkIf cfg.enableFzf {
      programs.fzf = {
        enable = true;
        enableZshIntegration = cfg.enableZsh;
        defaultCommand = "fd --type f --hidden --follow --exclude .git";
        defaultOptions = [
          "--height 40%"
          "--layout=reverse"
          "--border"
          "--inline-info"
          "--color=dark"
          "--color=fg:-1,bg:-1,hl:#c678dd,fg+:#ffffff,bg+:#4b5263,hl+:#d858fe"
          "--color=info:#98c379,prompt:#61afef,pointer:#be5046,marker:#e5c07b,spinner:#61afef,header:#61afef"
          # Vim-style navigation
          "--bind=alt-j:down,alt-k:up"
          "--bind=alt-h:backward-char,alt-l:forward-char"
          "--bind=alt-u:preview-half-page-up,alt-d:preview-half-page-down"
          "--bind=alt-f:preview-page-down,alt-b:preview-page-up"
          "--bind=alt-g:first,alt-G:last"
          # Ctrl bindings
          "--bind=ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down"
          "--bind=ctrl-f:preview-page-down,ctrl-b:preview-page-up"
          "--bind=ctrl-/:toggle-preview"
        ];
        fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
        fileWidgetOptions = [
          "--preview 'bat --color=always --line-range :100 {}'"
          "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
        ];
        changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
        changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
        historyWidgetOptions = [
          "--sort"
          "--exact"
          "--preview 'echo {}'"
          "--preview-window up:3:hidden:wrap"
          "--bind 'ctrl-/:toggle-preview'"
          "--color header:italic"
          "--header 'Press CTRL-Y to copy command into clipboard'"
        ];
      };
    })

    # Starship prompt
    (lib.mkIf cfg.enableStarship {
      programs.starship = {
        enable = true;
        enableZshIntegration = cfg.enableZsh;
        settings = {
          add_newline = true;
          scan_timeout = 10;

          format = builtins.concatStringsSep "" [
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

          right_format = builtins.concatStringsSep "" [
            "$kubernetes"
            "$aws"
          ];

          custom = {
              jj = {
                  when = "jj starship detect";
                  shell = ["jj-starship"];
                  format = "$output ";
              };
          };

          character = {
            success_symbol = "[➜](bold green)";
            error_symbol = "[➜](bold red)";
            vicmd_symbol = "[](bold green)";
          };

          directory = {
            truncation_length = 3;
            truncate_to_repo = true;
            style = "bold cyan";
          };

          nix_shell = {
            symbol = "❄️ ";
            style = "bold blue";
            format = "[$symbol$state( \\($name\\))]($style) ";
          };

          cmd_duration = {
            min_time = 2000;
            show_milliseconds = false;
            style = "bold yellow";
            format = "[⏱ $duration]($style) ";
          };

          jobs = {
            symbol = "✦";
            style = "bold blue";
            threshold = 1;
            format = "[$symbol$number]($style) ";
          };

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

          kubernetes = {
            disabled = false;
            symbol = "☸ ";
            style = "dimmed blue";
            format = "[$symbol$context]($style) ";
          };

          aws = {
            symbol = "aws:";
            style = "dimmed yellow";
            format = "[$symbol$profile]($style) ";
          };

          docker_context = {
            symbol = "docker:";
            style = "bold blue";
            format = "[$symbol$context]($style) ";
          };

          time = {
            disabled = true;
            format = "[$time]($style) ";
            style = "bold dimmed white";
          };
        };
      };
    })

    # Direnv
    (lib.mkIf cfg.enableDirenv {
      programs.direnv = {
        enable = true;
        enableZshIntegration = cfg.enableZsh;
        nix-direnv.enable = true;
      };
    })

    # Zoxide
    (lib.mkIf cfg.enableZoxide {
      programs.zoxide = {
        enable = true;
        enableZshIntegration = cfg.enableZsh;
      };
    })

    # Alacritty terminal configuration
    (lib.mkIf cfg.enableAlacritty {
      programs.alacritty = {
        enable = true;
        # Use catppuccin_mocha theme from alacritty-theme package
        theme = "catppuccin_mocha";
        settings = {
          # Window configuration
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
          } // lib.optionalAttrs pkgs.stdenv.isDarwin {
            option_as_alt = "OnlyLeft";
          };

          # Font configuration
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

          # Cursor configuration
          cursor = {
            style = {
              shape = "Block";
              blinking = "Off";
            };
            unfocused_hollow = true;
          };

          # Selection behavior (copy-on-select)
          selection = {
            save_to_clipboard = true;
          };

          # Scrolling configuration
          scrolling = {
            history = 10000;
            multiplier = 3;
          };

          # Keyboard bindings
          keyboard.bindings =
            # Ctrl+Space: Send CSI u sequence so tmux recognizes it as C-Space (not C-@/NUL)
            # Without this, Ctrl+Space sends NUL (0x00) which tmux sees as C-@
            # \u001b[32;5u = ESC [ 32 ; 5 u = CSI u encoding for Ctrl+Space
            [
              { key = "Space"; mods = "Control"; chars = "\\u001b[32;5u"; }
            ]
            # macOS-specific bindings (standard Cmd shortcuts)
            ++ lib.optionals pkgs.stdenv.isDarwin [
              { key = "K"; mods = "Command"; action = "ClearHistory"; }
              { key = "N"; mods = "Command"; action = "SpawnNewInstance"; }
              { key = "W"; mods = "Command"; action = "Quit"; }
              { key = "C"; mods = "Command"; action = "Copy"; }
              { key = "V"; mods = "Command"; action = "Paste"; }
              { key = "Plus"; mods = "Command"; action = "IncreaseFontSize"; }
              { key = "Minus"; mods = "Command"; action = "DecreaseFontSize"; }
              { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
            ]
            # Tmux window navigation: Super+1-9 (Cmd on macOS, Ctrl+Shift on Linux)
            ++ tmuxWindowBindings;
        };
      };
    })

    # Common packages needed by the terminal configuration
    # These are required for the shell aliases and functions in sources.sh to work
    {
      home.packages = with pkgs; [
        # Shell completion
        zsh-completions
        carapace

        # Modern CLI replacements (required by shell aliases)
        eza       # ls replacement
        bat       # cat replacement
        ripgrep   # grep replacement
        fd        # find replacement
        htop      # top replacement
        dust      # du replacement
        duf       # df replacement
        procs     # ps replacement

        # Core utilities
        git
        tree      # used by fzf directory preview
      ] ++ lib.optionals cfg.enableFzf [
        fzf       # fuzzy finder (also enabled via programs.fzf)
      ];
    }
  ]);
}
