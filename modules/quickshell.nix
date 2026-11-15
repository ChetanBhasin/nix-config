{
  flake.modules.homeManager.quickshell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.home-config-manager;
      themeFile = pkgs.writeText "Theme.js" (
        builtins.replaceStrings
          [ "@fontFamily@" "@fontSize@" ]
          [ config.stylix.fonts.monospace.name (toString config.stylix.fonts.sizes.desktop) ]
          (config.lib.stylix.render (builtins.readFile ../home/quickshell/config/Theme.js))
      );

      quickshellConfig = pkgs.runCommandLocal "quickshell-config" { } ''
        mkdir -p "$out"
        cp -R ${../home/quickshell/config}/. "$out/"
        chmod -R u+w "$out"

        cp ${themeFile} "$out/Theme.js"

        substituteInPlace "$out/ControlCenter.qml" \
          --replace-fail '@nmConnectionEditor@' '${lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor"}'
      '';
    in
    {
      config = lib.mkIf cfg.enableHyprland {
        programs.quickshell = {
          enable = true;
          package = pkgs.quickshell;
          configs."desktop" = quickshellConfig;
          activeConfig = "desktop";
          systemd = {
            enable = true;
            target = "hyprland-session.target";
          };
        };

        systemd.user.services.quickshell.Unit = {
          PartOf = [ "hyprland-session.target" ];
          # The config is an atomically replaced store symlink, which Quickshell's
          # file watcher cannot follow across generations. Restart on config changes.
          X-Restart-Triggers = [ quickshellConfig ];
        };
      };
    };
}
