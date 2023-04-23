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
  };

  programs.alacritty = {
    enable = true;
    package = pkgs.alacritty;
    settings = {
      font = { size = 14; };
      env = { TERM = "xterm-256color"; };
      colors = {
        primary = {
          background = "#1E1E2E";
          foreground = "#CDD6F4";
          dim_foreground = "#CDD6F4";
          bright_foreground = "#CDD6F4";
        };
        cursor = {
          text = "#1E1E2E";
          cursor = "#F5E0DC";
        };
        vi_mode_cursor = {
          text = "#1E1E2E";
          cursor = "#B4BEFE";
        };
        selection = {
          text = "#1E1E2E";
          background = "#F5E0DC";
        };
        hints = {
          start = {
            foreground = "#1E1E2E";
            background = "#A6ADC8";
          };
          end = {
            foreground = "#1E1E2E";
            background = "#A6ADC8";
          };
        };
        search = {
          matches = {
            foreground = "#1E1E2E";
            background = "#A6ADC8";
          };
          focused_match = {
            foreground = "#1E1E2E";
            background = "#A6ADC8";
          };
          footer_bar = {
            foreground = "#1E1E2E";
            background = "#A6ADC8";
          };
        };
        normal = {
          black = "#45475A";
          red = "#F38BA8";
          green = "#A6E3A1";
          yellow = "#F9E2AF";
          blue = "#89B4FA";
          magenta = "#F5C2E7";
          cyan = "#94E2D5";
          white = "#BAC2DE";
        };
        bright = {
          black = "#585B70";
          red = "#F38BA8";
          green = "#A6E3A1";
          yellow = "#F9E2AF";
          blue = "#89B4FA";
          magenta = "#F5C2E7";
          cyan = "#94E2D5";
          white = "#A6ADC8";
        };
        dim = {
          black = "#45475A";
          red = "#F38BA8";
          green = "#A6E3A1";
          yellow = "#F9E2AF";
          blue = "#89B4FA";
          magenta = "#F5C2E7";
          cyan = "#94E2D5";
          white = "#BAC2DE";
        };
        indexed_colors = [
          {
            index = 16;
            color = "#FAB387";
          }
          {
            index = 17;
            color = "#F5E0DC";
          }
        ];
      };
      window = {
        padding.x = 5;
        padding.y = 5;
        dynamic_padding = false;
        dimensions = {
          lines = 35;
          columns = 100;
        };
      };
      key_bindings = [{
        key = "K";
        mods = "Control";
        chars = "\\x0c";
      }];
    };
  };
}
