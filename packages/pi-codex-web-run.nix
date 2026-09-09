{
  autoPatchelfHook,
  fetchurl,
  glibc,
  lib,
  openssl,
  stdenv,
  stdenvNoCC,
}:

let
  version = "3.0.23";
  system = stdenvNoCC.hostPlatform.system;
  binaries = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-linux" = "linux-x64";
  };
  binary = binaries.${system} or (throw "pi-codex-web-run does not provide web_run for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "pi-codex-web-run";
  inherit version;

  # Keep this in lockstep with the exact npm package declaration in
  # home/pi/config/settings.json. The npm release is the source of the native
  # helper; only the selected helper is copied into the Nix store.
  src = fetchurl {
    url = "https://registry.npmjs.org/@howaboua/pi-codex-conversion/-/pi-codex-conversion-${version}.tgz";
    hash = "sha256-qWoZznxbQvwgfDZz27RYdnT+LeHPHbDJScgUbjNPCWY=";
  };

  sourceRoot = "package";
  dontBuild = true;

  # The upstream Linux helpers are dynamically linked ELF binaries. Keep every
  # needed runtime library explicit instead of relying on nix-ld or the mutable
  # npm realization. Darwin's selected Mach-O helper is copied unchanged.
  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    (lib.getLib openssl)
    (lib.getLib stdenv.cc.cc)
    (lib.getLib glibc)
  ];

  installPhase = ''
    runHook preInstall
    test -x "src/tools/web-run/bin/${binary}/web_run"
    install -Dm755 "src/tools/web-run/bin/${binary}/web_run" "$out/bin/web_run"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x "$out/bin/web_run"

    # This helper has no help subcommand. Invoking it without JSON must reach
    # its local argument validation; it neither needs network access nor auth.
    set +e
    "$out/bin/web_run" </dev/null >"$TMPDIR/web_run.stdout" 2>"$TMPDIR/web_run.stderr"
    status=$?
    set -e
    if [ "$status" -eq 126 ] || [ "$status" -eq 127 ]; then
      echo "web_run failed to spawn (native loader or executable failure)" >&2
      cat "$TMPDIR/web_run.stderr" >&2
      exit "$status"
    fi
    grep -F "web_run requires JSON arguments" "$TMPDIR/web_run.stderr" >/dev/null
    runHook postInstallCheck
  '';

  passthru = {
    codexConversionVersion = version;
    binaryDirectory = binary;
  };

  meta = {
    description = "Nix-owned web_run helper from pi-codex-conversion";
    homepage = "https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion";
    license = lib.licenses.mit;
    mainProgram = "web_run";
    platforms = builtins.attrNames binaries;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
