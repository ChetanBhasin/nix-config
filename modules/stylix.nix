{ inputs, ... }:
let
  themes = {
    berrit = {
      scheme = import ../theme/berrit.nix;
      image = ../home/wallpapers/berrit.png;
      font = "jetbrains-mono";
      fontName = "JetBrainsMono Nerd Font";
      accent = "base0A";
      hint = "base0F";
      comment = "base04";
      roles = {
        selectionBg = "base0A";
        selectionFg = "base00";
        statusText = "base06";
        paneBorder = "base03";
        paneActiveBorder = "base0A";
        lockInput = "base01";
      };
      tokens = {
        paneBorderLines = "heavy";
        shellRadius = "10";
        shellSmallRadius = "7";
      };
      lock = {
        useWallpaper = false;
        background = {
          path = "screenshot";
          blur_size = 25;
          blur_passes = 2;
          brightness = 0.45;
          contrast = 0.8;
          vibrancy = 0.1;
        };
        backgroundAlpha = "cc";
        inputAlpha = "66";
        rounding = 14;
        outline = 2;
      };
      targets = {
        hyprland = {
          base0D = "base09";
          base03 = "base0D";
        };
        hyprlock = {
          base03 = "base02";
          base0A = "base0C";
        };
      };
    };
    navy = {
      scheme = import ../theme/navy.nix;
      image = ../home/wallpapers/navy.png;
      font = "lilex";
      fontName = "Lilex Nerd Font";
      accent = "base0F";
      hint = "base0D";
      comment = "base03";
      roles = {
        selectionBg = "base01";
        selectionFg = "base0F";
        statusText = "base05";
        paneBorder = "base02";
        paneActiveBorder = "base02";
        lockInput = "base00";
      };
      tokens = {
        paneBorderLines = "single";
        shellRadius = "4";
        shellSmallRadius = "3";
      };
      lock = {
        useWallpaper = true;
        background.blur_passes = 0;
        backgroundAlpha = "ff";
        inputAlpha = "ff";
        rounding = 4;
        outline = 1;
      };
      targets = {
        gtk = {
          base0D = "base0F";
          base0E = "base0A";
        };
        qt = {
          base0D = "base0F";
          base0E = "base0F";
        };
        hyprland = {
          base0D = "base0F";
          base03 = "base02";
        };
        hyprlock = {
          base03 = "base02";
          base0A = "base0F";
        };
        fzf = {
          base0A = "base0F";
          base0C = "base0F";
          base0D = "base0F";
        };
      };
    };
  };
  defaults =
    {
      config,
      lib,
      pkgs,
      specialArgs,
      ...
    }:
    let
      theme = themes.${config.cb.theme};
    in
    {
      options.cb.theme = lib.mkOption {
        type = lib.types.enum (builtins.attrNames themes);
        default = "berrit";
        description = "Shared color, font and wallpaper theme.";
      };
      config = {
        cb.theme = lib.mkDefault (specialArgs.osConfig.cb.theme or "berrit");
        stylix = {
          # System-to-Home Manager inheritance uses mkDefault (1000).
          autoEnable = lib.mkOverride 1100 false;
          base16Scheme = lib.mkOverride 1100 theme.scheme;
          polarity = lib.mkOverride 1100 "dark";
          fonts = {
            monospace = {
              package = lib.mkOverride 1100 pkgs.nerd-fonts.${theme.font};
              name = lib.mkOverride 1100 theme.fontName;
            };
            sizes = {
              terminal = lib.mkOverride 1100 14;
              desktop = lib.mkOverride 1100 13;
            };
          };
        };
      };
    };
  wallpaper = { config, lib, ... }: {
    stylix.image = lib.mkDefault themes.${config.cb.theme}.image;
  };
in
{
  flake.modules.homeManager.theme =
    {
      config,
      lib,
      specialArgs,
      ...
    }:
    let
      theme = themes.${config.cb.theme};
      colors = config.lib.stylix.colors.withHashtag;
      # Derive formats once from the raw scheme, preserving global overrides.
      overrideColors =
        overrides:
        (config.stylix.base16.mkSchemeAttrs config.stylix.base16Scheme).override (
          config.stylix.override // overrides
        );
      palette =
        lib.genAttrs (map (n: "base${n}") [
          "00"
          "01"
          "02"
          "03"
          "04"
          "05"
          "06"
          "07"
          "08"
          "09"
          "0A"
          "0B"
          "0C"
          "0D"
          "0E"
          "0F"
        ]) (name: colors.${name})
        // {
          signal = colors.${theme.accent};
          dimNeutral = colors.base03;
          softNeutral = colors.base04;
          hint = colors.${theme.hint};
          comment = colors.${theme.comment};
          ok = colors.base0B;
          warning = colors.base0A;
          error = colors.base08;
          info = colors.base0D;
          primaryAccent = colors.${theme.accent};
          primarySurface = colors.base01;
          inactiveBorder = colors.base02;
          activeBorder = colors.${theme.accent};
        }
        // lib.mapAttrs (_: slot: colors.${slot}) theme.roles;
      renderValues = palette // theme.tokens;
    in
    {
      key = "nix-config-stylix";
      # System Stylix already imports its Home Manager module. Importing its
      # anonymous initializer twice defines read-only options twice.
      imports = [
        defaults
      ]
      ++ lib.optional (
        !(
          specialArgs ? osConfig
          && specialArgs.osConfig ? stylix
          && specialArgs.osConfig.stylix.enable
          && specialArgs.osConfig.stylix.homeManagerIntegration.autoImport
        )
      ) inputs.stylix.homeModules.stylix;
      config = {
        stylix.targets =
          lib.mapAttrs (_: slots: {
            colors.override = overrideColors (lib.mapAttrs (_: slot: colors.${slot}) slots);
          }) theme.targets
          // {
            # The custom tmux layout renders its colors from the same palette.
            tmux.enable = lib.mkDefault false;
          };
        lib.stylix.palette = palette;
        lib.stylix.lock = theme.lock;
        lib.stylix.render = builtins.replaceStrings (map (name: "@${name}@") (
          builtins.attrNames renderValues
        )) (builtins.attrValues renderValues);
        home.packages = lib.mkIf config.stylix.enable config.stylix.fonts.packages;
      };
    };

  flake.modules.darwin.theme =
    { config, lib, ... }:
    {
      imports = [
        inputs.stylix.darwinModules.stylix
        defaults
        wallpaper
      ];
      stylix.enable = true;
      fonts.packages = config.stylix.fonts.packages;
      system.defaults.NSGlobalDomain = {
        AppleInterfaceStyle = if config.stylix.polarity == "light" then null else "Dark";
        AppleInterfaceStyleSwitchesAutomatically = false;
      };
      # nix-darwin ignores null defaults; light mode must remove the dark key.
      system.activationScripts.userDefaults.text = lib.mkAfter (
        lib.optionalString (config.stylix.polarity == "light") ''
          launchctl asuser "$(id -u -- ${lib.escapeShellArg config.system.primaryUser})" \
            sudo --user=${lib.escapeShellArg config.system.primaryUser} -- \
            defaults delete -g AppleInterfaceStyle 2>/dev/null || true
        ''
      );
    };

  flake.modules.nixos.theme =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        inputs.stylix.nixosModules.stylix
        defaults
        wallpaper
      ];
      stylix = {
        enable = true;
        cursor = {
          package = lib.mkDefault pkgs.bibata-cursors;
          name = lib.mkDefault "Bibata-Original-Ice";
          size = lib.mkDefault 24;
        };
        targets.console.enable = true;
      };
      fonts.packages = config.stylix.fonts.packages;
      environment.sessionVariables.XCURSOR_THEME = config.stylix.cursor.name;
    };
}
