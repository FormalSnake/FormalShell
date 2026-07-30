{ lib, stdenv, zig, pkg-config, systemd }:
stdenv.mkDerivation {
  pname = "formalshell-eds";
  version = "0.1.0-dev";
  src = ../tools/eds;
  nativeBuildInputs = [ zig.hook pkg-config ];
  buildInputs = [ systemd ];
  meta = {
    description = "Evolution Data Server calendar companion CLI for FormalShell";
    mainProgram = "formalshell-eds";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
