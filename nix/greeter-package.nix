# Same makeWrapper shape as package.nix, pointed at greeter/greeter.qml
# instead of shell/shell.qml — deliberately NOT the same derivation body:
# the greeter never touches audio/location/media, so it needs none of
# package.nix's brightnessctl/wl-clipboard/curl PATH entries or
# qtpositioning/qtmultimedia QML import paths, and it has no
# lock-before-sleep-style companion script. What IS shared is the actual
# QML source (src = ../shell, same as package.nix) — greeter.qml is
# layered into that same tree so `import qs.Core`/`qs.Components` resolve
# to the one real Core/Components, never a second copy.
{ lib, stdenvNoCC, makeWrapper, quickshell }:
stdenvNoCC.mkDerivation {
  pname = "formalshell-greeter";
  version = "0.1.0-dev";
  src = ../shell;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell-greeter $out/bin
    cp -r . $out/share/formalshell-greeter/
    cp ${../greeter/greeter.qml} $out/share/formalshell-greeter/greeter.qml
    makeWrapper ${lib.getExe' quickshell "qs"} $out/bin/formalshell-greeter \
      --add-flags "-p $out/share/formalshell-greeter/greeter.qml"
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell-greeter"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
