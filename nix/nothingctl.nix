# nothingctl (github.com/FormalSnake/nothingctl, MIT), the one process that
# speaks the Nothing protocol for the earbuds panel. Built the way the
# repo's own nix/package.nix builds it: bluer links libdbus.
{ lib, rustPlatform, fetchFromGitHub, pkg-config, dbus }:

rustPlatform.buildRustPackage rec {
  pname = "nothingctl";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "FormalSnake";
    repo = "nothingctl";
    rev = "v${version}";
    hash = "sha256-OjPbHavyLwXEL8Vnn4G6+2gTF4+pEHoCguoxOBTFpJM=";
  };

  cargoHash = "sha256-gkVmLnK4xVj0s2ygiFt/PZTQk/T3ebVyc9qjUzQln6k=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ dbus ];

  meta = {
    description = "Control Nothing and CMF audio devices over Bluetooth";
    homepage = "https://github.com/FormalSnake/nothingctl";
    license = lib.licenses.mit;
    mainProgram = "nothingctl";
    platforms = lib.platforms.linux;
  };
}
