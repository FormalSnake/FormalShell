{ rustCommon, dbus }:

rustCommon.craneLib.cargoTest (rustCommon.checkArgs // {
  pname = "fs-tray";
  cargoExtraArgs = "--locked --package fs-tray";
  # The integration tests start their own session bus.
  nativeCheckInputs = [ dbus ];
})
