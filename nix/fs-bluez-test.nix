{ lib, stdenv, rustPlatform, cargo, rustc, jq, dbus, bluez, testers }:

# crates/fs-bluez against real bluetoothd in a NixOS VM. The VM has no
# controller, so hci_vhci provides one: btvirt (bluez's emulator, built here
# with --enable-testing since nixpkgs leaves it out) creates two virtual
# controllers on /dev/vhci, and the live test makes one find, pair with and
# forget the other. The fake-bus tests (a zbus-served org.bluez on a private
# dbus-daemon) run in the same VM.
let
  bluezWithBtvirt = bluez.overrideAttrs (old: {
    configureFlags = old.configureFlags ++ [ "--enable-testing" ];
    postInstall = (old.postInstall or "") + ''
      install -Dm755 emulator/btvirt $out/bin/btvirt
    '';
  });

  # The test binaries without running them: cargo's own JSON names them.
  tests = stdenv.mkDerivation {
    name = "fs-bluez-tests";

    src = lib.fileset.toSource {
      root = ../.;
      fileset = ../crates;
    };
    sourceRoot = "source/crates";

    cargoDeps = rustPlatform.importCargoLock { lockFile = ../crates/Cargo.lock; };

    nativeBuildInputs = [ rustPlatform.cargoSetupHook cargo rustc jq ];

    buildPhase = ''
      runHook preBuild
      cargo test --offline -p fs-bluez --no-run --message-format=json > build.json
      runHook postBuild
    '';

    installPhase = ''
      mkdir -p $out/bin
      jq -r 'select(.profile.test == true and .executable != null) | .executable' build.json | while read -r exe; do
        name=$(basename "$exe")
        cp "$exe" "$out/bin/''${name%-*}"
      done
    '';
  };
in
# The mac's linux-builder advertises kvm but not nixos-test (dev/linux-builder.sh
# machines_line), so the test derivation asks for kvm alone.
(testers.runNixOSTest {
  name = "fs-bluez";

  nodes.machine = { ... }: {
    hardware.bluetooth = {
      enable = true;
      package = bluezWithBtvirt;
    };
    boot.kernelModules = [ "hci_vhci" ];
    environment.systemPackages = [ tests bluezWithBtvirt ];
  };

  testScript = ''
    # bluetooth.service is conditional on /sys/class/bluetooth, which exists
    # once the bluetooth core module is loaded, and it was skipped at boot.
    machine.succeed("modprobe hci_vhci")
    machine.succeed("test -d /sys/class/bluetooth")
    machine.succeed("systemctl start bluetooth.service")
    machine.wait_for_unit("bluetooth.service")

    with subtest("fake org.bluez on a private bus"):
        machine.succeed("FS_BLUEZ_DBUS_DAEMON=${dbus}/bin/dbus-daemon fake_bluez --ignored --test-threads=1 2>&1")

    with subtest("bluetoothd with no controller"):
        machine.succeed("live --ignored --nocapture bluetoothd_without_a_controller 2>&1")

    with subtest("two virtual controllers"):
        machine.succeed("systemd-run --unit=btvirt btvirt -l2")
        machine.wait_until_succeeds("test -e /sys/class/bluetooth/hci1")
        machine.succeed("live --ignored --nocapture two_virtual_controllers 2>&1")

    with subtest("pure tests"):
        machine.succeed("fs_bluez 2>&1")
  '';
}).overrideTestDerivation (old: { requiredSystemFeatures = [ "kvm" ]; })
