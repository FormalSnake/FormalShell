{ lib, stdenvNoCC, rustCommon, makeWrapper, lucide-font, nerd-fonts, noto-fonts-color-emoji, matugen, brightnessctl, ddcutil, wlsunset
, wireplumber, cava, mpv, curl, util-linux, uxplay, iphone-bridge, openscq30, nothingctl, earbuds, formalshell-eds, git, qrencode, networkmanager
, wl-clipboard, grim, slurp, wf-recorder, tesseract, ffmpeg-headless, pulseaudio, xdg-utils, tensaku, ttfx }:

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
      ../shell/Menu/default-menu.jsonc
      ../shell/Menu/emoji.json
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
    cp -r --no-preserve=mode ${../branding} $out/share/formalshell-rs/branding
    wrapProgram $out/bin/formalshell-rs \
      --set-default FS_RS_ICON_FONT ${lucide-font}/share/fonts/truetype/lucide.ttf \
      --set-default FS_RS_FONT_DIRS ${nerd-fonts.symbols-only}/share/fonts:${noto-fonts-color-emoji}/share/fonts \
      --set-default FS_TEMPLATE_DIR $out/share/formalshell-rs/templates \
      --set-default FS_BRANDING_DIR $out/share/formalshell-rs/branding \
      --prefix PATH : ${lib.makeBinPath [ matugen brightnessctl ddcutil wlsunset wireplumber cava mpv curl util-linux git formalshell-eds qrencode wl-clipboard grim slurp wf-recorder tesseract ffmpeg-headless pulseaudio xdg-utils ttfx ]} \
      --suffix PATH : ${lib.makeBinPath ([ tensaku uxplay iphone-bridge networkmanager ] ++ lib.optionals (lib.meta.availableOn stdenvNoCC.hostPlatform earbuds) [ earbuds openscq30 ] ++ lib.optional (lib.meta.availableOn stdenvNoCC.hostPlatform nothingctl) nothingctl)}
  '';

  meta = {
    description = "FormalShell rust rewrite";
    license = lib.licenses.mit;
    mainProgram = "formalshell-rs";
  };
})
