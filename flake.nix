{
  description = "Chetan Bhasin's Nix configuration";
  inputs = {
    # Package sets
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Environment/system management
    darwin = {
      url = "github:lnl7/nix-darwin";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
    };

    # Other sources
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, flake-utils, deploy-rs
    , devshell, nixos-generators, ... }:
    let
      nixpkgsConfig = with inputs; {
        config = { allowUnfree = true; };
        overlays = [
          inputs.rust-overlay.overlays.default
        ];
      };
      darwinModules = { user, host }:
        with inputs; [
          # Main `nix-darwin` config
          (./. + "/hosts/${host}/configuration.nix")
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
        with inputs; [
          # Main `nixos` config
          (./. + "/hosts/${host}/configuration.nix")
          # `home-manager` module
          home-manager.nixosModules.home-manager
          {
            nixpkgs = nixpkgsConfig;
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
          moduels = darwinModules {
            user = "chetan";
            host = "markus";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
      };
      nixosConfigurations = {
        bill = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = nixosModules {
            host = "bill";
            user = "chetan";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
        goku = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = nixosModules {
            host = "goku";
            user = "chetan";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
      };
    };

}
