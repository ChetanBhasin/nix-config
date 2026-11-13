{ inputs, ... }:
{
  flake.modules.darwin.nix = {
    imports = [ inputs.determinate.darwinModules.default ];
    nix.enable = false;
    determinateNix = {
      # Settings written to `/etc/nix/nix.custom.conf`.
      customSettings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        experimental-features = [
          "nix-command"
          "flakes"
          "external-builders"
        ];
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
        ];

        # Trust your admin group (and this user) so restricted settings from flakes are honored.
        trusted-users = [
          "root"
          "@admin"
          "chetan"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };

      # Configure Determinate Nixd (writes `/etc/determinate/config.json`).
      determinateNixd.builder.state = "enabled";
    };

  };
  flake.modules.nixos.nix = {
    imports = [ inputs.determinate.nixosModules.default ];
    nix = {
      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        experimental-features = [
          "external-builders"
          "nix-command"
          "flakes"
        ];
        substituters = [
          "https://cache.nixos.org/"
          "https://nix-community.cachix.org"
          "https://devenv.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
        trusted-users = [
          "root"
          "@wheel"
        ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

  };
}
