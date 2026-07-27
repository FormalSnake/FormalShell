#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
# With --dump, also calls the `debug` IPC target and cats the JSON reply.
# With --wallpaper, generates a solid-color test PNG, drives it through
# `wallpaper set` + `theme status` over IPC in-session before screenshotting,
# so the screenshot proves the background/bar actually recolored.
set -euo pipefail
cd "$(dirname "$0")/.."

dump_mode=false
wallpaper_mode=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) dump_mode=true; shift ;;
    --wallpaper) wallpaper_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--wallpaper]" >&2; exit 1 ;;
  esac
done

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

if $wallpaper_mode; then
  if command -v convert >/dev/null 2>&1; then
    convert_bin=convert
  else
    convert_bin="nix run nixpkgs#imagemagick -- convert"
  fi
fi
shell_path=$(readlink -f result/share/formalshell)

# The nested instance is a Wayland client of the host compositor, so it needs
# the host's WAYLAND_DISPLAY. This shell may not have it exported (e.g. a
# non-interactive session) even though the host session is up; fall back to
# asking the user systemd session, which niri-session always populates. The
# nested niri we're about to spawn also imports ITS OWN WAYLAND_DISPLAY into
# that same systemd environment on startup, so the fallback must reject a
# stale value left behind by an earlier nested run, and the host's value must
# be restored once this run tears down so later services (this script's next
# run, autostart.nix apps) don't inherit a dead display. A dead Wayland socket
# file can outlive its compositor (no listener left to unlink it on exit), so
# rejecting the fallback needs an actual liveness check, not just existence:
# `ss` only lists a unix socket path here while something still has it bound
# and listening.
wayland_socket_live() {
  ss -xl 2>/dev/null | awk -v p="$1" '$1 == "u_str" && $2 == "LISTEN" && $5 == p { found=1 } END { exit !found }'
}

wayland_display="${WAYLAND_DISPLAY:-}"
if [ -z "$wayland_display" ]; then
  fallback=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')
  if [ -n "$fallback" ] && wayland_socket_live "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$fallback"; then
    wayland_display="$fallback"
  fi
fi
if [ -z "$wayland_display" ]; then
  echo "SMOKE_FAIL: no live WAYLAND_DISPLAY found (host compositor not running?)" >&2
  exit 1
fi

host_wayland_display=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')
restore_host_wayland_display() {
  if [ -n "$host_wayland_display" ]; then
    systemctl --user set-environment WAYLAND_DISPLAY="$host_wayland_display" 2>/dev/null || true
  else
    systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null || true
  fi
}
trap restore_host_wayland_display EXIT

shot_dir=$(mktemp -d)
dump_path="$shot_dir/dump.json"
status_path="$shot_dir/status.json"
cfg=$(mktemp -d)/config.kdl

if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  $convert_bin -size 640x480 xc:'#7a3fb0' "$wp_path"
fi

{
  echo 'hotkey-overlay {'
  echo '    skip-at-startup'
  echo '}'
  echo "spawn-at-startup \"$PWD/result/bin/formalshell\""
  if $dump_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call debug dump > $dump_path 2>&1\""
  fi
  if $wallpaper_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc --any-display -p '$shell_path' call wallpaper set '$wp_path'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc --any-display -p '$shell_path' call theme status > $status_path 2>&1\""
  fi
  echo "spawn-at-startup \"sh\" \"-c\" \"sleep 8 && niri msg action screenshot-screen --path $shot_dir/smoke.png && sleep 1 && niri msg action quit --skip-confirmation\""
} > "$cfg"

WAYLAND_DISPLAY="$wayland_display" timeout 30 $niri_bin --config "$cfg" || true

if $dump_mode; then
  if [ -s "$dump_path" ]; then
    cat "$dump_path"
  else
    echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
  fi
fi

if $wallpaper_mode; then
  if [ -s "$status_path" ]; then
    cat "$status_path"
  else
    echo "SMOKE_FAIL: no theme status produced" >&2; exit 1
  fi
fi

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
