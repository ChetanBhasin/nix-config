{ config, pkgs, lib, ... }:
with lib;
let cfg = config.home-config-manager;
in
{
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

        # Library packages
        openssl
        clang
        libcxx
        lld
        zsh-completions
        nushell
        carapace
        rdkafka
        gnuplot
        graphviz
        # CLI Packages
        poetry
        sops
        awscli2
        jujutsu
        sqlx-cli
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
        deno
        pipx
        gitoxide
        tree
        bat
        htop
        eza
        fd
        gnupg
        virtualenv
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
        helmfile
        kubernetes-helm
      ] ++ lib.optionals cfg.enableExtras [
        wasm-pack
        colmena
        elixir
        gleam
        rebar3
        erlang
        ngrok
        argocd
      ] ++ lib.optionals cfg.enableProf [
        tilt
        grpc
        protobuf
        vault
        readline
      ] ++ lib.optionals pkgs.stdenv.isDarwin [
        darwin.apple_sdk.frameworks.Security
        darwin.apple_sdk.frameworks.CoreFoundation
        darwin.apple_sdk.frameworks.CoreServices
        darwin.apple_sdk.frameworks.SystemConfiguration
        pam-reattach
      ];

    home.stateVersion = "23.05";
  };
}
