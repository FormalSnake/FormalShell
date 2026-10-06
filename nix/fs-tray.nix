{ lib, rustPlatform, dbus }:

rustPlatform.buildRustPackage {
  pname = "fs-tray";
  version = "0.1.1";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoLock.lockFile = ../crates/Cargo.lock;

  cargoBuildFlags = [ "--package" "fs-tray" ];
  cargoTestFlags = [ "--package" "fs-tray" ];

  # The integration tests start their own session bus.
  nativeCheckInputs = [ dbus ];

  installPhase = "touch $out";
}
