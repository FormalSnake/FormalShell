# NASA's Blue Marble Next Generation, July 2004, topography and bathymetry
# (visibleearth.nasa.gov/images/73751): the satellite picture Radio Atlas
# wraps its globe in. NASA imagery is public domain.
#
# The 21600x10800 original cut into a pyramid of 512 px JPEG tiles, 21600
# wide down to 2700 (nix/earth-tiles.py), so the shell decodes only the
# tiles a zoomed view needs, plus the 4096x2048 single picture it falls
# back to without them. dev/tarball.sh runs the same script.
{ stdenvNoCC, fetchurl, python3 }:
stdenvNoCC.mkDerivation {
  pname = "blue-marble";
  version = "200407";

  src = fetchurl {
    url = "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73751/world.topo.bathy.200407.3x21600x10800.jpg";
    hash = "sha256-0iXx81pkSKTR2PbebkjzQz5HAIW3CjWADmTzhPJpp7A=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ (python3.withPackages (p: [ p.pillow ])) ];

  installPhase = ''
    runHook preInstall
    python3 ${./earth-tiles.py} $src $out/share/formalshell
    runHook postInstall
  '';
}
