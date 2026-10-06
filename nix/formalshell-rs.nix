{ lib, rustPlatform, pkg-config, makeWrapper, fontconfig, lucide-font, matugen }:

rustPlatform.buildRustPackage {
  pname = "formalshell-rs";
  version = "0.1.1";

  # fs-theme embeds the chrome tables the QML shell reads too, one of its
  # tests reads Core/Theme.qml, and the theme service's tests run matugen
  # shims against the shell's own templates.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../crates
      ../shell/Theme/themes
      ../shell/Theme/templates
      ../shell/Core/Theme.qml
    ];
  };
  cargoRoot = "crates";
  buildAndTestSubdir = "crates";

  cargoLock.lockFile = ../crates/Cargo.lock;

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ fontconfig ];

  # The icon font by path, registered with parley at startup: the same
  # lucide build nix/package.nix hands Qt through XDG_DATA_DIRS.
  postInstall = ''
    mkdir -p $out/share/formalshell-rs
    cp -r ${../shell/Theme/templates} $out/share/formalshell-rs/templates
    wrapProgram $out/bin/formalshell-rs \
      --set-default FS_RS_ICON_FONT ${lucide-font}/share/fonts/truetype/lucide.ttf \
      --set-default FS_TEMPLATE_DIR $out/share/formalshell-rs/templates \
      --prefix PATH : ${lib.makeBinPath [ matugen ]}
  '';

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
}
