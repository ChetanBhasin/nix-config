{ config, pkgs, lib, ... }:
with lib;
let
  python-debug = pkgs.python3.withPackages (p: with p; [ debugpy ]);
  nvchad = pkgs.fetchFromGitHub {
    owner = "NvChad";
    repo = "NvChad";
    rev = "main";
    sha256 = "sha256-B7KX+o1wNGhq7cqUb6WWaocrk1/h81jl8HLI9JDlME0=";
  };
in {
  config = {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      extraPackages = with pkgs;
        [
          lua
          ctags
          stylua
          ripgrep
          nerdfonts
          (rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
            targets = [ "wasm32-unknown-unknown" ];
          })
        ] ++ lib.optionals pkgs.stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
          (rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
            targets = [ "aarch64-apple-darwin" "wasm32-unknown-unknown" ];
          })
        ];
    };

    xdg.configFile."nvim".source = nvchad;
    xdg.configFile."nvim".recursive = true;
  };
}
