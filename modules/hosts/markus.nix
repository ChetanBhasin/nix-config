{ config, inputs, ... }:
let
  modules = config.flake.modules;
in
{
  flake.modules.darwin.markus = { config, pkgs, ... }: {

    darwin-config-manager = {
      enableSudoTouch = true;
      enableExtras = true;
      enableProf = false;

      extraBrews = [
        "octopusdeploy/taps/octopus-cli"
      ];
    };

    # Force U.S. keyboard layout so ~ is produced directly instead of as a dead key
    system.defaults.CustomUserPreferences."com.apple.HIToolbox" = {
      AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.US";
      AppleEnabledInputSources = [
        {
          "InputSourceKind" = "Keyboard Layout";
          "KeyboardLayout ID" = 0;
          "KeyboardLayout Name" = "U.S.";
        }
      ];
      AppleSelectedInputSources = [
        {
          "InputSourceKind" = "Keyboard Layout";
          "KeyboardLayout ID" = 0;
          "KeyboardLayout Name" = "U.S.";
        }
      ];
    };

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
  flake.darwinConfigurations.markus = inputs.darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      modules.darwin.markus
      modules.darwin.nix
      modules.darwin.user
      modules.darwin.nixpkgs
    ];
  };
}
