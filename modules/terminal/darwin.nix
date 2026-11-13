{
  flake.modules.homeManager.terminal-personal =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    with lib;
    let
      # Team whose Developer ID Application certificate re-signs Alacritty.
      signingTeam = "5C469GAA4P";
      alacrittyApp = "${pkgs.alacritty}/Applications/Alacritty.app";
      # Alacritty without its app bundle, so copyApps leaves it alone.
      alacrittyWithoutApp =
        pkgs.runCommand "alacritty-${pkgs.alacritty.version}"
          {
            inherit (pkgs.alacritty) version meta;
          }
          ''
            mkdir -p $out
            for entry in ${pkgs.alacritty}/*; do
              [[ $(basename "$entry") == Applications ]] || ln -s "$entry" $out/
            done
          '';
    in
    {
      config = mkIf config.home-config-manager.isDarwin {
        # Copy app bundles into ~/Applications/Home Manager Apps so Spotlight and
        # the Dock see real apps. The terminal needs App Management permission.
        targets.darwin = {
          copyApps = {
            enable = true;
            # The preflight resets every App Management grant on any write failure,
            # including root-owned apps. Let rsync report the actual error instead.
            enableChecks = false;
          };
          linkApps.enable = false;
        };

        # The terminal running activation is the app that needs App Management, so
        # it cannot be one copyApps replaces: a nix build is ad-hoc signed, its
        # designated requirement is its cdhash, and every rebuild revokes the grant.
        # Alacritty is installed to ~/Applications instead and re-signed with the
        # Developer ID, whose requirement (bundle id + team) survives rebuilds. It
        # is copied and signed only when the store path or identity changes.
        programs.alacritty.package = alacrittyWithoutApp;

        home.activation.installAlacritty = lib.hm.dag.entryAfter [ "copyApps" ] ''
          src=${lib.escapeShellArg alacrittyApp}
          dst="$HOME/Applications/Alacritty.app"
          marker=${lib.escapeShellArg "${config.xdg.stateHome}/nix-config/alacritty-app"}
          identity=$(/usr/bin/security find-identity -v -p codesigning \
            | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Developer ID Application: .*(${signingTeam})"$/\1/p' \
            | head -n 1)

          if [[ -z $identity ]]; then
            warnEcho "No Developer ID for team ${signingTeam}; Alacritty stays ad-hoc signed and loses App Management on every rebuild."
          fi

          if [[ ! -d $dst || "$(cat "$marker" 2>/dev/null)" != "$src $identity" ]]; then
            run mkdir -p "$dst"
            run ${lib.getExe pkgs.rsync} --recursive --checksum --links --copy-unsafe-links \
              --perms --chmod=+w --delete "$src/" "$dst/"
            if [[ -n $identity ]]; then
              run /usr/bin/codesign --force --sign "$identity" "$dst"
            fi
            if [[ ! -v DRY_RUN ]]; then
              mkdir -p "$(dirname "$marker")"
              echo "$src $identity" > "$marker"
            fi
          fi
        '';

      };
    };
}
