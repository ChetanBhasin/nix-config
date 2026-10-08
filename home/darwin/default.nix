{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  zenDir = config.home.homeDirectory + "/Library/Application Support/zen";
in
{
  config = mkIf config.home-config-manager.isDarwin {
    home.file.".hammerspoon" = {
      source = ./hammerspoon;
      recursive = true;
    };

    # Copy app bundles into ~/Applications/Home Manager Apps so Spotlight and
    # the Dock see real apps. Updating a notarised bundle needs the terminal to
    # hold App Management (Privacy & Security); activation checks for it first.
    targets.darwin = {
      copyApps.enable = true;
      linkApps.enable = false;
    };

    # Zen picks its profile by hashing the app's path and rebuilds
    # profiles.ini/installs.ini from scratch whenever that hash is missing,
    # stranding the real profile behind a new empty one. A Home Manager module
    # owning profiles.ini caused exactly that on 2026-08-24 and again on
    # 2026-09-14; nothing here manages those files any more, but the app moving
    # would do it too, so keep pre-activation copies to restore the mapping from.
    home.activation.snapshotZenIni = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      zen=${lib.escapeShellArg zenDir}
      if [[ -d "$zen" ]]; then
        run mkdir -p "$zen/ini-snapshots"
        stamp=$(date +%Y%m%d-%H%M%S)
        for f in profiles.ini installs.ini; do
          if [[ -f "$zen/$f" ]]; then
            run cp -p "$zen/$f" "$zen/ini-snapshots/$f.$stamp"
            # Keep the 20 most recent copies of each file.
            ( ls -t "$zen/ini-snapshots/$f."* 2>/dev/null || true ) | tail -n +21 | while read -r old; do
              run rm -f "$old"
            done
          fi
        done
      fi
    '';
  };
}
