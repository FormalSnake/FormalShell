{ lib, stdenv, rustPlatform, cargo, rustc, clippy, pam }:

# Clippy, the crate's unit tests and the two probe binaries the fs-auth VM
# test drives.
stdenv.mkDerivation {
  name = "fs-auth-probes";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoDeps = rustPlatform.importCargoLock { lockFile = ../crates/Cargo.lock; };

  nativeBuildInputs = [ rustPlatform.cargoSetupHook cargo rustc clippy ];
  buildInputs = [ pam ];

  buildPhase = ''
    runHook preBuild
    cargo clippy --offline -p fs-auth --all-targets -- -D warnings
    cargo test --offline -p fs-auth
    cargo build --offline --release -p fs-auth --examples
    runHook postBuild
  '';

  installPhase = ''
    install -Dm755 target/release/examples/pam_probe $out/bin/fs-auth-pam-probe
    install -Dm755 target/release/examples/polkit_probe $out/bin/fs-auth-polkit-probe
  '';
}
