{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "tmux-fleet";
  version = "0.1.0";

  src = ./tmux-fleet;
  cargoLock.lockFile = ./tmux-fleet/Cargo.lock;

  doCheck = true;

  meta = {
    description = "On-demand local tmux and SSH target session picker";
    license = lib.licenses.mit;
    mainProgram = "tmux-fleet";
    platforms = lib.platforms.unix;
  };
}
