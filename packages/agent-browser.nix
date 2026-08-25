{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.34.0";
  system = stdenvNoCC.hostPlatform.system;
  binaries = {
    "aarch64-darwin" = "agent-browser-darwin-arm64";
    "x86_64-darwin" = "agent-browser-darwin-x64";
    "aarch64-linux" = "agent-browser-linux-arm64";
    "x86_64-linux" = "agent-browser-linux-x64";
  };
  binary = binaries.${system} or (throw "agent-browser does not provide a binary for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "agent-browser";
  inherit version;

  # The published npm tarball contains the release's native binaries. Select
  # one at install time instead of allowing agent-browser to download Chrome
  # or another executable into writable state.
  src = fetchurl {
    url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
    hash = "sha512-eR6Ey4I/DMs9zZ60b3ziV6pgLIgpxXWzggr3dfFbtskLmeXPJAgXCIIwVL4PihVYJqEUpvWgUKlZ2CIjY1u44g==";
  };

  sourceRoot = "package";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "bin/${binary}" "$out/bin/agent-browser"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$($out/bin/agent-browser --version)" = "agent-browser ${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Fast native browser automation CLI for AI agents";
    homepage = "https://agent-browser.dev/";
    changelog = "https://github.com/vercel-labs/agent-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "agent-browser";
    platforms = builtins.attrNames binaries;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
