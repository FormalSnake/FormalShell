# NASA's Blue Marble Next Generation, July 2004, topography and bathymetry
# (visibleearth.nasa.gov/images/73751): the satellite picture Radio Atlas
# wraps its globe in. NASA imagery is public domain.
#
# Shipped at 4096x2048, about one texel per pixel at the globe's centre in
# the atlas on a 2560px output at scale 1. The 5400x2700 original decodes
# to 44 MB of RGB the shell would hold while the atlas is open; this one is
# 25 MB. dev/tarball.sh makes the same resize.
{ stdenvNoCC, fetchurl, imagemagick }:
stdenvNoCC.mkDerivation {
  pname = "blue-marble";
  version = "200407";

  src = fetchurl {
    url = "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73751/world.topo.bathy.200407.3x5400x2700.jpg";
    hash = "sha256-T0JAZzo6Gxc9YbkspLB7rF/RcFnqX3JbptpanFOGt7o=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ imagemagick ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/formalshell
    magick $src -resize '4096x2048!' -strip -quality 90 $out/share/formalshell/earth.jpg
    runHook postInstall
  '';
}
