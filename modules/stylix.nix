{ inputs, ... }:
let
  defaults =
    { lib, pkgs, ... }:
    {
      stylix = {
        # System-to-Home Manager inheritance uses mkDefault (1000).
        autoEnable = lib.mkOverride 1100 false;
        base16Scheme = lib.mkOverride 1100 (import ../theme/gruvbox-night.nix);
        polarity = lib.mkOverride 1100 "dark";
        fonts = {
          monospace = {
            package = lib.mkOverride 1100 pkgs.nerd-fonts.jetbrains-mono;
            name = lib.mkOverride 1100 "JetBrainsMono Nerd Font";
          };
          sizes = {
            terminal = lib.mkOverride 1100 14;
            desktop = lib.mkOverride 1100 13;
          };
        };
      };
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
      colors = config.lib.stylix.colors.withHashtag;
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
          signal = colors.base0A;
          dimNeutral = colors.base03;
          softNeutral = colors.base04;
          hint = colors.base0F;
          ok = colors.base0B;
          warning = colors.base0A;
          error = colors.base08;
          info = colors.base0D;
          primaryAccent = colors.base0A;
          primarySurface = colors.base01;
          inactiveBorder = colors.base02;
          activeBorder = colors.base0A;
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
          # These applications retain custom layouts and consume the palette below.
          neovim.enable = lib.mkDefault false;
          tmux.enable = lib.mkDefault false;
          hyprland.enable = lib.mkDefault false;
          hyprlock.enable = lib.mkDefault false;
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
      ];
      stylix.enable = true;
      stylix.image = lib.mkDefault ../home/wallpapers/orbital-lesson.png;
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
      ];
      stylix = {
        enable = true;
        image = lib.mkDefault ../home/wallpapers/orbital-lesson.png;
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
