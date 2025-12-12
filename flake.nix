{
  description = "Chetan Bhasin's Nix configuration.";
  inputs = {
    # Package sets
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Environment/system management
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other sources
    flake-utils = { url = "github:numtide/flake-utils"; };
    devshell = {
      url = "github:numtide/devshell";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };

  };

  outputs = inputs@{ nixpkgs, darwin, home-manager, determinate, ... }:
    let
      nixpkgsConfig = {
        config = { allowUnfree = true; };
        overlays = [ ];
      };
      darwinModules = { user, host }:
        [
          # Main `nix-darwin` config
          (./. + "/hosts/${host}/configuration.nix")
          { nix.enable = false; }
          determinate.darwinModules.default
          {
            determinate-nix.customSettings = {
              # Experimental features needed by Determinate’s builder (+ your usual ones)
              experimental-features = "flakes external-builders";
# Trust your admin group so restricted settings from flakes are honored
              trusted-users = "root @admin chetan";

              # Determinate Linux builder wiring (JSON, one line)
              external-builders = ''
                [{"systems":["aarch64-linux","x86_64-linux"],"program":"/usr/local/bin/determinate-nixd","args":["builder"]}]'';
            };
          }
          # `home-manager` module
          home-manager.darwinModules.home-manager
          {
            nixpkgs = nixpkgsConfig;
            # `home-manager` config
            users.users.${user}.home = "/Users/${user}";
            home-manager = {
              useGlobalPkgs = true;
              users.${user} = import (./. + "/hosts/${host}/home.nix");
            };
          }
        ];
      nixosModules = { user, host }:
        [
          # Main `nixos` config
          (./. + "/hosts/${host}/configuration.nix")
          # `home-manager` module
          home-manager.nixosModules.home-manager
          {
            nixpkgs = nixpkgsConfig;
            users.users.${user}.shell = nixpkgs.zsh;
            # `home-manager` config
            users.users.${user} = {
              home = "/home/${user}";
              isNormalUser = true;
              group = "${user}";
              extraGroups = [ "wheel" ];
            };
            users.groups.${user} = { };
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = import (./. + "/hosts/${host}/home.nix");
            };
          }
        ];
    in {
      darwinConfigurations = {
        nix.enable = false;
        environment.etc."determinate/config.json".text =
          builtins.toJSON { builder = { state = "enabled"; }; };

        hugh = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = darwinModules {
            user = "chetan";
            host = "hugh";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
        markus = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = darwinModules {
            user = "chetan";
            host = "markus";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
      };
    };
}
