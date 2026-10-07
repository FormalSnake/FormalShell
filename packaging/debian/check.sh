#!/usr/bin/env bash
# Installs the built packages on a fresh Debian or Ubuntu system and checks
# them: every packaged tool runs, the shell's binaries resolve every library
# they link, and both fonts reach fontconfig.
#
#   check.sh DEBDIR
set -euo pipefail
debs=$(cd "$1" && pwd)
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y "$debs"/*.deb fontconfig
dpkg -L formalshell >/dev/null

formalshell-eds --help
ttfx --version
tensaku --version
matugen --version
localsend-cli --help
omarchy-iphone-bridge --help
omarchy-iphone-ams --help
ancs4linux-ctl --help
clipssh --help
nothingctl --help
openscq30 --help
earbuds --help

if ldd /usr/lib/formalshell/formalshell-rs /usr/bin/formalshell-ipc | grep 'not found'; then
  exit 1
fi
# No shell is running: the client says so and exits 255.
formalshell-ipc show || [ $? = 255 ]

fc-list | grep -i lucide
fc-list | grep -i 'Symbols Nerd Font'
echo CHECK_OK
