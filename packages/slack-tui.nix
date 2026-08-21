{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.6.1";
  system = stdenvNoCC.hostPlatform.system;
  # Hashes come from checksums.txt published with the matching GitHub release.
  assets = {
    "aarch64-darwin" = {
      name = "slack-tui_${version}_darwin_arm64.tar.gz";
      hash = "sha256-tP/Uz+3FI523jBMCwEAJsdeexFDEjMJI3s4yWC6zgls=";
    };
    "x86_64-darwin" = {
      name = "slack-tui_${version}_darwin_amd64.tar.gz";
      hash = "sha256-z1Oa3+J4m2TD231SI4KAs5gpYjgCq5S6ums78V+0ub0=";
    };
    "aarch64-linux" = {
      name = "slack-tui_${version}_linux_arm64.tar.gz";
      hash = "sha256-XxwWGX6CxGWvgGEpKmJuXitmthkZQ8HphTM3Sqr4Afw=";
    };
    "x86_64-linux" = {
      name = "slack-tui_${version}_linux_amd64.tar.gz";
      hash = "sha256-J7FbfIqQ0pWu2SaqwqlQ+5Sd9rpRzVFlMQf7/aAo7VU=";
    };
  };
  asset = assets.${system} or (throw "slack-tui does not provide a release binary for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "slack-tui";
  inherit version;

  src = fetchurl {
    url = "https://github.com/kurenn/slack-tui/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  # GoReleaser puts the executable and accompanying files at the archive root.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 slack-tui "$out/bin/slack-tui"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/slack-tui" --version)" = "slack-tui ${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Keyboard-first Vim-modal Slack client for the terminal";
    homepage = "https://github.com/kurenn/slack-tui";
    changelog = "https://github.com/kurenn/slack-tui/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "slack-tui";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
