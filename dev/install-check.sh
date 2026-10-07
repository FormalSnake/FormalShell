#!/usr/bin/env bash
# install.sh from nothing on each distro family it supports, in the test
# VM's nested Hyprland session: builds the aarch64 release tarball in a
# container on this machine (`just tarball`), copies it and install.sh into
# the VM's ~/install-check, runs dev/smoke.sh --installed <distro> there
# through dev/vm-lock.sh (dev/smoke.d/installed.sh has what the leg proves),
# and saves each distro's frames and logs under artifacts/installed/<distro>/.
#
#   dev/install-check.sh [--no-build] [distro...]
#
# A distro is arch, trixie or fedora; the default is all three. --no-build
# reuses artifacts/tarball/.
set -uo pipefail
cd "$(dirname "$0")/.."
repo=$(pwd)

build=1
if [ "${1:-}" = --no-build ]; then build=; shift; fi
distros=("$@")
[ ${#distros[@]} -gt 0 ] || distros=(arch trixie fedora)

tarball=$repo/artifacts/tarball/formalshell-aarch64-linux.tar.gz
if [ -n "$build" ]; then
  just tarball || { echo "install-check: tarball build failed (artifacts/tarball/)"; exit 1; }
fi
[ -f "$tarball" ] || { echo "install-check: no $tarball; run without --no-build"; exit 1; }

run_distro() {
  local distro=$1 dest out status line
  dest=$repo/artifacts/installed/$distro
  mkdir -p "$dest"
  echo "installed $distro: running in the VM"
  # One lock for the copy and the run: each slot is its own VM, so the
  # tarball has to land in the VM the run gets.
  # shellcheck disable=SC2016  # expanded by the inner bash
  out=$(tar -C "$repo" -cf - install.sh -C "$repo/artifacts/tarball" "$(basename "$tarball")" \
    | dev/vm-lock.sh bash -c '
        dev/vm.sh run "rm -rf ~/install-check && mkdir -p ~/install-check && tar -C ~/install-check -xf -" \
          || { echo "installed $1: copying the tarball into the VM failed"; exit 1; }
        dev/vm.sh smoke --installed "$1" < /dev/null' _ "$distro" 2>&1)
  status=$?
  printf '%s\n' "$out" > "$dest/run.log"
  while IFS= read -r line; do
    mv -f "$line" "$dest/"
  done < <(printf '%s\n' "$out" | sed -nE 's/^pulled (screenshot|dump\/status output): //p')
  # Each image is several GB against the VM's 40, and every rebuild leaves
  # the last one dangling. A failed one stays for the rerun.
  if [ "$status" = 0 ]; then
    dev/vm-lock.sh dev/vm.sh run "podman image rm -f localhost/formalshell-installed:$distro" > /dev/null 2>&1
  fi
  dev/vm-lock.sh dev/vm.sh run "podman image prune -f" > /dev/null 2>&1
  return "$status"
}

failed=0
results=()
for distro in "${distros[@]}"; do
  if run_distro "$distro"; then
    results+=("installed $distro: PASS")
  else
    results+=("installed $distro: FAIL (artifacts/installed/$distro/run.log)")
    failed=1
  fi
done
printf '%s\n' "${results[@]}"
exit "$failed"
