{
  description = "Chetan Bhasin's Nix configuration";
  inputs = {
    # Package sets
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Environment/system management
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Other sources
    flake-utils = { url = "github:numtide/flake-utils"; };
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
    snm = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, flake-utils, devshell
    , snm, ... }:
    let
      nixpkgsConfig = with inputs; {
        config = { allowUnfree = true; };
        overlays = [ ];
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
          modules = darwinModules {
            user = "chetan";
            host = "markus";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
      };
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            config = { allowUnfree = true; };
            overlays = [ ];
          };
        };

        venus = {
          deployment = {
            targetHost = "venus";
            targetUser = "chetan";
            allowLocalDeployment = true;
            buildOnTarget = true;
          };
          imports = [ inputs.snm.nixosModule ];
        };

        defaults = { pkgs, name, ... }: {
          deployment = {
            keys."tailscale.auth" = {
              keyCommand = [ "sops" "--decrypt" "secrets/tailscale" ];
              destDir = "/run/keys";
            };
          };
          imports = [
            (./. + "/bootconfig/${name}.nix")
            (./. + "/hosts/${name}/configuration.nix")
            # `home-manager` module
            home-manager.nixosModules.home-manager
            {
              nixpkgs = nixpkgsConfig;
              # `home-manager` config
              users.users.chetan = {
                home = "/home/chetan";
                isNormalUser = true;
                group = "chetan";
                extraGroups = [ "wheel" ];
              };
              users.groups.chetan = { };
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.chetan = import (./. + "/hosts/venus/home.nix");
              };
            }
          ];
          networking.hostName = "${name}";
          users.users.root.openssh.authorizedKeys.keys = [
            # chetan's mac key
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8y+WOiiqxKGRQHGdtRGL2R4Ptqs7uEXX89WwvUQTc9A2zTFjGNcQvDCP6+qw6FQgDCaLdNozojfPQxo/VqMiWf1KXvBOPMONc+AUURhPxw8lD1FSc5AsLAw68BrxnFLbYrKmJT6qr3Ap/D6NGNlJUN3mR/e8Bj2wpKNSidmn9aDBxuGLkBmYJ8K8Wdalg47WwQ7wvzxCn4MFjM8CINyaI3p0mouZdCeCd/JcJgeLqN1JGuHCdgwzS9FgAWwQ0s/zb33icxS3qlHYLOch8YpD1wCceHJEv8dRQxwoEbdho9VwUzZGE8y2YPLxNLShSjUEPK5rLbfz4kUrWZCEX0LHhwyBKW0u8O7RArCKVDjJkiVEWoIrTmYx3CxppYnuyKPe85vUwqQzafN1EVvtfwQcJHBknG/9Fo5sU+juuTMIbFHNwFjBH4MzOnIRBAV2lGy4YsGZwE/+HVB9kFqZf3KrBeRSZsNMUxC0AXapOHKimHyUyHS/bJUH3onqPV1cD8/k= chetan@Chetans-Air"
          ];
          users.users.chetan.openssh.authorizedKeys.keys = [
            # chetan's mac key
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8y+WOiiqxKGRQHGdtRGL2R4Ptqs7uEXX89WwvUQTc9A2zTFjGNcQvDCP6+qw6FQgDCaLdNozojfPQxo/VqMiWf1KXvBOPMONc+AUURhPxw8lD1FSc5AsLAw68BrxnFLbYrKmJT6qr3Ap/D6NGNlJUN3mR/e8Bj2wpKNSidmn9aDBxuGLkBmYJ8K8Wdalg47WwQ7wvzxCn4MFjM8CINyaI3p0mouZdCeCd/JcJgeLqN1JGuHCdgwzS9FgAWwQ0s/zb33icxS3qlHYLOch8YpD1wCceHJEv8dRQxwoEbdho9VwUzZGE8y2YPLxNLShSjUEPK5rLbfz4kUrWZCEX0LHhwyBKW0u8O7RArCKVDjJkiVEWoIrTmYx3CxppYnuyKPe85vUwqQzafN1EVvtfwQcJHBknG/9Fo5sU+juuTMIbFHNwFjBH4MzOnIRBAV2lGy4YsGZwE/+HVB9kFqZf3KrBeRSZsNMUxC0AXapOHKimHyUyHS/bJUH3onqPV1cD8/k= chetan@Chetans-Air"
          ];
        };
      };
    };
}
