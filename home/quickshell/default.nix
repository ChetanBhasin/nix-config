{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.home-config-manager;
  theme = import ../../modules/theme/gruvbox-night.nix;

  quickshellConfig = pkgs.runCommandLocal "quickshell-${theme.name}-config" { } ''
    mkdir -p "$out"
    cp -R ${./config}/. "$out/"
    chmod -R u+w "$out"

    substituteInPlace "$out/Theme.js" \
      --replace-fail '@base00@' '${theme.base00}' \
      --replace-fail '@base01@' '${theme.base01}' \
      --replace-fail '@base02@' '${theme.base02}' \
      --replace-fail '@base05@' '${theme.base05}' \
      --replace-fail '@base06@' '${theme.base06}' \
      --replace-fail '@base07@' '${theme.base07}' \
      --replace-fail '@base08@' '${theme.base08}' \
      --replace-fail '@base09@' '${theme.base09}' \
      --replace-fail '@base0A@' '${theme.base0A}' \
      --replace-fail '@base0B@' '${theme.base0B}' \
      --replace-fail '@base0D@' '${theme.base0D}' \
      --replace-fail '@base0E@' '${theme.base0E}' \
      --replace-fail '@signal@' '${theme.signal}' \
      --replace-fail '@dimNeutral@' '${theme.dimNeutral}' \
      --replace-fail '@softNeutral@' '${theme.softNeutral}' \
      --replace-fail '@info@' '${theme.info}' \
      --replace-fail '@primaryAccent@' '${theme.primaryAccent}' \
      --replace-fail '@primarySurface@' '${theme.primarySurface}' \
      --replace-fail '@inactiveBorder@' '${theme.inactiveBorder}' \
      --replace-fail '@activeBorder@' '${theme.activeBorder}'

    substituteInPlace "$out/ControlCenter.qml" \
      --replace-fail '@nmConnectionEditor@' '${lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor"}'
  '';
in
{
  config = lib.mkIf cfg.enableHyprland {
    programs.quickshell = {
      enable = true;
      package = pkgs.quickshell;
      configs."gruvbox-night" = quickshellConfig;
      activeConfig = "gruvbox-night";
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
}
