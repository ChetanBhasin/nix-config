{
  home-manager,
  pkgs,
}:

let
  lib = pkgs.lib;
  piConfig = pkgs.callPackage ../../../packages/pi-config.nix { };

  mkHome =
    enable:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../../../modules/homeManager/pi.nix
        {
          home = {
            username = "pi-test";
            homeDirectory = "/home/pi-test";
            stateVersion = "23.05";
          };
          cb.pi.enable = enable;
        }
      ];
    };

  enabled = mkHome true;
  disabled = mkHome false;
  cfg = enabled.config;
  piProgram = cfg.programs.pi-coding-agent;
  configDirDefinitions = enabled.options.programs.pi-coding-agent.configDir.definitionsWithLocations;
  homeFileTargets = map (entry: entry.target) (builtins.attrValues cfg.home.file);
  piActivation = cfg.home.activation.piPreflight;
  preflightData = builtins.unsafeDiscardStringContext piActivation.data;
  piConfigPath = builtins.unsafeDiscardStringContext (toString piConfig);
  addedActivations = lib.subtractLists (builtins.attrNames disabled.config.home.activation) (
    builtins.attrNames cfg.home.activation
  );

  assertions = {
    cbPiExposesOnlySupportedOptions =
      builtins.attrNames enabled.options.cb.pi == [
        "enable"
        "enableLspTooling"
        "extraPackages"
        "package"
      ];
    noPiHomeFileTargets = builtins.all (target: !(lib.hasInfix ".pi" target)) homeFileTargets;
    noPiDirectoryEnvironmentOverrides =
      !(cfg.home.sessionVariables ? PI_CODING_AGENT_DIR)
      && !(cfg.home.sessionVariables ? PI_CODING_AGENT_SESSION_DIR);
    portableProgramValuesRemainEmpty =
      piProgram.settings == { }
      && piProgram.keybindings == { }
      && piProgram.models == { }
      && piProgram.context == "";
    configDirUsesUpstreamDefault =
      piProgram.configDir == "/home/pi-test/.pi/agent"
      && builtins.length configDirDefinitions == 1
      && lib.hasSuffix "/modules/programs/pi-coding-agent.nix" (builtins.head configDirDefinitions).file;
    lockedPiVersion = lib.getVersion piProgram.package == "0.84.2";
    completeCuratedTooling =
      map lib.getName piProgram.extraPackages == [
        "nodejs"
        "git"
        "rust-analyzer"
        "rustfmt"
        "nixd"
        "nixfmt"
        "basedpyright"
        "ruff"
        "gopls"
        "lua-language-server"
        "stylua"
        "typescript-language-server"
        "vscode-langservers-extracted"
        "bash-language-server"
        "yaml-language-server"
        "dockerfile-language-server"
        "terraform-ls"
        "marksman"
        "taplo"
        "just-lsp"
        "just"
        "bazel-lsp"
        "bazelisk"
        "bazel-buildtools"
      ];
    installsPiAndSyncCli =
      let
        packageNames = map lib.getName cfg.home.packages;
      in
      builtins.elem "pi-config" packageNames && builtins.elem "pi-coding-agent-wrapped" packageNames;
    onlyPiActivationIsPreflight = addedActivations == [ "piPreflight" ];
    preflightRunsBeforeWriteBoundary =
      piActivation.before == [ "writeBoundary" ] && piActivation.after == [ ];
    preflightIsDirectReadOnlyCommand =
      lib.hasInfix "${piConfigPath}/bin/pi-config _activation-preflight" preflightData
      && !(lib.hasInfix "run " preflightData);
  };

  failed = builtins.attrNames (lib.filterAttrs (_name: passed: !passed) assertions);
in
{
  inherit assertions;

  check =
    assert lib.assertMsg (failed == [ ]) (
      "Pi Home Manager module assertions failed: " + lib.concatStringsSep ", " failed
    );
    pkgs.runCommand "pi-home-manager-module-test" { } ''
      touch "$out"
    '';
}
