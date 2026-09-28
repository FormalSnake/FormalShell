# 0w0mewo/localsend-cli (Go, MIT), picked over the official localsend/localsend
# `cli/` crate (Rust) after reading both at HEAD on 2026-09-28: the official
# CLI's headless mode is `send --to <alias|ip> <paths>` only, it declines
# every incoming transfer, and it has no `recv`/`scan` at all (the TUI is the
# only receiver). This one has all three: `scan` for peer discovery, `send -f
# -p` for files, and `recv -n -d` that auto-accepts every upload with no
# prompt (internal/localsend/recv/handlers.go). See
# docs/superpowers/plans/2026-09-28-m75-iphone.md Task 5 for the exact flags
# and output shape LocalsendService parses.
#
# Upstream's own README calls the project deprecated, compatible with the
# official app's v1.17.0 rather than the current v1.18.0. It still speaks the
# same LocalSend v2 wire protocol the README claims, and it is the only
# candidate with unattended receive and scriptable discovery, so the risk is
# accepted here and re-checked in Task 5's own real loopback transfer.
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "localsend-cli";
  version = "0-unstable-2026-08-16";

  src = fetchFromGitHub {
    owner = "0w0mewo";
    repo = "localsend-cli";
    rev = "7865fb1cf26e4f782c6400167a7d218d69313cff";
    hash = "sha256-SwdVmVr64YnNq8c93nzhngPmg/SYR9FUezx9zet+h1o=";
  };

  vendorHash = "sha256-2F5zoXbHUb+b6m3L7xIBBHNFMacnJuuH+c4Ut/hFRjs=";

  meta = {
    description = "Headless LocalSend v2 protocol client: peer scan, file send, unattended receive";
    homepage = "https://github.com/0w0mewo/localsend-cli";
    license = lib.licenses.mit;
    mainProgram = "localsend-cli";
    platforms = lib.platforms.linux;
  };
}
