{ lib, stdenv, pkgs, crane, rustPlatform, pkg-config, fontconfig, libxkbcommon, pipewire, pam, clippy }:

# The workspace's registry dependencies, built once. Every Rust derivation
# (the runtime package, rust-tests and the fs-* checks) takes `cargoArtifacts`
# and `commonArgs` from here, so they must keep building in the release
# profile: crane's artifacts are profile specific, and a dev-profile cargo
# would recompile everything.
let
  craneLib = crane.mkLib pkgs;  linux = stdenv.hostPlatform.isLinux;

  # The dependency build only reads manifests and the lock file (crane swaps
  # every source for a stub), so unrelated edits never invalidate it.
  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  commonArgs = {
    nativeBuildInputs = lib.optionals linux [ pkg-config rustPlatform.bindgenHook ];
    buildInputs = lib.optionals linux [ fontconfig libxkbcommon pipewire pam ];
  };

  # crane's own vendoring makes one derivation per crate (hundreds of remote
  # builds on a cold store); the fixed-output fetches below substitute.
  cargoVendorDir = rustPlatform.importCargoLock { lockFile = ../crates/Cargo.lock; };

  cargoArtifacts = craneLib.buildDepsOnly (commonArgs // {
    inherit src cargoVendorDir;
    pname = "formalshell-deps";
    version = "0.2.0";
    # Cargo resolves features per selected package set, and a dependency built
    # under a different feature set is compiled again. formalshell-rs pulls in
    # nearly every other crate, so its set is the one the artifacts match.
    # The mac has no pam or pipewire, and only builds the pure crates.
    cargoExtraArgs =
      if linux then "--locked --package formalshell-rs"
      else "--locked -p fs-js -p fs-chrome -p fs-info -p fs-system -p fs-devices -p fs-media -p fs-menu -p fs-screensaver -p fs-theme";
  });

  # Shared by every check derivation that builds from crates/ alone.
  checkArgs = commonArgs // {
    inherit src cargoVendorDir cargoArtifacts;
    version = "0.2.0";
    doInstallCargoArtifacts = false;
    nativeBuildInputs = commonArgs.nativeBuildInputs ++ [ clippy ];
  };
in
{ inherit craneLib commonArgs cargoVendorDir cargoArtifacts checkArgs src; }
