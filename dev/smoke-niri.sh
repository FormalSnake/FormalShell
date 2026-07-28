#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
# With --dump, also calls the `debug` IPC target and cats the JSON reply.
# With --wallpaper, generates a solid-color test PNG, drives it through
# `wallpaper set` + `theme status` over IPC in-session before screenshotting,
# so the screenshot proves the background/bar actually recolored.
# With --menu, drives the real `menu` IPC target in-session: `summon` opens
# it at root, `select` switches it into select mode (screenshot proves the
# option list renders), then `close` cancels the pending select and the
# resulting selection.txt is read back to prove the {cancelled:true} write.
# Menu.qml's FORMALSHELL_SMOKE_OPEN_MENU env-gated auto-open still exists
# (harmless, useful for manual debugging) but this script no longer relies
# on it now that the real IPC route is wired.
# With --notify, fires `notify-send -u normal` then `-u critical` in-session
# and screenshots the resulting toasts.
# With --center, fires one more `notify-send -u normal` and waits for
# non-critical popups to auto-expire into the `pending` tier before summoning
# the notification center over the `notifications` IPC target and
# screenshotting it — combine with --notify so there's a critical notify-send
# still sitting sticky in the popup layer: Toasts.qml suppresses that whole
# stack for as long as the center is open, so the screenshot shows the
# center alone, not the two surfaces overlapping.
# With --osd, drives the bottom-center OSD three ways: `qs ipc call osd
# volume` (manual trigger, screenshotted as osd-manual.png — its path is
# printed on its own line since it isn't the run's canonical SMOKE_OK
# artifact), then `wpctl set-volume @DEFAULT_AUDIO_SINK@ 30%` (the auto-show
# trigger via AudioService.changed, screenshotted as this run's
# smoke.png/SMOKE_OK), then `qs ipc call osd brightness` (screenshotted as
# osd-brightness.png — the VM has no backlight device, so this only proves
# the surface itself renders that kind correctly, not that hardware exists).
# Each trigger is followed 1s later by its own screenshot — comfortably
# inside the OSD's 1.6s auto-hide window — with enough gap between triggers
# that the previous popup has long since auto-hidden before the next fires.
# With --panel <name>, drives the `panel` IPC target's real route: `qs ipc
# call panel open <name>` opens the named popout (no bar-cell click, so
# Panel.qml's anchorX stays unset and the frame falls back to sitting under
# the bar's right region — see Panel.qml's own header comment), left open
# through the run's normal screenshot so it shows in smoke.png/SMOKE_OK; it
# has no auto-close, so no timing race with the rest of the run's triggers.
# `--panel calendar` additionally proves real events render: the isolated
# HOME always carries a one-event .ics fixture dated today (see the
# calendar-events fixture setup below) pointed at by settings.json's
# calendar.icsDir, so the day grid shows an accent dot on today's cell and
# the TODAY section lists it by summary.
# With --clipboard, `wl-copy`s three fixture strings, dumps `clipboard list`
# (clip-list-1.json — proves capture + newest-first order), re-copies the
# newest one (dedup proof: the reducer must move it to front, not insert a
# duplicate), dumps `clipboard list` again (clip-list-2.json — item count
# must stay 3), then activates the SECOND entry via the exact self-targeting
# `qs ipc --any-display -p <shellDir> call clipboard copy <id>` invocation
# Menu/providers.js's clipboardProvider builds (clip-copy.txt — must read
# "ok", not "No running instances"; a wrong `-p` target fails silently there)
# and reads the system clipboard back (clip-paste.txt — must have flipped to
# the re-copied entry's text), proving the menu row's copy action actually
# reaches the running shell end to end, not just that the rows render. Then
# `menu summon clipboard` so the run's screenshot shows the provider's rows
# rendered as real menu cells, left open through smoke.png/SMOKE_OK same as
# --panel.
#
# D-Bus isolation (M5 hard rule): the whole nested niri invocation runs under
# `dbus-run-session`, giving formalshell's NotificationServer (and anything
# else that talks D-Bus in there) a private session bus instead of the
# host's — the host's is owned by DMS, and NotificationServer acquiring
# org.freedesktop.Notifications on it would steal that name out from under
# the real desktop. Verified every run: the host's
# `busctl --user status org.freedesktop.Notifications` owner PID must be
# identical before and after.
#
# Host-session safety: the nested niri invocation (and everything it spawns —
# formalshell, and in --wallpaper mode, matugen and the user's own matugen
# ecosystem) runs under an isolated HOME/XDG_*_HOME, never this user's real
# ones. Without this, ThemeEngine reads the owner's live
# ~/.config/matugen/config.toml verbatim and re-executes every post_hook in
# it (keyboard LEDs, ghostty/spicetify/niri reloads, …) against the real
# desktop on every smoke run — observed 2026-07-27. WAYLAND_DISPLAY and
# XDG_RUNTIME_DIR stay the host's: the nested compositor is a Wayland client
# of the host and needs the real socket to connect and to publish its own
# IPC/quickshell sockets.
set -euo pipefail
cd "$(dirname "$0")/.."

dump_mode=false
wallpaper_mode=false
menu_mode=false
notify_mode=false
center_mode=false
osd_mode=false
panel_mode=false
panel_name=""
clipboard_mode=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) dump_mode=true; shift ;;
    --wallpaper) wallpaper_mode=true; shift ;;
    --menu) menu_mode=true; shift ;;
    --notify) notify_mode=true; shift ;;
    --center) center_mode=true; shift ;;
    --osd) osd_mode=true; shift ;;
    --panel) panel_mode=true; panel_name="$2"; shift 2 ;;
    --clipboard) clipboard_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--wallpaper] [--menu] [--notify] [--center] [--osd] [--panel <name>] [--clipboard]" >&2; exit 1 ;;
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

if $osd_mode; then
  if command -v wpctl >/dev/null 2>&1; then
    wpctl_bin=$(command -v wpctl)
  else
    wpctl_bin=$(nix build 'nixpkgs#wireplumber^out' --no-link --print-out-paths)/bin/wpctl
  fi
fi

if $clipboard_mode; then
  if command -v wl-copy >/dev/null 2>&1; then
    wl_copy_bin=$(command -v wl-copy)
  else
    wl_copy_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-copy
  fi
  if command -v wl-paste >/dev/null 2>&1; then
    wl_paste_bin=$(command -v wl-paste)
  else
    wl_paste_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-paste
  fi
fi

if $notify_mode || $center_mode; then
  # Resolved to a real absolute path (not a "nix run ..." prefix): it's
  # embedded inside a generated `sh -c` string below, same requirement as
  # $qs_bin/$shell_path.
  if command -v notify-send >/dev/null 2>&1; then
    notify_send_bin=$(command -v notify-send)
  else
    notify_send_bin=$(nix build 'nixpkgs#libnotify^out' --no-link --print-out-paths)/bin/notify-send
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
status_path="$shot_dir/status.json"
query_path="$shot_dir/query.json"
selection_path="$shot_dir/selection.txt"
osd_manual_path="$shot_dir/osd-manual.png"
osd_brightness_path="$shot_dir/osd-brightness.png"
clip_list1_path="$shot_dir/clip-list-1.json"
clip_list2_path="$shot_dir/clip-list-2.json"
clip_copy_path="$shot_dir/clip-copy.txt"
clip_paste_path="$shot_dir/clip-paste.txt"
cfg=$(mktemp -d)/config.kdl

# Isolated HOME for the nested niri process and everything it spawns — see
# the host-session safety note at the top of this file.
iso_home=$(mktemp -d)

# A deterministic fixture .desktop entry — DesktopEntries scans
# $XDG_DATA_HOME/applications, which is isolated below, so without this the
# apps provider's list depends on whatever's installed on the host running
# the smoke test.
mkdir -p "$iso_home/.local/share/applications"
cat > "$iso_home/.local/share/applications/formalshell-smoke-fixture.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Formal Test App
Exec=true
Icon=utilities-terminal
EOF

# Calendar events fixture (M6 Task 5): a khal/vdir-style directory of one
# .ics file with a single VEVENT dated today (computed at run time so the
# fixture never goes stale), so --panel calendar's screenshot proves a real
# event renders — the accent dot on today's day cell and the row in the
# TODAY ledger section — not just that the grid itself draws.
mkdir -p "$iso_home/.config/formalshell" "$iso_home/.local/share/formalshell/calendar"
today_ics=$(date -u +%Y%m%d)
cat > "$iso_home/.local/share/formalshell/calendar/smoke-fixture.ics" <<EOF
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:smoke-fixture-1
SUMMARY:SMOKE FIXTURE EVENT
DTSTART;VALUE=DATE:$today_ics
END:VEVENT
END:VCALENDAR
EOF
# M6 Task 8: the VM/nested session has no Wi-Fi radio, so geoclue never
# gets a fix — location.latitude/longitude here exercises the documented
# settings.json override fallback (the actually-verifiable path) so
# --panel weather's screenshot proves a real open-meteo fetch/forecast
# render, not just the "NO LOCATION" honest-empty state. Berlin, the
# open-meteo docs' own example coordinates.
cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}}
EOF

if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  $convert_bin -size 640x480 xc:'#7a3fb0' "$wp_path"
fi

# --menu's IPC steps are written as standalone helper scripts (rather than
# inline "sh -c" one-liners like the other modes) because `menu select`'s
# JSON-array argument needs to survive quoting through both this generator
# script and niri's own KDL string parsing — a real file sidesteps that
# entirely. `menu_finish_script` runs after the screenshot (never before:
# closing the surface would leave nothing to screenshot), cancelling the
# still-pending select and reading back its {cancelled:true} write.
if $menu_mode; then
  menu_open_script="$shot_dir/menu-open.sh"
  cat > "$menu_open_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc --any-display -p "$shell_path" call menu summon ""
EOF

  # `qs ipc call`'s CLI11 arg parser auto-splits any positional argument that
  # literally starts with "[" and ends with "]" into multiple comma-joined
  # arguments (its vector-literal shorthand, CLI11's Option_inl.hpp) — a bare
  # '["a","b","c"]' arrives at the handler as 3 extra arguments, not one JSON
  # string. A leading space defeats the front()=='[' check without tripping
  # JSON.parse, which tolerates surrounding whitespace.
  menu_select_script="$shot_dir/menu-select.sh"
  cat > "$menu_select_script" <<EOF
#!/usr/bin/env bash
sleep 6
"$qs_bin" ipc --any-display -p "$shell_path" call menu select "Pick" ' ["a","b","c"]' tok1 > /dev/null 2>&1
EOF

  menu_finish_script="$shot_dir/menu-finish.sh"
  cat > "$menu_finish_script" <<EOF
#!/usr/bin/env bash
sleep 9
"$qs_bin" ipc --any-display -p "$shell_path" call menu close > /dev/null 2>&1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
EOF
fi

# --clipboard's whole sequence lives in one script (internal sleeps, one
# spawn-at-startup line) rather than --menu's per-step files: nothing here
# needs to interleave with a niri-side sleep the way menu-select's KDL
# quoting constraint did.
if $clipboard_mode; then
  clipboard_drive_script="$shot_dir/clipboard-drive.sh"
  cat > "$clipboard_drive_script" <<EOF
#!/usr/bin/env bash
sleep 2
"$wl_copy_bin" "clipboard smoke one"
sleep 1
"$wl_copy_bin" "clipboard smoke two"
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call clipboard list > "$clip_list1_path" 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call clipboard list > "$clip_list2_path" 2>&1
sleep 1
copy_id=\$(grep -o '"id":"[^"]*"' "$clip_list2_path" | sed -n '2p' | cut -d'"' -f4)
"$qs_bin" ipc --any-display -p "$shell_path" call clipboard copy "\$copy_id" > "$clip_copy_path" 2>&1
sleep 1
"$wl_paste_bin" --no-newline > "$clip_paste_path" 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call menu summon clipboard > /dev/null 2>&1
EOF
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
  if $menu_mode; then
    echo "spawn-at-startup \"bash\" \"$menu_open_script\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call debug query 'e' > $query_path 2>&1\""
    echo "spawn-at-startup \"bash\" \"$menu_select_script\""
    echo "spawn-at-startup \"bash\" \"$menu_finish_script\""
  fi
  if $notify_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$notify_send_bin' -u normal 'Test' 'Hello'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$notify_send_bin' -u critical 'Crit' 'Now'\""
  fi
  if $center_mode; then
    # A second normal notify-send, offset from notify_mode's own so the
    # model's default 6s popup timeout has both non-critical popups clear of
    # their expiry (and the 1s reducer tick has had a chance to run) well
    # before the summon below — the critical one from notify_mode is sticky
    # and stays a popup regardless.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$notify_send_bin' -u normal 'Second' 'World'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications showHistory\""
  fi
  if $osd_mode; then
    # Manual trigger, screenshotted 1s later (well inside the 1.6s auto-hide
    # window) — its own artifact, printed separately below rather than as
    # this run's SMOKE_OK. wpctl fires at sleep 9, four seconds after the
    # manual OSD (sleep4 + 1.6s hide) has long since gone, so the generic
    # tail screenshot below (sleep 10) proves auto-show, not leftover
    # visibility from the manual call. A third leg (sleep 13/14) drives the
    # brightness kind too — BrightnessService.available is honestly false in
    # the VM (no backlight device), so this only proves the surface itself
    # renders that kind correctly (BRIGHTNESS label, 0% + empty bar), not
    # that a real device exists.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call osd volume\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && niri msg action screenshot-screen --path $osd_manual_path\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 9 && '$wpctl_bin' set-volume @DEFAULT_AUDIO_SINK@ 30%\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc --any-display -p '$shell_path' call osd brightness\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 14 && niri msg action screenshot-screen --path $osd_brightness_path\""
  fi
  if $panel_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc --any-display -p '$shell_path' call panel open '$panel_name'\""
  fi
  if $clipboard_mode; then
    echo "spawn-at-startup \"bash\" \"$clipboard_drive_script\""
  fi
  # menu_mode's finish script (menu close + selection read) fires 1s after
  # the screenshot at sleep 9 — give it a 3s buffer before quit instead of
  # the other modes' 1s so it has time to land first. osd_mode's brightness
  # leg (sleep 13/14, see above) needs the same kind of buffer past its own
  # sleep-10 screenshot.
  tail_gap=1
  if $menu_mode; then
    tail_gap=3
  elif $osd_mode; then
    tail_gap=5
  fi
  # center_mode needs the popup->pending transition (see above) plus the
  # showHistory summon to land before the screenshot; osd_mode's final
  # screenshot must land 1s after its sleep-9 wpctl trigger, still inside
  # the OSD's auto-hide window; every other mode keeps the original 8s
  # budget.
  screenshot_delay=8
  if $center_mode; then
    screenshot_delay=15
  elif $osd_mode; then
    screenshot_delay=10
  elif $clipboard_mode; then
    # clipboard-drive.sh's last step (menu summon) lands at its own sleep 10
    # (two dumps, a copy-and-paste round trip, then the summon); 3s buffer
    # for the menu to render before the shot.
    screenshot_delay=13
  fi
  echo "spawn-at-startup \"sh\" \"-c\" \"sleep $screenshot_delay && niri msg action screenshot-screen --path $shot_dir/smoke.png && sleep $tail_gap && niri msg action quit --skip-confirmation\""
} > "$cfg"

HOME="$iso_home" \
XDG_CONFIG_HOME="$iso_home/.config" \
XDG_STATE_HOME="$iso_home/.local/state" \
XDG_DATA_HOME="$iso_home/.local/share" \
XDG_DATA_DIRS="$iso_home/.local/share" \
XDG_CACHE_HOME="$iso_home/.cache" \
WAYLAND_DISPLAY="$wayland_display" dbus-run-session -- timeout 30 $niri_bin --config "$cfg" || true

host_notifications_owner_after=$(host_notifications_owner)
if [ "$host_notifications_owner_before" != "$host_notifications_owner_after" ]; then
  echo "SMOKE_FAIL: host org.freedesktop.Notifications owner PID changed ($host_notifications_owner_before -> $host_notifications_owner_after) — nested NotificationServer touched the host bus" >&2
  exit 1
fi

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

if $menu_mode; then
  if [ -s "$query_path" ]; then
    cat "$query_path"
  else
    echo "SMOKE_FAIL: no menu query result produced" >&2; exit 1
  fi
  if [ -s "$selection_path" ] && grep -q '"cancelled":true' "$selection_path"; then
    cat "$selection_path"
  else
    echo "SMOKE_FAIL: menu close in select mode did not write {cancelled:true}" >&2; exit 1
  fi
fi

if $clipboard_mode; then
  if [ -s "$clip_list1_path" ]; then
    cat "$clip_list1_path"
  else
    echo "SMOKE_FAIL: no clipboard list (pre-recopy) produced" >&2; exit 1
  fi
  if [ -s "$clip_list2_path" ]; then
    cat "$clip_list2_path"
  else
    echo "SMOKE_FAIL: no clipboard list (post-recopy) produced" >&2; exit 1
  fi
  # Item count must stay 3 across the re-copy — a 4th entry would mean the
  # dedup-to-front path inserted a duplicate instead of moving the existing
  # "clipboard smoke three" entry.
  count1=$(grep -o '"id":' "$clip_list1_path" | wc -l | tr -d ' ')
  count2=$(grep -o '"id":' "$clip_list2_path" | wc -l | tr -d ' ')
  if [ "$count1" != "3" ] || [ "$count2" != "3" ]; then
    echo "SMOKE_FAIL: clipboard list item count drifted (before=$count1 after-recopy=$count2, want 3/3)" >&2; exit 1
  fi
  # The actual menu-copy-action round trip: the self-targeting `clipboard
  # copy <id>` call must find the running instance ("ok", not "No running
  # instances") and its side effect (wl-copy) must land on the real system
  # clipboard.
  if [ -s "$clip_copy_path" ]; then
    cat "$clip_copy_path"
  else
    echo "SMOKE_FAIL: no clipboard copy result produced" >&2; exit 1
  fi
  if ! grep -q "^ok$" "$clip_copy_path"; then
    echo "SMOKE_FAIL: clipboard copy IPC call did not return ok — got: $(cat "$clip_copy_path")" >&2; exit 1
  fi
  if [ -s "$clip_paste_path" ]; then
    cat "$clip_paste_path"
  else
    echo "SMOKE_FAIL: no post-copy clipboard readback produced" >&2; exit 1
  fi
  if ! grep -q "clipboard smoke two" "$clip_paste_path"; then
    echo "SMOKE_FAIL: system clipboard did not flip to the re-copied entry — got: $(cat "$clip_paste_path")" >&2; exit 1
  fi
fi

if $notify_mode; then
  echo "host org.freedesktop.Notifications owner PID unchanged: $host_notifications_owner_after"
fi

if $osd_mode; then
  if [ -f "$osd_manual_path" ]; then
    echo "SMOKE_OSD_MANUAL $osd_manual_path"
  else
    echo "SMOKE_FAIL: no osd-manual screenshot produced" >&2; exit 1
  fi
  if [ -f "$osd_brightness_path" ]; then
    echo "SMOKE_OSD_BRIGHTNESS $osd_brightness_path"
  else
    echo "SMOKE_FAIL: no osd-brightness screenshot produced" >&2; exit 1
  fi
fi

if [ -f "$shot_dir/smoke.png" ]; then
  echo "SMOKE_OK $shot_dir/smoke.png"
else
  echo "SMOKE_FAIL: no screenshot produced" >&2; exit 1
fi
