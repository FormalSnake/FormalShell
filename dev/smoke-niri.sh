#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
# With --dump, also calls the `debug` IPC target and cats the JSON reply.
# With --wallpaper, generates a solid-color test PNG, drives it through
# `wallpaper set` + `theme status` over IPC in-session before screenshotting,
# so the screenshot proves the background/bar actually recolored.
# With --theme-toggle (M13b Task 3, don't combine with --wallpaper: the
# assertions require wallpaper to stay ""), drives `theme mode toggle` twice
# with NO wallpaper set: grim the dark session (theme-dark.png), toggle,
# assert `theme status` reports mode:"light" with wallpaper still "", grim
# again (theme-light.png — the mode-matched Flexoki fallback theme.json
# recoloring every consumer live, no matugen involved), toggle back, assert
# mode:"dark". The run's own smoke.png/SMOKE_OK then shows the session dark
# again. grim, not niri's screenshot-screen, for the usual no-toast reason:
# the two shots exist to compare background/bar colors.
# With --menu, drives the real `menu` IPC target in-session: `summon` opens
# it at root, `select` switches it into select mode (screenshot proves the
# option list renders), then `close` cancels the pending select and the
# resulting selection.txt is read back to prove the {cancelled:true} write.
# Menu.qml's FORMALSHELL_SMOKE_OPEN_MENU env-gated auto-open still exists
# (harmless, useful for manual debugging) but this script no longer relies
# on it now that the real IPC route is wired. After the screenshot, the
# finish script also drives the emoji instant-paste round trip (M13 Task 6):
# `menu summon emoji` + `menu activate 0` wl-copies GRINNING FACE and, once
# the surface has closed, spawns wtype with the same char — asserted via a
# wl-paste readback plus an argv-logging wtype shim on the shell's PATH
# (real typing into a refocused window is host-trial territory). A trailing
# apps leg (M13b Task 1) then summons the apps route over two fixture
# .desktop entries — one with an icon honestly installed into the isolated
# hicolor tree, one whose icon has no theme here — screenshots the rows
# (menu-apps.png: display-name labels, one real icon image, no raw icon
# name as text) and asserts both labels + iconSource states via debug query.
# The nix runner (M13b Task 4) is driven twice over: a serial states script
# walks every end state through a query-dispatching PATH-shimmed nix —
# SEARCHING while the shim blocks on a gate flag file, the canned rows once
# released, SEARCH FAILED on a nonzero exit, NO RESULTS on a clean `{}` —
# then the finish script's last leg summons the menu with the ':nix hello'
# prefill route, activates row 0, and screenshots the resulting NIX RUN
# toast (nix-toast.png) with a `notifications status` popup-count assert.
# With --notify, fires `notify-send -u normal` then `-u critical` in-session
# and screenshots the resulting toasts. Then flips DND on over the existing
# `notifications` IPC target (`setDnd true`, dumped to dnd-status.txt — both
# notify-sends already landed, so this can't retroactively suppress them)
# and screenshots the bar again (indicator-dnd.png) to prove the bell cell
# (BellWidget.qml, M13b Task 2) swaps to its bell-off glyph.
# With --center, fires one more `notify-send -u normal` and waits for
# non-critical popups to auto-expire into the `pending` tier before summoning
# the notification center over the `notifications` IPC target and
# screenshotting it — combine with --notify so there's a critical notify-send
# still sitting sticky in the popup layer: Toasts.qml suppresses that whole
# stack for as long as the center is open, so the screenshot shows the
# center alone, not the two surfaces overlapping. `notifications status` is
# dumped closed -> open -> closed around a showHistory toggle round trip
# (the same center.open()/close() the bell cell's own click calls, so this
# is the click's IPC stand-in) and asserted: pending non-zero before the
# summon, centerOpen flipping true then back false.
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
# `--panel github` runs against the same PATH-shimmed `gh` --bar-layout
# uses (extended with canned PR/issue node rows, M13 Task 3), so the
# panel's on-open poll renders both sections — "PULL REQUESTS / 3" and
# "ISSUES / 2" with the canned titles and dimmed repo slugs — without
# network or auth; the github widget itself stays out of the bar (the
# default no-`bar`-key layout), which is exactly the no-widget IPC-open
# path GithubPanel.qml's header describes.
# `--panel calendar` additionally proves real events render from BOTH of
# CalendarEventsService's backends (M12 Task 3): the isolated HOME always
# carries a one-event .ics fixture dated today (see the calendar-events
# fixture setup below) pointed at by settings.json's calendar.icsDir, and a
# drive script seeds one more real VEVENT into EDS's system-calendar over
# the run's private session bus (`formalshell-eds seed`, a genuine
# CreateObjects write that D-Bus-activates evolution-data-server in the
# isolated session — never a mock) before opening the panel, whose on-open
# refresh then reads it back through `formalshell-eds events`. The seed's
# own stdout/rc lands in eds-seed.txt and a failed seed fails the run.
# Day selection (M13 Task 4): a second EDS VEVENT dated tomorrow is seeded
# too, then `calendar select <tomorrow>` runs after the open — the
# screenshot must show tomorrow's cell inverted (today's cell accent-filled
# next to it) and the events ledger listing EDS TOMORROW EVENT under the
# dated meta header; `calendar status` must report tomorrow selected.
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
# independently of the idle timer. That manual activation then proves
# continuous cycling (M13b Task 5): the settings fixture shortens
# screensaver.holdSeconds to 2s, `screensaver frameInfo` right after the
# start records the cycles:0 baseline (screensaver-cycle-info-1.json), and
# a read-only frameInfo poll — no IPC nudge, the reroll happens purely from
# the effect converging and the hold elapsing — waits until cycles leaves 0
# (screensaver-cycle-info-2.json), asserting afterwards that the counter
# incremented and the reported effect changed (random never repeats the
# immediately previous effect; with SCREENSAVER_EFFECT pinned the effect
# must instead stay the same, the pinned-replay proof).
# With --screensaver-gif, records all five effects in effect.js as GIFs
# rather than screenshotting one: for each effect in turn, its own isolated
# settings.json fixture pins screensaver.effect to that name, a fresh nested
# niri session boots, `screensaver start` shows it, `screensaver frameInfo`
# reads back the real convergence frame (ScreensaverIpc's M11 Task 1 verb —
# never guessed, since the VM's llvmpipe rendering makes wall-clock capture
# uneven), then `screensaver frame <n>` pins and screenshots every frame from
# 0 through convergence plus a short hold before `screensaver stop` and quit.
# Runs entirely separately from every other mode's shared single-session
# timeline below (it needs five independent sessions, not one), assembling
# each effect's captured frames into docs/media/screensaver-<effect>.gif with
# imagemagick (scaled to 640px wide, palette-capped, layers-optimized) before
# moving to the next effect. This run's SMOKE_OK points at the last captured
# frame of the final effect (a real converged banner), and each effect's own
# GIF path/byte size is printed on its own SMOKE_SCREENSAVER_GIF_<EFFECT> line.
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
# with the same item count); then `tray activate tray-fixture-2` drives the
# exact Activate() call Tray.qml's own left-click handler makes, and the
# stub's --activate-file (tray-activate.txt) is asserted afterward, proving
# the D-Bus Activate round trip reached the item. Opening an item's DBusMenu
# stays host-trial territory (a platform QMenu with no pointer to dismiss it
# would wedge a headless run — see TrayIpc.qml). This run's generic
# smoke.png/SMOKE_OK is taken after the expand call, so it shows every item
# as its own cell, drawer open. The stub processes are killed by PID
# (tray-pids.txt, same pattern as --media's mpv) right before niri quits.
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
# With --bar-layout, points settings.json's bar.layout at a left region led
# by the opt-in github builtin (M12 Task 8, against a PATH-shimmed `gh`
# returning canned graphql counts, same hermetic-producer idea as the nix
# shim below — first in the list so the region's clip can never hide it),
# then six bar.modules entries, then the reordered builtins (activeWindow
# before workspaces — swapped from today's default, M10 Task 3): a
# "command" module printing known Waybar-JSON `{text, tooltip, class}`
# (happy path), four more "command" modules that each exercise one of
# CommandModule.qml's failure paths — non-zero exit, output that isn't
# valid JSON, a command that outlives its configured `timeout`, and a
# command binary that doesn't exist at all (quickshell's Process only
# emits runningChanged for that case, never `exited` — the bug this task
# fixed) — so the screenshot shows all four rendering the same honest
# "MODULE ERROR" cell rather than staying blank, and a "qml" module (a
# fixture file that itself `import qs.Core`s and reads Theme, proving a
# loaded user component really does share the shell's own engine). Left
# rather than right: it's the nearly-empty region (two builtins, both
# narrow), so six more wide cells still fit ahead of the centered clock
# instead of growing the right region's Row wide enough to overlap it. No
# drive script needed — layout.js resolves this from settings.json at
# startup same as any other Config-driven surface — so the run's own
# generic smoke.png already shows all of them; bar-layout.png is the same
# shot under a name
# that doesn't depend on remembering which run produced smoke.png. Every
# other mode
# still omits the `bar` key entirely, so their own screenshots keep proving
# the no-config fallback renders today's exact arrangement.
#
# With --screenshot, drives the `screenshot` IPC target (M12 Task 9, M13
# Task 7). First the region/cancel round trip: `screenshot region` starts a
# real themed slurp in the nested session (it blocks on a drag no headless
# run can supply — the exact stuck state the cancel path exists for), the
# drive proves it via pgrep plus status capturing:true, then `screenshot
# cancel` kills it and status must settle to capturing:false /
# lastCancelled:true / empty lastError with slurp gone and no file written.
# Then the full-capture flow in the same session: `screenshot full` replies
# synchronously with the destination path (the grim/wl-copy pipeline it
# starts is async), the drive polls `screenshot status` until
# capturing:false, then dumps the clipboard's offered MIME types via
# wl-paste. Post-run assertions: the reply path exists and file(1) calls it
# a PNG, status settled with an empty lastError and lastPath matching the
# reply, and the type dump offers image/png (the wl-copy proof). No
# screenshot.directory is set in the settings fixture on purpose: the
# capture landing under the isolated HOME's Pictures/Screenshots proves the
# documented default resolves. This run's generic smoke.png, taken at the
# usual 8s, additionally shows the SCREENSHOT CANCELLED and SCREENSHOT
# SAVED toasts (fired around 4-5s, 6s popup timeout). Slurp's dim/accent
# overlay look and a real drag stay host-trial; the 90s watchdog rides the
# same _cancel path the verb drives, so the verb round trip is its proof.
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
theme_toggle_mode=false
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
screensaver_gif_mode=false
picker_mode=false
tray_mode=false
bar_layout_mode=false
screenshot_mode=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) dump_mode=true; shift ;;
    --wallpaper) wallpaper_mode=true; shift ;;
    --theme-toggle) theme_toggle_mode=true; shift ;;
    --menu) menu_mode=true; shift ;;
    --notify) notify_mode=true; shift ;;
    --center) center_mode=true; shift ;;
    --osd) osd_mode=true; shift ;;
    --panel) panel_mode=true; panel_name="$2"; shift 2 ;;
    --clipboard) clipboard_mode=true; shift ;;
    --media) media_mode=true; shift ;;
    --lock) lock_mode=true; shift ;;
    --screensaver) screensaver_mode=true; shift ;;
    --screensaver-gif) screensaver_gif_mode=true; shift ;;
    --picker) picker_mode=true; shift ;;
    --tray) tray_mode=true; shift ;;
    --bar-layout) bar_layout_mode=true; shift ;;
    --screenshot) screenshot_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--wallpaper] [--theme-toggle] [--menu] [--notify] [--center] [--osd] [--panel <name>] [--clipboard] [--media] [--lock] [--screensaver] [--screensaver-gif] [--picker] [--tray] [--bar-layout] [--screenshot]" >&2; exit 1 ;;
  esac
done

# --panel github shares the gh shim (and its PATH splice) with --bar-layout.
panel_github_mode=false
if $panel_mode && [ "$panel_name" = "github" ]; then
  panel_github_mode=true
fi

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

if $wallpaper_mode || $picker_mode || $screensaver_gif_mode || $menu_mode; then
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
fi

# screenshot_mode and menu_mode only read the clipboard back (the shell's
# own wrapper PATH carries the wl-copy side); clipboard_mode needs both
# directions.
if $clipboard_mode || $screenshot_mode || $menu_mode; then
  if command -v wl-paste >/dev/null 2>&1; then
    wl_paste_bin=$(command -v wl-paste)
  else
    wl_paste_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-paste
  fi
fi

if $screenshot_mode; then
  if command -v file >/dev/null 2>&1; then
    file_bin=$(command -v file)
  else
    file_bin=$(nix build 'nixpkgs#file^out' --no-link --print-out-paths)/bin/file
  fi
fi

# --panel calendar seeds a real VEVENT into EDS (M12 Task 3). In the VM
# formalshell-eds sits in systemPackages; anywhere else, build it from this
# repo's own flake output rather than guessing at a store path.
if $panel_mode && [ "$panel_name" = "calendar" ]; then
  if command -v formalshell-eds >/dev/null 2>&1; then
    eds_bin=$(command -v formalshell-eds)
  else
    eds_bin=$(nix build .#formalshell-eds --no-link --print-out-paths)/bin/formalshell-eds
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
fi

if $lock_mode || $screensaver_gif_mode || $menu_mode || $theme_toggle_mode; then
  # niri's own `screenshot-screen` msg action is deliberately refused while
  # the session is locked (niri-wm/niri discussion #2384: "to prevent people
  # from spamming your disk with images even when the session is locked") —
  # confirmed by reproducing it: the action silently no-ops, no error, no
  # file. grim talks the underlying wlr-screencopy protocol directly as an
  # ordinary Wayland client, which niri does NOT gate behind the lock, and
  # is what actually proves the three lock-state screenshots below.
  # screensaver_gif_mode reuses grim for the opposite reason: `screenshot-
  # screen` triggers niri's own "Screenshot captured" toast every single
  # call, which stacks up across a frame-stepping run's dozens of captures
  # and visibly covers part of the banner (reproduced on the mac VM rig,
  # 2026-07-29) — grim's screencopy-protocol path never does that.
  # menu_mode's trailing apps-route capture (M13b Task 1) picks grim for
  # the same no-toast reason: the shot exists to read two menu rows.
  # theme_toggle_mode's dark/light pair (M13b Task 3) likewise: those two
  # shots exist to compare background/bar colors.
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

# --screensaver-gif: five independent nested-niri sessions (one per effect),
# entirely separate from every other mode's shared single-session timeline
# below. Frame-stepping (ScreensaverIpc's `frame(n)`/`frameInfo()`, M11 Task
# 1) means each frame's capture only needs to wait for one repaint, not a
# wall-clock-timed slot in a fixed schedule — the reason a naive burst
# screenshot of the live animation would look choppy on this VM's llvmpipe
# rendering in the first place.
if $screensaver_gif_mode; then
  ss_gif_hold=8   # extra frames held on the finished banner after convergence
  ss_gif_home=$(mktemp -d)
  media_dir="$PWD/docs/media"
  mkdir -p "$media_dir" "$ss_gif_home/.config/formalshell"

  # SCREENSAVER_GIF_EFFECTS (optional, additive, space-separated): limits
  # the run to a subset — a recorder-contract verification only needs one
  # effect and must not regenerate every committed GIF to prove it.
  ss_gif_effects=(decrypt rain expand slide scatter)
  if [ -n "${SCREENSAVER_GIF_EFFECTS:-}" ]; then
    read -r -a ss_gif_effects <<< "$SCREENSAVER_GIF_EFFECTS"
  fi
  for ss_gif_i in "${!ss_gif_effects[@]}"; do
    effect="${ss_gif_effects[$ss_gif_i]}"
    # One tmp dir per effect (frames + config + drive script together,
    # mirroring every other mode's single shot_dir) — rm -rf'd once its GIF
    # is built, except the last effect's, which cmd_smoke still needs to
    # scp its SMOKE_OK frame back after this script exits.
    effect_dir=$(mktemp -d)
    frames_dir="$effect_dir/frames"
    mkdir -p "$frames_dir"
    cat > "$ss_gif_home/.config/formalshell/settings.json" <<EOF
{"screensaver": {"effect": "$effect"}}
EOF

    ss_gif_cfg="$effect_dir/config.kdl"
    ss_gif_convergence_path="$frames_dir/frame-info.json"
    ss_gif_drive_script="$frames_dir/drive.sh"
    cat > "$ss_gif_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver start > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver frameInfo > "$ss_gif_convergence_path" 2>&1
convergence=\$(grep -o '"convergenceFrame":[0-9]*' "$ss_gif_convergence_path" | cut -d: -f2)
last=\$((convergence + $ss_gif_hold))
for ((i = 0; i <= last; i++)); do
  "$qs_bin" ipc --any-display -p "$shell_path" call screensaver frame "\$i" > /dev/null 2>&1
  sleep 0.15
  printf -v padded "%04d" "\$i"
  "$grim_bin" "$frames_dir/frame-\$padded.png"
done
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver stop > /dev/null 2>&1
niri msg action quit --skip-confirmation
EOF

    {
      echo 'hotkey-overlay {'
      echo '    skip-at-startup'
      echo '}'
      echo "spawn-at-startup \"$PWD/result/bin/formalshell\""
      echo "spawn-at-startup \"bash\" \"$ss_gif_drive_script\""
    } > "$ss_gif_cfg"

    HOME="$ss_gif_home" \
    XDG_CONFIG_HOME="$ss_gif_home/.config" \
    XDG_STATE_HOME="$ss_gif_home/.local/state" \
    XDG_DATA_HOME="$ss_gif_home/.local/share" \
    XDG_DATA_DIRS="$ss_gif_home/.local/share" \
    XDG_CACHE_HOME="$ss_gif_home/.cache" \
    WAYLAND_DISPLAY="$wayland_display" dbus-run-session -- timeout 200 $niri_bin --config "$ss_gif_cfg" || true

    if [ ! -s "$ss_gif_convergence_path" ] || ! grep -q "\"effect\":\"$effect\"" "$ss_gif_convergence_path"; then
      echo "SMOKE_FAIL: screensaver frameInfo did not report effect '$effect' — got: $(cat "$ss_gif_convergence_path" 2>/dev/null)" >&2
      exit 1
    fi
    convergence=$(grep -o '"convergenceFrame":[0-9]*' "$ss_gif_convergence_path" | cut -d: -f2)
    expected_frames=$((convergence + ss_gif_hold + 1))

    shopt -s nullglob
    frame_files=("$frames_dir"/frame-*.png)
    shopt -u nullglob
    frame_count=${#frame_files[@]}
    # Exact match, not just "enough frames": a session killed mid-capture
    # (the drive script's own `timeout 200`, or slide's 92-frame run at
    # 0.15s/frame plus one qs ipc spawn each) would otherwise still produce
    # a plausible-looking but truncated GIF that never reaches the banner,
    # and this would exit 0 regardless.
    if [ "$frame_count" -ne "$expected_frames" ]; then
      echo "SMOKE_FAIL: $effect captured $frame_count frame(s), expected the full convergence run of $expected_frames (convergence $convergence + hold $ss_gif_hold + 1) — session likely killed mid-capture" >&2
      exit 1
    fi

    out_gif="$media_dir/screensaver-$effect.gif"
    # -delay 9 (90ms/frame) matches the real Timer interval exactly, since
    # every frame is captured (no stride) — layers-optimize plus a capped
    # palette is what keeps a mostly-static-background animation small.
    "$convert_bin" -delay 9 -loop 0 "$frames_dir"/frame-*.png -resize 640x -coalesce -layers Optimize -colors 96 "$out_gif"
    if [ ! -s "$out_gif" ]; then
      echo "SMOKE_FAIL: imagemagick did not produce $out_gif for effect $effect" >&2
      exit 1
    fi
    gif_size=$(wc -c < "$out_gif" | tr -d ' ')
    echo "SMOKE_SCREENSAVER_GIF_${effect^^} $out_gif ($gif_size bytes, $frame_count frames)"

    ss_gif_last_frame="${frame_files[$((frame_count - 1))]}"
    # Every effect but the last is done with its raw frames the moment its
    # GIF exists; the last effect's dir survives so cmd_smoke can still scp
    # its SMOKE_OK frame back after this script has already exited.
    if [ "$ss_gif_i" -lt "$((${#ss_gif_effects[@]} - 1))" ]; then
      rm -rf "$effect_dir"
    fi
  done

  host_notifications_owner_after=$(host_notifications_owner)
  if [ "$host_notifications_owner_before" != "$host_notifications_owner_after" ]; then
    echo "SMOKE_FAIL: host org.freedesktop.Notifications owner PID changed ($host_notifications_owner_before -> $host_notifications_owner_after) — nested NotificationServer touched the host bus" >&2
    exit 1
  fi

  echo "SMOKE_OK $ss_gif_last_frame"
  exit 0
fi

shot_dir=$(mktemp -d)
dump_path="$shot_dir/dump.json"
status_path="$shot_dir/status.json"
theme_dark_png="$shot_dir/theme-dark.png"
theme_light_png="$shot_dir/theme-light.png"
theme_toggle_status_path="$shot_dir/theme-toggle-status.json"
theme_toggle_status2_path="$shot_dir/theme-toggle-status-2.json"
query_path="$shot_dir/query.json"
calc_query_path="$shot_dir/calc-query.json"
emoji_query_path="$shot_dir/emoji-query.json"
nix_searching_arm_path="$shot_dir/nix-searching-arm.json"
nix_searching_path="$shot_dir/nix-searching.json"
nix_released_path="$shot_dir/nix-released.json"
nix_failed_path="$shot_dir/nix-failed.json"
nix_empty_path="$shot_dir/nix-empty.json"
nix_gate_path="$shot_dir/nix-gate.flag"
nix_states_done_path="$shot_dir/nix-states-done.flag"
nix_run_drive_path="$shot_dir/nix-run-drive.txt"
nix_toast_png="$shot_dir/nix-toast.png"
nix_toast_status_path="$shot_dir/nix-toast-status.json"
wall_query_path="$shot_dir/wall-query.json"
apps_query_path="$shot_dir/apps-query.json"
menu_apps_png="$shot_dir/menu-apps.png"
toggle_path="$shot_dir/menu-toggle.txt"
emoji_drive_path="$shot_dir/emoji-drive.txt"
emoji_paste_path="$shot_dir/emoji-paste.txt"
emoji_type_path="$shot_dir/emoji-wtype.txt"
selection_path="$shot_dir/selection.txt"
dnd_status_path="$shot_dir/dnd-status.txt"
dnd_indicator_path="$shot_dir/indicator-dnd.png"
center_status_before_path="$shot_dir/center-status-before.json"
center_status_open_path="$shot_dir/center-status-open.json"
center_status_closed_path="$shot_dir/center-status-closed.json"
osd_manual_path="$shot_dir/osd-manual.png"
osd_brightness_path="$shot_dir/osd-brightness.png"
clip_list1_path="$shot_dir/clip-list-1.json"
clip_list2_path="$shot_dir/clip-list-2.json"
clip_copy_path="$shot_dir/clip-copy.txt"
clip_paste_path="$shot_dir/clip-paste.txt"
media_status_path="$shot_dir/media-status.json"
eds_seed_path="$shot_dir/eds-seed.txt"
eds_seed2_path="$shot_dir/eds-seed-2.txt"
calendar_select_path="$shot_dir/calendar-select.txt"
calendar_status_path="$shot_dir/calendar-status.json"
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
ss_cycle_info1_path="$shot_dir/screensaver-cycle-info-1.json"
ss_cycle_info2_path="$shot_dir/screensaver-cycle-info-2.json"
ss_final_status_path="$shot_dir/screensaver-final-status.json"
picker_grid_path="$shot_dir/picker-grid.png"
picker_theme_status_path="$shot_dir/picker-theme-status.json"
picker_selection_path="$shot_dir/picker-selection.txt"
tray_status1_path="$shot_dir/tray-status-1.json"
tray_status2_path="$shot_dir/tray-status-2.json"
tray_collapsed_path="$shot_dir/tray-collapsed.png"
tray_pids_path="$shot_dir/tray-pids.txt"
tray_activate_path="$shot_dir/tray-activate.txt"
tray_activate_reply_path="$shot_dir/tray-activate-reply.txt"
bar_layout_path="$shot_dir/bar-layout.png"
screenshot_reply_path="$shot_dir/screenshot-reply.txt"
screenshot_status_path="$shot_dir/screenshot-status.json"
screenshot_types_path="$shot_dir/screenshot-types.txt"
screenshot_region_reply_path="$shot_dir/screenshot-region-reply.txt"
screenshot_region_status_path="$shot_dir/screenshot-region-status.json"
screenshot_cancel_reply_path="$shot_dir/screenshot-cancel-reply.txt"
screenshot_cancelled_status_path="$shot_dir/screenshot-cancelled-status.json"
screenshot_slurp_before_path="$shot_dir/screenshot-slurp-before.txt"
screenshot_slurp_after_path="$shot_dir/screenshot-slurp-after.txt"

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

# M13b Task 1: a second fixture app whose icon actually resolves. The PNG
# is honestly installed into the isolated data dir's hicolor tree (with the
# minimal index.theme QIconLoader requires to enumerate directories at all —
# without it QIcon::fromTheme finds nothing, verified against the pinned
# quickshell rev), so the menu's app rows render one themed icon image and
# one honest icon-less row ("Formal Test App" above: utilities-terminal has
# no theme here, check-resolution answers "", never a missing-texture box).
if $menu_mode; then
  cat > "$iso_home/.local/share/applications/formalshell-smoke-iconic.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Iconic Test App
Exec=true
Icon=formalshell-smoke
EOF
  mkdir -p "$iso_home/.local/share/icons/hicolor/48x48/apps"
  $convert_bin -size 48x48 xc:'#CE5D97' "$iso_home/.local/share/icons/hicolor/48x48/apps/formalshell-smoke.png"
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
  # holdSeconds shortened the same way timeoutSeconds is: the cycle proof
  # waits out a real convergence + hold, just on an affordable schedule.
  screensaver_settings=', "screensaver": {"timeoutSeconds": 3, "guardMediaPlayback": true, "holdSeconds": 2'"$ss_effect_json$ss_ascii_json"'}'
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
# bar_layout_mode (M10 Task 3): points five bar.modules entries (written to
# disk below, after settings.json itself) at the front of the left region,
# ahead of the reordered activeWindow/workspaces builtins. Every other mode
# leaves the `bar` key out entirely, which is itself the no-config-fallback
# proof.
bar_settings=""
bar_cmd_fixture_path="$shot_dir/bar-cmd-fixture.sh"
bar_cmd_fail_path="$shot_dir/bar-cmd-fail.sh"
bar_cmd_badjson_path="$shot_dir/bar-cmd-badjson.sh"
bar_cmd_timeout_path="$shot_dir/bar-cmd-timeout.sh"
bar_qml_fixture_path="$shot_dir/bar-qml-fixture.qml"
if $bar_layout_mode; then
  bar_settings=', "bar": {"layout": {"left": ["github", "custom:cmdfixture", "custom:cmdfail", "custom:cmdbadjson", "custom:cmdtimeout", "custom:cmdmissing", "custom:qmlfixture", "activeWindow", "workspaces"]}, "modules": [{"id": "cmdfixture", "type": "command", "command": ["bash", "'"$bar_cmd_fixture_path"'"], "interval": 2000}, {"id": "cmdfail", "type": "command", "command": ["bash", "'"$bar_cmd_fail_path"'"], "interval": 20000}, {"id": "cmdbadjson", "type": "command", "command": ["bash", "'"$bar_cmd_badjson_path"'"], "interval": 20000}, {"id": "cmdtimeout", "type": "command", "command": ["bash", "'"$bar_cmd_timeout_path"'"], "interval": 20000, "timeout": 1000}, {"id": "cmdmissing", "type": "command", "command": ["'"$shot_dir"'/no-such-formalshell-smoke-binary"], "interval": 20000}, {"id": "qmlfixture", "type": "qml", "source": "'"$bar_qml_fixture_path"'"}]}'
fi
cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$screensaver_settings$picker_settings$bar_settings}
EOF

if $bar_layout_mode; then
  cat > "$bar_cmd_fixture_path" <<'EOF'
#!/usr/bin/env bash
printf '{"text": "CMD 42", "tooltip": "smoke fixture tooltip", "class": "warning"}'
EOF
  chmod +x "$bar_cmd_fixture_path"
  # Four failure-path fixtures (CommandModule.qml, M10 review brief): a
  # non-zero exit despite well-formed stdout, well-formed exit but
  # unparsable stdout, a command that outlives its module's own `timeout`
  # (set to 1s above, well inside the 5s wait before this run's screenshot),
  # and a command path that doesn't exist at all — no script written for
  # that last one, `cmdmissing`'s own settings.json command entry above
  # points straight at a path under $shot_dir that's never created. Each
  # must render "MODULE ERROR" rather than staying blank.
  cat > "$bar_cmd_fail_path" <<'EOF'
#!/usr/bin/env bash
printf '{"text": "should not render"}'
exit 1
EOF
  chmod +x "$bar_cmd_fail_path"
  cat > "$bar_cmd_badjson_path" <<'EOF'
#!/usr/bin/env bash
printf 'not json'
EOF
  chmod +x "$bar_cmd_badjson_path"
  cat > "$bar_cmd_timeout_path" <<'EOF'
#!/usr/bin/env bash
sleep 5
printf '{"text": "too late"}'
EOF
  chmod +x "$bar_cmd_timeout_path"
  # Deliberately `import qs.Core` and read Theme — proof that a loaded user
  # component really does share the shell's own engine (QmlModule.qml's own
  # header comment: Loader isolates load-time failures only, not a runtime
  # sandbox), not just a static string.
  cat > "$bar_qml_fixture_path" <<'EOF'
import QtQuick
import qs.Core

Text {
    text: "QML OK"
    color: Theme.color.foreground
    font.family: Theme.font.family
    font.pixelSize: Theme.fontSize.body
}
EOF
fi

# PATH-shimmed gh fixture (M12 Task 8, same hermetic-producer idea as the
# nix shim above): a canned `gh api graphql` answer in the exact shape
# GithubPanel.qml's combined search query returns, so --bar-layout's
# screenshot proves the whole poll -> parse -> "3/2" cell path and --panel
# github's proves the two panel sections' canned rows, without network or
# auth. Real `gh` behaviour (auth, exit code 4) is host-trial territory.
if $bar_layout_mode || $panel_github_mode; then
  gh_shim_dir="$shot_dir/gh-shim"
  mkdir -p "$gh_shim_dir"
  cat > "$gh_shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ]; then
  printf '%s\n' '{"data":{"prs":{"issueCount":3,"nodes":[{"title":"Sort workspaces by idx","url":"https://github.com/formalshell/formalshell/pull/101","repository":{"nameWithOwner":"formalshell/formalshell"}},{"title":"Tray dbusmenu support","url":"https://github.com/formalshell/formalshell/pull/102","repository":{"nameWithOwner":"formalshell/formalshell"}},{"title":"Panel motion tokens","url":"https://github.com/formalshell/formalshell/pull/103","repository":{"nameWithOwner":"formalshell/formalshell"}}]},"issues":{"issueCount":2,"nodes":[{"title":"Calendar day selection","url":"https://github.com/formalshell/formalshell/issues/201","repository":{"nameWithOwner":"formalshell/formalshell"}},{"title":"Emoji picker should paste","url":"https://github.com/formalshell/formalshell/issues/202","repository":{"nameWithOwner":"formalshell/formalshell"}}]}}}'
  exit 0
fi
exit 1
EOF
  chmod +x "$gh_shim_dir/gh"
fi

if $picker_mode; then
  for name_color in "img-0:#c0392b" "img-1:#27ae60" "img-2:#2980b9" "img-3:#f1c40f" "img-4:#8e44ad"; do
    $convert_bin -size 64x64 "xc:${name_color#*:}" "$picker_dir/${name_color%:*}.png"
  done
fi

if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  $convert_bin -size 640x480 xc:'#7a3fb0' "$wp_path"
fi

# --theme-toggle's drive: the dark shot waits out shell startup (same 4s the
# other modes' first actions allow llvmpipe), each toggle then gets 2s for
# ThemeEngine's fallback theme.json write plus Theme.qml's FileView reload
# before the status dump and (first leg) the light shot.
if $theme_toggle_mode; then
  theme_toggle_drive_script="$shot_dir/theme-toggle-drive.sh"
  cat > "$theme_toggle_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$grim_bin" "$theme_dark_png"
"$qs_bin" ipc --any-display -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call theme status > "$theme_toggle_status_path" 2>&1
"$grim_bin" "$theme_light_png"
"$qs_bin" ipc --any-display -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call theme status > "$theme_toggle_status2_path" 2>&1
EOF
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
  # the outer `timeout 40` fired.
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

  # The trailing no-arg `menu toggle` round trip (M13 Task 5: the win+space
  # keybind regression was summon's mandatory-route arity) runs after the
  # close, from the same closed state a keybind would hit: toggle-open,
  # status (isOpen true at root), toggle-close, status (isOpen false) — all
  # four replies land in one file the assertions below check in order.
  menu_finish_script="$shot_dir/menu-finish.sh"
  cat > "$menu_finish_script" <<EOF
#!/usr/bin/env bash
sleep 9
"$qs_bin" ipc --any-display -p "$shell_path" call menu close > /dev/null 2>&1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
{
  "$qs_bin" ipc --any-display -p "$shell_path" call menu toggle
  "$qs_bin" ipc --any-display -p "$shell_path" call menu status
  "$qs_bin" ipc --any-display -p "$shell_path" call menu toggle
  "$qs_bin" ipc --any-display -p "$shell_path" call menu status
} > "$toggle_path" 2>&1
EOF

  # Emoji instant paste (M13 Task 6), appended to the finish script so it
  # runs from the same closed state the toggle round trip leaves behind:
  # re-summon at the emoji route and activate row 0 (GRINNING FACE, the
  # deterministic browse head; `menu activate` is the rig's stand-in for
  # Enter, PickerIpc.choose's division). The row's action wl-copies the
  # char, then Menu.qml's post-close settle spawns wtype — resolved here to
  # the argv-logging shim below, which outranks the package's own bundled
  # wtype because package.nix wires that one in with --suffix (see its
  # comment). The 2s sleep covers close + 150ms settle + spawn on the VM's
  # slow rig; real typing into a refocused window is host-trial territory.
  cat >> "$menu_finish_script" <<EOF
{
  "$qs_bin" ipc --any-display -p "$shell_path" call menu summon emoji
  "$qs_bin" ipc --any-display -p "$shell_path" call menu activate 0
} > "$emoji_drive_path" 2>&1
sleep 2
"$wl_paste_bin" --no-newline > "$emoji_paste_path" 2>&1 || true
EOF

  # Apps rows (M13b Task 1), appended after the emoji leg so it runs from a
  # closed menu: summon the apps route, give llvmpipe 2s to paint the two
  # fixture rows, grim the surface (the run's proof an app row renders a
  # real themed icon image, not the raw icon name as text), then rank "test
  # app" over the live tree — the query's iconSource field asserts the
  # themed lookup resolved (and honestly didn't, for the icon-less fixture)
  # without needing the screenshot. tail_gap below is stretched to cover
  # this trailing leg before niri quits.
  cat >> "$menu_finish_script" <<EOF
"$qs_bin" ipc --any-display -p "$shell_path" call menu summon apps > /dev/null 2>&1
sleep 2
"$grim_bin" "$menu_apps_png" 2>/dev/null || true
"$qs_bin" ipc --any-display -p "$shell_path" call debug query "test app" > "$apps_query_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call menu close > /dev/null 2>&1
EOF

  # Launch feedback (M13b Task 4), the trailing leg: summon with the
  # ':nix hello' prefill (open()'s ":"-led route — the keybind path, no
  # keyboard delivery needed), wait out the debounce + shim round trip,
  # activate row 0. Activation fires NotificationService.notify("NIX RUN",
  # "hello") alongside the terminal spawn (ghostty isn't in the VM, so that
  # sh dies silently — exactly the slow/absent-terminal case the toast
  # exists for), so the grim 1s later shows the toast card over the bare
  # session and the status dump shows a live popup. Gated on the states
  # script's done flag (written below): its serial want-query sequence must
  # fully land before this summon re-arms the search with hello.
  cat >> "$menu_finish_script" <<EOF
until [ -f "$nix_states_done_path" ]; do sleep 0.5; done
{
  "$qs_bin" ipc --any-display -p "$shell_path" call menu summon ':nix hello'
  sleep 2
  "$qs_bin" ipc --any-display -p "$shell_path" call menu activate 0
} > "$nix_run_drive_path" 2>&1
sleep 1
"$grim_bin" "$nix_toast_png" 2>/dev/null || true
"$qs_bin" ipc --any-display -p "$shell_path" call notifications status > "$nix_toast_status_path" 2>&1
EOF

  # PATH-shimmed nix fixture (M12 Task 7; M13b Task 4 made it dispatch on
  # the query — same hermetic-producer idea as dev/sni-stub.py) so each of
  # the runner's end states is drivable through the real debounce ->
  # Process -> outcome path: `slowblock` blocks until the gate flag file
  # exists (the SEARCHING assertion window), `failplease` exits 1 (SEARCH
  # FAILED), `emptyplease` prints nix's clean zero-hit `{}` (NO RESULTS),
  # anything else answers the canned two-row set. The shim dir is prepended
  # to PATH for the shell spawn alone (below), so nothing else in the run —
  # including this script's own `nix build` — ever sees it. Real `nix
  # search` behaviour and its tens-of-seconds cold-cache timing are
  # host-trial territory.
  nix_shim_dir="$shot_dir/nix-shim"
  mkdir -p "$nix_shim_dir"
  cat > "$nix_shim_dir/nix" <<EOF
#!/usr/bin/env bash
canned='{"legacyPackages.x86_64-linux.hello":{"description":"A program that produces a familiar, friendly greeting","pname":"hello","version":"2.12.1"},"legacyPackages.x86_64-linux.hello-wayland":{"description":"Hello world Wayland client","pname":"hello-wayland","version":"unstable-2023-03-16"}}'
if [ "\${1:-}" = "search" ]; then
  case "\${3:-}" in
    slowblock)
      until [ -f "$nix_gate_path" ]; do sleep 0.2; done
      printf '%s\n' "\$canned"; exit 0 ;;
    failplease)
      echo 'error: unable to download' >&2; exit 1 ;;
    emptyplease)
      printf '%s\n' '{}'; exit 0 ;;
    *)
      printf '%s\n' "\$canned"; exit 0 ;;
  esac
fi
exit 1
EOF
  chmod +x "$nix_shim_dir/nix"

  # M13b Task 4: drives each end state through the real path via `debug
  # query` (which arms the search exactly like typing). Strictly serial in
  # one script — a want-query flip mid-flight would starve whichever query
  # a parallel one-liner asserted — and safe to run alongside the
  # menu-open/select drives, since `debug query` never touches the open
  # surface. The done flag at the end releases the finish script's toast
  # leg above, whose summon re-arms the search with its own query.
  nix_states_script="$shot_dir/nix-states.sh"
  cat > "$nix_states_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix slowblock' > "$nix_searching_arm_path" 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix slowblock' > "$nix_searching_path" 2>&1
touch "$nix_gate_path"
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix slowblock' > "$nix_released_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix failplease' > /dev/null 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix failplease' > "$nix_failed_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix emptyplease' > /dev/null 2>&1
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call debug query ':nix emptyplease' > "$nix_empty_path" 2>&1
touch "$nix_states_done_path"
EOF

  # PATH-shimmed wtype (M13 Task 6, same hermetic-producer idea as the nix
  # shim above): logs its argv instead of typing, proving Menu.qml's
  # post-close spawn fired with the raw char.
  wtype_shim_dir="$shot_dir/wtype-shim"
  mkdir -p "$wtype_shim_dir"
  cat > "$wtype_shim_dir/wtype" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$emoji_type_path"
EOF
  chmod +x "$wtype_shim_dir/wtype"
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

# --panel calendar's drive (M12 Task 3) replaces the generic sleep-3 panel
# open below for that one panel name: seed one real VEVENT into EDS's
# system-calendar first (the CreateObjects write itself D-Bus-activates
# evolution-data-server on this run's private bus, under the isolated
# HOME), then open the panel, whose on-open refresh reads the event back
# through `formalshell-eds events`. Strictly ordered — seed, then open —
# because the shell's own startup refresh has usually already run before
# the seed lands. M13 Task 4 adds a second seed dated tomorrow plus a
# `calendar select` drive AFTER the open (open resets selection to today,
# so the order matters): the run's screenshot then shows tomorrow's cell
# inverted, today's cell accent-filled, and the events ledger listing the
# tomorrow fixture under a dated meta header instead of TODAY.
if $panel_mode && [ "$panel_name" = "calendar" ]; then
  eds_drive_script="$shot_dir/eds-drive.sh"
  cat > "$eds_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$eds_bin" seed "EDS FIXTURE EVENT" "\$(date +%F)" > "$eds_seed_path" 2>&1
echo "rc=\$?" >> "$eds_seed_path"
"$eds_bin" seed "EDS TOMORROW EVENT" "\$(date -d tomorrow +%F)" > "$eds_seed2_path" 2>&1
echo "rc=\$?" >> "$eds_seed2_path"
"$qs_bin" ipc --any-display -p "$shell_path" call panel open calendar
sleep 2
"$qs_bin" ipc --any-display -p "$shell_path" call calendar select "\$(date -d tomorrow +%F)" > "$calendar_select_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call calendar status > "$calendar_status_path" 2>&1
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
  # it depends on auto-triggering again. The cycle proof (M13b Task 5)
  # rides that manual activation because its start time is deterministic:
  # frameInfo lands well inside cycle 0 (the fastest effect converges 3.6s
  # in, plus the 2s hold), then a read-only poll waits for the reroll. The
  # 40s SECONDS deadline covers the worst first pick — slide at 161 frames
  # is ~14.5s + 2s hold after a manual start ~15-17s into the script — and
  # a poll that never sees cycles leave 0 just runs out and fails the
  # post-run assertion honestly.
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
"$qs_bin" ipc --any-display -p "$shell_path" call screensaver frameInfo > "$ss_cycle_info1_path" 2>&1
while [ "\$SECONDS" -lt 40 ]; do
  "$qs_bin" ipc --any-display -p "$shell_path" call screensaver frameInfo > "$ss_cycle_info2_path" 2>&1
  grep -q '"cycles":0}' "$ss_cycle_info2_path" || break
  sleep 1
done
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

# --screenshot: the region/cancel round trip runs first (M13 Task 7):
# `screenshot region` launches a real themed slurp in the nested session and
# blocks on a drag no headless run can supply — which is exactly the stuck
# state the cancel path exists for. The drive proves slurp is genuinely
# running (pgrep, plus status capturing:true), then `screenshot cancel` kills
# it: status must settle to capturing:false with lastCancelled:true and an
# empty lastError, pgrep must come back empty, and the region reply path
# must never appear on disk. Then the original full-capture flow runs in the
# same session: `screenshot full` replies with the destination path before
# its grim/wl-copy pipeline finishes (IpcHandler replies are synchronous;
# see ScreenshotIpc.qml's header), so the drive polls `screenshot status`
# until capturing:false before dumping the clipboard's offered MIME types,
# the wl-copy proof. The capture lands under the isolated HOME's default
# Pictures/Screenshots directory (no screenshot.directory in the settings
# fixture on purpose), and the assertions below read it back by the reply
# path after the run. Slurp's overlay look (dim + accent border) and a real
# drag stay host-trial: no synthetic pointer exists here. The watchdog
# rides the same _cancel path the cancel verb drives, at its 90s default —
# too slow to wait out in a smoke run, so the verb round trip is its proof.
if $screenshot_mode; then
  screenshot_drive_script="$shot_dir/screenshot-drive.sh"
  cat > "$screenshot_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc --any-display -p "$shell_path" call screenshot region > "$screenshot_region_reply_path" 2>&1
sleep 1
pgrep -x slurp > "$screenshot_slurp_before_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call screenshot status > "$screenshot_region_status_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call screenshot cancel > "$screenshot_cancel_reply_path" 2>&1
sleep 1
pgrep -x slurp > "$screenshot_slurp_after_path" 2>&1 || true
"$qs_bin" ipc --any-display -p "$shell_path" call screenshot status > "$screenshot_cancelled_status_path" 2>&1
"$qs_bin" ipc --any-display -p "$shell_path" call screenshot full > "$screenshot_reply_path" 2>&1
for _ in \$(seq 1 20); do
  "$qs_bin" ipc --any-display -p "$shell_path" call screenshot status > "$screenshot_status_path" 2>&1
  if grep -q '"capturing":false' "$screenshot_status_path"; then
    break
  fi
  sleep 0.5
done
"$wl_paste_bin" --list-types > "$screenshot_types_path" 2>&1
EOF
fi

# --tray: launches six real SNI producers in the background (PIDs recorded
# for the kill step below), then proves the collapsed state (status dump +
# screenshot) before driving the same expand() the overflow cell's own click
# calls and proving the expanded state (status dump), then drives the same
# activate() the item cells' own left click calls and lets the stub's
# --activate-file prove the D-Bus round trip; this run's generic
# smoke.png/SMOKE_OK, taken later, shows the drawer already expanded.
if $tray_mode; then
  tray_drive_script="$shot_dir/tray-drive.sh"
  cat > "$tray_drive_script" <<EOF
#!/usr/bin/env bash
sleep 1
"$python3_bin" "$sni_stub_path" --id tray-fixture-1 --title "Tray Fixture 1" --color c0392b --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-2 --title "Tray Fixture 2" --color 27ae60 --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-3 --title "Tray Fixture 3" --color 2980b9 --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-4 --title "Tray Fixture 4" --color f1c40f --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-5 --title "Tray Fixture 5" --color 8e44ad --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
"$python3_bin" "$sni_stub_path" --id tray-fixture-6 --title "Tray Fixture 6" --color 16a085 --activate-file "$tray_activate_path" & echo \$! >> "$tray_pids_path"
sleep 6
"$qs_bin" ipc --any-display -p "$shell_path" call tray status > "$tray_status1_path" 2>&1
sleep 1
niri msg action screenshot-screen --path "$tray_collapsed_path"
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call tray expand > /dev/null 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call tray status > "$tray_status2_path" 2>&1
sleep 1
"$qs_bin" ipc --any-display -p "$shell_path" call tray activate tray-fixture-2 > "$tray_activate_reply_path" 2>&1
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
  # Shims must sit ahead of the real binaries on the SHELL's own PATH
  # (Menu.qml's search Process and GithubWidget.qml's poll inherit it) —
  # scoped to this one spawn so a host whose $niri_bin is itself a
  # `nix run ...` prefix, and every drive script below, keep resolving the
  # real nix/gh. $PATH is expanded here at generation time: it's exactly
  # what the nested session would inherit anyway.
  shim_path_prefix=""
  if $menu_mode; then
    shim_path_prefix="$nix_shim_dir:$wtype_shim_dir:$shim_path_prefix"
  fi
  if $bar_layout_mode || $panel_github_mode; then
    shim_path_prefix="$gh_shim_dir:$shim_path_prefix"
  fi
  if [ -n "$shim_path_prefix" ]; then
    echo "spawn-at-startup \"sh\" \"-c\" \"PATH='$shim_path_prefix$PATH' exec '$PWD/result/bin/formalshell'\""
  else
    echo "spawn-at-startup \"$PWD/result/bin/formalshell\""
  fi
  if $dump_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc --any-display -p '$shell_path' call debug dump > $dump_path 2>&1\""
  fi
  if $wallpaper_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc --any-display -p '$shell_path' call wallpaper set '$wp_path'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc --any-display -p '$shell_path' call theme status > $status_path 2>&1\""
  fi
  if $theme_toggle_mode; then
    echo "spawn-at-startup \"bash\" \"$theme_toggle_drive_script\""
  fi
  if $menu_mode; then
    echo "spawn-at-startup \"bash\" \"$menu_open_script\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call debug query 'e' > $query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call debug query '2+2*3' > $calc_query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call debug query ':e thumbs' > $emoji_query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc --any-display -p '$shell_path' call debug query 'wall' > $wall_query_path 2>&1\""
    # The nix end-state drive (M13b Task 4) replaced M12's plain two-pass
    # ':nix hello' one-liners: the gated slowblock release covers the same
    # debounce -> shim -> parse -> rows proof, plus SEARCHING while blocked
    # and the failed/zero-hit outcomes. Serial in its own script — see its
    # generation comment.
    echo "spawn-at-startup \"bash\" \"$nix_states_script\""
    echo "spawn-at-startup \"bash\" \"$menu_select_script\""
    echo "spawn-at-startup \"bash\" \"$menu_finish_script\""
  fi
  if $notify_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$notify_send_bin' -u normal 'Test' 'Hello'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$notify_send_bin' -u critical 'Crit' 'Now'\""
    # Bell cell DND display (M13b Task 2, formerly Indicators.qml's DND
    # glyph, M10 Task 2): both notify-sends above have already fired by
    # sleep 6, so flipping DND on here can't suppress them (dnd bypass is
    # per-notification-on-arrival, not retroactive) — dndState is dumped
    # right after the toggle to prove it actually flipped, then the bar is
    # screenshotted a second later to show BellWidget.qml swap to its
    # bell-off glyph.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications setDnd true > $dnd_status_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 7 && niri msg action screenshot-screen --path $dnd_indicator_path\""
  fi
  if $center_mode; then
    # A second normal notify-send, offset from notify_mode's own so the
    # model's default 6s popup timeout has both non-critical popups clear of
    # their expiry (and the 1s reducer tick has had a chance to run) well
    # before the summon below — the critical one from notify_mode is sticky
    # and stays a popup regardless.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$notify_send_bin' -u normal 'Second' 'World'\""
    # Status dumps bracket a showHistory toggle round trip: closed with a
    # non-zero pending count (the same NotificationService.pending.length
    # the bell cell's meta label renders), open right before this run's
    # sleep-15 screenshot, closed again after a second showHistory at 16 —
    # the IPC stand-in for the bell cell's own left click, which calls the
    # exact same center.open()/close().
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 12 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications status > $center_status_before_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications showHistory\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 14 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications status > $center_status_open_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 16 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications showHistory\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 17 && '$qs_bin' ipc --any-display -p '$shell_path' call notifications status > $center_status_closed_path 2>&1\""
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
    if [ "$panel_name" = "calendar" ]; then
      echo "spawn-at-startup \"bash\" \"$eds_drive_script\""
    else
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc --any-display -p '$shell_path' call panel open '$panel_name'\""
    fi
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
  if $screenshot_mode; then
    echo "spawn-at-startup \"bash\" \"$screenshot_drive_script\""
  fi
  if $bar_layout_mode; then
    # 5s: shell startup plus room for the command module's first poll
    # (fires immediately once Config.settings resolves, well under 2s).
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && niri msg action screenshot-screen --path $bar_layout_path\""
  fi
  # menu_mode's finish script (menu close + selection read + toggle round
  # trip + emoji instant-paste + apps + nix toast legs) fires 1s after the
  # screenshot at sleep 9 and needs a much longer buffer before quit than
  # the other modes' 1s — see the branch comment below. osd_mode's
  # brightness leg (sleep 13/14, see above) needs the same kind of buffer
  # past its own sleep-10 screenshot.
  tail_gap=1
  if $menu_mode; then
    # 18, not the pre-Task-4 12: after the apps leg the finish script now
    # waits for the nix states script's done flag (~13-17s in) and runs the
    # toast leg (summon + 2s debounce wait + activate + grim + status,
    # ~5s), landing ~23-26s in on the VM's llvmpipe timing.
    tail_gap=18
  elif $osd_mode; then
    tail_gap=5
  elif $center_mode; then
    # The toggle-closed leg (showHistory at 16, status dump at 17) lands
    # after this mode's sleep-15 screenshot — 4s keeps it inside the run.
    tail_gap=4
  fi
  # center_mode needs the popup->pending transition (see above) plus the
  # showHistory summon to land before the screenshot; osd_mode's final
  # screenshot must land 1s after its sleep-9 wpctl trigger, still inside
  # the OSD's auto-hide window; every other mode keeps the original 8s
  # budget.
  screenshot_delay=8
  if $center_mode; then
    screenshot_delay=15
  elif $theme_toggle_mode; then
    # theme-toggle-drive.sh's own final step (the back-to-dark status dump)
    # lands around its internal sleep sum plus grim/qs spawn overhead on
    # llvmpipe (~9-13s in); this run's generic smoke.png/SMOKE_OK is taken
    # after that, showing the session dark again after the round trip.
    screenshot_delay=14
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
    # ss-drive.sh's cycle-proof poll can run until its 40s SECONDS deadline
    # (worst first random pick, see the drive script's own comment), and the
    # final status dump lands ~2s after the poll breaks; this run's generic
    # smoke.png/SMOKE_OK is taken after that worst case, showing the
    # ordinary session with the screensaver already dismissed for good.
    screenshot_delay=44
  elif $picker_mode; then
    # picker-drive.sh's own final step (the selection-file readback) lands
    # around its internal sleep sum (~10s in); this run's generic
    # smoke.png/SMOKE_OK is taken 4s after that, showing the ordinary session
    # with the picker already closed again.
    screenshot_delay=14
  elif $tray_mode; then
    # tray-drive.sh's own final step (the activate call on fixture 2) lands
    # around its internal sleep sum (~11s in); this run's generic
    # smoke.png/SMOKE_OK is taken 2s after that, showing every registered
    # item as its own cell with the drawer already expanded.
    screenshot_delay=13
  elif $panel_mode && [ "$panel_name" = "calendar" ]; then
    # eds-drive.sh opens the panel only after its two seed writes return
    # (~4-7s in when this run's private bus has to cold-activate EDS
    # first), then selects tomorrow 2s after the open; 13s leaves the
    # on-open refresh's own `formalshell-eds events` run and the select
    # comfortable room before the shot.
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

# The 40s default comfortably outlives every mode's screenshot-then-quit
# schedule except screensaver_mode's, whose worst-case cycle-proof poll
# pushes the smoke.png shot itself to 44s (see screenshot_delay above).
session_timeout=40
if $screensaver_mode; then
  session_timeout=62
fi

HOME="$iso_home" \
XDG_CONFIG_HOME="$iso_home/.config" \
XDG_STATE_HOME="$iso_home/.local/state" \
XDG_DATA_HOME="$iso_home/.local/share" \
XDG_DATA_DIRS="$iso_home/.local/share" \
XDG_CACHE_HOME="$iso_home/.cache" \
WAYLAND_DISPLAY="$wayland_display" dbus-run-session -- timeout "$session_timeout" $niri_bin --config "$cfg" || true

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

if $theme_toggle_mode; then
  # First toggle: mode flipped to light with NO wallpaper involved — the
  # mode-matched Flexoki fallback path, not matugen.
  if [ -s "$theme_toggle_status_path" ] \
    && grep -qF '"wallpaper":""' "$theme_toggle_status_path" \
    && grep -qF '"mode":"light"' "$theme_toggle_status_path" \
    && grep -qF '"themeJsonPresent":true' "$theme_toggle_status_path"; then
    cat "$theme_toggle_status_path"
  else
    echo "SMOKE_FAIL: theme status after toggle did not report mode:light with no wallpaper" >&2
    [ -f "$theme_toggle_status_path" ] && cat "$theme_toggle_status_path" >&2
    exit 1
  fi
  # Second toggle: back to dark, still no wallpaper.
  if [ -s "$theme_toggle_status2_path" ] \
    && grep -qF '"wallpaper":""' "$theme_toggle_status2_path" \
    && grep -qF '"mode":"dark"' "$theme_toggle_status2_path"; then
    cat "$theme_toggle_status2_path"
  else
    echo "SMOKE_FAIL: theme status after the second toggle did not report mode:dark" >&2
    [ -f "$theme_toggle_status2_path" ] && cat "$theme_toggle_status2_path" >&2
    exit 1
  fi
  if [ ! -s "$theme_dark_png" ] || [ ! -s "$theme_light_png" ]; then
    echo "SMOKE_FAIL: missing theme-toggle screenshot pair ($theme_dark_png / $theme_light_png)" >&2
    exit 1
  fi
  echo "theme dark screenshot: $theme_dark_png"
  echo "theme light screenshot: $theme_light_png"
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
  # Calc provider (M12 Task 5): the ranked result for an expression query
  # must lead with the CALC row's "= 8" label.
  if [ -s "$calc_query_path" ] && grep -qF '"= 8"' "$calc_query_path"; then
    cat "$calc_query_path"
  else
    echo "SMOKE_FAIL: menu query '2+2*3' did not rank a '= 8' calc row" >&2; exit 1
  fi
  # Emoji provider (M12 Task 6): the ":e thumbs" trigger must answer with
  # the thumbs-up row from the vendored dataset (the char rides the icon
  # field, raw UTF-8 through JSON.stringify).
  if [ -s "$emoji_query_path" ] && grep -qF '👍' "$emoji_query_path" && grep -qF '"THUMBS UP"' "$emoji_query_path"; then
    cat "$emoji_query_path"
  else
    echo "SMOKE_FAIL: menu query ':e thumbs' did not return the thumbs-up emoji row" >&2; exit 1
  fi
  # Wallpaper root node (M13 Task 5): ranking "wall" must surface the
  # injected wallpaper action row (providers.wallpaperEntry, merged at
  # tree-build time).
  if [ -s "$wall_query_path" ] && grep -qF '"id":"wallpaper"' "$wall_query_path" && grep -qF '"label":"Wallpaper"' "$wall_query_path"; then
    cat "$wall_query_path"
  else
    echo "SMOKE_FAIL: menu query 'wall' did not return the wallpaper row" >&2
    [ -f "$wall_query_path" ] && cat "$wall_query_path" >&2
    exit 1
  fi
  # Apps rows (M13b Task 1): both fixture apps must rank with their real
  # display-name labels (never the .desktop id), the iconic one's
  # iconSource must be the resolved image URL, and the icon-less one's
  # must be the honest "" (check-resolution, no missing-texture box).
  if [ -s "$apps_query_path" ] \
    && grep -qF '"label":"Iconic Test App","kind":"app","iconSource":"image://icon/formalshell-smoke"' "$apps_query_path" \
    && grep -qF '"label":"Formal Test App","kind":"app","iconSource":""' "$apps_query_path"; then
    cat "$apps_query_path"
  else
    echo "SMOKE_FAIL: apps query did not return display-name rows with a resolved icon" >&2
    [ -f "$apps_query_path" ] && cat "$apps_query_path" >&2
    exit 1
  fi
  if [ ! -s "$menu_apps_png" ]; then
    echo "SMOKE_FAIL: no apps-route screenshot produced at $menu_apps_png" >&2
    exit 1
  fi
  echo "menu apps screenshot: $menu_apps_png"
  # No-arg toggle (M13 Task 5): the four stacked replies must read
  # ok / isOpen:true at root / ok / isOpen:false — order-sensitive, so the
  # greps check line pairs, not mere presence.
  if [ -s "$toggle_path" ] \
    && [ "$(sed -n '1p' "$toggle_path")" = "ok" ] \
    && sed -n '2p' "$toggle_path" | grep -qF '"isOpen":true' \
    && [ "$(sed -n '3p' "$toggle_path")" = "ok" ] \
    && sed -n '4p' "$toggle_path" | grep -qF '"isOpen":false'; then
    cat "$toggle_path"
  else
    echo "SMOKE_FAIL: no-arg menu toggle round trip did not flip isOpen true -> false" >&2
    [ -f "$toggle_path" ] && cat "$toggle_path" >&2
    exit 1
  fi
  # Nix runner end states (M13b Task 4, gated shim): while the shim blocks
  # on the gate flag the debounced search is genuinely in flight, so the
  # query must answer the dim SEARCHING note row; after the release it must
  # answer the canned rows ("hello 2.12.1" proves the
  # legacyPackages.<system>. prefix was stripped, the description proves
  # the dimmed desc field rides along — M12's original two-pass proof); the
  # failing and zero-hit queries must answer SEARCH FAILED / NO RESULTS.
  if [ -s "$nix_searching_path" ] && grep -qF '"label":"SEARCHING"' "$nix_searching_path" && grep -qF '"kind":"note"' "$nix_searching_path"; then
    cat "$nix_searching_path"
  else
    echo "SMOKE_FAIL: gated nix search did not report SEARCHING while blocked" >&2
    [ -f "$nix_searching_arm_path" ] && cat "$nix_searching_arm_path" >&2
    [ -f "$nix_searching_path" ] && cat "$nix_searching_path" >&2
    exit 1
  fi
  if [ -s "$nix_released_path" ] && grep -qF '"hello 2.12.1"' "$nix_released_path" && grep -qF 'friendly greeting' "$nix_released_path"; then
    cat "$nix_released_path"
  else
    echo "SMOKE_FAIL: released nix search did not return the canned attr rows" >&2
    [ -f "$nix_released_path" ] && cat "$nix_released_path" >&2
    exit 1
  fi
  if [ -s "$nix_failed_path" ] && grep -qF '"label":"SEARCH FAILED"' "$nix_failed_path"; then
    cat "$nix_failed_path"
  else
    echo "SMOKE_FAIL: failing nix search did not report SEARCH FAILED" >&2
    [ -f "$nix_failed_path" ] && cat "$nix_failed_path" >&2
    exit 1
  fi
  if [ -s "$nix_empty_path" ] && grep -qF '"label":"NO RESULTS"' "$nix_empty_path"; then
    cat "$nix_empty_path"
  else
    echo "SMOKE_FAIL: zero-hit nix search did not report NO RESULTS" >&2
    [ -f "$nix_empty_path" ] && cat "$nix_empty_path" >&2
    exit 1
  fi
  # Launch feedback: the ':nix hello' prefill summon and the row activation
  # must both answer ok, the NIX RUN toast must be a live popup in the
  # status dump, and nix-toast.png is the visual proof (Read on the mac).
  if [ -s "$nix_run_drive_path" ] && [ "$(grep -c '^ok$' "$nix_run_drive_path")" = "2" ]; then
    cat "$nix_run_drive_path"
  else
    echo "SMOKE_FAIL: nix prefill summon/activate did not both answer ok" >&2
    [ -f "$nix_run_drive_path" ] && cat "$nix_run_drive_path" >&2
    exit 1
  fi
  if [ -s "$nix_toast_status_path" ] && grep -qE '"popups":[1-9]' "$nix_toast_status_path"; then
    cat "$nix_toast_status_path"
  else
    echo "SMOKE_FAIL: no live popup after nix row activation (NIX RUN toast missing)" >&2
    [ -f "$nix_toast_status_path" ] && cat "$nix_toast_status_path" >&2
    exit 1
  fi
  if [ ! -s "$nix_toast_png" ]; then
    echo "SMOKE_FAIL: no nix toast screenshot produced at $nix_toast_png" >&2
    exit 1
  fi
  echo "nix toast screenshot: $nix_toast_png"
  # Emoji instant paste (M13 Task 6): summon + activate must both answer
  # ok, the row's copy action must land on the real session clipboard, and
  # the post-close settle must have spawned wtype with the same raw char
  # (the argv-logging shim's file).
  if [ -s "$emoji_drive_path" ] && [ "$(grep -c '^ok$' "$emoji_drive_path")" = "2" ]; then
    cat "$emoji_drive_path"
  else
    echo "SMOKE_FAIL: emoji summon/activate did not both answer ok" >&2
    [ -f "$emoji_drive_path" ] && cat "$emoji_drive_path" >&2
    exit 1
  fi
  # wl-paste --no-newline leaves no trailing newline — explicit echo, same
  # as clip_paste_path below.
  if [ -s "$emoji_paste_path" ] && grep -qF '😀' "$emoji_paste_path"; then
    cat "$emoji_paste_path"; echo
  else
    echo "SMOKE_FAIL: emoji activation did not wl-copy 😀" >&2
    [ -f "$emoji_paste_path" ] && cat "$emoji_paste_path" >&2
    exit 1
  fi
  if [ -s "$emoji_type_path" ] && grep -qF '😀' "$emoji_type_path"; then
    cat "$emoji_type_path"
  else
    echo "SMOKE_FAIL: wtype was not invoked with 😀 after the menu closed" >&2
    [ -f "$emoji_type_path" ] && cat "$emoji_type_path" >&2
    exit 1
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

if $panel_mode && [ "$panel_name" = "calendar" ]; then
  # The screenshot is the render proof; this guards the write path — a
  # failed seed means the run showed the ics fixture alone and proved
  # nothing about EDS.
  if [ -s "$eds_seed_path" ] && grep -q '^rc=0$' "$eds_seed_path"; then
    cat "$eds_seed_path"
  else
    echo "SMOKE_FAIL: formalshell-eds seed did not succeed" >&2
    [ -f "$eds_seed_path" ] && cat "$eds_seed_path" >&2
    exit 1
  fi
  if [ -s "$eds_seed2_path" ] && grep -q '^rc=0$' "$eds_seed2_path"; then
    cat "$eds_seed2_path"
  else
    echo "SMOKE_FAIL: formalshell-eds tomorrow seed did not succeed" >&2
    [ -f "$eds_seed2_path" ] && cat "$eds_seed2_path" >&2
    exit 1
  fi
  # Day selection (M13 Task 4): the select call must find the running
  # instance and accept the date, and the panel's own status must report
  # tomorrow as the selected day — the screenshot's inverted cell and dated
  # events header are the render half of the same proof.
  if [ -s "$calendar_select_path" ] && grep -q '^ok$' "$calendar_select_path"; then
    :
  else
    echo "SMOKE_FAIL: calendar select IPC call did not return ok — got: $(cat "$calendar_select_path" 2>/dev/null)" >&2
    exit 1
  fi
  tomorrow_iso=$(date -d tomorrow +%F)
  if [ -s "$calendar_status_path" ] && grep -q "\"selected\":\"$tomorrow_iso\"" "$calendar_status_path"; then
    cat "$calendar_status_path"
  else
    echo "SMOKE_FAIL: calendar status does not report tomorrow ($tomorrow_iso) selected — got: $(cat "$calendar_status_path" 2>/dev/null)" >&2
    exit 1
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
  # Continuous cycling proof (M13b Task 5): the baseline frameInfo must be
  # cycle 0 of the manual activation, and the drive's read-only poll must
  # have seen the counter leave 0 with no IPC nudge — the reroll came purely
  # from the effect converging and the 2s hold elapsing.
  if [ -s "$ss_cycle_info1_path" ] && grep -q '"cycles":0}' "$ss_cycle_info1_path"; then
    cat "$ss_cycle_info1_path"
  else
    echo "SMOKE_FAIL: screensaver frameInfo baseline was not cycles:0 right after the manual start — got: $(cat "$ss_cycle_info1_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$ss_cycle_info2_path" ] && grep -q '"cycles":' "$ss_cycle_info2_path" && ! grep -q '"cycles":0}' "$ss_cycle_info2_path"; then
    cat "$ss_cycle_info2_path"
  else
    echo "SMOKE_FAIL: screensaver cycles never left 0 within the drive's 40s deadline — got: $(cat "$ss_cycle_info2_path" 2>/dev/null)" >&2; exit 1
  fi
  ss_cycle_effect1=$(grep -o '"effect":"[a-z]*"' "$ss_cycle_info1_path")
  ss_cycle_effect2=$(grep -o '"effect":"[a-z]*"' "$ss_cycle_info2_path")
  if [ -n "${SCREENSAVER_EFFECT:-}" ]; then
    # A pinned effect must replay itself across the reroll.
    if [ "$ss_cycle_effect1" != "$ss_cycle_effect2" ]; then
      echo "SMOKE_FAIL: pinned screensaver effect changed across the reroll ($ss_cycle_effect1 -> $ss_cycle_effect2)" >&2; exit 1
    fi
  else
    # The default "random" must never repeat the immediately previous
    # effect, so cycle 1's report has to differ from cycle 0's.
    if [ "$ss_cycle_effect1" = "$ss_cycle_effect2" ]; then
      echo "SMOKE_FAIL: random screensaver reroll repeated the previous effect ($ss_cycle_effect1)" >&2; exit 1
    fi
  fi
  echo "SMOKE_SCREENSAVER_CYCLE $ss_cycle_effect1 -> $ss_cycle_effect2"
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
  if [ -s "$tray_activate_reply_path" ]; then
    cat "$tray_activate_reply_path"
  else
    echo "SMOKE_FAIL: no tray activate IPC reply produced" >&2; exit 1
  fi
  if ! grep -q '^ok$' "$tray_activate_reply_path"; then
    echo "SMOKE_FAIL: tray activate IPC call did not return ok — got: $(cat "$tray_activate_reply_path")" >&2; exit 1
  fi
  if [ ! -s "$tray_activate_path" ]; then
    echo "SMOKE_FAIL: no tray-activate.txt produced — the shell's activate() never reached the stub over D-Bus" >&2; exit 1
  fi
  cat "$tray_activate_path"
  if ! grep -q '^tray-fixture-2: Activate(' "$tray_activate_path"; then
    echo "SMOKE_FAIL: tray-activate.txt does not record Activate on tray-fixture-2 — got: $(cat "$tray_activate_path")" >&2; exit 1
  fi
  tray_activate_lines=$(wc -l < "$tray_activate_path" | tr -d ' ')
  if [ "$tray_activate_lines" != "1" ]; then
    echo "SMOKE_FAIL: expected exactly one activate record (got $tray_activate_lines) — activate hit more than the targeted item" >&2; exit 1
  fi
fi

if $bar_layout_mode; then
  if [ -f "$bar_layout_path" ]; then
    echo "SMOKE_BAR_LAYOUT $bar_layout_path"
  else
    echo "SMOKE_FAIL: no bar-layout screenshot produced" >&2; exit 1
  fi
fi

if $screenshot_mode; then
  if [ -s "$screenshot_region_reply_path" ]; then
    cat "$screenshot_region_reply_path"
  else
    echo "SMOKE_FAIL: no screenshot region IPC reply produced" >&2; exit 1
  fi
  screenshot_region_file=$(head -n1 "$screenshot_region_reply_path" | tr -d '\r')
  case "$screenshot_region_file" in
    error*|"") echo "SMOKE_FAIL: screenshot region replied with an error: $(cat "$screenshot_region_reply_path")" >&2; exit 1 ;;
  esac
  if [ ! -s "$screenshot_slurp_before_path" ]; then
    echo "SMOKE_FAIL: no slurp process found while the region capture was pending — slurp never launched" >&2; exit 1
  fi
  if ! grep -q '"capturing":true' "$screenshot_region_status_path"; then
    echo "SMOKE_FAIL: status did not report capturing:true while slurp was pending: $(cat "$screenshot_region_status_path" 2>/dev/null)" >&2; exit 1
  fi
  if ! grep -q '^ok$' "$screenshot_cancel_reply_path"; then
    echo "SMOKE_FAIL: screenshot cancel did not return ok — got: $(cat "$screenshot_cancel_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$screenshot_slurp_after_path" ]; then
    echo "SMOKE_FAIL: slurp still running after cancel (pids: $(cat "$screenshot_slurp_after_path"))" >&2; exit 1
  fi
  if [ -s "$screenshot_cancelled_status_path" ]; then
    cat "$screenshot_cancelled_status_path"
  else
    echo "SMOKE_FAIL: no post-cancel screenshot status produced" >&2; exit 1
  fi
  if ! grep -q '"capturing":false' "$screenshot_cancelled_status_path" \
    || ! grep -q '"lastCancelled":true' "$screenshot_cancelled_status_path" \
    || ! grep -q '"lastError":""' "$screenshot_cancelled_status_path"; then
    echo "SMOKE_FAIL: post-cancel status did not settle to a clean cancel: $(cat "$screenshot_cancelled_status_path")" >&2; exit 1
  fi
  if [ -e "$screenshot_region_file" ]; then
    echo "SMOKE_FAIL: cancelled region capture still wrote a file: $screenshot_region_file" >&2; exit 1
  fi
  echo "SMOKE_SCREENSHOT_CANCEL region pending -> cancelled clean, slurp killed, no file at $screenshot_region_file"
  if [ -s "$screenshot_reply_path" ]; then
    cat "$screenshot_reply_path"
  else
    echo "SMOKE_FAIL: no screenshot IPC reply produced" >&2; exit 1
  fi
  screenshot_file=$(head -n1 "$screenshot_reply_path" | tr -d '\r')
  case "$screenshot_file" in
    error*|"") echo "SMOKE_FAIL: screenshot full replied with an error: $(cat "$screenshot_reply_path")" >&2; exit 1 ;;
  esac
  if [ ! -f "$screenshot_file" ]; then
    echo "SMOKE_FAIL: screenshot reply path does not exist: $screenshot_file" >&2; exit 1
  fi
  if ! "$file_bin" "$screenshot_file" | grep -q "PNG image data"; then
    echo "SMOKE_FAIL: screenshot file is not a valid PNG, file(1) says: $("$file_bin" -b "$screenshot_file")" >&2; exit 1
  fi
  echo "SMOKE_SCREENSHOT $screenshot_file ($("$file_bin" -b "$screenshot_file"))"
  if [ -s "$screenshot_status_path" ]; then
    cat "$screenshot_status_path"
  else
    echo "SMOKE_FAIL: no screenshot status produced" >&2; exit 1
  fi
  if ! grep -q '"capturing":false' "$screenshot_status_path" || ! grep -q '"lastError":""' "$screenshot_status_path"; then
    echo "SMOKE_FAIL: screenshot status did not settle clean: $(cat "$screenshot_status_path")" >&2; exit 1
  fi
  if ! grep -qF "\"lastPath\":\"$screenshot_file\"" "$screenshot_status_path"; then
    echo "SMOKE_FAIL: screenshot status lastPath does not match the reply path ($screenshot_file): $(cat "$screenshot_status_path")" >&2; exit 1
  fi
  if [ -s "$screenshot_types_path" ] && grep -q "image/png" "$screenshot_types_path"; then
    cat "$screenshot_types_path"
  else
    echo "SMOKE_FAIL: wl-paste --list-types did not offer image/png after the capture: $(cat "$screenshot_types_path" 2>/dev/null)" >&2; exit 1
  fi
fi

if $notify_mode; then
  echo "host org.freedesktop.Notifications owner PID unchanged: $host_notifications_owner_after"
  if [ -s "$dnd_status_path" ]; then
    cat "$dnd_status_path"
  else
    echo "SMOKE_FAIL: no dnd status produced" >&2; exit 1
  fi
  if ! grep -q "^on$" "$dnd_status_path"; then
    echo "SMOKE_FAIL: notifications setDnd true did not report on — got: $(cat "$dnd_status_path")" >&2; exit 1
  fi
  if [ -f "$dnd_indicator_path" ]; then
    echo "SMOKE_INDICATOR_DND $dnd_indicator_path"
  else
    echo "SMOKE_FAIL: no indicator-dnd screenshot produced" >&2; exit 1
  fi
fi

if $center_mode; then
  for f in "$center_status_before_path" "$center_status_open_path" "$center_status_closed_path"; do
    if [ -s "$f" ]; then
      cat "$f"
    else
      echo "SMOKE_FAIL: no notifications status produced at $f" >&2; exit 1
    fi
  done
  # "pending":0 would mean the expired notify-sends never reached the tier
  # the bell cell counts — the center summon below would show an empty list.
  if grep -q '"pending":0,' "$center_status_before_path"; then
    echo "SMOKE_FAIL: pending count was zero before the center summon: $(cat "$center_status_before_path")" >&2; exit 1
  fi
  if ! grep -q '"centerOpen":false' "$center_status_before_path"; then
    echo "SMOKE_FAIL: center reported open before the summon: $(cat "$center_status_before_path")" >&2; exit 1
  fi
  if ! grep -q '"centerOpen":true' "$center_status_open_path"; then
    echo "SMOKE_FAIL: showHistory did not open the center: $(cat "$center_status_open_path")" >&2; exit 1
  fi
  if ! grep -q '"centerOpen":false' "$center_status_closed_path"; then
    echo "SMOKE_FAIL: second showHistory did not close the center: $(cat "$center_status_closed_path")" >&2; exit 1
  fi
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
