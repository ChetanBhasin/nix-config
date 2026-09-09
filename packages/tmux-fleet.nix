{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "tmux-fleet";
  version = "0.1.0";

  src = ./tmux-fleet;
  cargoLock.lockFile = ./tmux-fleet/Cargo.lock;

  doCheck = true;

  meta = {
    description = "Unified local and SSH-backed tmux session picker";
    license = lib.licenses.mit;
    mainProgram = "tmux-fleet";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
