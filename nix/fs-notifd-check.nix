{ lib, rustPlatform, dbus, libnotify }:

rustPlatform.buildRustPackage {
  pname = "fs-notifd-check";
  version = "0.1.1";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoLock.lockFile = ../crates/Cargo.lock;

  cargoBuildFlags = [ "--package" "fs-notifd" ];
  cargoTestFlags = [ "--package" "fs-notifd" ];

  # The tests start their own private session bus and run the real
  # notify-send against it.
  nativeCheckInputs = [ dbus libnotify ];

  installPhase = "touch $out";
}
