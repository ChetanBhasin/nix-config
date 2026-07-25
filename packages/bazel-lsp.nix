{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.6.4";
  system = stdenvNoCC.hostPlatform.system;
  assets = {
    "x86_64-linux" = {
      target = "linux-amd64";
      hash = "sha256-Yqr/+wkAGGMud6r6kBeBgyEP3UIYRY3uJRNMd9qipZo=";
    };
    "aarch64-linux" = {
      target = "linux-arm64";
      hash = "sha256-xRDgsAYxXJ+Wh17W2HusxfBVgLM5jc6LGnRSfo4kJus=";
    };
    "x86_64-darwin" = {
      target = "osx-amd64";
      hash = "sha256-WpnMHQSNASfi4yBBTGxZVSYXfqni1UznukafKEsf068=";
    };
    "aarch64-darwin" = {
      target = "osx-arm64";
      hash = "sha256-2FKiACFaTTJ/c4JfWaT81LemwDwg6cw2JcbA9rxZ/8I=";
    };
  };
  asset = assets.${system} or (throw "bazel-lsp does not provide a release binary for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "bazel-lsp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/cameron-martin/bazel-lsp/releases/download/v${version}/bazel-lsp-${version}-${asset.target}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/bazel-lsp"
    runHook postInstall
  '';

  meta = {
    description = "Language server for Bazel";
    homepage = "https://github.com/cameron-martin/bazel-lsp";
    license = lib.licenses.asl20;
    mainProgram = "bazel-lsp";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
