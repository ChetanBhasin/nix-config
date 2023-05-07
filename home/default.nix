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
        clojure
        gnuplot
        graphviz

        # CLI Packages
        leiningen
        wapm-cli
        nodejs-18_x
        wasmer
        yarn
        cmake
        cachix
        starship
        tmux
        kubectl
        gawk
        gettext
        htop
        kubectx
        jq
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
        luajit
        terraform
        rustup
      ] ++ lib.optionals cfg.enableExtras [ wasm-pack podman ]
      ++ lib.optionals cfg.enableProf [
        tilt
        helmfile
        atlantis
        consul
        grpc
        nomad
        protobuf
        vault
        readline
      ] ++ lib.optionals pkgs.stdenv.isDarwin [
        darwin.apple_sdk.frameworks.Security
        darwin.apple_sdk.frameworks.CoreFoundation
        darwin.apple_sdk.frameworks.CoreServices
      ];

    home.stateVersion = "23.05";
  };
}
