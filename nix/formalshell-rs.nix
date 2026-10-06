{ lib, rustPlatform, pkg-config, makeWrapper, fontconfig, lucide-font }:

rustPlatform.buildRustPackage {
  pname = "formalshell-rs";
  version = "0.1.1";

  src = lib.fileset.toSource {
    root = ../crates;
    fileset = ../crates;
  };

  cargoLock.lockFile = ../crates/Cargo.lock;

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ fontconfig ];

  # The icon font by path, registered with parley at startup: the same
  # lucide build nix/package.nix hands Qt through XDG_DATA_DIRS.
  postInstall = ''
    wrapProgram $out/bin/formalshell-rs \
      --set-default FS_RS_ICON_FONT ${lucide-font}/share/fonts/truetype/lucide.ttf
  '';

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
}
