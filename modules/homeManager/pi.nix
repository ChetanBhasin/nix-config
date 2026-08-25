# Package-only Pi Coding Agent Home Manager configuration.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cb.pi;
  bazelLsp = pkgs.callPackage ../../packages/bazel-lsp.nix { };
  piConfig = pkgs.callPackage ../../packages/pi-config.nix { };

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
  options.cb.pi = {
    enable = lib.mkEnableOption "Chetan's Pi Coding Agent configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pi-coding-agent;
      description = "Pi Coding Agent package to install";
    };

    enableLspTooling = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Expose the curated language-server toolchain to Pi";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to expose to Pi and its shell tools";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = cfg.package;
      extraPackages = [
        pkgs.nodejs
        pkgs.git
      ]
      ++ lib.optionals cfg.enableLspTooling lspPackages
      ++ cfg.extraPackages;
      settings = { };
      keybindings = { };
      models = { };
      context = "";
    };

    home.packages = [ piConfig ];

    # This deliberately bypasses Home Manager's `run` helper so dry-run
    # activation performs the same read-only verification as a real run.
    home.activation.piPreflight = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      ${piConfig}/bin/pi-config _activation-preflight
    '';
  };
}
