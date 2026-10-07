{ rustCommon, dbus, libnotify }:

rustCommon.craneLib.cargoTest (rustCommon.checkArgs // {
  pname = "fs-notifd-check";
  cargoExtraArgs = "--locked --package fs-notifd";
  # The tests start their own private session bus and run the real
  # notify-send against it.
  nativeCheckInputs = [ dbus libnotify ];
})
