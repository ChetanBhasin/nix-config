{ config, inputs, ... }:
let
  modules = config.flake.modules;
in
{
  flake.modules.darwin.hugh = { config, pkgs, ... }: {

    darwin-config-manager = {
      enableSudoTouch = true;
      enableExtras = true;
      enableProf = false;

      extraCasks = [
        "1password"
        "balenaetcher"
        "proton-mail-bridge"
        "zoom"
        "steam"
        "whatsapp@beta"
        "shureplus-motiv"
        "screen-studio"
        "insta360-studio"
        "cryptomator"
      ];
    };

    environment.systemPackages = with pkgs; [ cloudflared ];

    imports = [
      modules.darwin.desktop
    ];
    home-manager.users.chetan = {
      imports = [ modules.homeManager.personal ];
      home-config-manager = {
        includeFonts = true;
        isDarwin = true;
        enableExtras = true;
      };
    };
  };
  flake.darwinConfigurations.hugh = inputs.darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      modules.darwin.hugh
      modules.darwin.nix
      modules.darwin.user
      modules.darwin.nixpkgs
    ];
  };
}
