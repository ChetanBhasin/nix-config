{ config, pkgs, lib, ... }:
with lib;
let cfg = config.home-config-manager;
in {
  options.home-config-manager = {
    includeFonts = lib.mkEnableOption "fonts";
    isDarwin = lib.mkEnableOption "include darwin configuration";
    enableExtras = lib.mkEnableOption "enable extra packages";
    enableProf = lib.mkEnableOption "enable professional packages";
  };

  imports = [ ./defaultPrograms ./vscode ./zsh ./neovim ./tmux ./darwin ];

  config = {

    home.packages = with pkgs;
      [
        #System packages
        # Make touchID work from inside tmux
        pam-reattach

        # Library packages
        openssl
        clang
        libcxxabi
        lld
        zsh-completions
        rdkafka

        # CLI Packages
        cmake
        cachix
        starship
        tmux
        kubectl
        gawk
        kubectx
        jq
        direnv
        git-ignore
        tree
        bat
        nixfmt
        htop
        exa
        fd
        gnupg
        virtualenv
        wget
        pkgconfig
        git-lfs
        curl
        fzf
        python3Full
        podman
        nixfmt
        protobuf
        zlib
        sccache
        libiconv
        direnv
      ] ++ lib.optionals cfg.enableExtras [ wasm-pack podman ]
      ++ lib.optionals cfg.enableProf [ tilt helmfile ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        darwin.apple_sdk.frameworks.Security
        darwin.apple_sdk.frameworks.CoreFoundation
        darwin.apple_sdk.frameworks.CoreServices
        (rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ "aarch64-apple-darwin" "wasm32-unknown-unknown" ];
        })
      ];

    home.stateVersion = "23.05";
  };
}
