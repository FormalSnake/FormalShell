#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
# With --dump, also calls the `debug` IPC target and cats the JSON reply.
set -euo pipefail
cd "$(dirname "$0")/.."

dump_mode=false
[ "${1:-}" = "--dump" ] && dump_mode=true

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell

if command -v niri >/dev/null 2>&1; then
  niri_bin=niri
else
  niri_bin="nix run nixpkgs#niri --"
fi

if command -v qs >/dev/null 2>&1; then
  qs_bin=qs
else
  qs_bin=$(nix develop -c bash -c 'command -v qs')
fi
shell_path=$(readlink -f result/share/formalshell)

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
dump_path="$shot_dir/dump.json"
cfg=$(mktemp -d)/config.kdl
{
  echo 'hotkey-overlay {'
  echo '    skip-at-startup'
  echo '}'
  echo "spawn-at-startup \"$PWD/result/bin/formalshell\""
  if $dump_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call debug dump > $dump_path 2>&1\""
  fi
  echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && niri msg action screenshot-screen --path $shot_dir/smoke.png && sleep 1 && niri msg action quit --skip-confirmation\""
} > "$cfg"

WAYLAND_DISPLAY="$wayland_display" timeout 30 $niri_bin --config "$cfg" || true

if $dump_mode; then
  if [ -s "$dump_path" ]; then
    cat "$dump_path"
  else
    echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
  fi
fi

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
