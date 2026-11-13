{
  description = "Chetan Bhasin's Nix configuration.";
  inputs = {
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";
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
    devshell = {
      url = "github:numtide/devshell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    jj-starship = {
      url = "github:dmmulroy/jj-starship";
    };

    # Maki is not in nixpkgs. Fetch the personal fork through GitHub so the
    # locked input is portable across Darwin and Linux home-directory layouts.
    # Its own flake pins the Rust toolchain and the Cargo git deps, so do not
    # make it follow this configuration's nixpkgs.
    maki = {
      url = "github:ChetanBhasin/maki";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.modules
        (inputs.import-tree ./modules)
      ];
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
    };
}
