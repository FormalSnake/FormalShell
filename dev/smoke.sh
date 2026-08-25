#!/usr/bin/env bash
# Hyprland smoke rig (M41): the shell's runtime verification loop on the
# backend the redesign ships. Builds the shell, brings up an isolated
# Hyprland session, drives one leg's IPC inside it, screenshots with grim,
# tears the session down, then asserts that leg's own evidence.
#
# dev/smoke-niri.sh is the reference for what each leg proves and stays the
# richer script until M46 deletes the niri backend. Legs here: the base bar
# shot, --dump, --menu, --notify, --center, --panel <name>, --panel-at <n>,
# --console, --wallpaper, --lock.
# shot, --dump, --menu, --notify, --osd, --panel <name> (with --tooltip),
# --console.
#
# --osd drives the bottom-centre pill three ways off one timeline: a manual
# `osd volume` (osd-manual.png), a real `wpctl set-volume` (the
# AudioService.changed auto-show trigger, this run's own SMOKE_OK frame),
# then `osd brightness` (osd-brightness.png). The VM has a pipewire null
# sink but no backlight device, so the brightness frame proves the surface
# renders that kind honestly (0%, empty track), not that hardware exists.
# The sink is set to a second value first, because pipewire outlives the
# session: re-setting an already-30% sink changes nothing, `changed` never
# fires, and the auto-show leg would photograph an empty screen.
#
# --tooltip rides on --panel <name>: after the panel's own frame is taken,
# it parks the pointer on the panel header's close button (wlrctl, a real
# zwlr_virtual_pointer_v1 client, this rig's only synthetic pointer) and
# proves the tooltip both maps and anchors there. `hyprctl -j layers` is
# dumped either side of the park, and the formalshell:tooltip namespace has
# to be absent before and present after: a tooltip that still suppressed
# itself under an open panel (the pre-M44 rule) would leave the second dump
# looking like the first.
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
center_mode=false
panel_mode=false
panel_name=""
panel_at_mode=false
panel_at_index=""
osd_mode=false
panel_mode=false
panel_name=""
tooltip_mode=false
console_mode=false
wallpaper_mode=false
lock_mode=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) dump_mode=true; shift ;;
    --menu) menu_mode=true; shift ;;
    --notify) notify_mode=true; shift ;;
    --center) center_mode=true; shift ;;
    --panel) panel_mode=true; panel_name="${2:-}"; shift 2 ;;
    --panel-at) panel_at_mode=true; panel_at_index="${2:-}"; shift 2 ;;
    --console) console_mode=true; shift ;;
    --wallpaper) wallpaper_mode=true; shift ;;
    --lock) lock_mode=true; shift ;;
    --osd) osd_mode=true; shift ;;
    --tooltip) tooltip_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--menu] [--notify] [--center] [--osd] [--panel <name> [--tooltip]] [--panel-at <n>] [--console] [--wallpaper] [--lock]" >&2; exit 1 ;;
  esac
done

if $panel_mode && [ -z "$panel_name" ]; then
  echo "usage: $0 --panel <name>" >&2; exit 1
fi

# The default right region (Bar/layout.js's DEFAULT_LAYOUT) in order, with
# the cells that open no panel dropped (tray, bell, indicators). This run
# writes no bar.layout, so `panel toggleAt <n>` has to land on the nth of
# these, which is the assertion below.
panel_at_expected=""
panel_at_defaults=(power audio network bluetooth weather)
if $panel_at_mode; then
  case "$panel_at_index" in
    [1-9]) ;;
    *) echo "usage: $0 --panel-at <n>, 1..${#panel_at_defaults[@]}" >&2; exit 1 ;;
  esac
  if [ "$panel_at_index" -gt "${#panel_at_defaults[@]}" ]; then
    echo "usage: $0 --panel-at <n>, the default right region has only ${#panel_at_defaults[@]} panel cells" >&2; exit 1
  fi
  panel_at_expected="${panel_at_defaults[$((panel_at_index - 1))]}"
fi

# The tooltip leg anchors to a panel header's own close button, so it has
# nothing to park on without a panel open.
if $tooltip_mode && ! $panel_mode; then
  echo "usage: $0 --panel <name> --tooltip" >&2; exit 1
fi

# Only the base leg gets the focused fixture window: every other leg's own
# screenshot exists to show a summoned surface instead, the same split
# dev/smoke-niri.sh draws.
fixture_window_mode=true
if $dump_mode || $menu_mode || $notify_mode || $center_mode || $osd_mode || $panel_mode \
  || $panel_at_mode || $console_mode || $wallpaper_mode || $lock_mode; then
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

if $notify_mode || $center_mode; then
  if command -v notify-send >/dev/null 2>&1; then
    notify_send_bin=$(command -v notify-send)
  else
    notify_send_bin=$(nix build --no-link --print-out-paths 'nixpkgs#libnotify^out')/bin/notify-send
  fi
fi

if $tooltip_mode; then
  if command -v wlrctl >/dev/null 2>&1; then
    wlrctl_bin=$(command -v wlrctl)
  else
    wlrctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#wlrctl^out')/bin/wlrctl
  fi
fi

if $osd_mode; then
  if command -v wpctl >/dev/null 2>&1; then
    wpctl_bin=$(command -v wpctl)
  else
    wpctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#wireplumber^out')/bin/wpctl
  fi
fi

if $fixture_window_mode || $wallpaper_mode; then
  if command -v convert >/dev/null 2>&1; then
    convert_bin=convert
  else
    convert_bin="nix run nixpkgs#imagemagick -- convert"
  fi
fi

# A real virtual-keyboard-unstable-v1 client. LockIpc deliberately has no
# "type this password" verb (see its header), so the only way to prove the
# unlock path is to actually type into it.
if $lock_mode; then
  if command -v wtype >/dev/null 2>&1; then
    wtype_bin=$(command -v wtype)
  else
    wtype_bin=$(nix build 'nixpkgs#wtype^out' --no-link --print-out-paths)/bin/wtype
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
menu_root_path="$shot_dir/menu-root.png"
toasts_expanded_path="$shot_dir/toasts-expanded.png"
toasts_expand_status_path="$shot_dir/toasts-expand-status.txt"
center_path="$shot_dir/center.png"
center_status_before_path="$shot_dir/center-status-before.json"
center_status_open_path="$shot_dir/center-status-open.json"
center_status_closed_path="$shot_dir/center-status-closed.json"
center_dismiss_one_path="$shot_dir/center-dismiss-one.txt"
panel_open_path="$shot_dir/panel-open.txt"
panel_state_path="$shot_dir/panel-state.txt"
panel_at_toggle_path="$shot_dir/panel-at-toggle.txt"
panel_at_state_path="$shot_dir/panel-at-state.txt"
panel_at_path="$shot_dir/panel-at.json"
panel_at_shot_path="$shot_dir/panel-at.png"
osd_manual_path="$shot_dir/osd-manual.png"
osd_brightness_path="$shot_dir/osd-brightness.png"
panel_open_path="$shot_dir/panel-open.txt"
panel_state_path="$shot_dir/panel-state.txt"
tooltip_dispatch_path="$shot_dir/tooltip-dispatch.txt"
tooltip_layers_before_path="$shot_dir/tooltip-layers-before.json"
tooltip_layers_after_path="$shot_dir/tooltip-layers-after.json"
tooltip_path="$shot_dir/panel-tooltip.png"
console_status_open_path="$shot_dir/console-status-open.json"
console_status_parked_path="$shot_dir/console-status-parked.json"
console_status_return_path="$shot_dir/console-status-return.json"
console_open_path="$shot_dir/console-open.png"
console_parked_path="$shot_dir/console-parked.png"
console_return_path="$shot_dir/console-return.png"
theme_status_path="$shot_dir/theme-status.json"
wallpaper_get_path="$shot_dir/wallpaper-get.txt"
wallpaper_solid_path="$shot_dir/wallpaper-solid.png"
wallpaper_gradient_path="$shot_dir/wallpaper-gradient.png"
lock_locked_path="$shot_dir/lock-locked.png"
lock_typing_path="$shot_dir/lock-typing.png"
lock_error_path="$shot_dir/lock-error.png"
lock_unlocked_path="$shot_dir/lock-unlocked.png"
lock_islocked1_path="$shot_dir/lock-islocked-1.txt"
lock_islocked2_path="$shot_dir/lock-islocked-2.txt"
lock_status_path="$shot_dir/lock-status.json"
lock_call_rc_path="$shot_dir/lock-call-rc.txt"
lock_before_sleep_rc_path="$shot_dir/lock-before-sleep-rc.txt"
cfg="$shot_dir/hyprland.conf"

# lock-before-sleep's exit-0-always proof (spec §8), run BEFORE the session
# below ever starts a shell instance: the exact "no running instance" case a
# real lock-before-sleep systemd unit has to survive. A bare `qs ipc call
# lock lock` exits 255 here; the wrapper must not.
if $lock_mode; then
  lock_before_sleep_rc=0
  "$PWD/result/bin/formalshell-lock-before-sleep" || lock_before_sleep_rc=$?
  echo "$lock_before_sleep_rc" > "$lock_before_sleep_rc_path"
fi

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

# The retro dither is opt-in since M45, so the default run writes no
# `wallpaper.dither` key at all and the --wallpaper leg asserts the plain
# image reached the screen. SMOKE_WALLPAPER_DITHER=1 turns the opt-in on for
# one run and flips that leg's own assertion with it, so both sides of the
# setting are provable without a second flag.
wallpaper_dither=false
wallpaper_settings=""
if $wallpaper_mode && [ "${SMOKE_WALLPAPER_DITHER:-0}" = "1" ]; then
  wallpaper_dither=true
  wallpaper_settings=', "wallpaper": {"dither": true}'
fi

cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$console_settings$systemupdate_settings$wallpaper_settings}
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

# --wallpaper's two fixtures. 1920x1080, not something small: a source below
# the screen's own size never exercises Background/LockSurface's sourceSize
# cap at all (Qt only scales a decode down), so a fixture has to at least
# meet the screen to prove the cap engages.
#
# The first is monotone and the second a left-to-right gradient, and the pair
# is what makes the dither assertions readable in both directions: a solid
# source has one color whether or not a pass ran, so it can only ever prove
# flatness, while a gradient carries far more colors than any derived palette
# is allowed and so is the only one that can tell a plain image from a
# quantized one. The gradient is generated portrait and rotated so the ramp
# runs along the axis a full-width sample crosses.
if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  $convert_bin -size 1920x1080 xc:'#7a3fb0' "$wp_path"
  wp2_path="$shot_dir/wp2.png"
  $convert_bin -size 1080x1920 gradient:'#3fb07a-#0b2d20' -rotate 90 "$wp2_path"
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
"$grim_bin" "$menu_root_path" > /dev/null 2>&1
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

if $center_mode; then
  # A normal notify-send of this leg's own, then a long enough wait for the
  # model's 8s popup timeout to move it (and --notify's, when the two flags
  # combine) into the `pending` tier the centre lists. The wait is 14s rather
  # than the 9 that timeout alone would need: on the VM's software renderer
  # the shell reaches the bus several seconds after the drive script starts,
  # so a notification's own clock begins well after its notify-send. Combine with --notify
  # and the critical popup is still sticky in the popup layer, which is what
  # makes the suppression claim readable: Center.qml is a fixed
  # right-anchored full-height card wherever notifications.position puts the
  # toast stack, so Toasts.qml drops its whole stack for as long as the
  # centre is open and center.png shows the centre alone.
  #
  # `notifications status` brackets a showHistory round trip (the IPC
  # stand-in for the bell cell's own click, which calls the same
  # center.open()/close()), and `dismissOne` is asserted here rather than in
  # --notify: it drops the front toast, which would change what that leg's
  # own frames show.
  center_script="$shot_dir/center-drive.sh"
  write_script "$center_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$notify_send_bin" -u normal 'Second' 'World'
sleep 14
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_before_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications showHistory > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_open_path" 2>&1
"$grim_bin" "$center_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications dismissOne > "$center_dismiss_one_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications showHistory > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call notifications status > "$center_status_closed_path" 2>&1
if $osd_mode; then
  # Each trigger is screenshotted a second later, well inside the pill's
  # 1.6s auto-hide window, with enough gap between them that the previous
  # card is long gone before the next fires. The sleep-7 set is not
  # photographed: it exists so the sleep-9 one is always a real change, see
  # the header.
  osd_script="$shot_dir/osd-drive.sh"
  write_script "$osd_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call osd volume > /dev/null 2>&1
sleep 1
"$grim_bin" "$osd_manual_path" > /dev/null 2>&1
sleep 2
"$wpctl_bin" set-volume @DEFAULT_AUDIO_SINK@ 80% > /dev/null 2>&1
sleep 2
"$wpctl_bin" set-volume @DEFAULT_AUDIO_SINK@ 30% > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call osd brightness > /dev/null 2>&1
sleep 1
"$grim_bin" "$osd_brightness_path" > /dev/null 2>&1
EOF
fi

if $tooltip_mode; then
  # 1886x74 is the panel header's close button, and it is the same point
  # whatever the panel's width: Panel.qml pins the frame's RIGHT edge at
  # screen.width - barMargin, the Card insets by panelPadding, and the
  # button is controlHeight square against that inset edge, verticalCentred
  # in a header that starts panelPadding below a frame top of
  # barHeight + barMargin.
  #
  # wlrctl, not `hyprctl dispatch movecursor`: the dispatcher warps the
  # cursor (`hyprctl cursorpos` reads the target back, and `grim -c` draws
  # it on the button) without sending the surface under it a pointer enter,
  # so nothing hover-driven ever fires. wlrctl is a real
  # zwlr_virtual_pointer_v1 client, the same line the lock leg's wtype draws
  # for the keyboard. Its protocol is relative only, so the pointer is first
  # slammed into the top-left corner, which the compositor clamps, and the
  # target is then one move from a known origin.
  tooltip_script="$shot_dir/tooltip-drive.sh"
  write_script "$tooltip_script" <<EOF
#!/usr/bin/env bash
sleep 9
"$hyprctl_bin" -j layers > "$tooltip_layers_before_path" 2>&1
"$wlrctl_bin" pointer move -4000 -4000 > "$tooltip_dispatch_path" 2>&1
sleep 1
"$wlrctl_bin" pointer move 1886 74 >> "$tooltip_dispatch_path" 2>&1
sleep 2
"$hyprctl_bin" cursorpos >> "$tooltip_dispatch_path" 2>&1
"$hyprctl_bin" -j layers > "$tooltip_layers_after_path" 2>&1
"$grim_bin" -c "$tooltip_path" > /dev/null 2>&1
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

if $panel_at_mode; then
  # `panel toggleAt <n>` is the positional keybind (M42 D4, SUPER+CTRL+1..9
  # in the shipped Hyprland example). What needs proving is that the index
  # walked the resolved right region and stopped on a panel-bearing cell, so
  # `panel state` is read back beside the route's own answer: a toggleAt that
  # returned ok while opening the wrong panel would look identical here
  # without it. Its own grim frame, since the run's smoke.png is timestamped
  # by the time dev/vm.sh has pulled it.
  panel_at_script="$shot_dir/panel-at-drive.sh"
  write_script "$panel_at_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call panel toggleAt $panel_at_index > "$panel_at_toggle_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call panel state > "$panel_at_state_path" 2>&1
"$grim_bin" "$panel_at_shot_path" > /dev/null 2>&1
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

# The lock leg's own clock. It starts late under --wallpaper so the two
# wallpaper frames land first (see the lock drive script's comment).
lock_t0=5
if $wallpaper_mode; then
  lock_t0=16
fi

# --wallpaper: set the solid fixture, dump `theme status` (the matugen
# recolour), photograph it while it is still the only thing on screen, then
# crossfade to the gradient and photograph that. Two frames, because the two
# dither assertions below read opposite things and neither can be made off
# the other's source.
if $wallpaper_mode; then
  wallpaper_script="$shot_dir/wallpaper-drive.sh"
  write_script "$wallpaper_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call wallpaper set "$wp_path" > /dev/null 2>&1
sleep 3
"$qs_bin" ipc -p "$shell_path" call theme status > "$theme_status_path" 2>&1
sleep 2
"$grim_bin" "$wallpaper_solid_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call wallpaper set "$wp2_path" > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call wallpaper get > "$wallpaper_get_path" 2>&1
sleep 1
"$grim_bin" "$wallpaper_gradient_path" > /dev/null 2>&1
EOF
fi

# --lock's whole sequence lives in one script: everything in it is strictly
# ordered (lock, prove it over IPC, photograph, type a wrong password,
# photograph the error state, type the real one, photograph unlocked, prove
# the flip back over IPC) with nothing needing to interleave.
#
# grim, not any compositor-side capture: the frames have to be taken while
# the session is genuinely locked, and grim talks wlr-screencopy as an
# ordinary client.
#
# Held back to $lock_t0 under --wallpaper so the two wallpaper frames above
# are taken before the lock surface covers the output, which puts a real
# matugen-recoloured gradient behind the lock plate in the bargain.
if $lock_mode; then
  lock_script="$shot_dir/lock-drive.sh"
  write_script "$lock_script" <<EOF
#!/usr/bin/env bash
sleep $lock_t0
"$qs_bin" ipc -p "$shell_path" call lock lock > /dev/null 2>&1
echo \$? > "$lock_call_rc_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked1_path" 2>&1
sleep 3
"$grim_bin" "$lock_locked_path" > /dev/null 2>&1
sleep 2
"$wtype_bin" "wrong-password"
sleep 1
"$grim_bin" "$lock_typing_path" > /dev/null 2>&1
"$wtype_bin" -k Return
# The PAM round trip for a wrong password forks and execs through the whole
# auth stack, which on this VM is slower than a first glance suggests: a 2s
# buffer intermittently caught the frame before authError had updated.
sleep 5
"$grim_bin" "$lock_error_path" > /dev/null 2>&1
sleep 2
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
sleep 3
"$grim_bin" "$lock_unlocked_path" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call lock status > "$lock_status_path" 2>&1
EOF
fi

screenshot_delay=8
session_timeout=40
if $console_mode; then
  screenshot_delay=24
  session_timeout=60
elif $osd_mode; then
  # The auto-show trigger lands at 9, and this run's own SMOKE_OK frame is
  # the one it produces.
  screenshot_delay=10
fi
if $wallpaper_mode; then
  screenshot_delay=16
  session_timeout=50
fi
if $lock_mode; then
  screenshot_delay=$((lock_t0 + 21))
  session_timeout=$((lock_t0 + 45))
fi
if $center_mode; then
  # center-drive.sh's own last status dump lands at 23s; this run's generic
  # smoke.png is taken after it, showing the session with the centre closed
  # again and the front toast gone.
  screenshot_delay=25
  session_timeout=70
fi
tail_gap=1
if $menu_mode; then
  # menu-finish.sh's own read-back lands at 10, so the session has to
  # outlive that, not just the screenshot.
  tail_gap=4
elif $osd_mode; then
  # The brightness frame lands at 14.
  tail_gap=5
elif $tooltip_mode; then
  # The tooltip frame lands at 12, a beat past the card's 400ms delay.
  tail_gap=8
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
  if $center_mode; then
    echo "exec-once = bash $center_script"
  fi
  if $osd_mode; then
    echo "exec-once = bash $osd_script"
  fi
  if $panel_mode; then
    echo "exec-once = bash $panel_script"
  fi
  if $panel_at_mode; then
    echo "exec-once = bash $panel_at_script"
  fi
  if $tooltip_mode; then
    echo "exec-once = bash $tooltip_script"
  fi
  if $console_mode; then
    echo "exec-once = bash $console_script"
  fi
  if $wallpaper_mode; then
    echo "exec-once = bash $wallpaper_script"
  fi
  if $lock_mode; then
    echo "exec-once = bash $lock_script"
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
  # The run's own smoke.png lands in select mode, whose three option rows
  # carry no route icons and no breadcrumb path. This second frame is the
  # root level, where the row icons and the tree's own chrome are. Printed
  # before the selection read-back, whose `cat` has no trailing newline and
  # would otherwise swallow this line's own start-of-line anchor.
  if [ ! -f "$menu_root_path" ]; then
    fail "no root-level menu screenshot produced"
  fi
  echo "SMOKE_MENU_ROOT $menu_root_path"
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

if $center_mode; then
  for f in "$center_status_before_path" "$center_status_open_path" "$center_status_closed_path"; do
    if [ -s "$f" ]; then
      cat "$f"; echo
    else
      fail "no notifications status produced at $f"
    fi
  done
  # "pending":0 would mean the expired notify-sends never reached the tier
  # the bell cell counts, and the summon would have shown an empty list.
  if grep -q '"pending":0,' "$center_status_before_path"; then
    fail "pending count was zero before the centre summon: $(cat "$center_status_before_path")"
  fi
  if ! grep -q '"centerOpen":false' "$center_status_before_path"; then
    fail "centre reported open before the summon: $(cat "$center_status_before_path")"
  fi
  if ! grep -q '"centerOpen":true' "$center_status_open_path"; then
    fail "showHistory did not open the centre: $(cat "$center_status_open_path")"
  fi
  if ! grep -q '"centerOpen":false' "$center_status_closed_path"; then
    fail "second showHistory did not close the centre: $(cat "$center_status_closed_path")"
  fi
  if [ ! -s "$center_dismiss_one_path" ]; then
    fail "no notifications dismissOne answer produced"
  fi
  cat "$center_dismiss_one_path"
  if $notify_mode; then
    # --notify's critical toast is sticky (expiresAt 0), so it is still the
    # only thing in the popup tier when dismissOne runs, and the tier has to
    # be empty afterwards.
    if ! grep -q "^ok$" "$center_dismiss_one_path"; then
      fail "dismissOne did not drop the sticky critical toast, got: $(cat "$center_dismiss_one_path")"
    fi
    if ! grep -q '"popups":0' "$center_status_closed_path"; then
      fail "a toast survived dismissOne: $(cat "$center_status_closed_path")"
    fi
  else
    # Run alone, every popup this leg fired has expired into pending by the
    # time dismissOne runs, and an empty popup tier answers `none` rather
    # than erroring.
    if ! grep -q "^none$" "$center_dismiss_one_path"; then
      fail "dismissOne on an empty popup tier did not answer none, got: $(cat "$center_dismiss_one_path")"
    fi
  fi
  if [ ! -f "$center_path" ]; then
    fail "no notification centre screenshot produced"
  fi
  echo "SMOKE_CENTER $center_path"
fi

if $osd_mode; then
  if [ ! -f "$osd_manual_path" ]; then
    fail "no osd-manual screenshot produced"
  fi
  echo "SMOKE_OSD_MANUAL $osd_manual_path"
  if [ ! -f "$osd_brightness_path" ]; then
    fail "no osd-brightness screenshot produced"
  fi
  echo "SMOKE_OSD_BRIGHTNESS $osd_brightness_path"
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

if $panel_at_mode; then
  if [ ! -s "$panel_at_toggle_path" ] || [ ! -s "$panel_at_state_path" ]; then
    fail "panel toggleAt $panel_at_index produced no result"
  fi
  printf '{"n":%s,"toggleAt":"%s","state":"%s","expected":"%s"}\n' \
    "$panel_at_index" "$(cat "$panel_at_toggle_path")" "$(cat "$panel_at_state_path")" "$panel_at_expected" \
    > "$panel_at_path"
  cat "$panel_at_path"
  if ! grep -q "^ok$" "$panel_at_toggle_path"; then
    fail "panel toggleAt $panel_at_index did not answer ok, got: $(cat "$panel_at_toggle_path")"
  fi
  if ! grep -q "^$panel_at_expected$" "$panel_at_state_path"; then
    fail "panel toggleAt $panel_at_index opened '$(cat "$panel_at_state_path")', expected '$panel_at_expected'"
  fi
  if [ ! -f "$panel_at_shot_path" ]; then
    fail "no panel-at screenshot produced"
  fi
  echo "SMOKE_PANEL_AT $panel_at_shot_path"
fi

if $tooltip_mode; then
  for f in "$tooltip_layers_before_path" "$tooltip_layers_after_path"; do
    if [ ! -s "$f" ]; then
      fail "no layer dump produced at $f"
    fi
  done
  # The surface does not exist at all until a cell's own lazy Loader arms
  # it, so its absence here is what makes the second dump mean something.
  if grep -q 'formalshell:tooltip' "$tooltip_layers_before_path"; then
    fail "a tooltip layer surface was already mapped before the pointer parked on anything"
  fi
  if ! grep -q 'formalshell:tooltip' "$tooltip_layers_after_path"; then
    echo "--- pointer moves, then cursorpos ---" >&2
    cat "$tooltip_dispatch_path" >&2 2>/dev/null || true
    echo "--- layer namespaces after the park ---" >&2
    grep -o '"namespace": "[^"]*"' "$tooltip_layers_after_path" >&2 || true
    fail "no formalshell:tooltip layer surface after parking the pointer on the panel header's close button"
  fi
  # Printed on the happy path too: it is the only evidence of WHERE the
  # pointer ended up, which the frame alone cannot be trusted for.
  cat "$tooltip_dispatch_path" 2>/dev/null || true
  if [ ! -f "$tooltip_path" ]; then
    fail "no panel-tooltip screenshot produced"
  fi
  echo "SMOKE_TOOLTIP $tooltip_path"
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

if $wallpaper_mode; then
  if [ ! -s "$theme_status_path" ]; then
    fail "no theme status produced"
  fi
  cat "$theme_status_path"; echo
  if [ ! -s "$wallpaper_get_path" ] || ! grep -qF "$wp2_path" "$wallpaper_get_path"; then
    fail "wallpaper get did not report the second wallpaper. Got: $(cat "$wallpaper_get_path" 2>/dev/null)"
  fi
  for f in "$wallpaper_solid_path" "$wallpaper_gradient_path"; do
    [ -f "$f" ] || fail "no wallpaper screenshot produced at $f"
  done

  # Reads whole pixels out of a cropped patch. The trailing [,)] tolerates an
  # alpha component, which grim's PNG may or may not carry; a pattern
  # anchored on ")" would silently parse nothing.
  read_patch() {
    $convert_bin "$1" -crop "$2" +repage txt:- 2>/dev/null \
      | sed -n 's/^[0-9]*,[0-9]*: (\([0-9]*\),\([0-9]*\),\([0-9]*\)[,)].*/\1 \2 \3/p'
  }

  # Half one, and the same claim whether or not the pass ran: a monotone
  # source's own color is its whole derived palette, so every cell matches an
  # entry exactly and nothing has a second-nearest to dither against. A 64x64
  # patch of bare wallpaper, well clear of the bar, must be #7a3fb0
  # (122,63,176) and nothing else. This is the owner's 2026-08-12 report as
  # an assertion: the posterize grid that preceded the derived palette
  # speckled exactly here.
  wallpaper_solid_pixels=$(read_patch "$wallpaper_solid_path" 64x64+100+500)
  if [ -z "$wallpaper_solid_pixels" ]; then
    fail "could not read any pixel out of the solid-wallpaper patch"
  fi
  wallpaper_solid_off=$(printf '%s\n' "$wallpaper_solid_pixels" \
    | awk '{ if ($1 != 122 || $2 != 63 || $3 != 176) { print; exit } }')
  if [ -n "$wallpaper_solid_off" ]; then
    fail "monotone wallpaper pixel ($wallpaper_solid_off) is not the source color 7a3fb0"
  fi
  echo "SMOKE_WALLPAPER_FLAT 64x64 patch of the monotone wallpaper is 7a3fb0 end to end"
  echo "SMOKE_WALLPAPER_SOLID $wallpaper_solid_path"

  # Half two, and the half that reads the setting: a full-width strip of the
  # gradient crosses the whole ramp. With the pass off (M45's default, and
  # what this run's settings.json leaves unset) the strip has to carry far
  # more colors than any derived palette is allowed, which is what proves the
  # plain image reached the screen. With SMOKE_WALLPAPER_DITHER=1 the same
  # strip has to land inside the palette cap instead, and carry more than a
  # couple of colors, which is what proves the opt-in still quantizes AND
  # dithers. Read as whole rows because the strip spans every column; a small
  # square could legitimately sit inside one flat palette cell.
  wallpaper_patch_pixels=$(read_patch "$wallpaper_gradient_path" 1920x40+0+500)
  if [ -z "$wallpaper_patch_pixels" ]; then
    fail "could not read any pixel out of the gradient-wallpaper patch"
  fi
  wallpaper_patch_colors=$(printf '%s\n' "$wallpaper_patch_pixels" | sort -u | wc -l | tr -d ' ')
  if $wallpaper_dither; then
    if [ "${wallpaper_patch_colors:-0}" -lt 3 ]; then
      fail "wallpaper.dither is on and the gradient strip carries only $wallpaper_patch_colors color(s), so nothing dithered"
    fi
    if [ "$wallpaper_patch_colors" -gt 6 ]; then
      fail "wallpaper.dither is on and the gradient strip carries $wallpaper_patch_colors colors, more than the 6-entry derived palette allows, so the pass did not quantize"
    fi
    echo "SMOKE_WALLPAPER_DITHER $wallpaper_patch_colors palette colors across a 1920x40 strip, wallpaper.dither on"
  else
    if [ "${wallpaper_patch_colors:-0}" -le 16 ]; then
      fail "wallpaper.dither is off and the gradient strip carries only $wallpaper_patch_colors colors, so something quantized it anyway"
    fi
    echo "SMOKE_WALLPAPER_PLAIN $wallpaper_patch_colors distinct colors across a 1920x40 strip, wallpaper.dither off"
  fi
  echo "SMOKE_WALLPAPER_GRADIENT $wallpaper_gradient_path"
fi

if $lock_mode; then
  if [ ! -s "$lock_before_sleep_rc_path" ] || ! grep -q "^0$" "$lock_before_sleep_rc_path"; then
    fail "formalshell-lock-before-sleep did not exit 0 with no shell instance running. Got: $(cat "$lock_before_sleep_rc_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_call_rc_path" ] || ! grep -q "^0$" "$lock_call_rc_path"; then
    fail "lock lock IPC call exited non-zero. Got: $(cat "$lock_call_rc_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_islocked1_path" ] || ! grep -q "^true$" "$lock_islocked1_path"; then
    fail "lock isLocked did not report true right after lock(). Got: $(cat "$lock_islocked1_path" 2>/dev/null)"
  fi
  for f in "$lock_locked_path" "$lock_typing_path" "$lock_error_path" "$lock_unlocked_path"; do
    [ -f "$f" ] || fail "no lock screenshot produced at $f"
  done
  echo "SMOKE_LOCK_LOCKED $lock_locked_path"
  echo "SMOKE_LOCK_TYPING $lock_typing_path"
  echo "SMOKE_LOCK_ERROR $lock_error_path"
  echo "SMOKE_LOCK_UNLOCKED $lock_unlocked_path"
  if [ ! -s "$lock_islocked2_path" ] || ! grep -q "^false$" "$lock_islocked2_path"; then
    fail "lock isLocked did not flip back to false after the real password. Got: $(cat "$lock_islocked2_path" 2>/dev/null)"
  fi
  if [ ! -s "$lock_status_path" ]; then
    fail "no lock status produced"
  fi
  cat "$lock_status_path"; echo
  if ! grep -q '"locked":false' "$lock_status_path"; then
    fail "lock status did not report locked:false after unlock. Got: $(cat "$lock_status_path")"
  fi
  # The swappable-locker half (M45 D2): this run writes no `lock.command`, so
  # the built-in surface is the one that came up and `external` has to say so.
  if ! grep -q '"external":false' "$lock_status_path"; then
    fail "lock status did not report external:false with no lock.command set. Got: $(cat "$lock_status_path")"
  fi
  # A locked frame and an unlocked one cannot be the same picture. The
  # cheapest guard there is against a leg that photographed the desktop four
  # times while every IPC answer stayed perfectly plausible.
  if cmp -s "$lock_locked_path" "$lock_unlocked_path"; then
    fail "lock-locked and lock-unlocked screenshots are byte-identical: the lock surface never mapped"
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
