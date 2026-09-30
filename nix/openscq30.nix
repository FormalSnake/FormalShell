# openscq30, the CLI of github.com/Oppzippy/OpenSCQ30 (GPL-3.0), built alone.
# nixpkgs' open-scq30 builds the GTK app too through `just build-cli
# build-gui`, and at the pinned nixpkgs (2.6.2) that recipe fails in the
# build phase (`just` rejects the justfile's which()). The JSON output the
# earbuds adapter reads is documented for 2.12.0's CLI, so this pins that.
{ lib, rustPlatform, fetchFromGitHub, pkg-config, protobuf, dbus, sqlite }:

rustPlatform.buildRustPackage rec {
  pname = "openscq30";
  version = "2.12.0";

  src = fetchFromGitHub {
    owner = "Oppzippy";
    repo = "OpenSCQ30";
    rev = "v${version}";
    hash = "sha256-5/b71nZrvN7Q/56FM/orMz6vb+FKf6k/qqYgusirTyI=";
  };

  cargoHash = "sha256-mLKK2J3CJ6qSM5EDjB6LkrFWKxijFl6jjcjrCgXVg8c=";

  nativeBuildInputs = [ pkg-config protobuf ];
  buildInputs = [ dbus sqlite ];

  cargoBuildFlags = [ "--package" "openscq30-cli" ];

  # The suite drives demo devices through insta-cmd snapshots and a
  # bluetooth session the build sandbox does not have.
  doCheck = false;

  meta = {
    description = "CLI for the settings of Soundcore headphones and earbuds";
    homepage = "https://github.com/Oppzippy/OpenSCQ30";
    license = lib.licenses.gpl3Only;
    mainProgram = "openscq30";
    platforms = lib.platforms.linux;
  };
}
