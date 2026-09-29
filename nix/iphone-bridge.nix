# The two Python scripts omarchy-iphone (github.com/kbbahaPro/omarchy-iphone,
# MIT) ships as standalone CLIs: bin/omarchy-iphone-bridge turns
# ancs4linux's ANCS D-Bus signals into JSONL on stdout, bin/omarchy-iphone-ams
# is an Apple Media Service GATT client for now-playing state and transport
# commands. Neither is a Python package (no pyproject.toml, no setup.py), so
# this installs them as scripts and repoints their shebang at a Python that
# actually has PyGObject, which plain /usr/bin/env python3 would not.
#
# The AMS patch makes `listen` exit non-zero when a subscribe write fails.
# Upstream emits the error and then reports available with no subscription,
# which is what a phone that is not GATT-ready yet produces right after the
# bridge sees it connect.
#
# The bond patch makes `listen` report connected off the LE bearer alone
# (BlueZ keeps Device1.Connected true over a BR/EDR audio link with LE down,
# where ANCS and AMS cannot reach the phone), reports a phone BlueZ still
# holds a bond for while it is not connected, and gives `pair` a `--forget`
# that drops that one device's keys before advertising: a phone that forgot
# this machine fails every new pairing while BlueZ holds the old ones.
{ lib, stdenvNoCC, fetchFromGitHub, python3 }:

let
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenvNoCC.mkDerivation {
  pname = "omarchy-iphone-bridge";
  version = "0-unstable-2026-09-24";

  src = fetchFromGitHub {
    owner = "kbbahaPro";
    repo = "omarchy-iphone";
    rev = "586f37dce6aceef72376afb8be8bcc8a04de41fe";
    hash = "sha256-s6HsH5sz3sXECG8vqZ4fwSWrq5HVa9RLL8dRzGnDDMM=";
  };

  patches = [ ./iphone-ams-subscribe.patch ./iphone-bridge-bond.patch ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 bin/omarchy-iphone-bridge $out/bin/omarchy-iphone-bridge
    install -m755 bin/omarchy-iphone-ams $out/bin/omarchy-iphone-ams
    substituteInPlace $out/bin/omarchy-iphone-bridge $out/bin/omarchy-iphone-ams \
      --replace-fail "#!/usr/bin/env python3" "#!${pythonEnv}/bin/python3"
    runHook postInstall
  '';

  meta = {
    description = "JSONL bridges turning ancs4linux's ANCS/AMS D-Bus signals into stdout streams";
    homepage = "https://github.com/kbbahaPro/omarchy-iphone";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
