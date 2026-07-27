#!/usr/bin/env bash
# Nested-Hyprland smoke: mirrors dev/smoke-niri.sh for the second backend.
# Runs the built shell in an isolated nested Hyprland session, dumps compositor
# state via the `debug` IPC target, screenshots via grim, tears down.
#
# D-Bus isolation (M5 hard rule, see dev/smoke-niri.sh's header): the nested
# Hyprland invocation runs under `dbus-run-session --`, giving formalshell's
# NotificationServer a private session bus instead of the host's — the
# host's is owned by DMS, and NotificationServer acquiring
# org.freedesktop.Notifications on it would steal that name out from under
# the real desktop. Verified every run: the host's
# `busctl --user status org.freedesktop.Notifications` owner PID must be
# identical before and after.
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
# WAYLAND_DISPLAY. See dev/smoke-niri.sh for why this may need the fallback,
# why the fallback must be validated against a live socket, and why the host
# value must be restored once this run tears down.
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

# D-Bus isolation check (see the header comment): captured now, compared
# against the same query once the nested session has torn down.
host_notifications_owner() {
  # `|| true`: busctl exits 1 with ENXIO when the name has no owner at all
  # (e.g. no host desktop on the VM rig) — a legitimate answer, not a
  # connectivity failure, so it must not trip `set -e`/pipefail here.
  busctl --user status org.freedesktop.Notifications 2>/dev/null | sed -n 's/^PID=//p' || true
}
host_notifications_owner_before=$(host_notifications_owner)

shot_dir=$(mktemp -d)
dump_path="$shot_dir/dump.json"
cfg=$(mktemp -d)/hyprland.conf

# Isolated HOME for the nested Hyprland process and everything it spawns —
# see dev/smoke-niri.sh's host-session safety note: formalshell must never
# read/write this user's real matugen config or state dir during a smoke run.
iso_home=$(mktemp -d)
{
  echo "exec-once = $PWD/result/bin/formalshell"
  echo "exec-once = sh -c \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call debug dump > '$dump_path' 2>&1\""
  echo "exec-once = sh -c \"sleep 6 && '$grim_bin' '$shot_dir/smoke.png' > '$shot_dir/grim.log' 2>&1; sleep 1 && '$hyprctl_bin' dispatch exit\""
} > "$cfg"

# -k force-kills 10s after the initial SIGTERM: Hyprland's SIGTERM handler can
# hang instead of exiting cleanly (observed when the exit-dispatch exec-once
# itself failed), and a stuck nested compositor would otherwise sit on the
# host's screen indefinitely.
HOME="$iso_home" \
XDG_CONFIG_HOME="$iso_home/.config" \
XDG_STATE_HOME="$iso_home/.local/state" \
XDG_DATA_HOME="$iso_home/.local/share" \
XDG_CACHE_HOME="$iso_home/.cache" \
WAYLAND_DISPLAY="$wayland_display" dbus-run-session -- timeout -k 10 30 $hyprland_bin --config "$cfg" || true

host_notifications_owner_after=$(host_notifications_owner)
if [ "$host_notifications_owner_before" != "$host_notifications_owner_after" ]; then
  echo "SMOKE_FAIL: host org.freedesktop.Notifications owner PID changed ($host_notifications_owner_before -> $host_notifications_owner_after) — nested NotificationServer touched the host bus" >&2
  exit 1
fi

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
