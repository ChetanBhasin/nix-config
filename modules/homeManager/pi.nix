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
  agentBrowser = pkgs.callPackage ../../packages/agent-browser.nix { };
  browserPackage = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.google-chrome else pkgs.chromium;
  browserExecutable = lib.getExe browserPackage;
  piPackage = pkgs.callPackage ../../packages/pi-coding-agent.nix { };
  piWebPackage = pkgs.callPackage ../../packages/pi-web.nix { piPackage = piPackage; };
  piConfig = pkgs.callPackage ../../packages/pi-config.nix { };

  piWithPolicy = pkgs.symlinkJoin {
    name = "pi-coding-agent-policy-${lib.getVersion cfg.package}";
    paths = [ cfg.package ];
    postBuild = ''
      rm "$out/bin/pi"
      cat > "$out/bin/pi" <<'EOF'
      #!${pkgs.runtimeShell}
      export AGENT_BROWSER_EXECUTABLE_PATH=${lib.escapeShellArg browserExecutable}
      export PI_LENS_DISABLE_LSP_INSTALL=1
      export PI_LENS_DISABLE_TOOL_INSTALL=1
      export PI_LENS_NO_CONTEXT_INJECTION=1
      export PI_LENS_CONFIG_PATH=${
        lib.escapeShellArg (config.home.homeDirectory + "/.pi/agent/extensions/config/lens-global.json")
      }
      export PI_AGENT_BROWSER_CONFIG=${
        lib.escapeShellArg (config.home.homeDirectory + "/.pi/agent/extensions/config/browser.json")
      }
      export PI_SUBAGENT_TASK_DELIVERY=file
      export PI_SUBAGENT_PI_BINARY=@piPolicyPackage@/bin/pi

      # Lens project configuration may re-enable mutation hooks. Its one-way
      # CLI switches keep Hashline authoritative once Lens is installed. A
      # freshly activated Pi has no mutable npm tree yet, so passing extension
      # flags before Lens can register them makes the core parser reject them.
      # Package-management subcommands always receive their original argv.
      case "''${1-}" in
        install|remove|uninstall|update|list|config|auth)
          exec ${lib.getExe cfg.package} "$@"
          ;;
        *)
          pi_agent_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
          if [ -e "$pi_agent_dir/npm/node_modules/pi-lens/dist/index.js" ]; then
            set -- \
              --no-tests \
              --no-opengrep \
              --no-read-guard \
              --no-autoformat \
              --no-autofix \
              --no-lens-context \
              --lens-compact-tool-line \
              "$@"
          fi
          exec ${lib.getExe cfg.package} "$@"
          ;;
      esac
      EOF
      substituteInPlace "$out/bin/pi" --replace-fail @piPolicyPackage@ "$out"
      chmod +x "$out/bin/pi"
    '';
    meta = cfg.package.meta // {
      mainProgram = "pi";
    };
    passthru.trackBPolicy = {
      lensInstallsDisabled = true;
      lensContextInjectionDisabled = true;
      lensMutationHooksDisabled = true;
      browserConfigIsExplicit = true;
      browserExecutableIsNixOwned = true;
      subagentTasksUseFiles = true;
    };
  };

  piWebWithNixServices = pkgs.symlinkJoin {
    name = "pi-web-nix-managed-${lib.getVersion cfg.webPackage}";
    paths = [ cfg.webPackage ];
    postBuild = ''
      rm "$out/bin/pi-web"
      cat > "$out/bin/pi-web" <<'EOF'
      #!${pkgs.runtimeShell}
      export PI_WEB_CONFIG=${
        lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web/config.json")
      }
      case "''${1-help}" in
        install)
          echo "PI WEB services are already managed by Home Manager; checking their declarative installation."
          exec ${cfg.webPackage}/bin/pi-web status
          ;;
        uninstall)
          echo "PI WEB services are Nix-managed. Set cb.pi.enableWeb = false and apply the configuration to uninstall them." >&2
          exit 2
          ;;
        update)
          echo "PI WEB updates are pinned in packages/pi-web.nix and applied through Nix." >&2
          exit 2
          ;;
        *)
          exec ${cfg.webPackage}/bin/pi-web "$@"
          ;;
      esac
      EOF
      chmod +x "$out/bin/pi-web"
    '';
    meta = cfg.webPackage.meta // {
      mainProgram = "pi-web";
    };
  };

  piRuntimePackages = [
    pkgs.nodejs
    pkgs.git
    agentBrowser
    pkgs.ast-grep
    browserPackage
  ]
  ++ lib.optionals cfg.enableLspTooling lspPackages
  ++ cfg.extraPackages;

  servicePath =
    lib.makeBinPath ([ piWithPolicy ] ++ piRuntimePackages)
    + lib.optionalString (pkgs.stdenv.hostPlatform.isDarwin) ":${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  serviceEnvironment = {
    AGENT_BROWSER_EXECUTABLE_PATH = browserExecutable;
    PATH = servicePath;
    PI_CODING_AGENT_DIR = config.home.homeDirectory + "/.pi/agent";
    PI_LENS_DISABLE_LSP_INSTALL = "1";
    PI_LENS_DISABLE_TOOL_INSTALL = "1";
    PI_LENS_NO_CONTEXT_INJECTION = "1";
    PI_LENS_CONFIG_PATH = config.home.homeDirectory + "/.pi/agent/extensions/config/lens-global.json";
    PI_AGENT_BROWSER_CONFIG = config.home.homeDirectory + "/.pi/agent/extensions/config/browser.json";
    PI_SUBAGENT_TASK_DELIVERY = "file";
    PI_SUBAGENT_PI_BINARY = lib.getExe piWithPolicy;
    PI_WEB_ASK_USER = "1";
    PI_WEB_CONFIG = config.home.homeDirectory + "/.config/pi-web/config.json";
    PI_WEB_ENVIRONMENT_FACTS = "1";
    PI_WEB_HOST = "127.0.0.1";
    PI_WEB_PORT = "8504";
    PI_WEB_SPAWN_SESSIONS = "0";
    PI_WEB_SUBSESSIONS = "0";
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    # Home Manager wraps store-backed LaunchAgent commands with wait4path.
    # PI WEB's patched doctor uses this explicit shell while inspecting that
    # wrapper rather than guessing from the caller's process environment.
    SHELL = "/bin/zsh";
  };

  piWebConfig = pkgs.writeText "pi-web-config.json" (
    builtins.toJSON {
      host = "127.0.0.1";
      port = 8504;
      spawnSessions = false;
      subsessions = false;
      askUser = true;
      environmentFacts = true;
    }
    + "\n"
  );

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
      default = piPackage;
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

    enableWeb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run the separately packaged PI WEB services";
    };

    webPackage = lib.mkOption {
      type = lib.types.package;
      default = piWebPackage;
      description = "Standalone PI WEB package, including its Pi SDK peers";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = piWithPolicy;
      extraPackages = piRuntimePackages;
      settings = { };
      keybindings = { };
      models = { };
      context = "";
    };

    home.packages = [
      piConfig
      agentBrowser
      pkgs.ast-grep
    ]
    ++ lib.optionals cfg.enableWeb [ piWebWithNixServices ];

    # Magic Context intentionally keeps its database, embeddings, and caches
    # local. Only its portable policy is projected through ~/.pi and exposed
    # at the package's shared CortexKit config path.
    home.file.".config/cortexkit/magic-context.jsonc" = {
      source = config.lib.file.mkOutOfStoreSymlink (
        config.home.homeDirectory + "/.pi/agent/extensions/config/magic-context.jsonc"
      );
      force = true;
    };

    home.activation.piWebDirectories = lib.mkIf cfg.enableWeb (
      if pkgs.stdenv.hostPlatform.isDarwin then
        lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
          run mkdir -p \
            ${lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web")} \
            ${lib.escapeShellArg (config.home.homeDirectory + "/.pi-web/logs")}
          if [[ ! -e ${
            lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web/config.json")
          } ]]; then
            run install -m 600 ${piWebConfig} \
              ${lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web/config.json")}
          fi
        ''
      else
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p \
            ${lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web")} \
            ${lib.escapeShellArg (config.home.homeDirectory + "/.pi-web/logs")}
          if [[ ! -e ${
            lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web/config.json")
          } ]]; then
            run install -m 600 ${piWebConfig} \
              ${lib.escapeShellArg (config.home.homeDirectory + "/.config/pi-web/config.json")}
          fi
        ''
    );

    launchd.agents.pi-web-sessiond = lib.mkIf (cfg.enableWeb && pkgs.stdenv.hostPlatform.isDarwin) {
      enable = true;
      config = {
        Label = "com.pi-web.sessiond";
        ProgramArguments = [ "${cfg.webPackage}/bin/pi-web-sessiond" ];
        EnvironmentVariables = serviceEnvironment;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Background";
        StandardOutPath = config.home.homeDirectory + "/.pi-web/logs/sessiond.log";
        StandardErrorPath = config.home.homeDirectory + "/.pi-web/logs/sessiond.log";
      };
    };

    launchd.agents.pi-web = lib.mkIf (cfg.enableWeb && pkgs.stdenv.hostPlatform.isDarwin) {
      enable = true;
      config = {
        Label = "com.pi-web.web";
        ProgramArguments = [ "${cfg.webPackage}/bin/pi-web-server" ];
        EnvironmentVariables = serviceEnvironment;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Background";
        StandardOutPath = config.home.homeDirectory + "/.pi-web/logs/web.log";
        StandardErrorPath = config.home.homeDirectory + "/.pi-web/logs/web.log";
      };
    };

    systemd.user.services.pi-web-sessiond =
      lib.mkIf (cfg.enableWeb && pkgs.stdenv.hostPlatform.isLinux)
        {
          Unit.Description = "PI WEB session daemon";
          Service = {
            ExecStart = "${cfg.webPackage}/bin/pi-web-sessiond";
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnvironment;
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "default.target" ];
        };

    systemd.user.services.pi-web = lib.mkIf (cfg.enableWeb && pkgs.stdenv.hostPlatform.isLinux) {
      Unit = {
        Description = "PI WEB server";
        After = [ "pi-web-sessiond.service" ];
        Wants = [ "pi-web-sessiond.service" ];
      };
      Service = {
        ExecStart = "${cfg.webPackage}/bin/pi-web-server";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnvironment;
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # This deliberately bypasses Home Manager's `run` helper so dry-run
    # activation performs the same read-only verification as a real run.
    home.activation.piPreflight = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      ${piConfig}/bin/pi-config _activation-preflight
    '';
  };
}
