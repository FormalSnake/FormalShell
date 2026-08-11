# Tensaku (github.com/jondkinney/tensaku) — the screenshot annotation editor
# the capture flow hands its PNG to. Not in nixpkgs as of 2026-08-11, and
# upstream's own flake ships a devShell only, so the derivation lives here.
#
# MPL-2.0, weak copyleft at file scope: this is packaged and invoked as a
# separate executable, never linked into or vendored by shell source, so
# FormalShell stays MIT.
#
# `tensaku` takes its input as a flag rather than a positional argument, so
# upstream ships assets/tensaku-edit to adapt the "editor <path>" calling
# convention. That wrapper is what `screenshot.editor` defaults to; it is
# installed here exactly as upstream's own AUR PKGBUILD installs it.
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, wrapGAppsHook4
, gtk4
, gtk4-layer-shell
, libadwaita
, libepoxy
, fontconfig
, glib
, libGL
, wl-clipboard
}:

rustPlatform.buildRustPackage rec {
  pname = "tensaku";
  version = "0.26.6";

  src = fetchFromGitHub {
    owner = "jondkinney";
    repo = "tensaku";
    rev = "v${version}";
    hash = "sha256-br4/PqdrPwB86Fgwv+ujAdRFFqJzUpM//AzR7NC5QTI=";
  };

  cargoHash = "sha256-oh5WTHfgeecZ4IHWX2/zIWpB8KVxPW5+dyjcGMD82dk=";

  # rust-toolchain.toml pins channel 1.95.0 for upstream CI determinism.
  # There is no rustup here to honour it, and nixpkgs' rustc is newer, so
  # drop it rather than leave a pin nothing reads.
  postPatch = ''
    rm -f rust-toolchain.toml
  '';

  nativeBuildInputs = [ pkg-config wrapGAppsHook4 ];

  # wrapGAppsHook4 is load-bearing beyond the usual schema/icon wrapping:
  # relm4-icons only resolves its icon resources after gtk::init() when the
  # app is wrapped (upstream says so in its own devShell).
  buildInputs = [ gtk4 gtk4-layer-shell libadwaita libepoxy fontconfig glib libGL ];

  buildFeatures = [ "ci-release" ];

  # The editor wrapper shells out to `wl-copy` for its save-to-clipboard
  # action, so it cannot rely on the caller's PATH.
  postInstall = ''
    substituteInPlace assets/tensaku-edit \
      --replace-fail 'exec tensaku \' 'exec '"$out"'/bin/tensaku \' \
      --replace-fail '--copy-command wl-copy' '--copy-command ${lib.getExe' wl-clipboard "wl-copy"}'
    install -Dm755 assets/tensaku-edit $out/bin/tensaku-edit

    install -Dm644 dev.tensaku.Tensaku.desktop \
      $out/share/applications/dev.tensaku.Tensaku.desktop
    install -Dm644 assets/tensaku.svg \
      $out/share/icons/hicolor/scalable/apps/dev.tensaku.Tensaku.svg
  '';

  # Upstream's suite wants a Wayland display and a writable HOME.
  doCheck = false;

  meta = {
    description = "Screenshot annotation for Wayland, with movable annotations";
    homepage = "https://tensaku.dev";
    license = lib.licenses.mpl20;
    mainProgram = "tensaku";
    platforms = lib.platforms.linux;
  };
}
