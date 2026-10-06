#!/usr/bin/env bash
# The native packages run in the test VM's nested Hyprland session, one
# release at a time: builds each release's arm64 packages in a container on
# this machine (any docker CLI, OrbStack on the mac), copies them into the
# VM, runs dev/smoke.sh --native there through dev/vm-lock.sh
# (dev/smoke.d/native.sh has what the leg proves), and saves the release's
# frames and logs under artifacts/native/<release>/.
#
#   dev/native-check.sh [--no-build] [release...]
#
# A release is packaging/debian/build.sh's --suite name, or arch. The
# default is all four the packaging supports: trixie forky resolute arch.
# --no-build reuses artifacts/native/pkgs/<release>/.
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$(pwd)

build=1
if [ "${1:-}" = --no-build ]; then build=; shift; fi
releases=("$@")
[ ${#releases[@]} -gt 0 ] || releases=(trixie forky resolute arch)

image_for() {
  case $1 in
    trixie) echo debian:trixie ;;
    forky) echo debian:forky ;;
    sid) echo debian:sid ;;
    resolute) echo ubuntu:26.04 ;;
    arch) echo menci/archlinuxarm:latest ;;
    *) return 1 ;;
  esac
}

# pacman's download sandbox needs Landlock, which a container is refused.
build_cmd() {
  case $1 in
    arch) echo "set -e
      sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
      pacman-key --init && pacman-key --populate
      pacman -Syu --noconfirm --needed base-devel git sudo
      useradd -m builder
      echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
      install -d -o builder /build
      su builder -c '/src/packaging/arch/build.sh --dir /build --syncdeps --noconfirm'
      cp /build/*.pkg.tar.* /out/" ;;
    *) echo "set -e
      /src/packaging/debian/build.sh --suite $1 --install-deps --dir /build
      cp /build/*.deb /out/" ;;
  esac
}

build_pkgs() {
  local release=$1 image=$2 out=$repo/artifacts/native/pkgs/$1 common
  mkdir -p "$out"
  find "$out" -maxdepth 1 \( -name '*.deb' -o -name '*.pkg.tar.*' \) -delete
  # A linked worktree's .git names the main checkout's git dir by absolute
  # path, so that directory is mounted where the file says it is.
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  docker run --rm --platform linux/arm64 \
    -v "$repo:/src:ro" -v "$common:$common:ro" -v "$out:/out" \
    -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    "$image" bash -c "$(build_cmd "$release")"
}

run_release() {
  local release=$1 image dest out status line
  image=$(image_for "$release") || { echo "unknown release: $release" >&2; return 1; }
  dest=$repo/artifacts/native/$release
  mkdir -p "$dest"
  if [ -n "$build" ]; then
    echo "native $release: building arm64 packages in $image"
    build_pkgs "$release" "$image" > "$dest/build.log" 2>&1 \
      || { echo "native $release: package build failed, see $dest/build.log"; return 1; }
  fi
  echo "native $release: running in the VM"
  tar -C "$repo/artifacts/native/pkgs/$release" -cf - . \
    | dev/vm-lock.sh dev/vm.sh run "rm -rf ~/native-pkgs/$release && mkdir -p ~/native-pkgs/$release && tar -C ~/native-pkgs/$release -xf -" \
    || { echo "native $release: copying the packages into the VM failed"; return 1; }
  out=$(dev/vm-lock.sh dev/vm.sh smoke --native "~/native-pkgs/$release" 2>&1)
  status=$?
  printf '%s\n' "$out" > "$dest/run.log"
  while IFS= read -r line; do
    mv -f "$line" "$dest/"
  done < <(printf '%s\n' "$out" | sed -nE 's/^pulled (screenshot|dump\/status output): //p')
  # Each image is about 4 GB against the VM's 40. A failed one stays for
  # the rerun.
  if [ "$status" = 0 ]; then
    dev/vm-lock.sh dev/vm.sh run "podman image rm -f localhost/formalshell-native:$release" > /dev/null 2>&1
  fi
  return "$status"
}

failed=0
results=()
for release in "${releases[@]}"; do
  if run_release "$release"; then
    results+=("native $release: PASS")
  else
    results+=("native $release: FAIL (artifacts/native/$release/run.log)")
    failed=1
  fi
done
printf '%s\n' "${results[@]}"
exit "$failed"
