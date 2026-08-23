{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  symlinkJoin,
  writeShellScriptBin,
  rustc,
  cargo,
}:

let
  # rust-glancer locates standard-library sources strictly via
  #   `rustc --print sysroot` -> <sysroot>/lib/rustlib/src/rust/library
  # (crates/engine/workspace/src/sysroot.rs). nixpkgs' rustc sysroot ships no
  # rust-src, and rust-glancer has no RUST_SRC_PATH override, so overlay rust-src
  # onto the real toolchain sysroot and force rustc to report it via `--sysroot`.
  sysrootWithSrc = symlinkJoin {
    name = "rust-glancer-sysroot";
    paths = [ rustc.unwrapped ];
    postBuild = ''
      mkdir -p "$out/lib/rustlib/src/rust"
      ln -s ${rustPlatform.rustLibSrc} "$out/lib/rustlib/src/rust/library"
    '';
  };

  # rustc shim that always reports the rust-src-enabled sysroot. cargo (invoked by
  # rust-glancer for `cargo metadata`) inherits it through PATH as well.
  rustcWithSrc = writeShellScriptBin "rustc" ''
    exec ${rustc}/bin/rustc --sysroot ${sysrootWithSrc} "$@"
  '';
in
rustPlatform.buildRustPackage {
  pname = "rust-glancer";
  version = "0-unstable-2026-08-22";

  src = fetchFromGitHub {
    owner = "rust-glancer";
    repo = "rust-glancer";
    rev = "b63c61536cd6a58ec0281f208cfeab17615c4781";
    hash = "sha256-DaaeZ+WpfnPQQn3IcSBkAGJPW/qgksPWbrXs5yk3x70=";
  };

  cargoHash = "sha256-GA1AbHuAqs97oJ7HsKxua1+LSylwqL/uSErlxZmBebA=";

  nativeBuildInputs = [ makeWrapper ];

  # Build only the language-server binary; the workspace also carries codegen
  # tooling and heavy test fixtures that are irrelevant to editor use.
  cargoBuildFlags = [
    "--package"
    "rust-glancer"
  ];

  # The test suite needs a full toolchain, on-disk fixtures, and network access.
  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/rust-glancer \
      --prefix PATH : ${
        lib.makeBinPath [
          rustcWithSrc
          cargo
        ]
      }
  '';

  meta = {
    description = "Lightweight Rust LSP optimized for low memory usage";
    homepage = "https://github.com/rust-glancer/rust-glancer";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "rust-glancer";
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
