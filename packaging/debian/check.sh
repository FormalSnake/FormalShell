#!/usr/bin/env bash
# Installs the built packages on a fresh Debian or Ubuntu system and checks
# them: every packaged tool runs, both fonts reach fontconfig, and the
# installed shell lints exactly like the repo's shell/ against this
# release's Qt and quickshell.
#
#   check.sh DEBDIR REPO
set -euo pipefail
debs=$(cd "$1" && pwd)
repo=$(cd "$2" && pwd)
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y "$debs"/*.deb qt6-declarative-dev-tools fontconfig
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
quickshell --version

fc-list | grep -i lucide
fc-list | grep -i 'Symbols Nerd Font'

# A difference is something the install step dropped or changed. Sorted,
# since qmllint's warning order within a file is not stable between runs.
qml=$(echo /usr/lib/*/qt6/qml)
lint() { (cd "$1" && /usr/lib/qt6/bin/qmllint -I "$qml" --bare $(find . -name '*.qml' | sort)) 2>&1 || true; }
lint "$repo/shell" | sort > /tmp/repo.log
lint /usr/share/formalshell | sort > /tmp/installed.log
diff /tmp/repo.log /tmp/installed.log
# Nothing may name a Qt module or type this release lacks. The shell's own
# types go unresolved under --bare too, so only names with no .qml file in
# the tree count.
missing=$( {
  sed -n 's/.*Failed to import \([A-Za-z][A-Za-z0-9.]*\).*/\1/p' /tmp/installed.log | grep -v '^qs\.' || true
  sed -n 's/.*: \([A-Za-z_][A-Za-z0-9_]*\) was not found\..*/\1/p' /tmp/installed.log | sort -u \
    | while read -r t; do [ -n "$(find /usr/share/formalshell -name "$t.qml" -print -quit)" ] || echo "$t"; done
} | sort -u )
if [ -n "$missing" ]; then
  echo "not available on this release: $missing" >&2
  exit 1
fi
echo CHECK_OK
