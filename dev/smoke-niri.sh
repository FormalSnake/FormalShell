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
# With --media, generates a short silent fixture track (ffmpeg lavfi
# anullsrc, tagged with a title/artist via -metadata) and plays it with mpv
# --script=<mpvScripts.mpris path> into the default (pipewire null-sink)
# audio device in-session, so MediaService picks up a real MPRIS player —
# `panel open media` then shows the screenshot with the panel open (album
# art cell, meta row, transport cells, progress fill), and `media status` is
# dumped to media-status.json so its title/artist can be cross-checked
# against the fixture's own tags. mpv is killed by PID right after the
# screenshot, before niri quits, so no player process outlives the run.
# With --lock: first, before the nested session even starts, runs
# `result/bin/formalshell-lock-before-sleep` with no shell instance running
# at all and records its exit code (lock-before-sleep-rc.txt must be "0" —
# the lock-before-sleep exit-0-always contract, spec §8). Then drives the
# `lock` IPC target end to end in-session: `lock lock`'s own exit code is
# recorded too (lock-call-rc.txt) locking the nested session (screenshotted
# as lock-locked.png — oversized clock, single input cell), `qs ipc call
# lock isLocked` is dumped to lock-islocked-1.txt to prove it flipped true,
# then `wtype` (a real virtual-keyboard-unstable-v1 client — LockIpc.qml
# deliberately has no "type this password" shortcut, see its own header
# comment) types a WRONG password into the real password TextInput and
# presses Return, screenshotted as lock-error.png (proves the failed-auth
# inversion + uppercase error meta row), then wtype retypes the VM's real
# throwaway test password (nix/testvm.nix's users.users.test.password) and
# Return, screenshotted as lock-unlocked.png, with a second `lock isLocked`
# (lock-islocked-2.txt) and `lock status` (lock-status.json) proving the
# round trip completed and the state flipped back to false. This run's
# generic smoke.png/SMOKE_OK is taken after the round trip, so it shows the
# normal unlocked session.
# With --screensaver, shortens screensaver.timeoutSeconds to 3s via the
# isolated settings.json fixture (real IdleMonitor, not a fake clock) and
# plays the same silent fixture track --media uses so MediaService.isPlaying
# is genuinely true. Since nothing in this whole nested session ever
# generates real Wayland input (qs/niri IPC calls travel their own sockets,
# not the input protocol), the compositor's own idle timer elapses
# naturally and stays elapsed for the rest of the run: first with mpv still
# playing, `screensaver status` is dumped (screensaver-guard-status.json)
# to prove the live media guard holds `active:false` even though `isIdle`
# already reads true; mpv is then killed and, after another wait past the
# timeout, the screensaver auto-activates purely from the guard clearing —
# no `screensaver start` call at all — screenshotted
# (screensaver-auto.png) and status-dumped again
# (screensaver-auto-status.json, `active:true`). `screensaver stop` then
# dismisses it (screensaver-dismiss-status.json proves `active:false`
# again), and a final explicit `screensaver start`/screenshot
# (screensaver-manual.png) / `stop` proves the manual IPC path
# independently of the idle timer.
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
# With --tray, launches six dev/sni-stub.py processes (a minimal Python/GLib
# StatusNotifierItem producer — see its own header comment) that each
# register a real item on the isolated session bus, giving
# Quickshell.Services.SystemTray genuine items to track. Tray.qml's visible
# limit is 4, so 6 items means 3 pinned cells plus one "+3" overflow cell —
# `tray status` is dumped (tray-status-1.json, proves the real item count
# and expanded:false) before a screenshot (tray-collapsed.png) shows the
# collapsed state, then `tray expand` (the smoke rig's stand-in for the
# overflow cell's own click — no synthetic pointer exists here) is called
# and `tray status` dumped again (tray-status-2.json, proves expanded:true
# with the same item count); this run's generic smoke.png/SMOKE_OK is taken
# after the expand call, so it shows every item as its own cell, drawer
# open. The stub processes are killed by PID (tray-pids.txt, same pattern as
# --media's mpv) right before niri quits.
# With --picker, generates a handful of fixture PNGs (imagemagick, one solid
# color each) into a directory pointed at by settings.json's picker.directory,
# then drives the `picker` IPC target: `summon` opens the wallpaper-mode grid
# (screenshotted as picker-grid.png — cursor cell inverted on the first
# image, proving the surface itself), `choose` picks a non-first fixture by
# path — the same action Enter/click on a cell would take, exposed over IPC
# rather than relying on unproven real keyboard/pointer delivery into an
# OnDemand-focus layer surface, the same "verify the action, not the input
# method" idiom every other mode already uses (media/wallpaper/lock) — which
# sets the wallpaper exactly like `wallpaper set` (picker-theme-status.json,
# same `theme status` proof `--wallpaper` uses, confirms ThemeEngine actually
# retheme'd). Then `select` reopens the grid over the same directory in the
# generic image-selector mode with a caller token, `choose` picks a different
# fixture, and `close`'s already-happened write to
# picker-selection.txt is read back (picker-selection.txt) to prove the
# request/answer handshake — MenuIpc's select()/input() pattern, reused
# rather than reinvented.
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
media_mode=false
lock_mode=false
screensaver_mode=false
picker_mode=false
tray_mode=false
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
    --media) media_mode=true; shift ;;
    --lock) lock_mode=true; shift ;;
    --screensaver) screensaver_mode=true; shift ;;
    --picker) picker_mode=true; shift ;;
    --tray) tray_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--wallpaper] [--menu] [--notify] [--center] [--osd] [--panel <name>] [--clipboard] [--media] [--lock] [--screensaver] [--picker] [--tray]" >&2; exit 1 ;;
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

if $wallpaper_mode || $picker_mode; then
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

if $media_mode || $screensaver_mode; then
  # The VM's mpv is pre-wrapped with mpvScripts.mpris baked into its
  # --script= flags (nix/testvm.nix's `mpv.override { scripts = ... }`), so
  # plain `mpv` on PATH there already announces itself over MPRIS. A host
  # without that package wired in gets the exact same wrapped derivation
  # built from this repo's own pinned nixpkgs input, not the flake registry
  # (`.override` isn't expressible as a flake installable attribute path).
  # screensaver_mode reuses this same fixture track/player to give
  # MediaService.isPlaying a real value to guard against.
  if command -v mpv >/dev/null 2>&1; then
    mpv_bin=$(command -v mpv)
  else
    mpv_bin=$(nix build --no-link --print-out-paths --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      in
        pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; }
    ')/bin/mpv
  fi
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg_bin=$(command -v ffmpeg)
  else
    ffmpeg_bin=$(nix build 'nixpkgs#ffmpeg-headless^out' --no-link --print-out-paths)/bin/ffmpeg
  fi
fi

if $lock_mode; then
  if command -v wtype >/dev/null 2>&1; then
    wtype_bin=$(command -v wtype)
  else
    wtype_bin=$(nix build 'nixpkgs#wtype^out' --no-link --print-out-paths)/bin/wtype
  fi
  # niri's own `screenshot-screen` msg action is deliberately refused while
  # the session is locked (niri-wm/niri discussion #2384: "to prevent people
  # from spamming your disk with images even when the session is locked") —
  # confirmed by reproducing it: the action silently no-ops, no error, no
  # file. grim talks the underlying wlr-screencopy protocol directly as an
  # ordinary Wayland client, which niri does NOT gate behind the lock, and
  # is what actually proves the three lock-state screenshots below.
  if command -v grim >/dev/null 2>&1; then
    grim_bin=$(command -v grim)
  else
    grim_bin=$(nix build 'nixpkgs#grim^out' --no-link --print-out-paths)/bin/grim
  fi
fi

if $tray_mode; then
  # nix/testvm.nix stages this exact wrapped derivation into
  # environment.systemPackages (M10 Task 1), so `command -v python3` already
  # resolves to a PyGObject-capable interpreter on the VM; the fallback
  # below is for a host that hasn't wired that in.
  if python3 -c 'import gi' >/dev/null 2>&1; then
    python3_bin=$(command -v python3)
  else
    python3_bin=$(nix build --no-link --print-out-paths --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      in
        pkgs.python3.withPackages (ps: [ ps.pygobject3 ])
    ')/bin/python3
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
sni_stub_path="$PWD/dev/sni-stub.py"

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
media_status_path="$shot_dir/media-status.json"
media_pid_path="$shot_dir/mpv.pid"
lock_locked_path="$shot_dir/lock-locked.png"
lock_error_path="$shot_dir/lock-error.png"
lock_unlocked_path="$shot_dir/lock-unlocked.png"
lock_islocked1_path="$shot_dir/lock-islocked-1.txt"
lock_islocked2_path="$shot_dir/lock-islocked-2.txt"
lock_status_path="$shot_dir/lock-status.json"
lock_call_rc_path="$shot_dir/lock-call-rc.txt"
lock_before_sleep_rc_path="$shot_dir/lock-before-sleep-rc.txt"
ss_pid_path="$shot_dir/ss-mpv.pid"
ss_guard_status_path="$shot_dir/screensaver-guard-status.json"
ss_auto_path="$shot_dir/screensaver-auto.png"
ss_auto_status_path="$shot_dir/screensaver-auto-status.json"
ss_dismiss_status_path="$shot_dir/screensaver-dismiss-status.json"
ss_manual_path="$shot_dir/screensaver-manual.png"
ss_final_status_path="$shot_dir/screensaver-final-status.json"
picker_grid_path="$shot_dir/picker-grid.png"
picker_theme_status_path="$shot_dir/picker-theme-status.json"
picker_selection_path="$shot_dir/picker-selection.txt"
tray_status1_path="$shot_dir/tray-status-1.json"
tray_status2_path="$shot_dir/tray-status-2.json"
tray_collapsed_path="$shot_dir/tray-collapsed.png"
tray_pids_path="$shot_dir/tray-pids.txt"

# lock-before-sleep exit-0-always proof (spec §8), run BEFORE the nested
# session below ever starts a shell instance — the exact "no running
# instance" scenario a real lock-before-sleep systemd unit must survive
# (bare `qs ipc call lock lock` exits 255 here; the wrapper must not).
if $lock_mode; then
  lock_before_sleep_rc=0
  "$PWD/result/bin/formalshell-lock-before-sleep" || lock_before_sleep_rc=$?
  echo "$lock_before_sleep_rc" > "$lock_before_sleep_rc_path"
fi

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
# screensaver_mode shortens the real IdleMonitor timeout to 3s (M7 Task 5)
# rather than faking a clock, so the guard/auto-trigger proof below exercises
# the genuine ext-idle-notify-v1 signal, just on a schedule this run can
# afford to wait out.
screensaver_settings=""
if $screensaver_mode; then
  # SCREENSAVER_EFFECT (optional, additive, unset by every caller except a
  # per-effect verification run — M8b Task 7) pins screensaver.effect for
  # this run's screensaver-manual.png instead of leaving it at the default
  # "random", so each of the five effects can be screenshotted on its own.
  ss_effect_json=""
  if [ -n "${SCREENSAVER_EFFECT:-}" ]; then
    ss_effect_json=', "effect": "'"$SCREENSAVER_EFFECT"'"'
  fi
  # SCREENSAVER_ASCII_TEXT (optional, additive, same rationale as
  # SCREENSAVER_EFFECT above): writes a custom banner file and points
  # screensaver.asciiPath at it, proving the bundled art is really
  # swappable rather than hardcoded.
  ss_ascii_json=""
  if [ -n "${SCREENSAVER_ASCII_TEXT:-}" ]; then
    ss_ascii_path="$iso_home/.config/formalshell/custom-screensaver.txt"
    printf '%s\n' "$SCREENSAVER_ASCII_TEXT" > "$ss_ascii_path"
    ss_ascii_json=', "asciiPath": "'"$ss_ascii_path"'"'
  fi
  screensaver_settings=', "screensaver": {"timeoutSeconds": 3, "guardMediaPlayback": true'"$ss_effect_json$ss_ascii_json"'}'
fi
# picker_mode (M7 Task 6): picker.directory points at a fixture directory of
# a handful of generated solid-color PNGs (below), so --picker's grid
# screenshot shows real images and its `choose` calls pick real files rather
# than paths that merely happen to parse.
picker_settings=""
picker_dir="$iso_home/.local/share/formalshell/pictures"
if $picker_mode; then
  mkdir -p "$picker_dir"
  picker_settings=', "picker": {"directory": "'"$picker_dir"'"}'
fi
cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$screensaver_settings$picker_settings}
EOF

if $picker_mode; then
  for name_color in "img-0:#c0392b" "img-1:#27ae60" "img-2:#2980b9" "img-3:#f1c40f" "img-4:#8e44ad"; do
    $convert_bin -size 64x64 "xc:${name_color#*:}" "$picker_dir/${name_color%:*}.png"
  done
fi

if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  $convert_bin -size 640x480 xc:'#7a3fb0' "$wp_path"
fi

# A short silent fixture track (M7 Task 1) rather than a committed binary
# asset — regenerated on every run so it never goes stale. The title/artist
# tags are what MediaService/MediaPanel must display verbatim, and what the
# post-run `media status` cross-check below compares against. screensaver_mode
# reuses this same track (via its own ss-media-play.sh below) purely to give
# MediaService.isPlaying a real value — it never checks the tags.
if $media_mode || $screensaver_mode; then
  media_track_path="$shot_dir/smoke-track.flac"
  media_track_title="FormalShell Smoke Track"
  media_track_artist="FormalShell Test Artist"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 20 \
    -metadata "title=$media_track_title" -metadata "artist=$media_track_artist" \
    -c:a flac -y "$media_track_path"
fi

if $media_mode; then
  # Script files (same rationale as menu_mode's below: real files sidestep
  # quoting hell through both this generator and niri's KDL string parser).
  # mpv's PID is written before the exec — exec replaces the shell's own
  # process image without forking, so $$ recorded here is exactly mpv's
  # eventual PID, letting the kill script target it precisely. A plain
  # `pkill -f <fixture path>` was tried first and self-matched: its own
  # invoking `sh -c "... pkill -f '<path>' ..."` argv contains that same
  # path substring, so pkill killed its own parent shell before the
  # trailing `niri msg action quit` ever ran, and the run only ended when
  # the outer `timeout 30` fired.
  media_play_script="$shot_dir/media-play.sh"
  cat > "$media_play_script" <<EOF
#!/usr/bin/env bash
sleep 2
echo \$\$ > "$media_pid_path"
exec "$mpv_bin" --no-video --really-quiet "$media_track_path"
EOF

  media_kill_script="$shot_dir/media-kill.sh"
  cat > "$media_kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$media_pid_path" ]; then
  kill "\$(cat "$media_pid_path")" 2>/dev/null || true
fi
EOF
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

# --lock's whole sequence lives in one script, same rationale as
# clipboard_drive_script: everything here is strictly ordered (lock, prove
# it over IPC, screenshot, type a wrong password, screenshot the error
# state, type the real one, screenshot unlocked, prove the flip back over
# IPC) with nothing needing to interleave with a niri-side sleep the way
# menu-select's KDL quoting constraint did.
if $lock_mode; then
  lock_drive_script="$shot_dir/lock-drive.sh"
  cat > "$lock_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc --any-display -p "$shell_path" call lock lock > /dev/null 2>&1
echo \$? > "$lock_call_rc_path"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call lock isLocked > "$lock_islocked1_path" 2>&1
sleep 3
"$grim_bin" "$lock_locked_path"
sleep 2
"$wtype_bin" "wrong-password"
"$wtype_bin" -k Return
# The PAM round trip for a wrong password (subprocess fork/exec through the
# full auth stack) measured ~2.5-3s on this VM, longer than a first glance
# suggests — a 2s buffer here intermittently caught the screenshot before
# authError updated. 5s leaves real margin.
sleep 5
"$grim_bin" "$lock_error_path"
sleep 2
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
sleep 3
"$grim_bin" "$lock_unlocked_path"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call lock isLocked > "$lock_islocked2_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call lock status > "$lock_status_path" 2>&1
EOF
fi

# --screensaver: mpv starts almost immediately (sleep 1, same fixture track
# --media uses) so MediaService.isPlaying is genuinely true well before
# settings.json's shortened 3s timeout can elapse — nothing else in this
# nested session ever generates real Wayland input, so the compositor's own
# idle timer, once it fires, stays fired for the rest of the run.
if $screensaver_mode; then
  ss_play_script="$shot_dir/ss-media-play.sh"
  cat > "$ss_play_script" <<EOF
#!/usr/bin/env bash
sleep 1
echo \$\$ > "$ss_pid_path"
exec "$mpv_bin" --no-video --really-quiet "$media_track_path"
EOF

  # Ordered the same way as clipboard/lock's own single drive scripts: the
  # guard-holds proof runs first (mpv still playing), then mpv is killed and
  # the auto-trigger proof runs (no `screensaver start` call at all — see
  # the header comment), then the explicit manual IPC start/stop proof runs
  # last, since it deliberately suppresses the auto-trigger for the rest of
  # the run (Screensaver.qml's own `_suppressed` comment) and nothing after
  # it depends on auto-triggering again.
  ss_drive_script="$shot_dir/ss-drive.sh"
  cat > "$ss_drive_script" <<EOF
#!/usr/bin/env bash
sleep 8
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver status > "$ss_guard_status_path" 2>&1
if [ -f "$ss_pid_path" ]; then
  kill "\$(cat "$ss_pid_path")" 2>/dev/null || true
fi
sleep 5
niri msg action screenshot-screen --path "$ss_auto_path"
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver status > "$ss_auto_status_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver stop > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver status > "$ss_dismiss_status_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver start > /dev/null 2>&1
sleep 1
niri msg action screenshot-screen --path "$ss_manual_path"
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver stop > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver status > "$ss_final_status_path" 2>&1
EOF
fi

# --picker: summon opens the wallpaper-mode grid (cursor defaults to index 0,
# so the screenshot needs no keypress at all to show the cursor cell
# inverted); choose picks a non-first fixture by path, over IPC — the same
# _choose() function Enter/click on a cell would call — proving both that a
# real selection sets the wallpaper (picker-theme-status.json, same
# `theme status` proof --wallpaper already uses) and, via a second
# select()/choose() round trip over an explicit token, that the generic
# image-selector's answer channel actually resolves.
if $picker_mode; then
  picker_drive_script="$shot_dir/picker-drive.sh"
  cat > "$picker_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc --any-display -p "$shell_path" call picker summon > /dev/null 2>&1
sleep 2
niri msg action screenshot-screen --path "$picker_grid_path"
"$qs_bin" ipc --any-display -p "$shell_path" call picker choose "$picker_dir/img-3.png" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call theme status > "$picker_theme_status_path" 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call picker select "$picker_dir" tok-picker > /dev/null 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call picker choose "$picker_dir/img-1.png" > /dev/null 2>&1
sleep 1
cat "$iso_home/.local/state/formalshell/picker-selection.txt" > "$picker_selection_path" 2>&1
EOF
fi

# --tray: launches six real SNI producers in the background (PIDs recorded
# for the kill step below), then proves the collapsed state (status dump +
# screenshot) before driving the same expand() the overflow cell's own click
# calls and proving the expanded state (status dump); this run's generic
# smoke.png/SMOKE_OK, taken later, shows the drawer already expanded.
if $tray_mode; then
  tray_drive_script="$shot_dir/tray-drive.sh"
  cat > "$tray_drive_script" <<EOF
#!/usr/bin/env bash
sleep 1
"$python3_bin" "$sni_stub_path" --id tray-fixture-1 --title "Tray Fixture 1" --color c0392b & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-2 --title "Tray Fixture 2" --color 27ae60 & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-3 --title "Tray Fixture 3" --color 2980b9 & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-4 --title "Tray Fixture 4" --color f1c40f & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-5 --title "Tray Fixture 5" --color 8e44ad & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-6 --title "Tray Fixture 6" --color 16a085 & echo \$! >> "$tray_pids_path"
sleep 6
"$qs_bin" ipc --any-display -p "$shell_path" call tray status > "$tray_status1_path" 2>&1
sleep 1
niri msg action screenshot-screen --path "$tray_collapsed_path"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call tray expand > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call tray status > "$tray_status2_path" 2>&1
EOF

  tray_kill_script="$shot_dir/tray-kill.sh"
  cat > "$tray_kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$tray_pids_path" ]; then
  while read -r pid; do
    kill "\$pid" 2>/dev/null || true
  done < "$tray_pids_path"
fi
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
  if $media_mode; then
    echo "spawn-at-startup \"bash\" \"$media_play_script\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call panel open media\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc --any-display -p '$shell_path' call media status > $media_status_path 2>&1\""
  fi
  if $lock_mode; then
    echo "spawn-at-startup \"bash\" \"$lock_drive_script\""
  fi
  if $screensaver_mode; then
    echo "spawn-at-startup \"bash\" \"$ss_play_script\""
    echo "spawn-at-startup \"bash\" \"$ss_drive_script\""
  fi
  if $picker_mode; then
    echo "spawn-at-startup \"bash\" \"$picker_drive_script\""
  fi
  if $tray_mode; then
    echo "spawn-at-startup \"bash\" \"$tray_drive_script\""
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
  elif $lock_mode; then
    # lock-drive.sh's own final step (the second isLocked/status dump) lands
    # around its internal sleep sum (~20s in, the wrong-password PAM round
    # trip's 5s buffer included); this run's generic smoke.png/SMOKE_OK is
    # taken 2s after that, so it shows the ordinary unlocked session, not
    # mid-round-trip.
    screenshot_delay=22
  elif $screensaver_mode; then
    # ss-drive.sh's own final step (the last status dump) lands around its
    # internal sleep sum (~16s in); this run's generic smoke.png/SMOKE_OK is
    # taken 4s after that, showing the ordinary session with the screensaver
    # already dismissed for good.
    screenshot_delay=20
  elif $picker_mode; then
    # picker-drive.sh's own final step (the selection-file readback) lands
    # around its internal sleep sum (~10s in); this run's generic
    # smoke.png/SMOKE_OK is taken 4s after that, showing the ordinary session
    # with the picker already closed again.
    screenshot_delay=14
  elif $tray_mode; then
    # tray-drive.sh's own final step (the post-expand status dump) lands
    # around its internal sleep sum (~10s in); this run's generic
    # smoke.png/SMOKE_OK is taken 3s after that, showing every registered
    # item as its own cell with the drawer already expanded.
    screenshot_delay=13
  fi
  # media_mode's mpv is killed by PID (media-kill.sh, written above) right
  # after the screenshot, before quit — it has no auto-close of its own and
  # would otherwise outlive the run. screensaver_mode's own mpv is already
  # killed mid-sequence by ss-drive.sh itself (see its own comment), so it
  # needs no second kill here.
  media_kill=""
  if $media_mode; then
    media_kill="bash '$media_kill_script'; "
  fi
  # tray_mode's stub processes have no auto-close of their own either (they
  # sit in GLib.MainLoop().run() forever) — killed by PID right after the
  # screenshot, same reasoning as media_kill above.
  tray_kill=""
  if $tray_mode; then
    tray_kill="bash '$tray_kill_script'; "
  fi
  echo "spawn-at-startup \"sh\" \"-c\" \"sleep $screenshot_delay && niri msg action screenshot-screen --path $shot_dir/smoke.png && ${media_kill}${tray_kill}sleep $tail_gap && niri msg action quit --skip-confirmation\""
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
    # wl-paste --no-newline (see clipboard_drive_script above) means this
    # file has no trailing newline of its own — without the explicit `echo`
    # here, the run's final SMOKE_OK line lands appended to it instead of
    # starting its own line (reproduced: "...smoke twoSMOKE_OK /tmp/...").
    cat "$clip_paste_path"; echo
  else
    echo "SMOKE_FAIL: no post-copy clipboard readback produced" >&2; exit 1
  fi
  if ! grep -q "clipboard smoke two" "$clip_paste_path"; then
    echo "SMOKE_FAIL: system clipboard did not flip to the re-copied entry — got: $(cat "$clip_paste_path")" >&2; exit 1
  fi
fi

if $media_mode; then
  if [ -s "$media_status_path" ]; then
    cat "$media_status_path"
  else
    echo "SMOKE_FAIL: no media status produced" >&2; exit 1
  fi
  if ! grep -q '"available":true' "$media_status_path"; then
    echo "SMOKE_FAIL: media status reports no player available — got: $(cat "$media_status_path")" >&2; exit 1
  fi
  if ! grep -q "\"title\":\"$media_track_title\"" "$media_status_path"; then
    echo "SMOKE_FAIL: media status title does not match the fixture track's tag ($media_track_title) — got: $(cat "$media_status_path")" >&2; exit 1
  fi
  if ! grep -q "\"artist\":\"$media_track_artist\"" "$media_status_path"; then
    echo "SMOKE_FAIL: media status artist does not match the fixture track's tag ($media_track_artist) — got: $(cat "$media_status_path")" >&2; exit 1
  fi
fi

if $lock_mode; then
  if [ -s "$lock_before_sleep_rc_path" ] && grep -q "^0$" "$lock_before_sleep_rc_path"; then
    :
  else
    echo "SMOKE_FAIL: formalshell-lock-before-sleep did not exit 0 with no shell instance running — got: $(cat "$lock_before_sleep_rc_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$lock_call_rc_path" ] && grep -q "^0$" "$lock_call_rc_path"; then
    :
  else
    echo "SMOKE_FAIL: lock lock IPC call exited non-zero — got: $(cat "$lock_call_rc_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$lock_islocked1_path" ] && grep -q "^true$" "$lock_islocked1_path"; then
    :
  else
    echo "SMOKE_FAIL: lock isLocked did not report true right after lock() — got: $(cat "$lock_islocked1_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -f "$lock_locked_path" ]; then
    echo "SMOKE_LOCK_LOCKED $lock_locked_path"
  else
    echo "SMOKE_FAIL: no lock-locked screenshot produced" >&2; exit 1
  fi
  if [ -f "$lock_error_path" ]; then
    echo "SMOKE_LOCK_ERROR $lock_error_path"
  else
    echo "SMOKE_FAIL: no lock-error screenshot produced" >&2; exit 1
  fi
  if [ -f "$lock_unlocked_path" ]; then
    echo "SMOKE_LOCK_UNLOCKED $lock_unlocked_path"
  else
    echo "SMOKE_FAIL: no lock-unlocked screenshot produced" >&2; exit 1
  fi
  if [ -s "$lock_islocked2_path" ] && grep -q "^false$" "$lock_islocked2_path"; then
    :
  else
    echo "SMOKE_FAIL: lock isLocked did not flip back to false after the real password — got: $(cat "$lock_islocked2_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$lock_status_path" ]; then
    cat "$lock_status_path"
  else
    echo "SMOKE_FAIL: no lock status produced" >&2; exit 1
  fi
  if ! grep -q '"locked":false' "$lock_status_path"; then
    echo "SMOKE_FAIL: lock status did not report locked:false after unlock — got: $(cat "$lock_status_path")" >&2; exit 1
  fi
fi

if $screensaver_mode; then
  # Guard-holds proof: mpv still playing, the 3s idle timeout has long
  # since elapsed with no real input anywhere in this session — isIdle
  # must be true, but the live media guard must keep active false anyway.
  if [ -s "$ss_guard_status_path" ]; then
    cat "$ss_guard_status_path"
  else
    echo "SMOKE_FAIL: no screensaver guard-status produced" >&2; exit 1
  fi
  if ! grep -q '"isIdle":true' "$ss_guard_status_path"; then
    echo "SMOKE_FAIL: screensaver status did not report isIdle:true while mpv was still playing — got: $(cat "$ss_guard_status_path")" >&2; exit 1
  fi
  if ! grep -q '"active":false' "$ss_guard_status_path"; then
    echo "SMOKE_FAIL: screensaver activated despite the media guard while mpv was still playing — got: $(cat "$ss_guard_status_path")" >&2; exit 1
  fi
  if ! grep -q '"mediaPlaying":true' "$ss_guard_status_path"; then
    echo "SMOKE_FAIL: screensaver status did not report mediaPlaying:true while mpv was still playing — got: $(cat "$ss_guard_status_path")" >&2; exit 1
  fi
  # Auto-trigger proof: mpv killed, no `screensaver start` call at all — the
  # guard clearing alone must flip active to true.
  if [ -f "$ss_auto_path" ]; then
    echo "SMOKE_SCREENSAVER_AUTO $ss_auto_path"
  else
    echo "SMOKE_FAIL: no screensaver-auto screenshot produced" >&2; exit 1
  fi
  if [ -s "$ss_auto_status_path" ]; then
    cat "$ss_auto_status_path"
  else
    echo "SMOKE_FAIL: no screensaver auto-status produced" >&2; exit 1
  fi
  if ! grep -q '"active":true' "$ss_auto_status_path"; then
    echo "SMOKE_FAIL: screensaver did not auto-activate once the media guard cleared — got: $(cat "$ss_auto_status_path")" >&2; exit 1
  fi
  if [ -s "$ss_dismiss_status_path" ] && grep -q '"active":false' "$ss_dismiss_status_path"; then
    :
  else
    echo "SMOKE_FAIL: screensaver stop IPC call did not flip active back to false — got: $(cat "$ss_dismiss_status_path" 2>/dev/null)" >&2; exit 1
  fi
  # Manual IPC start/stop proof, independent of the idle timer.
  if [ -f "$ss_manual_path" ]; then
    echo "SMOKE_SCREENSAVER_MANUAL $ss_manual_path"
  else
    echo "SMOKE_FAIL: no screensaver-manual screenshot produced" >&2; exit 1
  fi
  if [ -s "$ss_final_status_path" ] && grep -q '"active":false' "$ss_final_status_path"; then
    :
  else
    echo "SMOKE_FAIL: screensaver did not report active:false after the final stop — got: $(cat "$ss_final_status_path" 2>/dev/null)" >&2; exit 1
  fi
fi

if $picker_mode; then
  if [ -f "$picker_grid_path" ]; then
    echo "SMOKE_PICKER_GRID $picker_grid_path"
  else
    echo "SMOKE_FAIL: no picker-grid screenshot produced" >&2; exit 1
  fi
  # Wallpaper-mode proof: choosing a fixture over IPC must have run
  # Core.State.setWallpaper() -> ThemeEngine.retheme(), the same `theme
  # status` check --wallpaper already relies on.
  if [ -s "$picker_theme_status_path" ]; then
    cat "$picker_theme_status_path"
  else
    echo "SMOKE_FAIL: no picker theme-status produced" >&2; exit 1
  fi
  if ! grep -q "\"wallpaper\":\"$picker_dir/img-3.png\"" "$picker_theme_status_path"; then
    echo "SMOKE_FAIL: theme status did not report the picker-chosen wallpaper — got: $(cat "$picker_theme_status_path")" >&2; exit 1
  fi
  # Generic image-selector proof: the second choose(), made against a
  # select()-mode request, must resolve that request's token with the
  # chosen path — the same request/answer handshake MenuIpc's select()
  # verifies via menu-selection.txt.
  if [ -s "$picker_selection_path" ]; then
    cat "$picker_selection_path"
  else
    echo "SMOKE_FAIL: no picker-selection.txt produced" >&2; exit 1
  fi
  if ! grep -q '"token":"tok-picker"' "$picker_selection_path" || ! grep -q "\"value\":\"$picker_dir/img-1.png\"" "$picker_selection_path"; then
    echo "SMOKE_FAIL: picker-selection.txt did not resolve tok-picker with the chosen path — got: $(cat "$picker_selection_path")" >&2; exit 1
  fi
fi

if $tray_mode; then
  if [ -s "$tray_status1_path" ]; then
    cat "$tray_status1_path"
  else
    echo "SMOKE_FAIL: no tray status (pre-expand) produced" >&2; exit 1
  fi
  tray_count1=$(grep -o '"id":' "$tray_status1_path" | wc -l | tr -d ' ')
  if [ "$tray_count1" != "6" ]; then
    echo "SMOKE_FAIL: tray status did not report all 6 fixture items before expand (got $tray_count1) — stub registration likely failed" >&2; exit 1
  fi
  if ! grep -q '"expanded":false' "$tray_status1_path"; then
    echo "SMOKE_FAIL: tray status did not report expanded:false before the expand call — got: $(cat "$tray_status1_path")" >&2; exit 1
  fi
  if [ -f "$tray_collapsed_path" ]; then
    echo "SMOKE_TRAY_COLLAPSED $tray_collapsed_path"
  else
    echo "SMOKE_FAIL: no tray-collapsed screenshot produced" >&2; exit 1
  fi
  if [ -s "$tray_status2_path" ]; then
    cat "$tray_status2_path"
  else
    echo "SMOKE_FAIL: no tray status (post-expand) produced" >&2; exit 1
  fi
  if ! grep -q '"expanded":true' "$tray_status2_path"; then
    echo "SMOKE_FAIL: tray expand IPC call did not flip expanded to true — got: $(cat "$tray_status2_path")" >&2; exit 1
  fi
  tray_count2=$(grep -o '"id":' "$tray_status2_path" | wc -l | tr -d ' ')
  if [ "$tray_count2" != "$tray_count1" ]; then
    echo "SMOKE_FAIL: tray item count changed across expand ($tray_count1 -> $tray_count2)" >&2; exit 1
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
