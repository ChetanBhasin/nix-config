{
  description = "Chetan Bhasin's Nix configuration";
  inputs = {
    # Package sets
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";

    # Environment/system management
    darwin = { url = "github:lnl7/nix-darwin"; };
    home-manager = { url = "github:nix-community/home-manager/release-23.05"; };

    # Other sources
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
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
        overlays = [ ];
      };
      darwinModules = { system, user, host }:
        let
          linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] system;
          pkgs = nixpkgs.legacyPackages."${system}";
          darwin-builder = nixpkgs.lib.nixosSystem {
            system = linuxSystem;
            modules = [
              "${nixpkgs}/nixos/modules/profiles/macos-builder.nix"
              {
                virtualisation.host.pkgs = pkgs;
                system.nixos.revision = nixpkgs.lib.mkForce null;
              }
            ];
          };
        in with inputs; [
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
          {
            nix.distributedBuilds = true;
            nix.buildMachines = [{
              hostName = "ssh://builder@localhost";
              system = linuxSystem;
              maxJobs = 4;
              supportedFeatures = [ "kvm" "benchmark" "big-parallel" ];
            }];
            launchd.daemons.darwin-builder = {
              command =
                "${darwin-builder.config.system.build.macos-builder-installer}/bin/create-builder";
              serviceConfig = {
                KeepAlive = true;
                RunAtLoad = true;
                StandardOutPath = "/var/log/darwin-builder.log";
                StandardErrorPath = "/var/log/darwin-builder.log";
              };
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
            system = "aarch64-darwin";
            user = "chetan";
            host = "hugh";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
        markus = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = darwinModules {
            system = "aarch64-darwin";
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
