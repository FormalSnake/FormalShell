#!/usr/bin/env bash
# Stages a source tree with every upstream source and its cargo and Go
# dependencies unpacked under third_party/, then runs dpkg-buildpackage on it
# offline. Runs on the Debian or Ubuntu release the packages are for.
#
#   build.sh [--tag vX.Y.Z] [--dir DIR] [--suite NAME] [--install-deps]
#
# With --tag, the source is GitHub's tarball for that tag; without it, the
# working tree. --suite names the release in the version (default: the
# os-release codename, which sid shares with testing). --install-deps, as
# root, installs what this script and the build need.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
tag=
dir=$here/build
codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
suite=$codename
deps=
while [ $# -gt 0 ]; do
  case $1 in
    --tag) tag=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    --suite) suite=$2; shift 2 ;;
    --install-deps) deps=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

version=$(sed -n '1s/^formalshell (\([^-]*\)-.*/\1/p' "$here/changelog")
[ -n "$tag" ] && version=${tag#v}
src=$dir/formalshell-$version
dl=$dir/downloads
export DEBIAN_FRONTEND=noninteractive

# name, url, sha256, and how many leading path components to strip.
sources=(
  "lucide-font https://github.com/lucide-icons/lucide/releases/download/1.34.0/lucide-font-1.34.0.zip 1606dba9b2abe06168ee818bea7e66e3c5b881b56ee73e6331cee1cb4e096756 1"
  "nerd-fonts-symbols https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.tar.xz 7f8c090da3b0eaa7108646bf34cbbb6ed13d5358a72460522108b06c7ecd716a 0"
  "ttfx https://github.com/omacom/ttfx/archive/refs/tags/v0.4.0.tar.gz 90a057971973917a45ae1cb2fc795cfaea33afc265180ba4a963172daf9f64ee 1"
  "tensaku https://github.com/jondkinney/tensaku/archive/refs/tags/v0.26.6.tar.gz 2387b38b5ac65fa61e3557fcf568b83585b15449e83d027bf860d4a0593fa17d 1"
  "matugen https://github.com/InioX/matugen/archive/refs/tags/v4.1.0.tar.gz b46507be24d01a6233597077512501f21075fe4ce19b60b410354f439f569ddf 1"
  "clipssh https://github.com/samuellawrentz/clipssh/archive/c7f4e8ddcf102302c6375ba51534c7505ddc2616.tar.gz f4c388645830e3afd9adeae2b71173441ce3b3b97a852915457c043e9cc99afd 1"
  "localsend-cli https://github.com/0w0mewo/localsend-cli/archive/7865fb1cf26e4f782c6400167a7d218d69313cff.tar.gz 0661e232dd939ad3c36c29025aac75db212fbf909f2701ded69bbc590bc96ab3 1"
  "omarchy-iphone https://github.com/kbbahaPro/omarchy-iphone/archive/586f37dce6aceef72376afb8be8bcc8a04de41fe.tar.gz b26cf068e47705ab6046b14c56e08c716afbad07f4b2d2a685785ee71c137ecb 1"
  "ancs4linux https://github.com/pzmarzly/ancs4linux/archive/b658546f08d1468f6d79aa900cc7faa9d938837d.tar.gz a3ea8bd735d6295cacbcf0dee0107f7d705b0ec156dfa7e76fc05c5db4b3de74 1"
  "nothingctl https://github.com/FormalSnake/nothingctl/archive/refs/tags/v0.1.1.tar.gz 3e52ae1254cfc09c0b88554b887c8e3653f5df606ab9f9490abb67f88cf57cab 1"
  "openscq30 https://github.com/Oppzippy/OpenSCQ30/archive/refs/tags/v2.12.0.tar.gz 5c2509ea0dd71ab0b6b2d81948ec2850fc4d72a1239e4cda79dac2dbad7f3860 1"
  "earbuds https://github.com/JojiiOfficial/LiveBudsCli/archive/refs/tags/v0.2.0.tar.gz b0174d4207312bdf54f5cb586fff22984ecd5be54bd0205c4debf7927878ea70 1"
)
case $(dpkg --print-architecture) in
  amd64) sources+=("zig https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz 70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 1") ;;
  arm64) sources+=("zig https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 1") ;;
  *) echo "no zig 0.16.0 build for $(dpkg --print-architecture)" >&2; exit 1 ;;
esac
fetch() {
  local url=$1 sum=$2 out=$dl/${1##*/}
  [ -f "$out" ] && echo "$sum  $out" | sha256sum -c --quiet 2>/dev/null && return
  curl -fsSL -o "$out" "$url"
  echo "$sum  $out" | sha256sum -c --quiet
}

unpack() {
  local archive=$1 into=$2 strip=$3
  mkdir -p "$into"
  case $archive in
    *.zip)
      local tmp=$into.zip.d
      rm -rf "$tmp"; mkdir -p "$tmp"
      (cd "$tmp" && unzip -q "$archive")
      if [ "$strip" = 1 ]; then mv "$tmp"/*/* "$into"/; else mv "$tmp"/* "$into"/; fi
      rm -rf "$tmp" ;;
    *) tar -xf "$archive" -C "$into" --strip-components="$strip" ;;
  esac
}

if [ -n "$deps" ]; then
  # trixie's Go (1.24) is older than localsend-cli needs; backports
  # carries a newer one.
  if [ "$codename" = trixie ]; then
    echo 'deb http://deb.debian.org/debian trixie-backports main' > /etc/apt/sources.list.d/trixie-backports.list
  fi
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl dpkg-dev git patch unzip xz-utils
fi
mkdir -p "$dl"
rm -rf "$src"
mkdir -p "$src"
if [ -n "$tag" ]; then
  curl -fsSL "https://github.com/FormalSnake/FormalShell/archive/refs/tags/v$version.tar.gz" \
    | tar -xz -C "$src" --strip-components=1
else
  git -C "$repo" ls-files -z --cached --others --exclude-standard \
    | (cd "$repo" && xargs -0 sh -c 'for f; do [ -e "$f" ] && printf "%s\0" "$f"; done' _) \
    | tar -C "$repo" --null -T - -cf - | tar -C "$src" -xf -
fi
mkdir -p "$src/debian"
(cd "$src/packaging/debian" && tar --exclude=./build.sh --exclude=./check.sh --exclude=./build -cf - .) | tar -C "$src/debian" -xf -
sed -i "1s/^formalshell ([^)]*) [^;]*;/formalshell ($version-1+$suite) $suite;/" "$src/debian/changelog"

if [ -n "$deps" ]; then
  apt-get build-dep -y "$src"
fi

tp=$src/third_party
for entry in "${sources[@]}"; do
  read -r name url sum strip <<<"$entry"
  fetch "$url" "$sum"
  unpack "$dl/${url##*/}" "$tp/$name" "$strip"
done

export CARGO_HOME=$tp/cargo-home GOPATH=$tp/gopath GOFLAGS=-modcacherw PATH=/usr/lib/go-1.25/bin:$PATH
host=$(rustc -vV | sed -n 's/^host: //p')
rm -f "$tp/tensaku/rust-toolchain.toml"
(cd "$src/crates" && cargo fetch --locked --target "$host")
for crate in ttfx tensaku matugen nothingctl openscq30 earbuds; do
  (cd "$tp/$crate" && cargo fetch --locked --target "$host")
done

# Same fix as nix/localsend-cli.nix: without a Content-Type every send is
# rejected by a fiber receiver, this CLI's own `recv` included.
cd "$tp/localsend-cli"
sed -i 's/req.SetBodyRaw(metaJson)/req.Header.SetContentType("application\/json"); req.SetBodyRaw(metaJson)/' \
  internal/localsend/send/fwdsend.go
grep -q 'SetContentType("application/json")' internal/localsend/send/fwdsend.go
GOTOOLCHAIN=local go mod download

cd "$tp/omarchy-iphone"
patch -Np1 -i "$src/nix/iphone-ams-subscribe.patch"
patch -Np1 -i "$src/nix/iphone-bridge-bond.patch"
cd "$tp/ancs4linux"
patch -Np1 -i "$tp/omarchy-iphone/patches/ancs4linux-metadata.patch"
patch -Np1 -i "$src/nix/ancs4linux-authorize.patch"

cd "$src"
dpkg-buildpackage -us -uc -b
