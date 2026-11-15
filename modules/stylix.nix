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
      # Rebuild derived formats before overriding an already overridden scheme.
      overrideColors =
        overrides: (config.stylix.base16.mkSchemeAttrs config.lib.stylix.colors).override overrides;
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
        };
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
        stylix.targets = {
          # The custom tmux layout renders its colors from the same palette.
          tmux.enable = lib.mkDefault false;
          hyprland.colors.override = overrideColors {
            base0D = colors.base09;
            base03 = colors.base0D;
          };
        };
        lib.stylix.palette = palette;
        lib.stylix.render = builtins.replaceStrings (map (name: "@${name}@") (builtins.attrNames palette)) (
          builtins.attrValues palette
        );
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
