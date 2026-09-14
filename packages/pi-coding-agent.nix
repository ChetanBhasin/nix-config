{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  makeBinaryWrapper,
  ripgrep,
  fd,
  stdenvNoCC,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:

# Keep the recipe with the pinned source: nixpkgs' Pi package can move to a
# different workspace layout independently of this version.
buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  version = "0.84.4";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7z8OXao1PzmBEepDkIqVqyfQBPHulBlKcGymDYsnMvc=";
  };
  modelData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
    hash = "sha512-AClAZxf5+c4RRu44NJPS6wyQy+Nmq+Mzyyrdvm4ZVMNuixelO02RZX4G4Aq1F145Yzp43wnM5S+hLlSI7ypfVw==";
  };
  npmDepsHash = "sha256-35GC3Q4Jf4URvqoEYHeM63x49tTmrth62//PvKm4I7Q=";
  npmWorkspace = "packages/coding-agent";

  # Skip native rebuilds for development and example workspaces.
  npmRebuildFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [ makeBinaryWrapper ];

  # The upstream model-data generator requires network access. Hydrate the
  # matching published pi-ai data exactly as the nixpkgs derivation does.
  preConfigure = ''
    mkdir -p packages/ai/src/providers/data
    tar --extract --gzip --file=${finalAttrs.modelData} \
      --directory=packages/ai/src/providers/data \
      --strip-components=4 \
      package/dist/providers/data
  '';

  # The pinned release defines the workspace order and copies model data and
  # other runtime assets itself, without running network-backed generators.
  buildPhase = ''
    runHook preBuild
    npm run build:offline
    runHook postBuild
  '';

  dontNpmPrune = true;
  preInstall = ''
    npm prune --omit=dev --no-save
  '';

  # npm's workspace links point into the build tree. Install the runtime SDKs
  # as real directories so Pi extensions and pi-web can import them as well.
  postInstall = ''
    local nm="$out/lib/node_modules/pi-monorepo/node_modules"
    for ws in @earendil-works/pi-ai:packages/ai \
              @earendil-works/pi-agent-core:packages/agent \
              @earendil-works/pi-client:packages/client \
              @earendil-works/pi-protocol:packages/protocol \
              @earendil-works/pi-telemetry:packages/telemetry \
              @earendil-works/pi-tui:packages/tui; do
      IFS=: read -r pkg src <<< "$ws"
      rm "$nm/$pkg"
      cp -r "$src" "$nm/$pkg"
    done

    find "$nm" -type l -lname '*/packages/*' -delete
    find "$nm/.bin" -xtype l -delete
  ''
  + lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    # Avoid auditing foreign Linux ELF binaries on Darwin.
    rm -rf \
      "$nm/@anthropic-ai/sandbox-runtime/dist/vendor/seccomp" \
      "$nm/@anthropic-ai/sandbox-runtime/vendor/seccomp"
  '';

  postFixup = ''
    wrapProgram $out/bin/pi --prefix PATH : ${
      lib.makeBinPath [
        ripgrep
        fd
      ]
    } \
      --set-default PI_SKIP_VERSION_CHECK 1 \
      --set-default PI_TELEMETRY 0
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgram = "${placeholder "out"}/bin/pi";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://pi.dev/";
    changelog = "https://github.com/earendil-works/pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
})
