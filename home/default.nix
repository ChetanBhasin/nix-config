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
        # User-specific CLI tools
        hl-log-viewer
        goose-cli
        zed-editor
        bazel
        duckdb
        gh
        k9s

        # User shell and terminal utilities
        zsh-completions
        carapace
        tmux

        # Enhanced CLI Tools (user-specific)
        ripgrep # Better grep
        bat # Better cat
        eza # Better ls
        fd # Better find
        dust # Better du
        duf # Better df
        procs # Better ps
        fzf # Fuzzy finder

        # Development Utilities (user-specific)
        nixfmt-classic
        tokei # Code statistics
        hyperfine # Benchmarking
        sccache # Compilation cache

        # Python ecosystem (user-specific)
        poetry
        pipx
        virtualenv

        # File Format and Data Processing (user-specific)
        sops
        poppler-utils

        # Compression and Archive Tools (user-specific)
        zlib
        gzip

        # Version Control and Project Management (user-specific)
        jujutsu
        gitoxide

        # System Utilities (user-specific)
        cachix
        direnv

        # Other development tools (user-specific)
        gnuplot
        graphviz
        awscli2
        gawk
        gettext
        gnupg
        luajit
        starship
        wasm-pack
        readline

        # File format utilities (user-specific)
        sqlx-cli

      ] ++ lib.optionals cfg.enableExtras [
        # Extra packages when enableExtras is true
        elixir
        gleam
        rebar3
        erlang
        ngrok
        flyctl
        nodenv
      ] ++ lib.optionals pkgs.stdenv.isDarwin [
        # Darwin-specific packages that need special handling
        pam-reattach
        libiconv
        cctools # for ld-classic and ar
      ] ++ lib.optionals pkgs.stdenv.isLinux [
        # Linux-specific packages
        systemd
      ];

    home.stateVersion = "23.05";
  };
}
