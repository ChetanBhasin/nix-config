# Opinionated Oh My Pi Home Manager configuration.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cb.omp;
  theme = import ../theme/gruvbox-night.nix;
  yaml = pkgs.formats.yaml { };
  json = pkgs.formats.json { };
  bazelLsp = pkgs.callPackage ../../packages/bazel-lsp.nix { };
  ompPackage = pkgs.callPackage ../../packages/omp.nix { };

  defaultSettings = {
    # macOS cannot always report terminal appearance through Zellij. Using the
    # same dark theme for both modes keeps OMP visually consistent everywhere.
    theme = {
      dark = theme.name;
      light = theme.name;
    };

    startup = {
      quiet = true;
      # The OMP binary is updated through this flake, not its own updater.
      checkUpdate = false;
    };

    symbolPreset = "nerd";
    statusLine = {
      preset = "compact";
      separator = "powerline-thin";
      sessionAccent = false;
      transparent = false;
    };

    shellPath = "${pkgs.zsh}/bin/zsh";

    # Keep external Slack writes behind an explicit user confirmation even
    # when OMP otherwise runs with its default yolo approval mode.
    tools.approval = {
      "mcp__slack_slack_slack_add_reaction" = "prompt";
      "mcp__slack_slack_slack_create_canvas" = "prompt";
      "mcp__slack_slack_slack_create_conversation" = "prompt";
      "mcp__slack_slack_slack_schedule_message" = "prompt";
      "mcp__slack_slack_slack_send_message" = "prompt";
      "mcp__slack_slack_slack_send_message_draft" = "prompt";
      "mcp__slack_slack_slack_update_canvas" = "prompt";
    };

    # Home Manager replaces this mutable file on activation, so persist the
    # completed onboarding state instead of reopening setup every time.
    dev.autoqaConsent = "denied";
    setupVersion = 2;
  };
  resolvedSettings = lib.recursiveUpdate defaultSettings cfg.settings;
  configFile = yaml.generate "omp-config.yml" resolvedSettings;

  lspConfig = {
    idleTimeoutMs = 600000;
    servers = {
      # Prefer the more capable Nix server when both happen to be installed.
      nil.disabled = true;

      bazel-lsp = {
        command = "${bazelLsp}/bin/bazel-lsp";
        args = [
          "--bazel"
          "${pkgs.bazelisk}/bin/bazelisk"
        ];
        fileTypes = [
          ".bzl"
          ".bazel"
          "BUILD"
          "BUILD.bazel"
        ];
        languageId = "starlark";
        rootMarkers = [
          "MODULE.bazel"
          "WORKSPACE.bazel"
          "WORKSPACE"
        ];
      };

      just-lsp = {
        command = "${pkgs.just-lsp}/bin/just-lsp";
        fileTypes = [
          "justfile"
          ".justfile"
        ];
        languageId = "just";
        rootMarkers = [
          "justfile"
          ".justfile"
        ];
      };

      taplo = {
        command = "${pkgs.taplo}/bin/taplo";
        args = [
          "lsp"
          "stdio"
        ];
        fileTypes = [ ".toml" ];
        languageId = "toml";
        rootMarkers = [
          "Cargo.toml"
          "pyproject.toml"
          "taplo.toml"
          ".taplo.toml"
        ];
      };
    };
  };

  lspPackages = with pkgs; [
    # Rust, Nix, Python, Go, Lua, TypeScript, and web formats
    rust-analyzer
    rustfmt
    nixd
    nixfmt
    basedpyright
    ruff
    gopls
    lua-language-server
    stylua
    typescript-language-server
    vscode-langservers-extracted

    # Shell, infrastructure, documentation, and repository formats
    bash-language-server
    yaml-language-server
    dockerfile-language-server
    terraform-ls
    marksman
    taplo
    just-lsp
    just

    # Bazel and Starlark
    bazelLsp
    bazelisk
    buildifier
  ];
in
{
  options.cb.omp = {
    enable = lib.mkEnableOption "Chetan's Oh My Pi coding-agent configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = ompPackage;
      description = "Oh My Pi package to install";
    };

    enableLspTooling = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the configured language servers and expose them to OMP";
    };

    settings = lib.mkOption {
      type = yaml.type;
      default = { };
      description = "Settings recursively merged over the opinionated OMP defaults";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to expose to OMP and its shell tools";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".omp/agent/themes/${theme.name}.json" = {
      source = json.generate "omp-${theme.name}.json" theme.omp;
      force = true;
    };

    home.file.".omp/agent/APPEND_SYSTEM.md" = {
      force = true;
      text = ''
        # Local working conventions

        - Prefer Jujutsu (`jj`) over Git whenever the repository supports it.
        - Inspect the working-copy state before editing and preserve unrelated user changes.
        - Do not commit, push, create bookmarks, or open or modify pull requests unless the user explicitly asks.
      '';
    };

    home.file.".omp/agent/lsp.json" = lib.mkIf cfg.enableLspTooling {
      source = json.generate "omp-lsp.json" lspConfig;
      force = true;
    };

    # OMP locks and rewrites this file when settings change at runtime. Copy a
    # writable file during activation instead of linking it into the Nix store.
    # Runtime changes remain usable until the next declarative activation.
    home.activation.ompConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/.omp/agent"
      run install -m 600 ${configFile} "$HOME/.omp/agent/config.yml"
    '';

    home.packages = [
      cfg.package
    ]
    ++ lib.optionals cfg.enableLspTooling lspPackages
    ++ cfg.extraPackages;
  };
}
