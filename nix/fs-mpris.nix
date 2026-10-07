{ rustCommon, dbus }:

# Library crate: the check is its test run against a private dbus-daemon.
rustCommon.craneLib.cargoTest (rustCommon.checkArgs // {
  pname = "fs-mpris-check";
  cargoExtraArgs = "--locked --package fs-mpris";
  nativeCheckInputs = [ dbus ];
})
