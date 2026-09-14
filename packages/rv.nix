{
  difftastic,
  fetchFromGitHub,
  lib,
  makeBinaryWrapper,
  rustPlatform,
  versionCheckHook,
}:

# Upstream ships a flake, but its derivation hardcodes version "1.0.0" while
# the workspace is well past that, and following it would pull a second nixpkgs
# into this lock. Build the tagged release here instead.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rv";
  version = "1.7.2";

  src = fetchFromGitHub {
    owner = "Firaenix";
    repo = "rv";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4OtJvSLhHzTZ/+7YaMvYTobnm2WCpnB3CTRddcYttzk=";
  };

  cargoHash = "sha256-enIVsYC2tP8h2iTJGI8qx6CS1Nem/9ICYnvDiExGvFE=";

  nativeBuildInputs = [ makeBinaryWrapper ];

  # rv finds difft on PATH and degrades to a line diff without it. A
  # nix-installed rv should not degrade for want of a wrapper.
  postInstall = ''
    wrapProgram "$out/bin/rv" --prefix PATH : ${lib.makeBinPath [ difftastic ]}
  '';

  # The suite spawns a jj workspace per test and takes minutes, as upstream's
  # own flake notes.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/rv";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Terminal code reviewer for Jujutsu stacks, with an agent-facing CLI";
    homepage = "https://github.com/Firaenix/rv";
    changelog = "https://github.com/Firaenix/rv/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "rv";
    platforms = lib.platforms.unix;
  };
})
