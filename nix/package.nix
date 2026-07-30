{ lib, stdenvNoCC, makeWrapper, quickshell, brightnessctl, wl-clipboard, curl, qt6, formalshell-eds }:
stdenvNoCC.mkDerivation {
  pname = "formalshell";
  version = "0.1.0-dev";
  src = ../shell;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell $out/bin
    cp -r . $out/share/formalshell/
    # Bundled default screensaver banner (M8b Task 7) — a sibling of shell/
    # in the repo, so Quickshell.shellPath("branding/...") still resolves it
    # once installed here alongside the copied shell tree.
    cp -r ${../branding} $out/share/formalshell/branding
    makeWrapper ${lib.getExe' quickshell "qs"} $out/bin/formalshell \
      --add-flags "-p $out/share/formalshell" \
      --prefix PATH : ${lib.makeBinPath [ brightnessctl wl-clipboard curl formalshell-eds ]} \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtpositioning}/lib/qt-6/qml \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtmultimedia}/lib/qt-6/qml \
      --prefix QT_PLUGIN_PATH : ${qt6.qtpositioning}/lib/qt-6/plugins \
      --prefix QT_PLUGIN_PATH : ${qt6.qtmultimedia}/lib/qt-6/plugins

    # lock-before-sleep contract (spec §8): whatever a systemd unit calls
    # before suspend must keep an exit-0-always behaviour so a lock failure
    # can never block suspend. `qs ipc call` itself exits nonzero (255) when
    # no shell instance is running at all — this wrapper is the actual
    # command such a unit invokes, and it never propagates that.
    cat > $out/bin/formalshell-lock-before-sleep <<SCRIPT
#!/usr/bin/env bash
${lib.getExe' quickshell "qs"} ipc --any-display -p $out/share/formalshell call lock lock >/dev/null 2>&1 || true
exit 0
SCRIPT
    chmod +x $out/bin/formalshell-lock-before-sleep
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
