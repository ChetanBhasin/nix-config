{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  nodejs,
  piPackage,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-web";
  version = "1.202608.2";

  src = fetchFromGitHub {
    owner = "jmfederico";
    repo = "pi-web";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ejqw/XZqSCky69nygt2Ro7MIkiPCzWtgvUi0HtafpdE=";
  };

  # Upstream sessiond otherwise auto-installs its optional Relay bundle from
  # inside the running package. In a Nix build that persists a generation-
  # specific /nix/store path in ~/.pi/agent/settings.json. Keep portable Pi
  # package policy explicit instead of mutating it at service startup.
  patches = [
    ./pi-web-disable-auto-install.patch
    ./pi-web-home-manager-launchd.patch
  ];

  # The published 1.202608.2 lockfile omitted integrity fields from six
  # nested Pi SDK entries. Restore the registry-provided SRI values before
  # Nix's dependency fetcher parses the lockfile.
  postPatch = ''
    patchLockEntry() {
      local name="$1"
      local integrity="$2"
      local entry="node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/$name"
      awk -v entry="$entry" -v integrity="$integrity" '
        index($0, "\"" entry "\": {") { inside = 1 }
        { print }
        inside && /"resolved":/ {
          print "      \"integrity\": \"" integrity "\"," 
          inside = 0
          patched = 1
        }
        END { if (!patched) exit 1 }
      ' package-lock.json > package-lock.json.patched
      mv package-lock.json.patched package-lock.json
    }

    patchLockEntry pi-agent-core 'sha512-evyzXYWCLQGmcaBYHlmSku02r8qoN4SGI60GZABo6iV+H+nqX+P9ud8fEZ4GmRq9mUSREvvfX+w9dA9ThF9C6w=='
    patchLockEntry pi-ai 'sha512-wMsAdJMxuNri08vLqTyYVI201DQQezGhPSTkzYsHdw5dYX3rCNwEmSvpaAwhi7ELKI/2tE/CEgSWg/6iRxSgdQ=='
    patchLockEntry pi-client 'sha512-/V5hGHE4Zq+jG0GtwIB9PyBUOGd6gBLZ7lkQYFKchKnxYHeH3rmWC5xw4kpnZKKBuBuFTdLVbU9vEjlAGMMb2A=='
    patchLockEntry pi-protocol 'sha512-Ox1pciyeSPGEEUcxvR0/dJcrY7C6hrEGA8y71rOsvSIUlXN1Cbp/be/eoL71OGDBk5O97TeQPfWN6Ju/2Ehjww=='
    patchLockEntry pi-telemetry 'sha512-180/xGJtsq7IoR3p9EKWjRd0e9M4DkxInhlo9xyD7prDC7Qrhqq+nhvwrW0lFjPfXcEI2FSHmGCSyvSJE9GsaQ=='
    patchLockEntry pi-tui 'sha512-udeXFbgEhJ6JiB0uguwNVNkDy2FENfmtQwPcY+/iJ8GWeq18wkal1tKqa5YyeH0IqtX1vG0cGh8zfSYzyzVuLA=='
  '';

  npmDepsHash = "sha256-yJY/JXpZj0nRGKNDRSGpLJiFprlz21uJC75lFdFV5zE=";
  npmDepsFetcherVersion = 2;
  npmBuildScript = "build";

  # node-pty is the one runtime dependency whose native install script is
  # required. Rebuild only it; do not broadly enable lifecycle scripts.
  npmRebuildFlags = [
    "node-pty"
    "--foreground-scripts"
  ];

  postInstall = ''
    local packageRoot="$out/lib/node_modules/@jmfederico/pi-web"
    local piRoot="${piPackage}/lib/node_modules/pi-monorepo"

    # npm prunes the SDK peers because upstream also lists them as development
    # dependencies. Supply the matching Nix-owned Pi 0.84.3 runtime instead of
    # duplicating or mutating Pi's writable package tree.
    rm -rf "$packageRoot/node_modules/@earendil-works"
    mkdir -p "$packageRoot/node_modules/@earendil-works"
    ln -s "$piRoot/node_modules/@earendil-works/pi-agent-core" \
      "$packageRoot/node_modules/@earendil-works/pi-agent-core"
    ln -s "$piRoot/node_modules/@earendil-works/pi-ai" \
      "$packageRoot/node_modules/@earendil-works/pi-ai"
    ln -s "$piRoot" \
      "$packageRoot/node_modules/@earendil-works/pi-coding-agent"

    # The npm tarball ships Darwin's helper without its executable bit when
    # lifecycle scripts are constrained. Linux's source rebuild produces the
    # same helper under build/Release.
    find "$packageRoot/node_modules/node-pty" -name spawn-helper -type f \
      -exec chmod +x {} +
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs ];
  installCheckPhase = ''
    runHook preInstallCheck
    packageRoot="$out/lib/node_modules/@jmfederico/pi-web"
    test "$($out/bin/pi-web --version)" = "${finalAttrs.version}"
    (
      cd "$packageRoot"
      node --input-type=module -e '
        import { readFileSync } from "node:fs";
        const expected = "0.84.3";
        for (const name of [
          "@earendil-works/pi-agent-core",
          "@earendil-works/pi-ai",
          "@earendil-works/pi-coding-agent",
        ]) {
          const value = JSON.parse(readFileSync(`node_modules/''${name}/package.json`, "utf8"));
          if (value.version !== expected) throw new Error(`''${name}: ''${value.version}`);
        }
        const known = await import("./dist/server/knownAutoInstallPiPackages.js");
        if (known.KNOWN_AUTO_INSTALLABLE_PI_PACKAGES.length !== 0) {
          throw new Error("PI WEB must not auto-install store-backed Pi packages");
        }
        await import("node-pty");
      '
    )
    runHook postInstallCheck
  '';

  meta = {
    description = "Web UI for persistent Pi Coding Agent sessions";
    homepage = "https://pi-web.dev/";
    changelog = "https://github.com/jmfederico/pi-web/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "pi-web";
    platforms = lib.platforms.unix;
  };
})
