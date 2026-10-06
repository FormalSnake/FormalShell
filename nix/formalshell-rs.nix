{ lib, stdenvNoCC, rustCommon, makeWrapper, lucide-font, nerd-fonts, matugen, brightnessctl
, openscq30, nothingctl, earbuds }:

rustCommon.craneLib.buildPackage (rustCommon.commonArgs // {
  inherit (rustCommon) cargoArtifacts cargoVendorDir;
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
  postUnpack = ''
    cd $sourceRoot/crates
    sourceRoot="."
  '';

  # The pure library crates read repo fixtures (shell/, tests/) that this
  # crates-only source does not carry, so the runtime package builds and tests
  # itself alone; `cargo test` at the workspace root covers the rest.
  cargoExtraArgs = "--locked --package formalshell-rs";

  nativeBuildInputs = rustCommon.commonArgs.nativeBuildInputs ++ [ makeWrapper ];

  # The icon fonts by path, registered with parley at startup: the same
  # lucide and font-logos builds nix/package.nix hands Qt through
  # XDG_DATA_DIRS.
  postInstall = ''
    mkdir -p $out/share/formalshell-rs
    cp -r --no-preserve=mode ${../shell/Theme/templates} $out/share/formalshell-rs/templates
    wrapProgram $out/bin/formalshell-rs \
      --set-default FS_RS_ICON_FONT ${lucide-font}/share/fonts/truetype/lucide.ttf \
      --set-default FS_RS_FONT_DIRS ${nerd-fonts.symbols-only}/share/fonts \
      --set-default FS_TEMPLATE_DIR $out/share/formalshell-rs/templates \
      --prefix PATH : ${lib.makeBinPath [ matugen brightnessctl ]} \
      --suffix PATH : ${lib.makeBinPath (lib.optionals (lib.meta.availableOn stdenvNoCC.hostPlatform earbuds) [ earbuds openscq30 ] ++ lib.optional (lib.meta.availableOn stdenvNoCC.hostPlatform nothingctl) nothingctl)}
  '';

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
})
