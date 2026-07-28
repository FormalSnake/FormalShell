{ lib, stdenvNoCC, makeWrapper, quickshell, brightnessctl, wl-clipboard, qt6 }:
stdenvNoCC.mkDerivation {
  pname = "formalshell";
  version = "0.1.0-dev";
  src = ../shell;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell $out/bin
    cp -r . $out/share/formalshell/
    makeWrapper ${lib.getExe' quickshell "qs"} $out/bin/formalshell \
      --add-flags "-p $out/share/formalshell" \
      --prefix PATH : ${lib.makeBinPath [ brightnessctl wl-clipboard ]} \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qt6.qtpositioning}/lib/qt-6/qml \
      --prefix QT_PLUGIN_PATH : ${qt6.qtpositioning}/lib/qt-6/plugins
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
