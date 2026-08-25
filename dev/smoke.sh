#!/usr/bin/env bash
# Hyprland smoke rig (M41): the shell's runtime verification loop on the
# backend the redesign ships. Builds the shell, brings up an isolated
# Hyprland session, drives one leg's IPC inside it, screenshots with grim,
# tears the session down, then asserts that leg's own evidence.
#
# dev/smoke-niri.sh is the reference for what each leg proves and stays the
# richer script until M46 deletes the niri backend. Legs here: the base bar
# shot, --dump, --menu, --notify, --panel <name>, --console.
#
# Two ways the session comes up, decided by what the machine can actually
# do (render_node_present and vkms_card_device below), never by a flag:
#   nested  the ordinary case and the only one a real host takes: Hyprland
#           is a Wayland client of the running session. aquamarine's wayland
#           backend needs the parent to advertise zwp_linux_dmabuf_v1, and
#           it allocates from the DRM render node that feedback names.
#   vkms    the mac VM rig, which has neither: its parent is a pixman
#           wlroots session on a guest with no GPU at all, so nesting dies
#           at CBackend::create() ("Missing protocols", then "no allocator
#           available"). Hyprland instead takes the software KMS card the
#           kernel's vkms module draws, pinned by AQ_DRM_DEVICES. The branch
#           is gated on that card's sysfs device really being vkms, so it
#           can never take a real GPU out from under a real session, and
#           opening it unprivileged needs seatd (nix/testvm.nix).
#
# D-Bus isolation (M5 hard rule, same as dev/smoke-niri.sh): the whole
# Hyprland invocation runs under `dbus-run-session --`, giving the shell's
# NotificationServer a private session bus instead of the host's. The host's
# is owned by DMS, and acquiring org.freedesktop.Notifications on it would
# steal that name out from under the real desktop. Verified every run: the
# host's `busctl --user status org.freedesktop.Notifications` owner PID must
# be identical before and after.
#
# Host-session safety: the Hyprland invocation and everything it spawns runs
# under an isolated HOME/XDG_*_HOME, never this user's own. Without it the
# ThemeEngine re-executes the owner's real matugen post_hooks against the
# live desktop (observed 2026-07-27). XDG_RUNTIME_DIR stays the host's,
# since the session has to publish its sockets somewhere the drive scripts
# can reach; InstanceLock.qml keys its own socket on WAYLAND_DISPLAY for
# exactly that reason.
set -euo pipefail
cd "$(dirname "$0")/.."

dump_mode=false
menu_mode=false
notify_mode=false
panel_mode=false
panel_name=""
console_mode=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) dump_mode=true; shift ;;
    --menu) menu_mode=true; shift ;;
    --notify) notify_mode=true; shift ;;
    --panel) panel_mode=true; panel_name="${2:-}"; shift 2 ;;
    --console) console_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--menu] [--notify] [--panel <name>] [--console]" >&2; exit 1 ;;
  esac
done

if $panel_mode && [ -z "$panel_name" ]; then
  echo "usage: $0 --panel <name>" >&2; exit 1
fi

# Only the base leg gets the focused fixture window: every other leg's own
# screenshot exists to show a summoned surface instead, the same split
# dev/smoke-niri.sh draws.
fixture_window_mode=true
if $dump_mode || $menu_mode || $notify_mode || $panel_mode || $console_mode; then
  fixture_window_mode=false
fi

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell

if command -v Hyprland >/dev/null 2>&1; then
  hyprland_bin=Hyprland
else
  hyprland_bin="nix run nixpkgs#hyprland --"
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl_bin=$(command -v hyprctl)
else
  hyprctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#hyprland^out')/bin/hyprctl
fi

if command -v grim >/dev/null 2>&1; then
  grim_bin=$(command -v grim)
else
  grim_bin=$(nix build --no-link --print-out-paths 'nixpkgs#grim^out')/bin/grim
fi

if command -v qs >/dev/null 2>&1; then
  qs_bin=$(command -v qs)
else
  qs_bin=$(nix develop -c bash -c 'command -v qs')
fi

if $fixture_window_mode || $console_mode; then
  if command -v foot >/dev/null 2>&1; then
    foot_bin=$(command -v foot)
  else
    foot_bin=$(nix build --no-link --print-out-paths 'nixpkgs#foot^out')/bin/foot
  fi
fi

if $notify_mode; then
  if command -v notify-send >/dev/null 2>&1; then
    notify_send_bin=$(command -v notify-send)
  else
    notify_send_bin=$(nix build --no-link --print-out-paths 'nixpkgs#libnotify^out')/bin/notify-send
  fi
fi

if $fixture_window_mode; then
  if command -v convert >/dev/null 2>&1; then
    convert_bin=convert
  else
    convert_bin="nix run nixpkgs#imagemagick -- convert"
  fi
fi

shell_path=$(readlink -f result/share/formalshell)

# A dead Wayland socket file outlives its compositor (nothing left to unlink
# it), so a value read back out of the systemd user environment has to be
# checked against a live listener rather than mere existence.
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

host_wayland_display=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p')
restore_host_wayland_display() {
  if [ -n "$host_wayland_display" ]; then
    systemctl --user set-environment WAYLAND_DISPLAY="$host_wayland_display" 2>/dev/null || true
  else
    systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null || true
  fi
}
trap restore_host_wayland_display EXIT

# A render node is the cheap stand-in for "this machine can nest": both
# halves of aquamarine's wayland backend (the parent's dmabuf advertisement
# and the allocator opened from that feedback's main device) come from one,
# and no software path substitutes for it. A KMS-only card cannot allocate
# dumb buffers from a second, non-master process, which is exactly what a
# nested compositor is.
render_node_present() {
  for node in /dev/dri/renderD*; do
    [ -e "$node" ] && return 0
  done
  return 1
}

# The driver name is not readable off card*/device/driver (vkms sits on the
# faux bus, whose symlink says faux_driver), but the device path itself is
# /sys/devices/faux/vkms/..., which nothing else produces.
vkms_card_device() {
  for sysfs in /sys/class/drm/card[0-9]*; do
    [ -e "$sysfs/device" ] || continue
    case "$(readlink -f "$sysfs/device")" in
      */vkms*) echo "/dev/dri/$(basename "$sysfs")"; return 0 ;;
    esac
  done
  return 1
}

session_mode=""
vkms_device=""
if [ -n "$wayland_display" ] && render_node_present; then
  session_mode="nested"
elif vkms_device=$(vkms_card_device); then
  session_mode="vkms"
else
  echo "SMOKE_FAIL: no way to bring up Hyprland here: no live parent session with a DRM render node to nest in, and no vkms card to render on" >&2
  exit 1
fi

# D-Bus isolation check (see the header): captured now, compared against the
# same query once the session has torn down.
host_notifications_owner() {
  # `|| true`: busctl exits 1 with ENXIO when the name has no owner at all
  # (the VM rig's normal answer, it has no desktop bus owner). That is a
  # legitimate reply, not a connectivity failure, so it must not trip
  # pipefail here.
  busctl --user status org.freedesktop.Notifications 2>/dev/null | sed -n 's/^PID=//p' || true
}
host_notifications_owner_before=$(host_notifications_owner)

shot_dir=$(mktemp -d)
shot_path="$shot_dir/smoke.png"
shell_log_path="$shot_dir/shell.log"
hypr_log_path="$shot_dir/hyprland.log"
dump_path="$shot_dir/dump.json"
query_path="$shot_dir/query.json"
selection_path="$shot_dir/menu-selection.txt"
toasts_expanded_path="$shot_dir/toasts-expanded.png"
toasts_expand_status_path="$shot_dir/toasts-expand-status.txt"
panel_open_path="$shot_dir/panel-open.txt"
panel_state_path="$shot_dir/panel-state.txt"
console_status_open_path="$shot_dir/console-status-open.json"
console_status_parked_path="$shot_dir/console-status-parked.json"
console_status_return_path="$shot_dir/console-status-return.json"
console_open_path="$shot_dir/console-open.png"
console_parked_path="$shot_dir/console-parked.png"
console_return_path="$shot_dir/console-return.png"
cfg="$shot_dir/hyprland.conf"

# Isolated HOME for the Hyprland process and everything it spawns, see the
# host-session safety note in the header.
iso_home=$(mktemp -d)
mkdir -p "$iso_home/.config/formalshell" "$iso_home/.local/share/applications" \
  "$iso_home/.local/share/formalshell/calendar"

console_settings=""
if $console_mode; then
  # The quake console spawns a REAL terminal (the shell embeds no emulator),
  # so the fixture is foot on a known blue background announcing the app id
  # ConsoleService matches on. Absolute path: this argv is spawned by the
  # shell through the compositor, against the session's PATH.
  console_settings=', "console": {"command": ["'"$foot_bin"'", "--app-id=formalshell-console", "--override=colors.background=1f6feb", "--override=colors.foreground=f4f4f4", "sh", "-c", "echo FORMALSHELL QUAKE CONSOLE; sleep 600"], "appId": "formalshell-console", "share": 0.5}'
fi

# --panel systemupdate needs a real flake to read, and this repo is one: the
# panel parses flake.lock itself (no nix invocation), so pointing it here
# renders the actual input rows instead of the honest NO FLAKE cell. Only
# that leg gets the key, so every other run keeps proving the unset default.
# The upstream probes are the one part that needs network; a VM with none
# lands on NO NETWORK, which is an honest state and still shows the rows.
systemupdate_settings=""
if $panel_mode && [ "$panel_name" = "systemupdate" ]; then
  systemupdate_settings=', "systemUpdate": {"flakeDir": "'"$PWD"'"}'
fi

cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$console_settings$systemupdate_settings}
EOF

# The calendar leg's own events, dated at run time so the fixture never goes
# stale: --panel calendar's screenshot then proves real events render (the
# dot on today's day cell, the rows under the TODAY label) rather than just
# that the grid draws. Three of them, one all-day and two timed, since the
# rows sort all-day first and the rest chronologically and only a timed one
# prints a time column. Fixed hours rather than offsets from the run's own
# clock: an "in progress" window computed at run time would cross midnight
# on a late run and drop off today entirely. No other leg reads this file.
today_ics=$(date -u +%Y%m%d)
cat > "$iso_home/.local/share/formalshell/calendar/smoke-fixture.ics" <<EOF
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:smoke-fixture-1
SUMMARY:Smoke fixture event
DTSTART;VALUE=DATE:$today_ics
END:VEVENT
BEGIN:VEVENT
UID:smoke-fixture-2
SUMMARY:Smoke fixture standup
DTSTART:${today_ics}T091500
DTEND:${today_ics}T094500
END:VEVENT
BEGIN:VEVENT
UID:smoke-fixture-3
SUMMARY:Smoke fixture review
DTSTART:${today_ics}T143000
DTEND:${today_ics}T160000
END:VEVENT
END:VCALENDAR
EOF

# The fixture window's app id resolves against this entry, so ActiveWindow
# renders a real display name and a real themed icon rather than whatever
# the machine running the rig happens to have installed.
if $fixture_window_mode; then
  cat > "$iso_home/.local/share/applications/formalshell-smoke-iconic.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Iconic Test App
Exec=true
Icon=formalshell-smoke
EOF
  mkdir -p "$iso_home/.local/share/icons/hicolor/48x48/apps"
  $convert_bin -size 48x48 xc:'#CE5D97' "$iso_home/.local/share/icons/hicolor/48x48/apps/formalshell-smoke.png"
  # QIconLoader enumerates no directories at all without an index.theme, so
  # a bare PNG in the right place still resolves to no icon.
  cat > "$iso_home/.local/share/icons/hicolor/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=48x48/apps

[48x48/apps]
Size=48
Context=Applications
Type=Threshold
EOF
fi

# Every leg is a standalone script rather than an inline exec-once string:
# `menu select`'s JSON array argument would otherwise have to survive both
# this generator and Hyprland's own config parsing.
write_script() {
  local path="$1"
  cat > "$path"
  chmod +x "$path"
}

shell_start_script="$shot_dir/shell-start.sh"
write_script "$shell_start_script" <<EOF
#!/usr/bin/env bash
# LIBGL_ALWAYS_SOFTWARE: on the vkms card the compositor advertises dmabuf
# with a main device Mesa cannot open for a client ("failed to get driver
# name for fd -1"), and Qt's EGL init takes the whole shell down with it.
# Forcing the software driver puts the shell back on the wl_shm/llvmpipe
# path it already renders on under niri. Scoped to this process: Hyprland's
# own EGL runs on gbm over that same card and must keep doing so.
export LIBGL_ALWAYS_SOFTWARE=1
# Captured, not discarded: a shell that dies on a QML error at startup would
# otherwise fail every assertion below with no way to see why.
exec "$PWD/result/bin/formalshell" > "$shell_log_path" 2>&1
EOF

if $fixture_window_mode; then
  # Spawned through the compositor (hyprctl dispatch exec), so the window is
  # tracked from the moment it maps and dies with the session.
  fixture_script="$shot_dir/fixture-window.sh"
  write_script "$fixture_script" <<EOF
#!/usr/bin/env bash
sleep 2
"$hyprctl_bin" dispatch exec "$foot_bin --app-id=formalshell-smoke-iconic --title='formalshell smoke session' sh -c 'sleep 300'"
EOF
fi

if $dump_mode; then
  dump_script="$shot_dir/dump.sh"
  write_script "$dump_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call debug dump > "$dump_path" 2>&1
EOF
fi

if $menu_mode; then
  # `qs ipc call`'s CLI11 parser splits any positional argument that starts
  # with "[" and ends with "]" into several comma-joined arguments (its
  # vector-literal shorthand), so the select list carries a leading space to
  # defeat that check. JSON.parse tolerates the whitespace.
  menu_script="$shot_dir/menu-drive.sh"
  write_script "$menu_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query 'e' > "$query_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu select "Pick" ' ["a","b","c"]' tok1 > /dev/null 2>&1
EOF

  # Runs after the screenshot, never before: closing the surface first would
  # leave nothing to photograph. The close cancels the still-pending select,
  # and the state file is what proves the {cancelled:true} write happened.
  menu_finish_script="$shot_dir/menu-finish.sh"
  write_script "$menu_finish_script" <<EOF
#!/usr/bin/env bash
sleep 9
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
EOF
fi

if $notify_mode; then
  # `notifications expand on/off` is the rig's stand-in for hovering the
  # stack: there is no synthetic pointer here. The expanded frame lands a
  # beat after the toggle so the reflow has settled, and `expand off`
  # restores the collapsed pile the run's own smoke.png reads.
  notify_script="$shot_dir/notify-drive.sh"
  write_script "$notify_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$notify_send_bin" -u normal 'Test' 'Hello'
sleep 1
"$notify_send_bin" -u critical 'Crit' 'Now'
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications expand on > "$toasts_expand_status_path" 2>&1
sleep 1
"$grim_bin" "$toasts_expanded_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications expand off > /dev/null 2>&1
EOF
fi

if $panel_mode; then
  # No bar-cell click happened, so Panel.qml's anchorX stays unset and the
  # frame falls back under the bar's right region. The panel has no
  # auto-close, so it is still open for the run's own screenshot.
  panel_script="$shot_dir/panel-drive.sh"
  write_script "$panel_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call panel open "$panel_name" > "$panel_open_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call panel state > "$panel_state_path" 2>&1
EOF
fi

if $console_mode; then
  # The Hyprland-specific claim: the console parks on a special workspace
  # here where niri moves the window, and the same window id has to come
  # back across all three toggles. A console that closed and respawned its
  # terminal would produce three perfectly good frames and throw the
  # session away, which is the whole feature.
  console_script="$shot_dir/console-drive.sh"
  write_script "$console_script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_open_path" 2>&1
"$grim_bin" "$console_open_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_parked_path" 2>&1
"$grim_bin" "$console_parked_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call console toggle > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call console status > "$console_status_return_path" 2>&1
"$grim_bin" "$console_return_path" > /dev/null 2>&1
EOF
fi

screenshot_delay=8
session_timeout=40
if $console_mode; then
  screenshot_delay=24
  session_timeout=60
fi
tail_gap=1
if $menu_mode; then
  # menu-finish.sh's own read-back lands at 10, so the session has to
  # outlive that, not just the screenshot.
  tail_gap=4
fi

shot_script="$shot_dir/shot.sh"
write_script "$shot_script" <<EOF
#!/usr/bin/env bash
sleep $screenshot_delay
"$grim_bin" "$shot_path" > "$shot_dir/grim.log" 2>&1
sleep $tail_gap
"$hyprctl_bin" dispatch exit
EOF

{
  # Pinned in both session modes: the vkms connector otherwise comes up
  # 1024x768 at scale 2, and a nested window takes aquamarine's own default
  # rather than a size the bar is worth reading at.
  echo "monitor = , 1920x1080@60, 0x0, 1"
  echo "general {"
  echo "    gaps_in = 0"
  echo "    gaps_out = 0"
  echo "    border_size = 0"
  echo "}"
  # DESIGN.md: nothing in the shell blurs anything, and a compositor blur
  # behind the bar's own transparent strip is exactly the frame this rig
  # exists to catch.
  echo "decoration {"
  echo "    rounding = 0"
  echo "    blur {"
  echo "        enabled = false"
  echo "    }"
  echo "}"
  echo "animations {"
  echo "    enabled = false"
  echo "}"
  # disable_watchdog_warning: without start-hyprland (a watchdog wrapper this
  # rig has no use for) Hyprland posts a red full-width notification across
  # the top of the screen for 15s, which is exactly where the bar is.
  echo "misc {"
  echo "    disable_watchdog_warning = true"
  echo "    disable_hyprland_logo = true"
  echo "    disable_splash_rendering = true"
  echo "    force_default_wallpaper = 0"
  echo "    disable_autoreload = true"
  echo "}"
  # suppress_errors: Hyprland's error overlay is a full-width banner across
  # the top of the screen, which is where the bar is. It renders over the
  # exact thing every leg here photographs.
  echo "debug {"
  echo "    suppress_errors = true"
  echo "    disable_logs = false"
  echo "    enable_stdout_logs = true"
  echo "}"
  echo "exec-once = bash $shell_start_script"
  if $fixture_window_mode; then
    echo "exec-once = bash $fixture_script"
  fi
  if $dump_mode; then
    echo "exec-once = bash $dump_script"
  fi
  if $menu_mode; then
    echo "exec-once = bash $menu_script"
    echo "exec-once = bash $menu_finish_script"
  fi
  if $notify_mode; then
    echo "exec-once = bash $notify_script"
  fi
  if $panel_mode; then
    echo "exec-once = bash $panel_script"
  fi
  if $console_mode; then
    echo "exec-once = bash $console_script"
  fi
  echo "exec-once = bash $shot_script"
} > "$cfg"

session_env=(
  "HOME=$iso_home"
  "XDG_CONFIG_HOME=$iso_home/.config"
  "XDG_STATE_HOME=$iso_home/.local/state"
  "XDG_DATA_HOME=$iso_home/.local/share"
  "XDG_DATA_DIRS=$iso_home/.local/share"
  "XDG_CACHE_HOME=$iso_home/.cache"
)
if [ "$session_mode" = "nested" ]; then
  session_env+=("WAYLAND_DISPLAY=$wayland_display")
else
  # Unset, not empty: aquamarine reads WAYLAND_DISPLAY's presence, and an
  # empty value still sends it down the wayland backend, which then fails
  # to connect at all.
  session_env+=("AQ_DRM_DEVICES=$vkms_device")
  unset WAYLAND_DISPLAY
fi

echo "session mode: $session_mode${vkms_device:+ ($vkms_device)}"

# -k 10 force-kills 10s after the initial SIGTERM: Hyprland's SIGTERM
# handler can hang instead of exiting, and a stuck session would sit on the
# card (or on the host's screen) indefinitely.
env "${session_env[@]}" dbus-run-session -- \
  timeout -k 10 "$session_timeout" $hyprland_bin --config "$cfg" > "$hypr_log_path" 2>&1 || true

host_notifications_owner_after=$(host_notifications_owner)
if [ "$host_notifications_owner_before" != "$host_notifications_owner_after" ]; then
  echo "SMOKE_FAIL: host org.freedesktop.Notifications owner PID changed ($host_notifications_owner_before -> $host_notifications_owner_after), the session's NotificationServer touched the host bus" >&2
  exit 1
fi

# Both logs, not just the compositor's: a session that came up fine with a
# shell that died at startup looks identical from the outside.
fail() {
  echo "SMOKE_FAIL: $1" >&2
  echo "--- hyprland log tail ---" >&2
  tail -20 "$hypr_log_path" >&2 2>/dev/null || true
  echo "--- shell log tail ---" >&2
  tail -20 "$shell_log_path" >&2 2>/dev/null || true
  exit 1
}

if $dump_mode; then
  if [ -s "$dump_path" ]; then
    cat "$dump_path"
  else
    fail "no debug dump produced"
  fi
fi

if $menu_mode; then
  if [ -s "$query_path" ]; then
    cat "$query_path"
  else
    fail "no menu query result produced"
  fi
  if [ -s "$selection_path" ] && grep -q '"cancelled":true' "$selection_path"; then
    cat "$selection_path"
  else
    [ -f "$selection_path" ] && cat "$selection_path" >&2
    fail "menu close in select mode did not write {cancelled:true}"
  fi
fi

if $notify_mode; then
  echo "host org.freedesktop.Notifications owner PID unchanged: $host_notifications_owner_after"
  if [ ! -s "$toasts_expand_status_path" ]; then
    fail "no notifications expand status produced"
  fi
  cat "$toasts_expand_status_path"
  if ! grep -q "^on$" "$toasts_expand_status_path"; then
    fail "notifications expand on did not report on, got: $(cat "$toasts_expand_status_path")"
  fi
  if [ ! -f "$toasts_expanded_path" ]; then
    fail "no toasts-expanded screenshot produced"
  fi
  echo "SMOKE_TOASTS_EXPANDED $toasts_expanded_path"
fi

if $panel_mode; then
  if [ ! -s "$panel_open_path" ] || ! grep -q "^ok$" "$panel_open_path"; then
    fail "panel open $panel_name did not answer ok, got: $(cat "$panel_open_path" 2>/dev/null)"
  fi
  cat "$panel_open_path"
  # The claim the screenshot cannot make on its own: the shell's own
  # bookkeeping says this panel, and only this one, is the open one.
  if [ ! -s "$panel_state_path" ] || ! grep -q "^$panel_name$" "$panel_state_path"; then
    fail "panel state is not '$panel_name', got: $(cat "$panel_state_path" 2>/dev/null)"
  fi
  cat "$panel_state_path"
fi

if $console_mode; then
  for f in "$console_status_open_path" "$console_status_parked_path" "$console_status_return_path"; do
    if [ ! -s "$f" ]; then
      fail "no console status produced at $f"
    fi
    cat "$f"; echo
  done
  console_open_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_open_path")
  console_parked_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_parked_path")
  console_return_id=$(sed -n 's/.*"windowId":"\([^"]*\)".*/\1/p' "$console_status_return_path")
  if [ -z "$console_open_id" ]; then
    fail "console toggle opened no window. Got: $(cat "$console_status_open_path")"
  fi
  if ! grep -q '"visible":true' "$console_status_open_path"; then
    fail "console not reported visible after the first toggle. Got: $(cat "$console_status_open_path")"
  fi
  if ! grep -q '"visible":false' "$console_status_parked_path"; then
    fail "console still reported visible after the hide. Got: $(cat "$console_status_parked_path")"
  fi
  if [ "$console_parked_id" != "$console_open_id" ]; then
    fail "the parked console is not the window that was opened (open=$console_open_id parked=$console_parked_id)"
  fi
  if ! grep -q '"visible":true' "$console_status_return_path"; then
    fail "console not reported visible again after the third toggle. Got: $(cat "$console_status_return_path")"
  fi
  if [ "$console_return_id" != "$console_open_id" ]; then
    fail "the console that came back is a different window (open=$console_open_id return=$console_return_id)"
  fi
  for f in "$console_open_path" "$console_parked_path" "$console_return_path"; do
    if [ ! -f "$f" ]; then
      fail "no console screenshot produced at $f"
    fi
  done
  echo "SMOKE_CONSOLE_OPEN $console_open_path"
  echo "SMOKE_CONSOLE_PARKED $console_parked_path"
  echo "SMOKE_CONSOLE_RETURN $console_return_path"
  if cmp -s "$console_open_path" "$console_parked_path"; then
    fail "console-open and console-parked screenshots are byte-identical: the special workspace never left the screen"
  fi
fi

# A crashed shell still leaves a perfectly good screenshot of quickshell's
# own crash dialog, so the frame's existence proves nothing on its own.
if grep -q "has crashed" "$shell_log_path" 2>/dev/null; then
  fail "the shell crashed during the run"
fi

if [ -f "$shot_path" ]; then
  echo "SMOKE_OK $shot_path"
else
  fail "no screenshot produced"
fi
