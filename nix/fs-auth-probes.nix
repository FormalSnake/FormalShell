{ rustCommon }:

# Clippy, the crate's unit tests and the two probe binaries the fs-auth VM
# test drives.
rustCommon.craneLib.mkCargoDerivation (rustCommon.checkArgs // {
  pname = "fs-auth-probes";
  buildPhaseCargoCommand = ''
    cargo clippy --release -p fs-auth --all-targets -- -D warnings
    cargo test --release -p fs-auth
    cargo build --release -p fs-auth --examples
  '';
  installPhaseCommand = ''
    install -Dm755 target/release/examples/pam_probe $out/bin/fs-auth-pam-probe
    install -Dm755 target/release/examples/polkit_probe $out/bin/fs-auth-polkit-probe
  '';
})
