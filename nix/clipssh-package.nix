# clipssh (github.com/samuellawrentz/clipssh, MIT): the clipssh route and
# clipssh.autoSendImages shell out to it. Not in nixpkgs; upstream is one bash
# script, pinned here with its clipboard and ssh tools on its own PATH.
{ lib, stdenvNoCC, fetchFromGitHub, makeWrapper, openssh, coreutils, gnugrep, wl-clipboard }:

stdenvNoCC.mkDerivation {
  pname = "clipssh";
  version = "0-unstable-2026-06-15";

  src = fetchFromGitHub {
    owner = "samuellawrentz";
    repo = "clipssh";
    rev = "c7f4e8ddcf102302c6375ba51534c7505ddc2616";
    hash = "sha256-HkSVap02E/Y6fhg6PYnnMbF8KOVh9XYf8WXXrf/pTZE=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 clipssh $out/bin/clipssh
    wrapProgram $out/bin/clipssh \
      --prefix PATH : ${lib.makeBinPath [ openssh coreutils gnugrep wl-clipboard ]}
    runHook postInstall
  '';

  meta = {
    description = "Paste local clipboard images into terminal tools over SSH";
    homepage = "https://github.com/samuellawrentz/clipssh";
    license = lib.licenses.mit;
    mainProgram = "clipssh";
    platforms = lib.platforms.linux;
  };
}
