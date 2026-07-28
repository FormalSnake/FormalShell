{ lib, stdenvNoCC, makeWrapper, quickshell, brightnessctl, wl-clipboard }:
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
      --prefix PATH : ${lib.makeBinPath [ brightnessctl wl-clipboard ]}
    runHook postInstall
  '';
  meta = { mainProgram = "formalshell"; license = lib.licenses.mit; platforms = lib.platforms.linux; };
}
