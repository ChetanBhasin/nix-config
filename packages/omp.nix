{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "17.4.0";
  system = stdenvNoCC.hostPlatform.system;
  # Hashes come from the checksums published with the matching GitHub release.
  assets = {
    "aarch64-darwin" = {
      name = "omp-darwin-arm64";
      hash = "sha256-hhrD16dkmdvDbm7IdptYthqWLarCtHdc5UVHTZAw5ro=";
    };
    "x86_64-darwin" = {
      name = "omp-darwin-x64";
      hash = "sha256-Hv02lUMN/d2CTkMfm5aL3hUaGIDqnZtYcONjHVjU2Sc=";
    };
    "aarch64-linux" = {
      # Prefer the self-contained musl release on NixOS.
      name = "omp-linux-musl-arm64";
      hash = "sha256-wRdXoHUjOk5prHTUTBGBUpj5/nmY+DQEgK2u7WftnTM=";
    };
    "x86_64-linux" = {
      # Prefer the self-contained musl release on NixOS.
      name = "omp-linux-musl-x64";
      hash = "sha256-0dTqnU5ToXTS6xroEZ5XSbhN3EwHa/WZEGy/mHuI7OA=";
    };
  };
  asset = assets.${system} or (throw "Oh My Pi does not provide a release binary for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "omp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ompCheckData="$TMPDIR/omp-check-data"
    mkdir -p "$ompCheckData/omp"
    XDG_DATA_HOME="$ompCheckData" "$out/bin/omp" --smoke-test | grep -q "smoke-test: ok"
    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal coding agent with LSP, browser, subagents, and Jujutsu support";
    homepage = "https://github.com/can1357/oh-my-pi";
    changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
