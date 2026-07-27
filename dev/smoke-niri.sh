#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
set -euo pipefail
cd "$(dirname "$0")/.."

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell

if command -v niri >/dev/null 2>&1; then
  niri_bin=niri
else
  niri_bin="nix run nixpkgs#niri --"
fi

# The nested instance is a Wayland client of the host compositor, so it needs
# the host's WAYLAND_DISPLAY. This shell may not have it exported (e.g. a
# non-interactive session) even though the host session is up; fall back to
# asking the user systemd session, which niri-session always populates.
wayland_display="${WAYLAND_DISPLAY:-}"
if [ -z "$wayland_display" ]; then
  wayland_display=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')
fi
if [ -z "$wayland_display" ]; then
  echo "SMOKE_FAIL: no WAYLAND_DISPLAY found (host compositor not running?)" >&2
  exit 1
fi

shot_dir=$(mktemp -d)
cfg=$(mktemp -d)/config.kdl
cat > "$cfg" <<EOF
hotkey-overlay {
    skip-at-startup
}
spawn-at-startup "$PWD/result/bin/formalshell"
spawn-at-startup "sh" "-c" "sleep 6 && niri msg action screenshot-screen --path $shot_dir/smoke.png && sleep 1 && niri msg action quit --skip-confirmation"
EOF

WAYLAND_DISPLAY="$wayland_display" timeout 30 $niri_bin --config "$cfg" || true

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
