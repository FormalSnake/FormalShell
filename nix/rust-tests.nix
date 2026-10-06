{ lib, stdenv, rustPlatform, cargo, rustc }:

# The pure crates' tests, which nix/formalshell-rs.nix leaves out: some read
# files under shell/ and tests/ relative to the repo root, so the source keeps
# the repo layout and cargo runs from crates/.
stdenv.mkDerivation {
  name = "formalshell-rs-tests";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [ ../crates ../shell ../tests/fixtures ];
  };
  sourceRoot = "source/crates";

  cargoDeps = rustPlatform.importCargoLock { lockFile = ../crates/Cargo.lock; };

  nativeBuildInputs = [ rustPlatform.cargoSetupHook cargo rustc ];

  buildPhase = ''
    runHook preBuild
    cargo test --offline --workspace --exclude formalshell-rs
    runHook postBuild
  '';

  installPhase = "touch $out";
}
