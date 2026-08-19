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

# --console (M37): drives the quake console over three `console toggle` calls
# and screenshots each state. This is the Hyprland-specific claim — the
# console lives on a special workspace here and the compositor toggles that
# overlay, where niri moves the window — so the niri rig's own --console leg
# cannot make it.
console_mode=false
if [ "${1:-}" = "--console" ]; then
  console_mode=true
  shift
fi

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

if $console_mode; then
  if command -v foot >/dev/null 2>&1; then
    foot_bin=$(command -v foot)
  else
    foot_bin=$(nix build 'nixpkgs#foot^out' --no-link --print-out-paths)/bin/foot
  fi
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
console_status_open_path="$shot_dir/console-status-open.json"
console_status_parked_path="$shot_dir/console-status-parked.json"
console_status_return_path="$shot_dir/console-status-return.json"
console_open_path="$shot_dir/console-open.png"
console_parked_path="$shot_dir/console-parked.png"
console_return_path="$shot_dir/console-return.png"
cfg=$(mktemp -d)/hyprland.conf

# Isolated HOME for the nested Hyprland process and everything it spawns —
# see dev/smoke-niri.sh's host-session safety note: formalshell must never
# read/write this user's real matugen config or state dir during a smoke run.
iso_home=$(mktemp -d)

# The console fixture, same shape the niri rig uses: a real foot on a known
# blue background, told to announce the app id ConsoleService matches on.
session_seconds=30
if $console_mode; then
  mkdir -p "$iso_home/.config/formalshell"
  cat > "$iso_home/.config/formalshell/settings.json" <<SETTINGS
{"console": {"command": ["$foot_bin", "--app-id=formalshell-console", "--override=colors.background=1f6feb", "--override=colors.foreground=f4f4f4", "sh", "-c", "echo FORMALSHELL QUAKE CONSOLE; sleep 600"], "appId": "formalshell-console", "share": 0.5}}
SETTINGS

  console_drive_script="$shot_dir/console-drive.sh"
  cat > "$console_drive_script" <<DRIVE
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_open_path" 2>&1
"$grim_bin" "$console_open_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_parked_path" 2>&1
"$grim_bin" "$console_parked_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_return_path" 2>&1
"$grim_bin" "$console_return_path"
DRIVE
  chmod +x "$console_drive_script"
  session_seconds=60
fi

{
  echo "exec-once = $PWD/result/bin/formalshell"
  echo "exec-once = sh -c \"sleep 4 && '$qs_bin' ipc -p '$shell_path' call debug dump > '$dump_path' 2>&1\""
  if $console_mode; then
    echo "exec-once = bash $console_drive_script"
    echo "exec-once = sh -c \"sleep 22 && '$grim_bin' '$shot_dir/smoke.png' > '$shot_dir/grim.log' 2>&1; sleep 1 && '$hyprctl_bin' dispatch exit\""
  else
    echo "exec-once = sh -c \"sleep 6 && '$grim_bin' '$shot_dir/smoke.png' > '$shot_dir/grim.log' 2>&1; sleep 1 && '$hyprctl_bin' dispatch exit\""
  fi
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
WAYLAND_DISPLAY="$wayland_display" dbus-run-session -- timeout -k 10 "$session_seconds" $hyprland_bin --config "$cfg" || true

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

# The console leg's own claims: the same window id across all three dumps
# (parked means parked, not closed), visible flipping true/false/true, and
# two frames that actually differ.
if $console_mode; then
  for f in "$console_status_open_path" "$console_status_parked_path" "$console_status_return_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no console status produced at $f" >&2; exit 1
    fi
    cat "$f"; echo
  done
  console_open_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_open_path")
  console_parked_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_parked_path")
  console_return_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_return_path")
  if [ -z "$console_open_id" ]; then
    echo "SMOKE_FAIL: console toggle opened no window. Got: $(cat "$console_status_open_path")" >&2; exit 1
  fi
  if ! grep -q '"visible":true' "$console_status_open_path"; then
    echo "SMOKE_FAIL: console not reported visible after the first toggle. Got: $(cat "$console_status_open_path")" >&2; exit 1
  fi
  if ! grep -q '"visible":false' "$console_status_parked_path"; then
    echo "SMOKE_FAIL: console still reported visible after the hide. Got: $(cat "$console_status_parked_path")" >&2; exit 1
  fi
  if [ "$console_parked_id" != "$console_open_id" ]; then
    echo "SMOKE_FAIL: the hidden console is not the window that was opened (open=$console_open_id parked=$console_parked_id)" >&2; exit 1
  fi
  if ! grep -q '"visible":true' "$console_status_return_path"; then
    echo "SMOKE_FAIL: console not reported visible again after the third toggle. Got: $(cat "$console_status_return_path")" >&2; exit 1
  fi
  if [ "$console_return_id" != "$console_open_id" ]; then
    echo "SMOKE_FAIL: the console that came back is a different window (open=$console_open_id return=$console_return_id)" >&2; exit 1
  fi
  for f in "$console_open_path" "$console_parked_path" "$console_return_path"; do
    if [ ! -f "$f" ]; then
      echo "SMOKE_FAIL: no console screenshot produced at $f" >&2; exit 1
    fi
  done
  echo "SMOKE_CONSOLE_OPEN $console_open_path"
  echo "SMOKE_CONSOLE_PARKED $console_parked_path"
  echo "SMOKE_CONSOLE_RETURN $console_return_path"
  if cmp -s "$console_open_path" "$console_parked_path"; then
    echo "SMOKE_FAIL: console-open and console-parked screenshots are byte-identical: the special workspace never left the screen" >&2; exit 1
  fi
fi

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
