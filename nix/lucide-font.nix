# Lucide (github.com/lucide-icons/lucide), the icon font `theme.icons`
# defaults to (spec "Icons", D2). Not in nixpkgs as of 2026-08-25.
#
# ISC, permissive: packaged and installed as a plain font file, never
# linked into or vendored by shell source, so FormalShell stays MIT.
#
# The release zip unpacks to a `lucide-font/` directory carrying the font
# in five formats plus `lucide.css` (the name-to-codepoint map
# `tools/gen-lucide-icons.sh` parses) and a duplicate-data `codepoints.json`/
# `info.json` pair the generator does not use, since the spec names the CSS
# as the source of truth.
{ lib, stdenvNoCC, fetchzip }:
stdenvNoCC.mkDerivation {
  pname = "lucide-font";
  version = "1.34.0";

  src = fetchzip {
    url = "https://github.com/lucide-icons/lucide/releases/download/1.34.0/lucide-font-1.34.0.zip";
    hash = "sha256-H6x+xA6rqlPEar64m4JoVKdqL8MRDfibssA5A2MFJAI=";
    stripRoot = false;
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 lucide-font/lucide.ttf $out/share/fonts/truetype/lucide.ttf
    install -Dm444 lucide-font/lucide.css $out/share/lucide/lucide.css
    runHook postInstall
  '';

  meta = {
    description = "Lucide icon font, TTF plus its CSS codepoint map";
    homepage = "https://lucide.dev";
    license = lib.licenses.isc;
    platforms = lib.platforms.all;
  };
}
