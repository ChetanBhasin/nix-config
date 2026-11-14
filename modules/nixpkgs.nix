{ inputs, ... }:
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
      (final: _prev: {
        rust-glancer = final.callPackage ../packages/rust-glancer.nix { };
      })
      (_final: prev: {
        tmux = prev.tmux.overrideAttrs (old: {
          configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-jemalloc" ];
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
  shared = {
    nixpkgs = nixpkgsConfig;
  };
in
{
  flake.modules.darwin.nixpkgs = shared;
  flake.modules.nixos.nixpkgs = shared;
}
