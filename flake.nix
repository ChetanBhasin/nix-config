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
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    jj-starship = {
      url = "github:dmmulroy/jj-starship";
    };

  };

  outputs =
    inputs@{
      nixpkgs,
      darwin,
      home-manager,
      determinate,
      ...
    }:
    let
      nixpkgsConfig = {
        config = {
          allowUnfree = true;
        };
        overlays = [
          (
            final: _prev:
            let
              system = final.stdenv.hostPlatform.system;
              packages = inputs.jj-starship.packages.${system};
            in
            {
              jj-starship = packages.jj-starship;
              jj-starship-no-git = packages.jj-starship-no-git;
            }
          )
          (_final: prev: {
            lazyjj = prev.lazyjj.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                mv "$out/bin/lazyjj" "$out/bin/lazyjj-unwrapped"

                cat > "$out/bin/lazyjj-jj" <<EOF
                #!/bin/sh
                exec ${prev.jujutsu}/bin/jj \
                  --config lazyjj.diff-format=git \
                  --config lazyjj.layout=horizontal \
                  --config lazyjj.layout-percent=30 \
                  --config 'lazyjj.highlight-color="#504945"' \
                  --config 'lazyjj.keybinds.log_tab.open-files=["enter", "o"]' \
                  "\$@"
                EOF

                cat > "$out/bin/lazyjj" <<EOF
                #!/bin/sh
                exec "$out/bin/lazyjj-unwrapped" --jj-bin "$out/bin/lazyjj-jj" "\$@"
                EOF

                chmod +x "$out/bin/lazyjj" "$out/bin/lazyjj-jj"
              '';
            });
          })
          (
            final: prev:
            let
              rapidfuzzOverride = pyFinal: pyPrev: {
                rapidfuzz = pyPrev.rapidfuzz.overridePythonAttrs (old: {
                  # RapidFuzz's C++ extension doesn't currently build on aarch64-darwin with
                  # this nixpkgs snapshot, so allow the pure-Python fallback on Darwin.
                  env =
                    (old.env or { })
                    // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
                      RAPIDFUZZ_BUILD_EXTENSION = 0;
                    };

                  doCheck = !prev.stdenv.hostPlatform.isDarwin;

                  # Work around RapidFuzz CMake configure failures on Darwin where
                  # `CMAKE_CXX_COMPILER_{AR,RANLIB}` are not auto-detected (CMake 4.x).
                  preBuild =
                    (old.preBuild or "")
                    + prev.lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
                      if [[ "''${CMAKE_ARGS:-}" != *"CMAKE_CXX_COMPILER_AR"* ]]; then
                        export CMAKE_ARGS="''${CMAKE_ARGS:-} -DCMAKE_CXX_COMPILER_AR=$AR -DCMAKE_CXX_COMPILER_RANLIB=$RANLIB"
                      fi
                    '';
                });

                pipx = pyPrev.pipx.overridePythonAttrs (old: {
                  # packaging 26 renders direct URL requirements in canonical PEP 508
                  # form ("name @ url"). pipx 1.8.0 still has tests expecting the
                  # older "name@ url" formatting.
                  disabledTests = (old.disabledTests or [ ]) ++ [
                    "test_fix_package_name"
                    "test_parse_specifier_for_metadata"
                  ];
                });
              };
            in
            {
              # Keep these fixes scoped to the Python 3.13 package set. Overriding
              # nixpkgs' global Python aliases changes the Darwin stdenv and Clang
              # derivations, preventing them from using the official binary cache.
              python313Packages = prev.python313Packages.overrideScope rapidfuzzOverride;
            }
          )
        ];
      };
      darwinModules = { user, host }: [
        # Main `nix-darwin` config
        (./. + "/hosts/${host}/configuration.nix")
        { nix.enable = false; }
        determinate.darwinModules.default
        {
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
                user
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
      nixosModules = { user, host }: [
        # Main `nixos` config
        (./. + "/hosts/${host}/configuration.nix")
        # `home-manager` module
        home-manager.nixosModules.home-manager
        (
          { pkgs, ... }:
          {
            nixpkgs = nixpkgsConfig;
            # `home-manager` config
            users.users.${user} = {
              home = "/home/${user}";
              isNormalUser = true;
              group = "${user}";
              extraGroups = [ "wheel" ];
              shell = pkgs.zsh;
            };
            users.groups.${user} = { };
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = import (./. + "/hosts/${host}/home.nix");
            };
          }
        )
      ];
    in
    {
      # Standalone Home Manager modules for use in other flakes
      # Usage: inputs.nix-config.homeManagerModules.neovim
      homeManagerModules = import ./modules/homeManager;

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

      nixosConfigurations = {
        boris = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = nixosModules {
            user = "chetan";
            host = "boris";
          };
          specialArgs = { inherit inputs nixpkgs; };
        };
      };
    };
}
