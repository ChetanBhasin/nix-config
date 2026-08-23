{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "4.6.0";
  system = stdenvNoCC.hostPlatform.system;
  # Hashes are the SHA-256 digests published on the matching GitHub release assets.
  assets = {
    "aarch64-darwin" = {
      name = "slack_cli_${version}_macOS_arm64.tar.gz";
      hash = "sha256-wVhq1WJaMdgCq7MapLAjvRL+PHlCIarxf2gUqqMhp5I=";
    };
    "x86_64-darwin" = {
      name = "slack_cli_${version}_macOS_amd64.tar.gz";
      hash = "sha256-BXNi8+HidTpBD0horoMvfnFWZaRq4M3Mw8K3iy+u998=";
    };
    "aarch64-linux" = {
      name = "slack_cli_${version}_linux_arm64.tar.gz";
      hash = "sha256-kPVCMqpc9E+gzX9DQL/dhUKgrnxoJahNqmV4RKVPUlU=";
    };
    "x86_64-linux" = {
      name = "slack_cli_${version}_linux_amd64.tar.gz";
      hash = "sha256-KGPnchrzRsrvcr59w74qUg23IH3gikQNBApuwTeLrso=";
    };
  };
  asset = assets.${system} or (throw "slack-official-cli does not support ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "slack-official-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/slackapi/slack-cli/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/slack "$out/bin/slack-cli"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/slack-cli" --version --skip-update --no-color)" = "Using slack-cli v${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Official CLI for calling arbitrary Slack Web API methods and developing Slack apps";
    homepage = "https://docs.slack.dev/tools/slack-cli/";
    changelog = "https://github.com/slackapi/slack-cli/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "slack-cli";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
