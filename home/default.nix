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
        libcxx
        lld
        zsh-completions
        rdkafka
        clojure
        gnuplot
        graphviz

        # CLI Packages
        sops
        sqlx-cli
        leiningen
        wasmer
        yq
        cmake
        cachix
        tmux
        kubectl
        gawk
        gettext
        htop
        kubectx
        jq
        pipx
        gitoxide
        git-ignore
        tree
        bat
        htop
        eza
        fd
        gnupg
        virtualenv
        vault
        wget
        pkg-config
        git-lfs
        curl
        fzf
        python3Full
        nixfmt-classic
        protobuf
        zlib
        sccache
        libiconv
        direnv
        luajit
        terraform
        starship
        rustup
      ] ++ lib.optionals cfg.enableExtras [
        wasm-pack
        colmena
        elixir
        gleam
        rebar3
        erlang
        ngrok
        qemu
      ] ++ lib.optionals cfg.enableProf [
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
        darwin.apple_sdk.frameworks.SystemConfiguration
      ];

    home.stateVersion = "23.05";
  };
}
