{ lib, rustPlatform, pkg-config, makeWrapper, fontconfig, lucide-font, nerd-fonts, matugen, wireplumber, cava, mpv, curl, util-linux, uxplay, iphone-bridge }:

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
      ../shell/Theme/icons
      ../shell/Theme/templates
      ../shell/Core/Theme.qml
    ];
  };
  cargoRoot = "crates";
  buildAndTestSubdir = "crates";

  cargoLock.lockFile = ../crates/Cargo.lock;

  # The pure library crates read repo fixtures (shell/, tests/) that this
  # crates-only source does not carry, so the runtime package builds and tests
  # itself alone; `cargo test` at the workspace root covers the rest.
  cargoBuildFlags = [ "--package" "formalshell-rs" ];
  cargoTestFlags = [ "--package" "formalshell-rs" ];

  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ fontconfig ];

  # The icon fonts by path, registered with parley at startup: the same
  # lucide and font-logos builds nix/package.nix hands Qt through
  # XDG_DATA_DIRS.
  postInstall = ''
    mkdir -p $out/share/formalshell-rs
    cp -r ${../shell/Theme/templates} $out/share/formalshell-rs/templates
    wrapProgram $out/bin/formalshell-rs \
      --set-default FS_RS_ICON_FONT ${lucide-font}/share/fonts/truetype/lucide.ttf \
      --set-default FS_RS_FONT_DIRS ${nerd-fonts.symbols-only}/share/fonts \
      --set-default FS_TEMPLATE_DIR $out/share/formalshell-rs/templates \
      --prefix PATH : ${lib.makeBinPath [ matugen wireplumber cava mpv curl util-linux ]} \
      --suffix PATH : ${lib.makeBinPath [ uxplay iphone-bridge ]}
  '';

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
}
