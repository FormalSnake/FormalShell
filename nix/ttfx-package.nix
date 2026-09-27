# ttfx (github.com/omacom/ttfx) — the terminal-text-effect engine behind
# the screensaver's banner animation. Not in nixpkgs as of 2026-08-11.
#
# MIT, same as FormalShell; invoked as a separate executable whose ANSI frame
# stream the screensaver surface parses, never linked into or vendored by
# shell source.
{ lib, rustPlatform, fetchFromGitHub, nasm, python3 }:

rustPlatform.buildRustPackage rec {
  pname = "ttfx";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    rev = "v${version}";
    hash = "sha256-JkCo8SYkimaW/4fdJImeBiu0sv7sp5Y9ZKI68ZD7liw=";
  };

  cargoHash = "sha256-U+CxNX/ijI+RdfT5likCbSsYV2w0Fu+hSztU4Y3kwgo=";

  # build.rs assembles the x86-64 engine (asm/) with NASM >= 3.0 and audits
  # each CPU tier's object with objdump and python3. A missing NASM silently
  # falls back to the pure-Rust engine, which is also what aarch64 gets.
  nativeBuildInputs = [ nasm python3 ];

  # tests/easing_goldens.rs asserts ttfx's easing curves are bit-identical to
  # CPython's, sample for sample. On aarch64 glibc one OutExpo sample lands a
  # single ULP away (0.18774760364376453 vs …442 at p=0.03) — libm's own
  # rounding, not a port bug, and upstream's README already scopes its
  # byte-exact suites to one platform for exactly this reason. Skipped rather
  # than doCheck = false: every other test, including the engine state
  # machines and the gradient values this shell renders, still runs.
  checkFlags = [ "--skip=easing_matches_python_bit_exactly" ];

  meta = {
    description = "Terminal text effects as a single static binary, a Rust and x86-64 assembly port of terminaltexteffects";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    mainProgram = "ttfx";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
