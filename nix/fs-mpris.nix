{ lib, rustPlatform, dbus }:

# Library crate: the check is its test run against a private dbus-daemon.
rustPlatform.buildRustPackage {
  pname = "fs-mpris-check";
  version = "0.1.1";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoLock.lockFile = ../crates/Cargo.lock;

  cargoBuildFlags = [ "--package" "fs-mpris" ];
  cargoTestFlags = [ "--package" "fs-mpris" ];

  nativeCheckInputs = [ dbus ];

  installPhase = "touch $out";
}
