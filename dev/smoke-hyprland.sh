#!/usr/bin/env bash
# Nested-Hyprland smoke: mirrors dev/smoke-niri.sh for the second backend.
# Runs the built shell in an isolated nested Hyprland session, dumps compositor
# state via the `debug` IPC target, screenshots via grim, tears down.
set -euo pipefail
cd "$(dirname "$0")/.."

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell

if command -v Hyprland >/dev/null 2>&1; then
  hyprland_bin=Hyprland
else
  hyprland_bin="nix run nixpkgs#hyprland --"
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl_bin=hyprctl
else
  hyprctl_bin=$(nix eval --raw nixpkgs#hyprland.outPath)/bin/hyprctl
fi

if command -v grim >/dev/null 2>&1; then
  grim_bin=grim
else
  grim_bin=$(nix eval --raw nixpkgs#grim.outPath)/bin/grim
fi

if command -v qs >/dev/null 2>&1; then
  qs_bin=qs
else
  qs_bin=$(nix develop -c bash -c 'command -v qs')
fi
shell_path=$(readlink -f result/share/formalshell)

# The nested instance is a Wayland client of the host compositor (Hyprland's
# aquamarine backend falls back to its wayland backend when no DRM device is
# grantable, which is exactly the case here), so it needs the host's
# WAYLAND_DISPLAY. See dev/smoke-niri.sh for why this may need the fallback.
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
cfg=$(mktemp -d)/hyprland.conf
{
  echo "exec-once = $PWD/result/bin/formalshell"
  echo "exec-once = sh -c \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call debug dump > '$dump_path' 2>&1\""
  echo "exec-once = sh -c \"sleep 6 && '$grim_bin' '$shot_dir/smoke.png' > '$shot_dir/grim.log' 2>&1; sleep 1 && '$hyprctl_bin' dispatch exit\""
} > "$cfg"

# -k force-kills 10s after the initial SIGTERM: Hyprland's SIGTERM handler can
# hang instead of exiting cleanly (observed when the exit-dispatch exec-once
# itself failed), and a stuck nested compositor would otherwise sit on the
# host's screen indefinitely.
WAYLAND_DISPLAY="$wayland_display" timeout -k 10 30 $hyprland_bin --config "$cfg" || true

if [ -s "$dump_path" ]; then
  cat "$dump_path"
else
  echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
fi

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
