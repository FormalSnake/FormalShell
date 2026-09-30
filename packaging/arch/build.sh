#!/usr/bin/env bash
# Stages PKGBUILD in a build directory with its first checksum pinned, writes
# .SRCINFO, and runs makepkg there with the remaining arguments.
#
#   build.sh [--tag vX.Y.Z] [--dir DIR] [makepkg args...]
#
# With --tag, the source is GitHub's tarball for that tag and pkgver follows
# it: the staged directory is then the AUR submission. Without it, the
# working tree is packed under the tarball's name, which makepkg uses in
# place of a download.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
tag=
dir=$here/build
while [ $# -gt 0 ]; do
  case $1 in
    --tag) tag=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    *) break ;;
  esac
done

pkgver=$(sed -n 's/^pkgver=//p' "$here/PKGBUILD")
[ -n "$tag" ] && pkgver=${tag#v}
tarball=FormalShell-$pkgver.tar.gz

mkdir -p "$dir"
cp "$here/PKGBUILD" "$here"/*.install "$dir/"
rm -f "$dir/$tarball"
if [ -n "$tag" ]; then
  curl -fsSL -o "$dir/$tarball" "https://github.com/FormalSnake/FormalShell/archive/refs/tags/v$pkgver.tar.gz"
else
  git -C "$repo" ls-files -z --cached --others --exclude-standard \
    | (cd "$repo" && xargs -0 sh -c 'for f; do [ -e "$f" ] && printf "%s\0" "$f"; done' _) \
    | tar -C "$repo" --null -T - --transform "s|^|FormalShell-$pkgver/|" -czf "$dir/$tarball"
fi
sum=$(sha256sum "$dir/$tarball" | cut -d' ' -f1)
sed -i -e "s/^pkgver=.*/pkgver=$pkgver/" -e "s/^sha256sums=('SKIP'/sha256sums=('$sum'/" "$dir/PKGBUILD"

cd "$dir"
makepkg --printsrcinfo > .SRCINFO
makepkg "$@"
