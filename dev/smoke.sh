#!/usr/bin/env bash
# Hyprland smoke rig (M41): the shell's runtime verification loop on the
# backend the redesign ships. Builds the shell, brings up an isolated
# Hyprland session, drives the legs a run asked for inside it, screenshots
# with grim, tears the session down, then asserts each leg's own evidence.
#
# One file per leg under dev/smoke.d/, sourced from here, each owning its
# flag, fixture, drive script and assertions: dump, menu, notify, center,
# osd, panel (and tooltip, which rides on it), panel_at, console, wallpaper,
# lock, picker, clipboard, monitor, processes, hotcorner. What a leg proves
# is in its own header; dev/smoke.d/README.md is the file contract.
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
# D-Bus isolation (M5 hard rule): the whole
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
script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir/.."

# Both temp dirs exist before the leg files are sourced: a leg names its own
# artifacts off them at source time, so a leg that is off this run still has
# readable paths for the leg that coordinates with it.
shot_dir=$(mktemp -d)
iso_home=$(mktemp -d)

legs=()
active_legs=()
settings_extra=""
fixture_cleanup=""
screenshot_delay=8
session_timeout=40
tail_gap=1

leg_on() {
  local v="leg_${1}_on"
  [ "${!v:-false}" = true ]
}

leg_arg() {
  local v="leg_${1}_arg"
  printf '%s' "${!v:-}"
}

# Merged by max across the active legs, so a combination always outlives its
# slowest half.
leg_timing() {
  if [ "${1:-0}" -gt "$screenshot_delay" ]; then screenshot_delay="$1"; fi
  if [ "${2:-0}" -gt "$session_timeout" ]; then session_timeout="$2"; fi
  if [ "${3:-0}" -gt "$tail_gap" ]; then tail_gap="$3"; fi
}

settings_fragment() {
  settings_extra="$settings_extra$1"
}

# A line for the teardown script, run after the run's own frame and before
# the compositor exits.
add_cleanup() {
  if [ -n "$fixture_cleanup" ]; then
    fixture_cleanup="$fixture_cleanup
$1"
  else
    fixture_cleanup="$1"
  fi
}

# Every leg is a standalone script rather than an inline exec-once string:
# `menu select`'s JSON array argument would otherwise have to survive both
# this generator and Hyprland's own config parsing.
write_script() {
  local path="$1"
  cat > "$path"
  chmod +x "$path"
}

for leg_file in "$script_dir"/smoke.d/*.sh; do
  leg_name=$(basename "$leg_file" .sh)
  # shellcheck source=/dev/null
  . "$leg_file"
  legs+=("$leg_name")
done

# Sourcing is alphabetical; the flag list, the settings fragments, the
# exec-once lines and the results all follow leg_<name>_order instead.
leg_order_list() {
  local n v
  for n in "${legs[@]}"; do
    v="leg_${n}_order"
    printf '%s %s\n' "${!v:-500}" "$n"
  done | sort -k1,1n -k2,2
}
ordered=()
while read -r _ leg_name; do
  ordered+=("$leg_name")
done < <(leg_order_list)
legs=("${ordered[@]}")

usage() {
  local n v line=""
  for n in "${legs[@]}"; do
    v="leg_${n}_flag"
    line="$line [${!v}]"
  done
  echo "usage: $0$line" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  matched=false
  for leg_name in "${legs[@]}"; do
    flag_var="leg_${leg_name}_flag"
    flag_decl="${!flag_var}"
    [ "$1" = "${flag_decl%% *}" ] || continue
    matched=true
    eval "leg_${leg_name}_on=true"
    if [ "$flag_decl" = "${flag_decl%% *}" ]; then
      shift
    else
      [ $# -ge 2 ] || usage
      eval "leg_${leg_name}_arg=\$2"
      shift 2
    fi
    break
  done
  $matched || usage
done

for leg_name in "${legs[@]}"; do
  if leg_on "$leg_name"; then active_legs+=("$leg_name"); fi
done

for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_validate" >/dev/null; then "leg_${leg_name}_validate"; fi
done

# Only the base run gets the focused fixture window: every other leg's own
# screenshot exists to show a summoned surface instead. A leg that
# photographs the ordinary desktop
# anyway declares leg_<name>_fixture_window=keep.
fixture_window_mode=true
for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  keep_var="leg_${leg_name}_fixture_window"
  if [ "${!keep_var:-}" != "keep" ]; then fixture_window_mode=false; fi
done

git add -A >/dev/null 2>&1 || true   # flakes only see tracked files
nix build .#formalshell

# Resolved once, on demand: a leg names what it needs in leg_<name>_needs
# and the scaffold's own four are always resolved.
need_bin() {
  local name
  for name in "$@"; do
    [ -n "$name" ] || continue
    "need_${name//-/_}"
  done
}

need_hyprland() {
  if [ -z "${hyprland_bin:-}" ]; then
    if command -v Hyprland >/dev/null 2>&1; then
      hyprland_bin=Hyprland
    else
      hyprland_bin="nix run nixpkgs#hyprland --"
    fi
  fi
}

need_hyprctl() {
  if [ -z "${hyprctl_bin:-}" ]; then
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl_bin=$(command -v hyprctl)
    else
      hyprctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#hyprland^out')/bin/hyprctl
    fi
  fi
}

need_grim() {
  if [ -z "${grim_bin:-}" ]; then
    if command -v grim >/dev/null 2>&1; then
      grim_bin=$(command -v grim)
    else
      grim_bin=$(nix build --no-link --print-out-paths 'nixpkgs#grim^out')/bin/grim
    fi
  fi
}

need_qs() {
  if [ -z "${qs_bin:-}" ]; then
    if command -v qs >/dev/null 2>&1; then
      qs_bin=$(command -v qs)
    else
      qs_bin=$(nix develop -c bash -c 'command -v qs')
    fi
  fi
}

need_foot() {
  if [ -z "${foot_bin:-}" ]; then
    if command -v foot >/dev/null 2>&1; then
      foot_bin=$(command -v foot)
    else
      foot_bin=$(nix build --no-link --print-out-paths 'nixpkgs#foot^out')/bin/foot
    fi
  fi
}

need_notify_send() {
  if [ -z "${notify_send_bin:-}" ]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify_send_bin=$(command -v notify-send)
    else
      notify_send_bin=$(nix build --no-link --print-out-paths 'nixpkgs#libnotify^out')/bin/notify-send
    fi
  fi
}

need_wlrctl() {
  if [ -z "${wlrctl_bin:-}" ]; then
    if command -v wlrctl >/dev/null 2>&1; then
      wlrctl_bin=$(command -v wlrctl)
    else
      wlrctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#wlrctl^out')/bin/wlrctl
    fi
  fi
}

need_wpctl() {
  if [ -z "${wpctl_bin:-}" ]; then
    if command -v wpctl >/dev/null 2>&1; then
      wpctl_bin=$(command -v wpctl)
    else
      wpctl_bin=$(nix build --no-link --print-out-paths 'nixpkgs#wireplumber^out')/bin/wpctl
    fi
  fi
}

need_convert() {
  if [ -z "${convert_bin:-}" ]; then
    if command -v convert >/dev/null 2>&1; then
      convert_bin=convert
    else
      convert_bin="nix run nixpkgs#imagemagick -- convert"
    fi
  fi
}

need_wtype() {
  if [ -z "${wtype_bin:-}" ]; then
    if command -v wtype >/dev/null 2>&1; then
      wtype_bin=$(command -v wtype)
    else
      wtype_bin=$(nix build 'nixpkgs#wtype^out' --no-link --print-out-paths)/bin/wtype
    fi
  fi
}

need_jq() {
  if [ -z "${jq_bin:-}" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq_bin=$(command -v jq)
    else
      jq_bin=$(nix build --no-link --print-out-paths 'nixpkgs#jq^out')/bin/jq
    fi
  fi
}

need_wl_copy() {
  if [ -z "${wl_copy_bin:-}" ]; then
    if command -v wl-copy >/dev/null 2>&1; then
      wl_copy_bin=$(command -v wl-copy)
    else
      wl_copy_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-copy
    fi
  fi
}

need_wl_paste() {
  if [ -z "${wl_paste_bin:-}" ]; then
    if command -v wl-paste >/dev/null 2>&1; then
      wl_paste_bin=$(command -v wl-paste)
    else
      wl_paste_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-paste
    fi
  fi
}

need_bin hyprland hyprctl grim qs
if $fixture_window_mode; then
  need_bin foot convert
fi
for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  needs_var="leg_${leg_name}_needs"
  leg_needs=()
  read -r -a leg_needs <<< "${!needs_var:-}" || true
  need_bin ${leg_needs[@]+"${leg_needs[@]}"}
done

# shellcheck disable=SC2034  # every leg drive script reads it
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

# A leg that cannot share the single session below takes the run over here,
# with the build done, the binaries resolved and the bus baseline captured,
# and exits itself: --screensaver-gif pins screensaver.effect through the
# settings fixture, which a session reads at startup, so recording five
# effects means five sessions.
for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_takeover" >/dev/null; then "leg_${leg_name}_takeover"; fi
done

shot_path="$shot_dir/smoke.png"
shell_log_path="$shot_dir/shell.log"
hypr_log_path="$shot_dir/hyprland.log"
cfg="$shot_dir/hyprland.conf"

# Isolated HOME for the Hyprland process and everything it spawns, see the
# host-session safety note in the header.
mkdir -p "$iso_home/.config/formalshell" "$iso_home/.local/share/applications" \
  "$iso_home/.local/share/formalshell/calendar"

for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_fixture" >/dev/null; then "leg_${leg_name}_fixture"; fi
done

cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$settings_extra}
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

# The shell's own wire traffic, for a leg that has to assert on what the
# shell said rather than on what the screen shows: a layer surface's
# exclusive zone is committed once and never read back, so a wrong one is
# invisible in a screenshot and in `hyprctl layers` alike (frame.sh). Opt-in
# per leg because it is a protocol dump: `leg_<n>_wayland_debug=1`.
wayland_debug_line=""
for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  wayland_debug_var="leg_${leg_name}_wayland_debug"
  if [ "${!wayland_debug_var:-0}" = 1 ]; then wayland_debug_line="export WAYLAND_DEBUG=1"; fi
done

shell_start_script="$shot_dir/shell-start.sh"
write_script "$shell_start_script" <<EOF
#!/usr/bin/env bash
# LIBGL_ALWAYS_SOFTWARE: on the vkms card the compositor advertises dmabuf
# with a main device Mesa cannot open for a client ("failed to get driver
# name for fd -1"), and Qt's EGL init takes the whole shell down with it.
# Forcing the software driver puts the shell back on the wl_shm/llvmpipe
# path it renders on anyway. Scoped to this process: Hyprland's
# own EGL runs on gbm over that same card and must keep doing so.
export LIBGL_ALWAYS_SOFTWARE=1
# Captured, not discarded: a shell that dies on a QML error at startup would
# otherwise fail every assertion below with no way to see why.
# Backgrounded rather than exec'd so the shell's pid lands in a file the
# screenshot script reads for its memory sample; the wrapper execs
# quickshell in place, so the pid stays the shell's own.
$wayland_debug_line
"$PWD/result/bin/formalshell" > "$shell_log_path" 2>&1 &
echo \$! > "$shot_dir/shell.pid"
wait
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
} > "$cfg"

# Not a subshell: a drive function writes its own scripts, echoes its
# exec-once lines onto the config, and may register a teardown line.
for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_drive" >/dev/null; then "leg_${leg_name}_drive" >> "$cfg"; fi
done

for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_timing" >/dev/null; then "leg_${leg_name}_timing"; fi
done

shot_script="$shot_dir/shot.sh"
write_script "$shot_script" <<EOF
#!/usr/bin/env bash
sleep $screenshot_delay
"$grim_bin" "$shot_path" > "$shot_dir/grim.log" 2>&1
sleep $tail_gap
# Memory sample of the shell at the end of the run, once every leg has
# driven what it drives: RSS and the QML JS heap (QV4's memfd chunks), the
# two numbers a memory regression shows up in first.
if shell_pid=\$(cat "$shot_dir/shell.pid" 2>/dev/null) && [ -r "/proc/\$shell_pid/smaps" ]; then
  rss_kb=\$(awk '/^VmRSS/{print \$2}' "/proc/\$shell_pid/status")
  js_kb=\$(awk '/^[0-9a-f]+-[0-9a-f]+ /{n=\$6} /^Rss:/{if (n ~ /JSGCHeap/) s+=\$2} END{print s+0}' "/proc/\$shell_pid/smaps")
  echo "SMOKE_MEM rss_kb=\$rss_kb jsheap_kb=\$js_kb" > "$shot_dir/mem.txt"
fi
$fixture_cleanup
"$hyprctl_bin" dispatch exit
EOF
echo "exec-once = bash $shot_script" >> "$cfg"

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

# Printed ahead of the asserts so a failing leg still reports what the
# shell weighed at the end of its run.
if [ -f "$shot_dir/mem.txt" ]; then
  cat "$shot_dir/mem.txt"
fi

for leg_name in ${active_legs[@]+"${active_legs[@]}"}; do
  if declare -F "leg_${leg_name}_assert" >/dev/null; then "leg_${leg_name}_assert"; fi
done

# A crashed shell still leaves a perfectly good screenshot of quickshell's
# own crash dialog, so the frame's existence proves nothing on its own.
if grep -q "has crashed" "$shell_log_path" 2>/dev/null; then
  fail "the shell crashed during the run"
fi

# A missing property or a missing import is a load error the QML engine
# reports once and then carries on from, so the surface it broke keeps
# drawing something plausible and no assert here ever looks at it: the
# display panel spent three weeks telling a session with an empty output
# list it was still LOADING, because one contract property was never
# declared on the backend (added 2026-08-06, found on e1504g 2026-08-26).
# Neither pattern can fire transiently, so this is a check on every run
# rather than a leg of its own.
if grep -qE "Cannot assign to non-existent property|is not a type" "$shell_log_path" 2>/dev/null; then
  grep -nE "Cannot assign to non-existent property|is not a type" "$shell_log_path" | head -5 >&2
  fail "the shell logged a QML load error (lines above)"
fi

if [ -f "$shot_path" ]; then
  echo "SMOKE_OK $shot_path"
else
  fail "no screenshot produced"
fi
