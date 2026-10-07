{ rustCommon, jq, testers, dbus }:

# fs-upower's check: clippy -D warnings and the unit tests, then the daemon
# tests (tests/daemon.rs) inside a NixOS VM running the real upowerd and
# power-profiles-daemon. The VM has no battery, so those tests read the honest
# empty answers and switch profiles; battery values and change signals come
# from a fake UPower the test serves on a private session bus.
let
  testBinary = rustCommon.craneLib.mkCargoDerivation (rustCommon.checkArgs // {
    pname = "fs-upower-daemon-test";
    nativeBuildInputs = rustCommon.checkArgs.nativeBuildInputs ++ [ jq ];
    buildPhaseCargoCommand = ''
      cargo clippy --release -p fs-upower --all-targets -- -D warnings
      cargo test --release -p fs-upower --lib
      cargo test --release -p fs-upower --test daemon --no-run \
        --message-format=json > build.json
    '';
    installPhaseCommand = ''
      mkdir -p $out/bin
      exe=$(jq -r 'select(.executable != null and .target.name == "daemon") | .executable' build.json)
      cp "$exe" $out/bin/fs-upower-daemon-test
    '';
  });
in
(testers.runNixOSTest {
  name = "fs-upower";

  nodes.machine = {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    # Switching a profile asks polkit.
    security.polkit.enable = true;
    environment.systemPackages = [ dbus ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    out = machine.succeed(
        "dbus-run-session -- ${testBinary}/bin/fs-upower-daemon-test"
        " --ignored --test-threads=1 --nocapture 2>&1"
    )
    print(out)
  '';
}).overrideTestDerivation {
  # The mac's linux-builder advertises kvm but not nixos-test.
  requiredSystemFeatures = [ "kvm" ];
}
