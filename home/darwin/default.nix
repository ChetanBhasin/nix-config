{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  zenProfile = config.home.homeDirectory + "/Library/Application Support/zen/profiles.ini";
in
{
  config = mkIf config.home-config-manager.isDarwin {
    home.file.".hammerspoon" = {
      source = ./hammerspoon;
      recursive = true;
    };

    targets.darwin = {
      copyApps.enable = false;
      linkApps.enable = true;
    };

    # The former Zen Home Manager module replaced profiles.ini with a store
    # link. Dereference it before linkGeneration cleans up that orphan so the
    # Homebrew app keeps the exact active profile selection and browser state.
    home.activation.preserveZenProfile = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      if [[ -L ${lib.escapeShellArg zenProfile} ]]; then
        zen_profile_target="$(readlink ${lib.escapeShellArg zenProfile})"
        case "$zen_profile_target" in
          /nix/store/*-home-manager-files/*)
            if [[ ! -e ${lib.escapeShellArg (zenProfile + ".pre-nix-rollback")} ]]; then
              run cp -pL -- \
                ${lib.escapeShellArg zenProfile} \
                ${lib.escapeShellArg (zenProfile + ".pre-nix-rollback")}
            fi
            run cp -pL -- \
              ${lib.escapeShellArg zenProfile} \
              ${lib.escapeShellArg (zenProfile + ".home-manager-migration")}
            run chmod u+w \
              ${lib.escapeShellArg (zenProfile + ".home-manager-migration")}
            run mv -f -- \
              ${lib.escapeShellArg (zenProfile + ".home-manager-migration")} \
              ${lib.escapeShellArg zenProfile}
            ;;
        esac
      fi
    '';
  };
}
