{ lib, rustPlatform, pkg-config, fontconfig }:

rustPlatform.buildRustPackage {
  pname = "formalshell-rs";
  version = "0.1.1";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoLock.lockFile = ../crates/Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ fontconfig ];

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
}
