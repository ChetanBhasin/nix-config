{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.home-config-manager;
  slackOfficialCli = pkgs.callPackage ../packages/slack-official-cli.nix { };
  slackTui = pkgs.callPackage ../packages/slack-tui.nix { };
in
{
  options.home-config-manager = {
    includeFonts = lib.mkEnableOption "fonts";
    isDarwin = lib.mkEnableOption "include darwin configuration";
    enableExtras = lib.mkEnableOption "enable extra packages";
    enableProf = lib.mkEnableOption "enable professional packages";
    enableHyprland = lib.mkEnableOption "Hyprland desktop session";
  };

  imports = [
    ./defaultPrograms
    ./vscode
    ./zsh
    ./neovim
    ./helix
    ./tmux
    ./zellij
    ./omp
    ./darwin
    ./hyprland
  ];

  config = {
    fonts.fontconfig = lib.mkIf cfg.includeFonts { enable = true; };

    home.packages =
      with pkgs;
      [
        # User-specific CLI tools
        hl-log-viewer
        bazelisk
        duckdb
        gh
        k9s
        bitwarden-cli
        slackOfficialCli
        slackTui

        # User shell and terminal utilities
        zsh-completions
        carapace
        tmux
        jj-starship

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
        nixfmt
        tokei # Code statistics
        hyperfine # Benchmarking
        sccache # Compilation cache
        samply # Sampling profiler

        # Python ecosystem (user-specific)
        poetry
        python313Packages.pipx
        python313Packages.virtualenv

        # File Format and Data Processing (user-specific)
        sops
        poppler-utils

        # Compression and Archive Tools (user-specific)
        zlib
        gzip

        # Version Control and Project Management (user-specific)
        jujutsu
        lazyjj
        gitoxide

        # System Utilities (user-specific)
        cachix
        direnv
        pv
        tldr
        watch

        # Other development tools (user-specific)
        gnuplot
        graphviz
        awscli2
        kubelogin-oidc # Provides the kubectl oidc-login plugin
        openbao
        gawk
        gettext
        gnupg
        luajit
        starship
        wasm-pack
        readline

        # File format utilities (user-specific)
        sqlx-cli

      ]
      ++ lib.optionals cfg.includeFonts [
        nerd-fonts.jetbrains-mono
        nerd-fonts.symbols-only
      ]
      ++ lib.optionals cfg.enableExtras [
        # Extra packages when enableExtras is true
        beamPackages.elixir
        beamPackages.rebar3
        beamPackages.erlang
        ngrok
        flyctl
        nodenv
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        # Darwin-specific packages that need special handling
        pam-reattach
        libiconv
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        # Linux-specific packages
        systemd
      ];

    home.stateVersion = "23.05";
  };
}
