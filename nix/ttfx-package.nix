# ttfx (github.com/omacom-io/ttfx) — the terminal-text-effect engine behind
# the screensaver's banner animation. Not in nixpkgs as of 2026-08-11.
#
# MIT, same as FormalShell; invoked as a separate executable whose ANSI frame
# stream the screensaver surface parses, never linked into or vendored by
# shell source.
{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "ttfx";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "omacom-io";
    repo = "ttfx";
    rev = "v${version}";
    hash = "sha256-KsKPtOEkyu172MSzIcu+/dy9JY99Yc0Mxu97GPTqm1Q=";
  };

  cargoHash = "sha256-srNL1EP2mdm6Gu9WNQqtERAYt7+Kdk6vzUOzzHWgYXQ=";

  # tests/easing_goldens.rs asserts ttfx's easing curves are bit-identical to
  # CPython's, sample for sample. On aarch64 glibc one OutExpo sample lands a
  # single ULP away (0.18774760364376453 vs …442 at p=0.03) — libm's own
  # rounding, not a port bug, and upstream's README already scopes its
  # byte-exact suites to one platform for exactly this reason. Skipped rather
  # than doCheck = false: every other test, including the engine state
  # machines and the gradient values this shell renders, still runs.
  checkFlags = [ "--skip=easing_matches_python_bit_exactly" ];

  meta = {
    description = "Terminal text effects as a single static binary, a Rust port of terminaltexteffects";
    homepage = "https://github.com/omacom-io/ttfx";
    license = lib.licenses.mit;
    mainProgram = "ttfx";
    platforms = lib.platforms.unix;
  };
}
