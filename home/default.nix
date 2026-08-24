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

    programs.zen-browser = {
      enable = true;
      darwin.packageMode = "signed";
      profiles.default = {
        id = 0;
        isDefault = true;
        name = "Default";
        path = "default";
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      unwrappedPackage = pkgs.zen-browser;
    };

    home.file."${config.programs.zen-browser.configPath}/profiles.ini".force = true;

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

        # Cross-platform desktop applications
        firefox
        google-chrome
        lens
        obsidian
        slack

        # User shell and terminal utilities
        zsh-completions
        carapace
        jj-starship

        # Enhanced CLI Tools (user-specific)
        ripgrep # Better grep
        eza # Better ls
        fd # Better find
        dust # Better du
        duf # Better df
        procs # Better ps

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
        gzip

        # Version Control and Project Management (user-specific)
        jujutsu
        lazyjj
        gitoxide

        # System Utilities (user-specific)
        cachix
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
        wasm-pack

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
        discord
        proton-pass
        proton-vpn
        protonmail-desktop
        signal-desktop
        spotify
        telegram-desktop
      ]
      ++ lib.optionals (cfg.enableExtras && pkgs.stdenv.hostPlatform.isLinux) [
        figma-linux
        ticktick
        yubioath-flutter
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
        # Darwin-specific packages that need special handling
        pam-reattach
        libiconv
        vlc-bin
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        # Linux-specific packages
        systemd
        vlc
        openlogi
      ];

    home.stateVersion = "23.05";
  };
}
