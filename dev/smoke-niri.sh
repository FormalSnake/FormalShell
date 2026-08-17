#!/usr/bin/env bash
# Nested-niri smoke: run the built shell in an isolated niri window,
# screenshot it, tear down. Prints the screenshot path on success.
# The plain/default leg (no mode flag beyond --dump/--wallpaper/etc. below)
# additionally focuses a real foot(1) window carrying the M13b
# smoke-iconic fixture's app-id (M14 Task 5), so its own smoke.png proves
# ActiveWindow.qml's bar cell renders the desktop entry's themed icon and
# name — not the raw appId — with the window title following dimmed.
# Every mode with its own dedicated surface to prove (menu/panel/wifi/lock/
# etc.) skips it; see active_window_fixture_mode below.
# With --dump, also calls the `debug` IPC target and cats the JSON reply.
# With --wallpaper, generates a solid-color test PNG, drives it through
# `wallpaper set` + `theme status` over IPC in-session before screenshotting,
# so the screenshot proves the background/bar actually recolored. On its own
# (not combined with --theme-toggle, which owns the timeline from sleep 9
# on) it then sets a SECOND wallpaper and lets Background.qml's crossfade
# run, which is the only way this rig covers the dithered path's fade gate:
# with wallpaper.dither on, the incoming layer only starts fading once its
# Canvas has painted. `wallpaper get` is dumped afterwards, and the run's
# own smoke.png is sampled directly. Both halves of the dither contract get
# their own sample (2026-08-12, image-derived palette): the FIRST wallpaper is
# solid, screenshotted on its own (wallpaper-solid.png) before the crossfade,
# and a 64x64 patch of it must be exactly that solid color end to end — a
# monotone source has its own color in its own derived palette, so it must
# paint perfectly flat with no dither dots anywhere. The second is a gradient,
# and a full-width strip of the settled crossfade must carry at least three
# distinct colors (it quantized AND dithered) and no more than
# wallpaper.ditherColors of them (it quantized to the palette).
# With --theme-toggle (M13b Task 3), drives `theme mode toggle` twice with
# NO wallpaper set: grim the dark session (theme-dark.png), toggle, assert
# `theme status` reports mode:"light" with wallpaper still "", grim again
# (theme-light.png — the mode-matched Flexoki fallback theme.json recoloring
# every consumer live, no matugen involved), toggle back, assert mode:"dark".
# The run's own smoke.png/SMOKE_OK then shows the session dark again. grim,
# not niri's screenshot-screen, for the usual no-toast reason: the two shots
# exist to compare background/bar colors.
# Combined with --wallpaper (2026-08-07), the same round trip runs WITH the
# wallpaper set instead: the drive waits out the initial matugen run, dumps
# the rendered theme.json before and after each toggle, and asserts every
# dump carries matugen-derived (non-Flexoki) values with the final dump
# byte-identical to the first — proving a mode toggle re-runs matugen
# against the set wallpaper rather than resetting to the fallback palette.
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
# With --notify, fires `notify-send -u normal` then `-u critical` then one
# carrying two real `-A` actions (M19 Task 4: proves NotificationCard.qml's
# action row renders as full-bleed ink-fill buttons) in-session and
# screenshots the resulting toasts. Then flips DND on over the existing
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
# `--panel appmenu` is the one panel leg that keeps the default leg's foot
# fixture window (every other mode drops it), because the app menu is about
# the focused app: the window's app-id resolves the isolated HOME's
# formalshell-smoke-iconic.desktop, whose two Desktop Action groups become
# the ACTIONS rows, and the compositor's own window list becomes the
# WINDOWS rows. A `debug dump` taken while the panel is open is asserted to
# still carry a non-empty heldFocusedWindowId — the shell's own surface has
# keyboard focus at that point, so a raw focused id would be gone (see
# shell/Compositor/focus.js).
# `--panel github` runs against the same PATH-shimmed `gh` --bar-layout
# uses (extended with canned PR/issue node rows, M13 Task 3), so the
# panel's on-open poll renders both sections — "PULL REQUESTS / 3" and
# "ISSUES / 2" with the canned titles and dimmed repo slugs — without
# network or auth; the github widget itself stays out of the bar (the
# default no-`bar`-key layout), which is exactly the no-widget IPC-open
# path GithubPanel.qml's header describes.
# `--panel tailscale` proves the honest unavailable state (M16 Task 8): the
# VM carries no tailscaled/tailscale binary at all, so TailscalePanel.qml's
# poll exits 127 and the screenshot must show the dim "NO TAILSCALE" row —
# real evidence of the missing-CLI path, not a stub. The connected/toggle/
# operator-permission states are owner-verified post-switchover against a
# real tailscaled, stated honestly in SWITCHOVER.md.
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
# With --wifi (M14 Task 3), drives the real `network` IPC target against
# nix/testvm.nix's mac80211_hwsim rig — three simulated radios: wlan0 stays
# NetworkManager's station device, wlan1/wlan2 are hostapd APs broadcasting
# FORMALTEST (WPA2-PSK) and FORMALTEST-EAP (hostapd's own integrated EAP
# server, PEAP/MSCHAPv2, no RADIUS daemon). Before anything else, restarts
# wpa_supplicant's own per-interface unit (`wpa_supplicant-wlan0.service`) —
# its internal scan-request queue can wedge from a prior run independently
# of anything NetworkManager itself persists, repeating "Reject scan trigger
# since one is already pending" forever and starving every SME authenticate
# attempt; the restart is what unwedges it, confirmed by reproducing the
# stuck state directly, and NetworkManager reconnects to the fresh
# supplicant over D-Bus on its own. `panel open network` first (turns
# on WifiDevice.scannerEnabled, NetworkPanel.qml's isOpen-tracked idiom — the
# station won't rescan without it), then polls `network status` for both
# SSIDs to surface from a real scan. `network connect FORMALTEST` with a
# WRONG psk drives NetworkManager's own real retry/give-up cycle (allow up
# to 45s — NM_DEVICE_STATE_REASON_SUPPLICANT_TIMEOUT, the standard "wrong
# wifi password" signal, verified against the pinned quickshell source's
# nm/network.cpp reason mapping, not assumed), screenshotted as
# wifi-wrong.png once `stateChanging` settles back to false (the panel's own
# wifiRow Connections react to the same connectionFailed(reason) signal
# regardless of who called connectWithPsk, so the WRONG PASSWORD row renders
# without the panel driving the connect itself). The real psk then connects
# for real (wifi-connected.png, polled for connected:true — hostapd's own
# DHCP-serving dnsmasq on the AP interface is what lets this settle into a
# genuine Connected state rather than stalling), `network forget` drops it
# back to not-known, and `network connectEap FORMALTEST-EAP` drives the
# enterprise leg (identity/password matching the eap_user_file fixture),
# screenshotted as wifi-eap-connected.png once connected:true. Every step's
# `network status` JSON lands on disk for the post-run assertions below —
# never trusting the screenshot alone for what NetworkManager actually did.
# With --media, generates a short silent fixture track (ffmpeg lavfi
# anullsrc, tagged with a title/artist via -metadata) and plays it with mpv
# --script=<mpvScripts.mpris path> into the default (pipewire null-sink)
# audio device in-session, so MediaService picks up a real MPRIS player —
# `panel open media` then shows the screenshot with the panel open (album
# art cell, meta row, transport cells, progress fill), and `media status` is
# dumped to media-status.json so its title/artist can be cross-checked
# against the fixture's own tags. Then M16 Task 11's marquee proof: the
# short-title state is screenshotted (media-marquee-static.png, expected
# static — the fixture title doesn't overflow the bar cell), mpv is
# retitled to a second, deliberately long fixture track (kill by PID,
# respawn on the long track), `media status` is polled until the long
# title lands, and a second screenshot lands mid-scroll
# (media-marquee-scroll.png). mpv is killed by PID right after, before
# niri quits, so no player process outlives the run.
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
# With --polkit, drives the real polkit agent end to end: `pkexec true` is
# spawned in-session (backgrounded within its own drive script so the
# script can keep issuing input while it blocks on the conversation) —
# the generic `org.freedesktop.policykit.exec` action's own shipped
# defaults are `auth_admin` for allow_any/allow_inactive/allow_active
# alike, so no extra polkit *policy* fixture is needed: the "test" user's
# existing `wheel` membership (an admin identity, `security.polkit.
# adminIdentities`'s own default) is the whole auth prerequisite. The one
# real fixture nix/testvm.nix needs is `security.polkit.
# enablePkexecWrapper = true` — on this pinned nixpkgs rev, `security.
# polkit.enable` alone no longer installs the setuid `pkexec` wrapper (a
# recent hardening split, reproduced directly: without it, `pkexec`
# resolves to the unwrapped, non-setuid `environment.systemPackages`
# binary and refuses to run at all, "pkexec must be setuid root", exit
# 127). Once PolkitDialog.qml maps (screenshotted as polkit-active.png),
# `wtype` types a wrong password and Return — the PAM round trip for a
# failed attempt is socket-activated (polkit-agent-helper@.service, not an
# in-process PamContext like --lock's), so it gets a 10s buffer rather
# than --lock's own 5s — screenshotted as polkit-error.png (urgent-italic
# "WRONG PASSWORD" over a still-usable field, the AuthPrompt idiom's retry
# state, M16 Task 4). Retyping the
# VM's real test password and Return resolves the same AuthFlow
# (module.md: a failed attempt auto-starts a fresh session, no second
# pkexec invocation needed); the backgrounded pkexec is then `wait`ed and
# its exit code recorded (polkit-rc.txt) — must be 0, the real proof `true`
# actually ran as root. This run's generic smoke.png/SMOKE_OK, taken after
# that, shows the ordinary session with the dialog already gone.
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
# With --screensaver-gif, records five of ttfx's effects as GIFs rather than
# screenshotting one: for each effect in turn, its own isolated settings.json
# fixture pins screensaver.effect to that name, a fresh nested niri session
# boots, `screensaver start` shows it, `screensaver frame 0` pins the run
# (which is what makes a ttfx run's frame count known at all — the engine
# streams, it doesn't precompute), `screensaver frameInfo` reads that count
# back (ScreensaverIpc's M11 Task 1 verb — never guessed, since the VM's
# llvmpipe rendering makes wall-clock capture uneven), then `screensaver
# frame <n>` pins and screenshots a strided sample of the run plus a short
# hold on the converged banner before `screensaver stop` and quit. Strided
# because a ttfx effect runs to hundreds of frames where effect.js's own ran
# to dozens: the capture budget is a fixed number of frames per GIF, and the
# GIF's frame delay is derived from the stride so playback stays real time.
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
# `qs ipc -p <shellDir> call clipboard copy <id>` invocation
# Menu/providers.js's clipboardProvider builds (clip-copy.txt — must read
# "ok", not "No running instances"; a wrong `-p` target fails silently there)
# and reads the system clipboard back (clip-paste.txt — must have flipped to
# the re-copied entry's text), proving the menu row's copy action actually
# reaches the running shell end to end, not just that the rows render. Then
# (M14 Task 6) an imagemagick fixture PNG is `wl-copy --type image/png`d,
# `clipboard list` is dumped a third time (clip-list-3.json — must show the
# new entry with `"kind":"image"` and a `path` under the isolated HOME's own
# `clipboard-images/<sha256>.png`, proving the second watcher actually
# content-addressed the capture), that entry's id is activated the same
# self-targeting way (clip-image-copy.txt), and `wl-paste --type image/png`
# is hashed and compared against the fixture's own hash (clip-image-paste-
# sha.txt) — proving the image copy-back round trip end to end, not just
# that a path string exists. Then `menu summon clipboard` so the run's
# screenshot shows the provider's rows rendered as real menu cells — the
# freshly-captured image now newest, so its thumbnail row is the one the
# shot proves — left open through smoke.png/SMOKE_OK same as --panel.
# With --clipssh, writes a two-alias ~/.clipssh/aliases into the isolated
# HOME and drives the menu's clipssh route over `menu activate` (the rig's
# Enter stand-in) against a PATH-shimmed clipssh speaking the real one's
# output contract: `box` takes six seconds and succeeds, `nohost` fails at
# once. Four frames off one timeline — clipssh-route.png (both rows),
# clipssh-sending.png (the transfer in flight: the bar's own indicator cell
# plus the SENDING toast, which is the state that had no feedback at all
# before), clipssh-copied.png (COPIED, carrying the remote path clipssh
# printed), clipssh-failed.png (a full-bleed urgent card carrying clipssh's
# own Error line). The shim stands in for the real binary because what has
# to be proven here is the shell's own path (row -> `@ipc:clipssh.send:` ->
# ClipsshService -> Process -> exit code -> toast + indicator), not whether
# the rig can reach an ssh host; real transfers are host-trial territory,
# same line --panel github's `gh` shim draws.
# With --tray, launches six dev/sni-stub.py processes (a minimal Python/GLib
# StatusNotifierItem producer — see its own header comment) that each
# register a real item on the isolated session bus, giving
# Quickshell.Services.SystemTray genuine items to track. The tray is a plain
# strip since M24: no drawer, no visible limit, no per-item buckets, since
# bounding a long strip is the bar chevron's job now (--chevron below, and
# Tray.qml's own header for the spec deviation that records). So `tray
# status` is dumped (tray-status.json, proves all six registered) and a
# screenshot (tray-strip.png) shows all six as their own cells, then
# `tray activate tray-fixture-2` drives the exact Activate() call Tray.qml's
# own left-click handler makes, and the stub's --activate-file
# (tray-activate.txt) is asserted afterward, proving the D-Bus Activate round
# trip reached the item and reached only that item. Opening an item's
# DBusMenu stays host-trial territory (a platform QMenu with no pointer to
# dismiss it would wedge a headless run, see TrayIpc.qml). The stub
# processes are killed by PID (tray-pids.txt, same pattern as --media's mpv)
# right before niri quits.
# With --chevron, writes a settings.json fixture putting `chevron` mid
# right-region (after bluetooth/weather/tray/bell/indicators, before
# battery/audio/network) and drives the `bar` IPC target across the collapse
# boundary it creates. A right-region chevron governs what precedes it (M25),
# so those five lead the region and the three that follow sit outboard
# against the screen edge, where the reveal never moves them.
# `bar chevron status` is dumped collapsed
# (chevron-status-collapsed.json; collapsed is the shipped default, so this
# is the state the bar boots into), screenshotted (chevron-collapsed.png),
# then `bar chevron expand` (the rig's stand-in for a click on the chevron
# cell, since no synthetic pointer exists here) is called, dumped again
# (chevron-status-expanded.json) and screenshotted (chevron-expanded.png).
# Both dumps are asserted, not just captured: the collapsed one must list
# every governed name under `hidden`, and the expanded one must
# report the same names still under `collapses` with `hidden` empty. The
# region is inferred rather than named, which is itself the proof that a
# single-chevron layout needs no argument. The two PNGs are asserted to
# differ, which is the cheapest possible guard against the M24 failure of
# shipping a correct IPC contract over a bar that never rendered the change.
# With --picker, generates 20 fixture PNGs (imagemagick, solid colors at
# 1920x1080 — bigger than the grid cell's decode cap and the VM's own
# screen, so both actually downscale rather than passing an already-smaller
# source through untouched) into a directory pointed at by settings.json's
# picker.directory, then drives the `picker` IPC target: `summon` opens the
# wallpaper-mode grid (screenshotted as picker-grid.png — cursor cell
# inverted on the first image, proving the surface itself). M16 Task 12: the
# same run first brackets a bare summon/close (no choose) with
# /proc/<pid>/smaps_rollup Rss samples at three points (pre-open, grid open,
# post-close) into picker-memory.json, scripted this time (open > pre-open,
# post-close < open) — kept deliberately separate from the choose()/retheme
# flow below, since setWallpaper()'s matugen retheme and Background's
# crossfade would otherwise swamp the picker's own delta. Only once that
# bracket closes does a fresh summon/`choose` pick a non-first fixture by
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
# Dark/Light variants (2026-08-12) close the same run. Every leg above runs
# against a FLAT directory, which is the no-variant listing every existing
# setup has (picker-status-flat.json: hasVariants false, all 20 images);
# staged `Dark` (5 fixtures) and `Light` (3) subdirectories are then moved
# into place mid-run and the route re-summoned, which also proves the scan
# genuinely re-runs per entry. picker-status-dark.json must report
# hasVariants with the entry variant taken from the theme's own mode and only
# the dark set listed; `picker variant light` (the switcher's own action over
# IPC, same division as `choose` above) must answer ok, the grid is
# screenshotted there (picker-variant.png — the DARK | LIGHT cells with LIGHT
# inverted), and picker-status-light.json must report the light set's own
# count.
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
# With --hotcorner, dumps `niri msg -j layers` and asserts exactly two layer
# surfaces carry the formalshell:hotcorner namespace, on the Top layer with
# keyboard_interactivity None. Two, not four: the default corner set leaves
# both TOP corners at "none" (the bar owns that edge) and this run writes no
# hotCorners config at all, so the count doubles as proof that a corner set
# to "none" costs no surface rather than a mapped-but-inert one. Entering a
# corner cannot be driven here — no synthetic pointer exists in this rig,
# the same limit the tray's overflow cell hits — so what this leg proves is
# that the surfaces map at the resolved corners with their per-corner
# PanelWindow.anchors bindings intact, which is the part most likely to be
# silently wrong.
#
# With --nightlight (M16 Task 6), drives the `nightlight` IPC target: `enable`
# starts a real wlsunset process (manual -S/-s dummy times plus -t
# <nightlight.temp>, default 4000 — kept out of wlsunset's geo-coordinate
# validation path on purpose, see NightLightService.qml's own header
# comment) and pins it to the fixed low temperature via wlsunset's own
# documented RUNTIME CONTROL (SIGUSR1 cycles OFF -> forced-high ->
# forced-low, each sent only after the previous one's own stderr
# confirmation line). `nightlight status` is polled until either
# `active:true` lands or a `lastError` appears — both are real evidence:
# nested niri's winit backend may not implement
# wlr-gamma-control-unstable-v1 at all, in which case wlsunset exits
# immediately and the honest failure surface (active:false + lastError) is
# exactly what gets screenshotted, never a silent no-op. `disable` then
# stops the process and status confirms active:false again.
#
# With --speedtest (M16 Task 9), drives the `network` IPC target's
# `speedtest`/`speedstatus` verbs: opens the network panel, starts a run,
# then polls status until `phase` reaches "done" (or a generous ceiling
# elapses) before screenshotting the panel. The VM's virtio NIC gives real
# NAT-routed internet access, so this exercises the genuine measurement:
# real `ip route get`/`cat /sys/class/net/.../statistics/*`/parallel `curl`
# transfers against Cloudflare's speed endpoints, not a stub; either real
# numbers or an honest NO NETWORK/NO CURL/poll-ceiling outcome is accepted
# as real evidence, the same bifurcation --nightlight already established.
#
# With --instance (post-M16 addendum, owner ask 2026-08-03: "i see two bars
# there has to be instance locking"), proves InstanceLock.qml's takeover lock
# for real: once the primary shell is up, the drive script launches a SECOND
# copy of the same result/bin/formalshell wrapper in the same nested session
# (the exact two-instance race the owner hit after a rebuild+respawn — the
# wrapped launcher, not a bare qs invocation, since it carries QT_PLUGIN_PATH/
# NIXPKGS_QT6_QML_IMPORT_PATH other services need), records both PIDs, then
# polls (bounded, 15s — generous for the old instance's own
# Wayland/D-Bus teardown on llvmpipe) until exactly one real daemon process
# remains (the same argv[1]=="-p" cmdline match the picker-memory leg already
# uses to tell the daemon apart from this run's own "qs ipc ... call"
# clients). Post-run assertions: the survivor's PID must be the second
# (newer) one, not the first, and both instances' own stdout/stderr are
# captured so the takeover's log lines ("live instance found" / "acquired
# at" on the new side, "being replaced" on the old side) are real evidence,
# not inferred from process counts alone. This run's generic smoke.png,
# taken after convergence, shows a single bar — the old instance's Wayland
# surfaces are already gone by then, not just its process.
#
# With --share (M17 Task 1), `wl-copy`s a fixture string, two-pass
# `debug query "share"` (the `when` condition's `command -v localsend_app`
# check resolves once at shell startup — Menu.qml's own
# `defaultMenuFile.onLoaded` runs _evalConditions() before this drive
# script's first sleep even elapses — so both passes are expected to
# already show it resolved; the second is redundant confirmation, not a
# race with a still-pending first pass), `menu summon share` + screenshot
# (share-menu.png — CLIPBOARD/PICK FROM HISTORY/RECEIVE rows), then `menu
# activate 0` fires the CLIPBOARD row: a real `localsend_app <path>` process
# must appear (pgrep -f) — the real, verified LocalSend CLI shape
# (`LoadSelectionFromArgsAction`, localsend/localsend upstream, skips every
# dash-prefixed arg outright and only keeps args that pass
# File(arg).existsSync()/Directory(arg).existsSync() — no `-t`/`--text`
# flag reaches a real message the way omarchy's own invocation implies; a
# text entry has to become a real file first) — its final argv element must
# be a real path this run's own drive script can still read off disk after
# the process is killed, and that path's contents must be the exact
# fixture text, proof the text reached LocalSend through a real file, not
# just that some string was passed on argv. It's killed by PID (no
# auto-close of its own, same reasoning as media_kill_script). A second phase proves the
# honest absent state for real, not inferred: a shim dir mirrors the
# session's own $PATH one level minus any entry named "localsend_app"
# (every other binary still resolves), and a second `formalshell` process
# is launched with PATH scoped to just that shim — the same takeover
# protocol --instance mode already proves (the first instance answers,
# hands off, quits) — so the surviving instance genuinely cannot find
# `localsend_app` on its own PATH. Two more `debug query "share"` passes
# against it must come back empty, and `menu summon` + screenshot
# (share-menu-absent.png) must show the root menu with no SHARE row at all.
#
# With --visualizer (owner ask: "next to the now playing it would be nice
# to have an ASCII style audio visualizer"), points settings.json's
# bar.layout at `["clock", "nowPlaying", "visualizer"]` (the settings-fixture
# idiom --bar-layout uses), generates a non-silent sine-tone fixture (unlike
# --media's silent one — cava needs a real signal), plays it with mpv into
# the pipewire null sink, and pgreps for the real `cava` child process
# VisualizerService.qml owns: present while the tone plays
# (visualizer-playing.png, screenshotted a couple seconds in so autosens has
# settled past the widget's all-baseline row), gone within a few seconds of
# killing mpv — DESIGN.md §4 rule 8's hard gate proven from outside the
# process, the same way share_mode's own pgrep proves a real
# `localsend_app` process rather than trusting an IPC reply.
#
# With --record (M22, finalize pass M27 Task 2), drives the `record` target
# through a real wf-recorder child: `record start screen desktop`
# (settings.json sets recording.noDmabuf, the one key llvmpipe makes
# non-optional: there is no GPU buffer to import in a software-rendered
# nested session; every other recording key stays at its default so this
# proves those defaults resolve; `desktop` audio needs only the VM's
# pipewire null sink's own monitor, no real microphone, so the finalize
# pass below has a genuine audio track to normalize), `record status` must
# report active:true against the exact destination path `start` replied
# with, and the bar is screenshotted mid recording (record-active.png)
# since that is the only state Indicators.qml's recording cell exists in.
# `record stop` then polls until `active` goes false (SIGTERM asks
# wf-recorder to finalize the container rather than truncate it), then
# polls `finalizing` (RecordingService's own trim/loudnorm pass) until it
# too settles false, so the ffprobe read that follows lands on the settled
# file rather than one mid-rewrite. That ffprobe read must show a positive
# duration and an audio stream (recording.finalize's default keeps the
# track rather than dropping it) — an exact before/after duration delta
# isn't asserted here: the 0.1s trim is proven at the unit level
# (tst_capture_model.qml's finalizeArgv tests), since a wall-clock
# comparison across llvmpipe scheduling jitter would be a coin flip at that
# margin. Finally `record gif <path>` runs the two-pass ffmpeg transcode
# and the .gif must exist, be non-empty, be a GIF by file(1), and match
# `record status`'s own lastGifPath. A wf-recorder that cannot start at all
# fails the run loudly with its own stderr (status's lastError), never a
# softer assertion.
# With --ocr (M22), drives the `capture` target's two verbs as far as a
# nested session honestly can, and says on its own SMOKE_OCR_LIMIT line
# where that stops. A real foot window carrying known text on a known
# #3fae2a background is the on-screen fixture (foot renders through the
# same fontconfig monospace alias the whole shell depends on, so there is
# no imagemagick font lookup to gamble on, and its own background is the
# solid fill a colour pick needs). `capture text` must start a real
# `slurp -d` and report capturing:true in mode "text"; `capture color` must
# start slurp's single-point mode instead (`slurp -p`, asserted through
# pgrep, since the two verbs differ only in the flags they hand slurp);
# both must cancel clean with no slurp left behind; and the clipboard must
# still hold the sentinel this rig put there, proving a cancelled capture
# copied nothing rather than merely reporting that it didn't. The OCR text
# and the picked hex actually reaching the clipboard stay host-trial: both
# verbs block on a real slurp drag, CaptureIpc exposes no geometry stand-in
# for that answer (unlike picker choose / screenshot key / tray expand),
# slurp cannot be shimmed off the shell's PATH the way nix/gh are
# (nix/package.nix installs it with makeWrapper's --prefix, which outranks
# anything this rig can put on the session PATH; wtype is --suffix for
# exactly the opposite reason and says so), and this rig has no synthetic
# pointer at all.
# With --reminder (M22), sets one real countdown and waits it out. 12s
# rather than 1s: the pending state has to survive long enough to be
# screenshotted (reminder-pending.png, the bar's countdown indicator
# cell), dumped through `reminder status` and read back out of the real
# state.json, which is where a reminder survives a restart. DND is turned
# ON before the reminder is ever set, so the toast that lands after the
# deadline (reminder-fired.png) can only have got into the popup tier
# through Notifications/model.js's bypassesDnd(): the urgency-2 bypass
# proven rather than read off the source. Afterwards `reminder status`
# must be back to count 0 and state.json must no longer carry the entry.
# With --toggles (M22), summons the menu's toggle hub and proves a
# checkmark flips live. `debug query` carries each row's resolved `checked`
# (Menu.qml's query() maps it through toggles.js's checkedFor), so the
# checkmark is readable from outside the process, and `menu status` before
# and after must be byte-identical: the surface stays open at the same
# level across the toggles, which is what "no rebuild" means here.
# `nightlight toggle` is the row the plan names and its assertion is the
# cross-check the row exists for: the checkmark must agree with
# `nightlight status` in BOTH samples, which is what proves the row renders
# the service's real state rather than the fact that a toggle was asked
# for. On this VM that means both stay honestly false (nested niri
# advertises no wlr-gamma-control-unstable-v1, so wlsunset exits on its
# own, the same deterministic branch --nightlight documents). The DND
# row's own "@state:" path has no external dependency, so it is what proves
# a checkmark genuinely flips false -> true inside the open hub, cross-checked
# against `notifications status`.
# With --keybinds (M22), writes a real niri config.kdl into the isolated
# XDG_CONFIG_HOME and reads the parsed binds back through the menu route.
# The nested session is launched with `--config <tmp>`, which is NOT on
# Menu.qml's own lookup chain (settings override, $NIRI_CONFIG, then
# $XDG_CONFIG_HOME/niri/config.kdl, then /etc/niri/config.kdl), so the
# fixture goes to the third candidate and the settings override is left
# unset: the documented lookup itself is what has to resolve. The fixture
# is a real config rather than a bare binds block (a preceding sibling
# block with nested braces, a quoted argument holding "//" and braces, a
# hotkey-overlay-title property, a line comment, a "/-"-disabled bind), and
# the assertions are exact: five live rows, the disabled bind absent, the
# fixture's own chords carrying their own actions, and none of the route's
# four honest end-state rows (a NO CONFIG here would mean the shell read
# some other file). Rows are inert notes by construction, so there is no
# activation to drive (see Compositor/keybinds.js).
# With --mic (M22), points bar.layout at the opt-in "microphone" builtin.
# THE HONEST NO MIC STATE IS THE PASSING RESULT: this VM has a pipewire
# null sink and no capture device at all, so AudioService.sourceAvailable
# is genuinely false and MicWidget renders its one dim NO MIC label instead
# of a glyph, staying visible because the user opted in. A glyph here would
# mean the widget invented a device. The live/muted states need real
# capture hardware and stay host-trial, the same split --nightlight and
# --panel tailscale already document.
# With --systemupdate (M22), points bar.layout at the opt-in "systemUpdate"
# builtin (which is what flips the panel's pollEnabled, so cell and panel
# read one poll) and settings.json's systemUpdate.flakeDir at THIS REPO, so
# the panel parses a real flake.lock and probes the real upstream refs
# behind its real inputs. `panel open systemupdate` then leaves the popout
# open through the screenshot. No count is asserted: that would be
# asserting the state of github rather than of this panel. N BEHIND, ALL
# CURRENT, NO NETWORK and CHECKING are all real answers here.
# With --plugins (M22), writes a real drop-in plugin directory
# (manifest.json + an entry.qml that itself imports qs.Core and reads
# Theme, the same shared-engine proof --bar-layout's `qml` module fixture
# makes) under the isolated config home and reads it back through the
# `plugins` target. No `bar` key is written for this leg on purpose: the
# manifest's own `region` is what places the cell, so dropping the
# directory in is the whole install. `plugins list` must show the resolved
# record and `plugins status` must report one loaded bar plugin with no
# errors and no warnings: the only place a plugin's entry QML failing to
# load is visible from outside the process, since plugin QML lives outside
# the repo and qmllint never sees it.
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
# IPC/quickshell sockets. Anything the nested shell keys off XDG_RUNTIME_DIR
# is therefore shared with the owner's live shell and has to distinguish the
# two itself: InstanceLock.qml's lock socket is per-WAYLAND_DISPLAY for exactly
# that reason (see its header), since a fixed name had the nested shell sending
# the owner's real bar a takeover request and quitting it on every run.
#
# quickshell's own IPC instance registry is one more thing keyed off
# XDG_RUNTIME_DIR: `by-path/<md5(configFilePath)>`, so a formalshell in the
# owner's live session built from the same store path shares the bucket this
# run's shell registers in. WAYLAND_DISPLAY is quickshell's only discriminator
# between them (QsPaths::collectInstances skips a mismatched
# `info.instance.display`), and multiple matches are not an error: selectInstance
# sorts oldest-first and takes instances.value(0). So NEVER pass --any-display
# on a call here, which is exactly the flag that drops that filter: the owner's
# older bar would answer while grim keeps photographing the nested session, and
# a leg would read as "the IPC state says X, the screenshot says not-X" with
# both halves honest about different processes (observed on g815 2026-08-11, the
# --record leg's missing bar indicator). Every call below runs inside the nested
# session (spawn-at-startup drive scripts), so it already carries the nested
# WAYLAND_DISPLAY and the filter selects this run's shell exactly.
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
clipssh_mode=false
wifi_mode=false
media_mode=false
lock_mode=false
polkit_mode=false
screensaver_mode=false
screensaver_gif_mode=false
picker_mode=false
tray_mode=false
chevron_mode=false
bar_layout_mode=false
screenshot_mode=false
capture_mode=false
nightlight_mode=false
speedtest_mode=false
instance_mode=false
share_mode=false
visualizer_mode=false
gallery_mode=false
record_mode=false
ocr_mode=false
reminder_mode=false
toggles_mode=false
keybinds_mode=false
mic_mode=false
systemupdate_mode=false
plugins_mode=false
hotcorner_mode=false
panel_keys_mode=false
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
    --clipssh) clipssh_mode=true; shift ;;
    --wifi) wifi_mode=true; shift ;;
    --media) media_mode=true; shift ;;
    --lock) lock_mode=true; shift ;;
    --polkit) polkit_mode=true; shift ;;
    --screensaver) screensaver_mode=true; shift ;;
    --screensaver-gif) screensaver_gif_mode=true; shift ;;
    --picker) picker_mode=true; shift ;;
    --tray) tray_mode=true; shift ;;
    --chevron) chevron_mode=true; shift ;;
    --bar-layout) bar_layout_mode=true; shift ;;
    --screenshot) screenshot_mode=true; shift ;;
    --capture) capture_mode=true; shift ;;
    --nightlight) nightlight_mode=true; shift ;;
    --speedtest) speedtest_mode=true; shift ;;
    --instance) instance_mode=true; shift ;;
    --share) share_mode=true; shift ;;
    --visualizer) visualizer_mode=true; shift ;;
    --gallery) gallery_mode=true; shift ;;
    --record) record_mode=true; shift ;;
    --ocr) ocr_mode=true; shift ;;
    --reminder) reminder_mode=true; shift ;;
    --toggles) toggles_mode=true; shift ;;
    --keybinds) keybinds_mode=true; shift ;;
    --mic) mic_mode=true; shift ;;
    --systemupdate) systemupdate_mode=true; shift ;;
    --plugins) plugins_mode=true; shift ;;
    --hotcorner) hotcorner_mode=true; shift ;;
    --panel-keys) panel_keys_mode=true; shift ;;
    *) echo "usage: $0 [--dump] [--wallpaper] [--theme-toggle] [--menu] [--notify] [--center] [--osd] [--panel <name>] [--clipboard] [--wifi] [--media] [--lock] [--polkit] [--screensaver] [--screensaver-gif] [--picker] [--tray] [--chevron] [--bar-layout] [--screenshot] [--capture] [--nightlight] [--speedtest] [--instance] [--share] [--visualizer] [--gallery] [--record] [--ocr] [--reminder] [--toggles] [--keybinds] [--mic] [--systemupdate] [--plugins] [--hotcorner] [--panel-keys]" >&2; exit 1 ;;
  esac
done

# --panel github shares the gh shim (and its PATH splice) with --bar-layout.
panel_github_mode=false
if $panel_mode && [ "$panel_name" = "github" ]; then
  panel_github_mode=true
fi

# M14 Task 5: only the plain/default leg gets the focused fixture window —
# every other mode's own smoke.png already exists to prove a different,
# more specific surface (a summoned panel/menu, a locked screen, …), so
# this stays scoped to the one leg CLAUDE.md already calls "THE visual
# verification loop for any bar/surface change".
active_window_fixture_mode=true
if $dump_mode || $wallpaper_mode || $theme_toggle_mode || $menu_mode || $notify_mode || $center_mode || $osd_mode || $panel_mode || $clipboard_mode || $clipssh_mode || $wifi_mode || $media_mode || $lock_mode || $polkit_mode || $screensaver_mode || $screensaver_gif_mode || $picker_mode || $tray_mode || $chevron_mode || $bar_layout_mode || $screenshot_mode || $capture_mode || $nightlight_mode || $speedtest_mode || $instance_mode || $share_mode || $visualizer_mode || $gallery_mode || $record_mode || $ocr_mode || $reminder_mode || $toggles_mode || $keybinds_mode || $mic_mode || $systemupdate_mode || $plugins_mode || $panel_keys_mode; then
  active_window_fixture_mode=false
fi
# --panel appmenu is the one panel leg that needs the fixture window back:
# the app menu is about the focused app, so with nothing focused its only
# honest rendering is the NO WINDOW cell.
if $panel_mode && [ "$panel_name" = "appmenu" ]; then
  active_window_fixture_mode=true
fi
# --capture needs it for the same reason and then some: the region picker is
# ABOUT windows, and the foot fixture is a real TILED niri window, which is
# precisely the case that has no rectangle to draw (see RegionPicker.qml's
# header). Without it the leg would exercise only the output rectangles and
# never reach the named-window path at all.
if $capture_mode; then
  active_window_fixture_mode=true
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

if $wallpaper_mode || $picker_mode || $screensaver_gif_mode || $menu_mode || $active_window_fixture_mode || $clipboard_mode || $media_mode || $visualizer_mode; then
  if command -v convert >/dev/null 2>&1; then
    convert_bin=convert
  else
    convert_bin="nix run nixpkgs#imagemagick -- convert"
  fi
fi

# ocr_mode reuses the same real terminal as its on-screen fixture: foot
# renders known text with the fontconfig monospace alias the whole shell
# already depends on, and its own background color is a known solid fill
# for the colour-pick leg: one real window carrying both targets, with no
# imagemagick font lookup to gamble on.
if $active_window_fixture_mode || $ocr_mode; then
  if command -v foot >/dev/null 2>&1; then
    foot_bin=$(command -v foot)
  else
    foot_bin=$(nix build 'nixpkgs#foot^out' --no-link --print-out-paths)/bin/foot
  fi
fi

if $osd_mode; then
  if command -v wpctl >/dev/null 2>&1; then
    wpctl_bin=$(command -v wpctl)
  else
    wpctl_bin=$(nix build 'nixpkgs#wireplumber^out' --no-link --print-out-paths)/bin/wpctl
  fi
fi

if $clipboard_mode || $share_mode || $ocr_mode; then
  if command -v wl-copy >/dev/null 2>&1; then
    wl_copy_bin=$(command -v wl-copy)
  else
    wl_copy_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-copy
  fi
fi

# screenshot_mode and menu_mode only read the clipboard back (the shell's
# own wrapper PATH carries the wl-copy side); clipboard_mode and ocr_mode
# need both directions (ocr_mode seeds a sentinel, then reads it back to
# prove a cancelled capture copied nothing over it).
if $clipboard_mode || $screenshot_mode || $menu_mode || $ocr_mode; then
  if command -v wl-paste >/dev/null 2>&1; then
    wl_paste_bin=$(command -v wl-paste)
  else
    wl_paste_bin=$(nix build 'nixpkgs#wl-clipboard^out' --no-link --print-out-paths)/bin/wl-paste
  fi
fi

if $screenshot_mode || $capture_mode || $record_mode; then
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

if $media_mode || $screensaver_mode || $visualizer_mode; then
  # The VM's mpv is pre-wrapped with mpvScripts.mpris baked into its
  # --script= flags (nix/testvm.nix's `mpv.override { scripts = ... }`), so
  # plain `mpv` on PATH there already announces itself over MPRIS. A host
  # without that package wired in gets the exact same wrapped derivation
  # built from this repo's own pinned nixpkgs input, not the flake registry
  # (`.override` isn't expressible as a flake installable attribute path).
  # screensaver_mode reuses this same fixture track/player to give
  # MediaService.isPlaying a real value to guard against; visualizer_mode
  # needs it too (its own fixture is a real tone, not the silent one below,
  # so cava has an actual spectrum to read).
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

# record_mode needs ffprobe alone (no mpv), to read back what
# RecordingService's own finalize pass did to a real captured file.
if $media_mode || $screensaver_mode || $visualizer_mode || $record_mode; then
  if [ -z "${ffmpeg_bin:-}" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg_bin=$(command -v ffmpeg)
    else
      ffmpeg_bin=$(nix build 'nixpkgs#ffmpeg-headless^out' --no-link --print-out-paths)/bin/ffmpeg
    fi
  fi
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe_bin=$(command -v ffprobe)
  else
    ffprobe_bin="$(dirname "$ffmpeg_bin")/ffprobe"
  fi
fi

if $lock_mode || $polkit_mode || $menu_mode || $panel_keys_mode; then
  if command -v wtype >/dev/null 2>&1; then
    wtype_bin=$(command -v wtype)
  else
    wtype_bin=$(nix build 'nixpkgs#wtype^out' --no-link --print-out-paths)/bin/wtype
  fi
fi

# No nix-build fallback: a pkexec built as a plain derivation has no setuid
# bit (the Nix store never preserves one), so it cannot actually escalate —
# unlike wtype/grim, this one has to already be the real, wrapper-owned
# binary nix/testvm.nix's `security.polkit.enable` installs.
if $polkit_mode; then
  if command -v pkexec >/dev/null 2>&1; then
    pkexec_bin=$(command -v pkexec)
  else
    echo "SMOKE_FAIL: pkexec not found on PATH — needs a real security.polkit.enablePkexecWrapper host (the setuid wrapper), not buildable via nix fallback" >&2
    exit 1
  fi
  # pkexec resets PATH to its own compiled-in secure default before
  # exec'ing the target, which has no notion of the Nix store — a bare
  # `true` 127s. `type -P`, not `command -v`: bash's own builtin `true`
  # shadows the real binary, and `command -v` on a builtin returns just the
  # bare word "true" (not a path) — reproduced directly, that bare word fed
  # to pkexec still 127s. `-P` forces a real $PATH search, skipping
  # builtins/aliases/functions entirely.
  true_bin=$(type -P true)
fi

if $lock_mode || $polkit_mode || $screensaver_gif_mode || $menu_mode || $theme_toggle_mode \
  || $record_mode || $ocr_mode || $reminder_mode || $toggles_mode || $keybinds_mode \
  || $mic_mode || $systemupdate_mode || $plugins_mode || $chevron_mode || $panel_keys_mode; then
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
  # The M22 legs (record/ocr/reminder/toggles/keybinds/mic/systemupdate/
  # plugins) all pick grim for that same no-toast reason: every one of their
  # shots exists to read one small thing (an indicator glyph, a toast, a
  # menu row, one bar cell), and niri's own capture toast lands on top of
  # exactly that corner. chevron_mode is the sharpest case of it: its whole
  # claim is which cells the bar's RIGHT region is drawing, which is
  # precisely where that toast lands.
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

# InstanceLock.qml keys its socket on WAYLAND_DISPLAY, so the nested shell and
# the owner's live bar can never share a lock even though this run deliberately
# keeps the outer XDG_RUNTIME_DIR (host-session-safety comment above). Stale
# sockets from earlier nested runs can still pile up in that shared runtime
# dir when a previous run's shell exited abnormally rather than losing its
# nested Wayland connection cleanly, so clear them before --instance's takeover
# proof runs. The host's own socket is skipped by name: removing it would not
# quit the live bar, but it would strand the next real rebuild+respawn takeover.
if $instance_mode; then
  instance_lock_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/formalshell"
  for stale in "$instance_lock_dir"/instance-*.sock; do
    [ -e "$stale" ] || continue
    if [ "$stale" != "$instance_lock_dir/instance-$wayland_display.sock" ]; then
      rm -f "$stale" 2>/dev/null || true
    fi
  done
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
  ss_gif_hold=8      # extra frames held on the finished banner after convergence
  ss_gif_budget=120  # captured frames per GIF, before the hold
  ss_gif_fps=60      # screensaver.frameRate's default, which these runs leave alone
  ss_gif_home=$(mktemp -d)
  media_dir="$PWD/docs/media"
  mkdir -p "$media_dir" "$ss_gif_home/.config/formalshell"

  # SCREENSAVER_GIF_EFFECTS (optional, additive, space-separated): limits
  # the run to a subset — a recorder-contract verification only needs one
  # effect and must not regenerate every committed GIF to prove it.
  #
  # ttfx names, and deliberately not matrix or thunderstorm: those two are
  # gated on wall-clock time rather than frame count, so a pinned run emits
  # however many frames the host manages inside that window and the same
  # frame index means something different on the next machine.
  ss_gif_effects=(decrypt rain expand slide scattered)
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
"$qs_bin" ipc -p "$shell_path" call screensaver start > /dev/null 2>&1
sleep 1
# Pin frame 0 before asking for the count: a ttfx run streams, so the only
# honest frame total is the one a completed pinned run actually produced,
# and frameInfo answers 0 until then rather than guessing.
"$qs_bin" ipc -p "$shell_path" call screensaver frame 0 > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call screensaver frameInfo > "$ss_gif_convergence_path" 2>&1
convergence=\$(grep -o '"convergenceFrame":[0-9]*' "$ss_gif_convergence_path" | cut -d: -f2)
stride=\$(( (convergence + $ss_gif_budget - 1) / $ss_gif_budget ))
[ "\$stride" -lt 1 ] && stride=1
idx=0
for ((i = 0; i < convergence; i += stride)); do
  "$qs_bin" ipc -p "$shell_path" call screensaver frame "\$i" > /dev/null 2>&1
  # Longer than the pre-ttfx 0.15s: a pin regenerates the whole run to reach
  # the frame, so the surface needs the generation plus one repaint before
  # grim reads the framebuffer.
  sleep 0.4
  printf -v padded "%04d" "\$idx"
  "$grim_bin" "$frames_dir/frame-\$padded.png"
  idx=\$((idx + 1))
done
# The hold is the converged banner repeated, which is exactly what the live
# surface shows between convergence and the next cycle — copied rather than
# re-captured, since re-pinning the same frame would regenerate the whole
# run again for a byte-identical screenshot.
printf -v last "%04d" "\$((idx - 1))"
for ((h = 0; h < $ss_gif_hold; h++)); do
  printf -v padded "%04d" "\$((idx + h))"
  cp "$frames_dir/frame-\$last.png" "$frames_dir/frame-\$padded.png"
done
"$qs_bin" ipc -p "$shell_path" call screensaver stop > /dev/null 2>&1
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
    # The engine is asserted, not assumed: with ttfx missing from the shell's
    # wrapper PATH the surface silently falls back to effect.js's builtin
    # effects, which would still record a plausible GIF of the wrong thing.
    if ! grep -q '"engine":"ttfx"' "$ss_gif_convergence_path"; then
      echo "SMOKE_FAIL: screensaver is not running the ttfx engine — got: $(cat "$ss_gif_convergence_path" 2>/dev/null)" >&2
      exit 1
    fi
    convergence=$(grep -o '"convergenceFrame":[0-9]*' "$ss_gif_convergence_path" | cut -d: -f2)
    if [ -z "$convergence" ] || [ "$convergence" -le 0 ]; then
      echo "SMOKE_FAIL: screensaver frameInfo reported no frames for '$effect' — got: $(cat "$ss_gif_convergence_path" 2>/dev/null)" >&2
      exit 1
    fi
    stride=$(( (convergence + ss_gif_budget - 1) / ss_gif_budget ))
    [ "$stride" -lt 1 ] && stride=1
    expected_frames=$(( (convergence + stride - 1) / stride + ss_gif_hold ))

    shopt -s nullglob
    frame_files=("$frames_dir"/frame-*.png)
    shopt -u nullglob
    frame_count=${#frame_files[@]}
    # Exact match, not just "enough frames": a session killed mid-capture
    # (the drive script's own `timeout 200`, or a long run at 0.15s/frame
    # plus one qs ipc spawn each) would otherwise still produce a
    # plausible-looking but truncated GIF that never reaches the banner, and
    # this would exit 0 regardless.
    if [ "$frame_count" -ne "$expected_frames" ]; then
      echo "SMOKE_FAIL: $effect captured $frame_count frame(s), expected $expected_frames (convergence $convergence at stride $stride + hold $ss_gif_hold) — session likely killed mid-capture" >&2
      exit 1
    fi

    out_gif="$media_dir/screensaver-$effect.gif"
    # Frame delay in centiseconds, derived from the stride so the GIF plays
    # at the speed the animation really runs: one captured frame stands for
    # `stride` frames at screensaver.frameRate. Floored at 2cs, which is as
    # fast as GIF playback goes in practice.
    gif_delay=$(( (stride * 100 + ss_gif_fps / 2) / ss_gif_fps ))
    [ "$gif_delay" -lt 2 ] && gif_delay=2
    "$convert_bin" -delay "$gif_delay" -loop 0 "$frames_dir"/frame-*.png -resize 640x -coalesce -layers Optimize -colors 96 "$out_gif"
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
wallpaper_get_path="$shot_dir/wallpaper-get.txt"
wallpaper_solid_path="$shot_dir/wallpaper-solid.png"
clipssh_route_path="$shot_dir/clipssh-route.png"
clipssh_sending_path="$shot_dir/clipssh-sending.png"
clipssh_copied_path="$shot_dir/clipssh-copied.png"
clipssh_failed_path="$shot_dir/clipssh-failed.png"
theme_dark_png="$shot_dir/theme-dark.png"
theme_light_png="$shot_dir/theme-light.png"
theme_toggle_status_path="$shot_dir/theme-toggle-status.json"
theme_toggle_status2_path="$shot_dir/theme-toggle-status-2.json"
theme_json_dump1_path="$shot_dir/theme-json-1.json"
theme_json_dump2_path="$shot_dir/theme-json-2.json"
theme_json_dump3_path="$shot_dir/theme-json-3.json"
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
menu_top_before_png="$shot_dir/menu-top-before.png"
menu_top_after_png="$shot_dir/menu-top-after.png"
menu_top_relevel_png="$shot_dir/menu-top-relevel.png"
toggle_path="$shot_dir/menu-toggle.txt"
emoji_drive_path="$shot_dir/emoji-drive.txt"
emoji_paste_path="$shot_dir/emoji-paste.txt"
emoji_type_path="$shot_dir/emoji-wtype.txt"
selection_path="$shot_dir/selection.txt"
menu_done_path="$shot_dir/menu-done.flag"
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
clip_image_fixture_path="$shot_dir/clip-fixture.png"
clip_list3_path="$shot_dir/clip-list-3.json"
clip_image_copy_path="$shot_dir/clip-image-copy.txt"
clip_image_paste_sha_path="$shot_dir/clip-image-paste-sha.txt"
wifi_scan_status_path="$shot_dir/wifi-scan-status.json"
wifi_wrong_path="$shot_dir/wifi-wrong.png"
wifi_wrong_status_path="$shot_dir/wifi-wrong-status.json"
wifi_connected_path="$shot_dir/wifi-connected.png"
wifi_connected_status_path="$shot_dir/wifi-connected-status.json"
wifi_forget_status_path="$shot_dir/wifi-forget-status.json"
wifi_eap_connected_path="$shot_dir/wifi-eap-connected.png"
wifi_eap_status_path="$shot_dir/wifi-eap-status.json"
wifi_eap_forget_status_path="$shot_dir/wifi-eap-forget-status.json"
wifi_reset_status_path="$shot_dir/wifi-reset-status.json"
media_status_path="$shot_dir/media-status.json"
media_marquee_static_path="$shot_dir/media-marquee-static.png"
media_marquee_scroll_path="$shot_dir/media-marquee-scroll.png"
media_status_long_path="$shot_dir/media-status-long.json"
eds_seed_path="$shot_dir/eds-seed.txt"
eds_seed2_path="$shot_dir/eds-seed-2.txt"
calendar_select_path="$shot_dir/calendar-select.txt"
calendar_status_path="$shot_dir/calendar-status.json"
media_pid_path="$shot_dir/mpv.pid"
visualizer_pid_path="$shot_dir/visualizer-mpv.pid"
visualizer_playing_path="$shot_dir/visualizer-playing.png"
visualizer_pgrep_playing_path="$shot_dir/visualizer-pgrep-playing.txt"
visualizer_pgrep_after_path="$shot_dir/visualizer-pgrep-after.txt"
gallery_log_path="$shot_dir/gallery.log"
active_window_pid_path="$shot_dir/foot.pid"
lock_locked_path="$shot_dir/lock-locked.png"
lock_typing_path="$shot_dir/lock-typing.png"
lock_error_path="$shot_dir/lock-error.png"
lock_unlocked_path="$shot_dir/lock-unlocked.png"
lock_islocked1_path="$shot_dir/lock-islocked-1.txt"
lock_islocked2_path="$shot_dir/lock-islocked-2.txt"
lock_status_path="$shot_dir/lock-status.json"
lock_call_rc_path="$shot_dir/lock-call-rc.txt"
lock_before_sleep_rc_path="$shot_dir/lock-before-sleep-rc.txt"
polkit_active_path="$shot_dir/polkit-active.png"
polkit_error_path="$shot_dir/polkit-error.png"
polkit_rc_path="$shot_dir/polkit-rc.txt"
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
picker_mem_path="$shot_dir/picker-memory.json"
picker_flat_status_path="$shot_dir/picker-status-flat.json"
picker_dark_status_path="$shot_dir/picker-status-dark.json"
picker_light_status_path="$shot_dir/picker-status-light.json"
picker_variant_reply_path="$shot_dir/picker-variant-reply.txt"
picker_variant_path="$shot_dir/picker-variant.png"
tray_status_path="$shot_dir/tray-status.json"
tray_strip_path="$shot_dir/tray-strip.png"
tray_pids_path="$shot_dir/tray-pids.txt"
tray_activate_path="$shot_dir/tray-activate.txt"
tray_activate_reply_path="$shot_dir/tray-activate-reply.txt"
chevron_status_collapsed_path="$shot_dir/chevron-status-collapsed.json"
chevron_status_expanded_path="$shot_dir/chevron-status-expanded.json"
chevron_expand_reply_path="$shot_dir/chevron-expand-reply.txt"
chevron_collapsed_path="$shot_dir/chevron-collapsed.png"
chevron_expanded_path="$shot_dir/chevron-expanded.png"
bar_layout_path="$shot_dir/bar-layout.png"
hotcorner_layers_path="$shot_dir/hotcorner-layers.json"
instance_status_path="$shot_dir/instance-status.json"
instance_primary_log_path="$shot_dir/instance-primary.log"
instance_second_log_path="$shot_dir/instance-second.log"
audio_panel_path="$shot_dir/audio-panel.png"
panel_keys_baseline_path="$shot_dir/panel-keys-baseline.png"
panel_keys_path="$shot_dir/panel-keys.png"
screenshot_reply_path="$shot_dir/screenshot-reply.txt"
screenshot_status_path="$shot_dir/screenshot-status.json"
screenshot_types_path="$shot_dir/screenshot-types.txt"
screenshot_region_reply_path="$shot_dir/screenshot-region-reply.txt"
screenshot_region_status_path="$shot_dir/screenshot-region-status.json"
screenshot_cancel_reply_path="$shot_dir/screenshot-cancel-reply.txt"
screenshot_cancelled_status_path="$shot_dir/screenshot-cancelled-status.json"
screenshot_slurp_before_path="$shot_dir/screenshot-slurp-before.txt"
screenshot_slurp_after_path="$shot_dir/screenshot-slurp-after.txt"
capture_picker_path="$shot_dir/capture-picker.png"
capture_open_status_path="$shot_dir/capture-open-status.json"
capture_cycled_status_path="$shot_dir/capture-cycled-status.json"
capture_pick_reply_path="$shot_dir/capture-pick-reply.txt"
capture_status_path="$shot_dir/capture-status.json"
capture_escape_status_path="$shot_dir/capture-escape-status.json"
capture_outputs_path="$shot_dir/capture-outputs.json"
capture_toolbar_path="$shot_dir/capture-toolbar-record.png"
capture_tool_status_path="$shot_dir/capture-tool-status.json"
capture_rec_reply_path="$shot_dir/capture-rec-reply.txt"
capture_rec_status_path="$shot_dir/capture-rec-status.json"
capture_rec_stopped_path="$shot_dir/capture-rec-stopped.json"
record_start_reply_path="$shot_dir/record-start-reply.txt"
record_status1_path="$shot_dir/record-status-1.json"
record_status2_path="$shot_dir/record-status-2.json"
record_status3_path="$shot_dir/record-status-3.json"
record_stop_reply_path="$shot_dir/record-stop-reply.txt"
record_gif_reply_path="$shot_dir/record-gif-reply.txt"
record_active_path="$shot_dir/record-active.png"
record_finalize_status_path="$shot_dir/record-finalize-status.json"
record_ffprobe_path="$shot_dir/record-ffprobe.txt"
ocr_fixture_png="$shot_dir/ocr-fixture-screen.png"
ocr_text_status_path="$shot_dir/ocr-text-status.json"
ocr_text_slurp_path="$shot_dir/ocr-text-slurp.txt"
ocr_text_overlay_png="$shot_dir/ocr-text-overlay.png"
ocr_text_cancel_path="$shot_dir/ocr-text-cancel.json"
ocr_textat_status_path="$shot_dir/ocr-textat-status.json"
ocr_textat_clipboard_path="$shot_dir/ocr-textat-clipboard.txt"
ocr_colorat_status_path="$shot_dir/ocr-colorat-status.json"
ocr_colorat_clipboard_path="$shot_dir/ocr-colorat-clipboard.txt"
ocr_color_status_path="$shot_dir/ocr-color-status.json"
ocr_color_slurp_path="$shot_dir/ocr-color-slurp.txt"
ocr_color_overlay_png="$shot_dir/ocr-color-overlay.png"
ocr_color_cancel_path="$shot_dir/ocr-color-cancel.json"
ocr_clipboard_path="$shot_dir/ocr-clipboard.txt"
ocr_slurp_after_path="$shot_dir/ocr-slurp-after.txt"
ocr_pid_path="$shot_dir/ocr-foot.pid"
reminder_set_reply_path="$shot_dir/reminder-set-reply.json"
reminder_status1_path="$shot_dir/reminder-status-1.json"
reminder_status2_path="$shot_dir/reminder-status-2.json"
reminder_state1_path="$shot_dir/reminder-state-1.json"
reminder_state2_path="$shot_dir/reminder-state-2.json"
reminder_dnd_path="$shot_dir/reminder-dnd.txt"
reminder_notifications_path="$shot_dir/reminder-notifications.json"
reminder_pending_png="$shot_dir/reminder-pending.png"
reminder_fired_png="$shot_dir/reminder-fired.png"
toggles_menu_status1_path="$shot_dir/toggles-menu-status-1.json"
toggles_menu_status2_path="$shot_dir/toggles-menu-status-2.json"
toggles_nl_status1_path="$shot_dir/toggles-nightlight-status-1.json"
toggles_nl_status2_path="$shot_dir/toggles-nightlight-status-2.json"
toggles_nl_query1_path="$shot_dir/toggles-nightlight-query-1.json"
toggles_nl_query2_path="$shot_dir/toggles-nightlight-query-2.json"
toggles_dnd_status1_path="$shot_dir/toggles-dnd-status-1.json"
toggles_dnd_status2_path="$shot_dir/toggles-dnd-status-2.json"
toggles_dnd_query1_path="$shot_dir/toggles-dnd-query-1.json"
toggles_dnd_query2_path="$shot_dir/toggles-dnd-query-2.json"
toggles_hub_png="$shot_dir/toggles-hub.png"
toggles_toggled_png="$shot_dir/toggles-toggled.png"
keybinds_query1_path="$shot_dir/keybinds-query-1.json"
keybinds_query2_path="$shot_dir/keybinds-query-2.json"
keybinds_menu_status_path="$shot_dir/keybinds-menu-status.json"
keybinds_menu_png="$shot_dir/keybinds-menu.png"
mic_bar_png="$shot_dir/mic-bar.png"
systemupdate_open_reply_path="$shot_dir/systemupdate-open-reply.txt"
systemupdate_state_path="$shot_dir/systemupdate-panel-state.txt"
systemupdate_panel_png="$shot_dir/systemupdate-panel.png"
plugins_list_path="$shot_dir/plugins-list.json"
plugins_status_path="$shot_dir/plugins-status.json"
plugins_bar_png="$shot_dir/plugins-bar.png"
nightlight_active_path="$shot_dir/nightlight-active.png"
nightlight_status1_path="$shot_dir/nightlight-status-1.json"
nightlight_status2_path="$shot_dir/nightlight-status-2.json"
speedtest_panel_path="$shot_dir/speedtest-panel.png"
speedtest_status_path="$shot_dir/speedtest-status.json"
share_query1_path="$shot_dir/share-query-1.json"
share_query2_path="$shot_dir/share-query-2.json"
share_menu_path="$shot_dir/share-menu.png"
share_pgrep_path="$shot_dir/share-pgrep.txt"
share_cmdline_path="$shot_dir/share-cmdline.txt"
share_tmpfile_path="$shot_dir/share-tmpfile.txt"
share_primary_log_path="$shot_dir/share-primary.log"
share_second_log_path="$shot_dir/share-second.log"
share_instance_status_path="$shot_dir/share-instance-status.json"
share_absent_query1_path="$shot_dir/share-absent-query-1.json"
share_absent_query2_path="$shot_dir/share-absent-query-2.json"
share_menu_absent_path="$shot_dir/share-menu-absent.png"

# --share's second phase (the honest-absent proof) needs a PATH that
# genuinely cannot find `localsend_app` — not a shim with a fake one ahead
# of it (the nix/gh/wtype shims above), but the session's real PATH minus
# that one binary, so every OTHER Process the shell spawns (sh for the
# `when` check itself, wl-paste, matugen, …) still resolves normally. PATH
# order is preserved (first directory wins) so this is a faithful mirror,
# not a guess at what else needs to be on it.
if $share_mode; then
  share_noshare_dir="$shot_dir/share-noshare-shim"
  mkdir -p "$share_noshare_dir"
  _share_saved_ifs="$IFS"
  IFS=':'
  for _share_path_dir in $PATH; do
    IFS="$_share_saved_ifs"
    [ -d "$_share_path_dir" ] || continue
    for _share_path_entry in "$_share_path_dir"/*; do
      [ -e "$_share_path_entry" ] || continue
      _share_entry_name=$(basename "$_share_path_entry")
      [ "$_share_entry_name" = "localsend_app" ] && continue
      [ -e "$share_noshare_dir/$_share_entry_name" ] && continue
      ln -s "$_share_path_entry" "$share_noshare_dir/$_share_entry_name"
    done
    IFS=':'
  done
  IFS="$_share_saved_ifs"
fi

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

# clipssh's own alias store, in the isolated HOME so the route's rows are
# this run's two and not whatever the host has saved. `nohost` is the row
# whose transfer fails; the shim above keys its failure off that name.
if $clipssh_mode; then
  mkdir -p "$iso_home/.clipssh"
  printf '%s\n' 'box=test@10.255.255.7' 'nohost=test@10.255.255.1' > "$iso_home/.clipssh/aliases"
fi

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
# M14 Task 5 reuses this exact same fixture (its id, "formalshell-smoke-
# iconic", is what the foot window below is spawned with as its Wayland
# app-id) so DesktopEntries.heuristicLookup's exact-id path resolves it for
# ActiveWindow.qml too, rather than standing up a second near-duplicate
# .desktop file. Its two Desktop Action groups are what `--panel appmenu`
# renders as the app menu's ACTIONS rows — real groups read back through
# the real XDG lookup, the same fixture-data-not-stubbed-code contract as
# the calendar leg's .ics file; the other legs never read them.
if $menu_mode || $active_window_fixture_mode; then
  cat > "$iso_home/.local/share/applications/formalshell-smoke-iconic.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Iconic Test App
Exec=true
Icon=formalshell-smoke
Actions=new-window;preferences;

[Desktop Action new-window]
Name=New Window
Exec=true

[Desktop Action preferences]
Name=Preferences
Exec=true
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
# --panel calendar's life-progress row (M20 Task 5e): pre-seeding state.json
# with a resolved birth-year/life-expectancy pair before the shell ever
# starts is the honest headless stand-in for a real double-click on the
# year-progress bar — CalendarPanel.qml's `_showLifeProgress` binding
# defaults to "on" the moment a valid pair exists, same as a user who
# already ran the easter egg once. The panel's screenshot then proves the
# life row renders ALONGSIDE the year row rather than replacing it, which a
# real double-click into this nested session cannot exercise at all.
if $panel_mode && [ "$panel_name" = "calendar" ]; then
  mkdir -p "$iso_home/.local/state/formalshell"
  cat > "$iso_home/.local/state/formalshell/state.json" <<EOF
{"wallpaper": "", "mode": "dark", "dnd": false, "calendarBirthYear": 1990, "calendarLifeExpectancy": 80, "appLaunches": []}
EOF
fi
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
elif $visualizer_mode; then
  # Puts the widget right where the owner asked for it — next to
  # nowPlaying — leaving left/right at their own DEFAULT_LAYOUT fallback
  # (only the `center` key is present).
  bar_settings=', "bar": {"layout": {"center": ["clock", "nowPlaying", "visualizer"]}}'
elif $mic_mode; then
  # The whole point of an opt-in builtin: the cell only exists because
  # bar.layout names it. Leading the right region rather than appended, so
  # it can't be clipped off the end of a full row.
  bar_settings=', "bar": {"layout": {"right": ["microphone", "battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators"]}}'
elif $chevron_mode; then
  # M24: the chevron's POSITION is its whole configuration, so the fixture is
  # today's exact default right region with one name inserted mid-way. M25
  # moved which side of that name collapses: a right-region chevron governs
  # what PRECEDES it, so the same five names (bluetooth, weather, tray, bell,
  # indicators) are the hidden set the status dumps below assert on only if
  # they now lead the region, with battery/audio/network sitting outboard
  # against the screen edge. Those three are what proves the anchoring: they
  # and the chevron itself hold their x across the two screenshots, since the
  # group opens inward into empty bar rather than pushing the edge.
  bar_settings=', "bar": {"layout": {"right": ["bluetooth", "weather", "tray", "bell", "indicators", "chevron", "battery", "audio", "network"]}}'
elif $systemupdate_mode; then
  # Naming the widget IS the opt-in to background polling
  # (SystemUpdateWidget's Component.onCompleted flips the panel's
  # pollEnabled), so the cell and the panel below are polling the same
  # real flake rather than two independent reads.
  bar_settings=', "bar": {"layout": {"right": ["systemUpdate", "battery", "audio", "network", "bluetooth", "weather", "tray", "bell", "indicators"]}}'
fi
# record_mode: wf-recorder's dmabuf path has no meaning under llvmpipe
# (the nested session renders in software, so there is no GPU buffer to
# import), and without this it fails to negotiate a buffer at all. Every
# other recording key stays at its documented default so this run proves
# those defaults resolve (recording.directory included), which is why the
# post-run assertions read the destination back out of `record status`
# rather than off a path this script chose.
record_settings=""
if $record_mode; then
  record_settings=', "recording": {"noDmabuf": true}'
fi
# systemupdate_mode: this repo's own flake is the target, so the panel
# parses a real flake.lock and probes the real upstream refs behind its
# real inputs. Nothing fabricates a "behind" count: whatever the network
# answers (or fails to) is what renders.
systemupdate_settings=""
if $systemupdate_mode; then
  systemupdate_settings=', "systemUpdate": {"flakeDir": "'"$PWD"'"}'
fi
cat > "$iso_home/.config/formalshell/settings.json" <<EOF
{"calendar": {"icsDir": "$iso_home/.local/share/formalshell/calendar"}, "location": {"latitude": 52.52, "longitude": 13.41}$screensaver_settings$picker_settings$bar_settings$record_settings$systemupdate_settings}
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
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize.body
}
EOF
fi

# --keybinds fixture: a real niri config the SHELL can find. The nested
# session is launched with `--config <tmp>/config.kdl`, which is not on
# Menu.qml's own lookup chain (settings override, $NIRI_CONFIG, then
# $XDG_CONFIG_HOME/niri/config.kdl, then /etc/niri/config.kdl), so the
# binds this leg asserts on are written to the third candidate, the
# isolated XDG_CONFIG_HOME, and the settings override is deliberately
# left unset so the documented lookup itself is what resolves.
#
# Content is a real config rather than a bare binds block: a preceding
# sibling block with its own nested braces (the case a brace-counting
# scanner gets wrong), a quoted argument holding "//" and braces, a
# hotkey-overlay-title property, a line comment, and a "/-"-disabled bind
# that must NOT appear as a live row.
if $keybinds_mode; then
  mkdir -p "$iso_home/.config/niri"
  cat > "$iso_home/.config/niri/config.kdl" <<'EOF'
layout {
    border {
        width 2
    }
}

binds {
    Mod+Shift+Slash { show-hotkey-overlay; }
    Mod+T hotkey-overlay-title="Open a Terminal" { spawn "ghostty"; }
    // a disabled thought
    Mod+Q repeat=false { close-window; }
    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+N { spawn "sh" "-c" "notify-send {braces} // not-a-comment"; }
    /-Mod+Z { quit; }
}
EOF
fi

# --plugins fixture: one real drop-in plugin directory under the isolated
# config home, in the exact shape manifest.js documents. No `bar` key is
# written for this leg on purpose: the manifest's own `region` is what
# places the cell (layout.js appends a bar plugin nobody named to the
# region its manifest asks for), so dropping the directory in is the whole
# install, which is the contract worth proving.
#
# The entry deliberately imports qs.Core and reads Theme, the same proof
# --bar-layout's `qml` module fixture makes: a loaded user component really
# does share the shell's own engine.
if $plugins_mode; then
  plugin_dir="$iso_home/.config/formalshell/plugins/smoke-bar"
  mkdir -p "$plugin_dir"
  cat > "$plugin_dir/manifest.json" <<'EOF'
{
  "apiVersion": 1,
  "id": "smoke-bar",
  "kind": "bar",
  "entry": "entry.qml",
  "name": "Smoke Bar Plugin",
  "region": "right"
}
EOF
  cat > "$plugin_dir/entry.qml" <<'EOF'
import QtQuick
import qs.Core

Text {
    text: "PLUGIN OK"
    color: Theme.color.accent
    font.family: Theme.fontFamily
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

# PATH-shimmed clipssh (same hermetic-producer idea as the nix/gh shims
# above). clipssh itself is a 200-line bash wrapper around ssh, so running
# the real one here would prove nothing about this shell and everything
# about whether the rig can reach an ssh host: what has to be exercised is
# the shell's own path, menu row -> `@ipc:clipssh.send:` -> ClipsshService
# -> Process -> exit code -> toast, plus the indicator cell that is up for
# exactly as long as the process runs. So the shim speaks clipssh's own
# output contract (its bin/clipssh v1.0.0: "Uploaded: <path>" on stdout at
# exit 0, "Error: <reason>" on stderr otherwise, both ANSI-colored) and
# takes 6 seconds over the success case so the in-flight state is a thing a
# screenshot can catch.
if $clipssh_mode; then
  clipssh_shim_dir="$shot_dir/clipssh-shim"
  mkdir -p "$clipssh_shim_dir"
  cat > "$clipssh_shim_dir/clipssh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "nohost" ]; then
  printf '\033[0;31mError:\033[0m Failed to upload to test@10.255.255.1\n' >&2
  exit 1
fi
sleep 6
printf '\033[0;32mUploaded: /tmp/clipboard-1755180000.png\033[0m\n'
printf 'Path copied to clipboard - paste it directly\n'
EOF
  chmod +x "$clipssh_shim_dir/clipssh"
fi

if $picker_mode; then
  # M16 Task 12 perf evidence: fixtures must be genuinely bigger than the
  # grid cell's decode cap (105px cell, 2x for the cover-not-fit fix, so
  # ~210px) and numerous enough that the Grid/Repeater's simultaneous decode
  # (no virtualization — every delegate decodes on open regardless of
  # scroll position) is real, measurable work. A 64x64-times-5 fixture set
  # decodes at native res regardless of any cap and frees under a megabyte
  # on close — indistinguishable from allocator noise. 20 fixtures at
  # 1920x1080 (also bigger than the VM's own screen, so a chosen one
  # exercises Background/LockSurface's cap too) give a signal an order of
  # magnitude above that. img-0..img-4 keep their original colors — later
  # assertions reference img-1.png/img-3.png by path, not color.
  picker_colors=(c0392b 27ae60 2980b9 f1c40f 8e44ad e67e22 16a085 2c3e50 d35400 c2185b 00838f 5d4037 7cb342 512da8 0097a7 ff7043 78909c 43a047 6d4c41 3949ab)
  for i in "${!picker_colors[@]}"; do
    $convert_bin -size 1920x1080 "xc:#${picker_colors[$i]}" "$picker_dir/img-$i.png"
  done
  # The Dark/Light variant sets (2026-08-12), STAGED rather than in place:
  # every leg of the drive above them runs against the flat listing, which is
  # what a directory with no variant pair does, and the drive moves these in
  # mid-run to cover the other half. `.stage` is not one of the scan's
  # starting points, so nothing here is visible until it is moved.
  #
  # 960x540, unlike the 20 above: those are sized to prove the grid's decode
  # cap and to give the Rss bracket a real signal, neither of which is this
  # set's job — it exists to be counted and switched between. Deliberately
  # different counts per variant, so a status dump reporting the wrong set is
  # unambiguous rather than a coincidence.
  picker_dark_colors=(1b2a4a 24344f 2f3f5c 3a4a68 111c33)
  picker_light_colors=(f5efe0 e8dcc3 fbf7ee)
  mkdir -p "$picker_dir/.stage/Dark" "$picker_dir/.stage/Light"
  for i in "${!picker_dark_colors[@]}"; do
    $convert_bin -size 960x540 "xc:#${picker_dark_colors[$i]}" "$picker_dir/.stage/Dark/dark-$i.png"
  done
  for i in "${!picker_light_colors[@]}"; do
    $convert_bin -size 960x540 "xc:#${picker_light_colors[$i]}" "$picker_dir/.stage/Light/light-$i.png"
  done
fi

# --clipboard's image leg fixture: a tiny solid-color PNG, hashed up front
# so the post-run assertions can predict the exact content-addressed path
# ClipboardService's image watcher must produce ($clip_image_fixture_sha.png
# under the isolated HOME's clipboard-images dir) and confirm the wl-paste
# readback round trip byte-for-byte, not just that some path string exists.
if $clipboard_mode; then
  $convert_bin -size 32x32 xc:'#3fae2a' "$clip_image_fixture_path"
  clip_image_fixture_sha=$(sha256sum "$clip_image_fixture_path" | cut -d ' ' -f1)
fi

if $wallpaper_mode; then
  wp_path="$shot_dir/wp.png"
  # 1920x1080, not 640x480: smaller than the VM's own screen never exercises
  # Background/LockSurface's sourceSize cap at all (Qt only scales a decode
  # down, never up, so a source already below the cap just decodes native)
  # — a fixture has to exceed the screen to prove the cap actually engages.
  $convert_bin -size 1920x1080 xc:'#7a3fb0' "$wp_path"
  # A second wallpaper, set once the first has settled, so the run covers
  # Background.qml's crossfade path and not just its first-paint shortcut.
  # That matters most with the dither on (wallpaper.dither, default true):
  # the fade only starts once the incoming layer's Canvas has actually
  # painted, and that gate is the one part of the surface a first-paint-only
  # run never touches.
  #
  # A left-to-right GRADIENT, not a second solid (2026-08-12): the dither
  # pass derives its palette from the image, so a solid source is proof of
  # flatness (that is what wp.png above is for) and can never be proof that
  # anything dithered. Generated portrait and rotated, so the ramp runs along
  # the axis a full-width sample crosses; the two ends are far enough apart in
  # luminance that the palette genuinely needs every entry it is allowed.
  wp2_path="$shot_dir/wp2.png"
  $convert_bin -size 1080x1920 gradient:'#3fb07a-#0b2d20' -rotate 90 "$wp2_path"
fi

# --theme-toggle's drive: the dark shot waits out shell startup (same 4s the
# other modes' first actions allow llvmpipe), each toggle then gets 2s for
# ThemeEngine's fallback theme.json write plus Theme.qml's FileView reload
# before the status dump and (first leg) the light shot. Combined with
# --wallpaper, the drive instead starts past the wallpaper spawn's own
# sleep-3 `wallpaper set` and the matugen run it triggers (the plain
# --wallpaper screenshot at sleep 8 already shows the recolor landed), each
# toggle gets 4s for a full matugen rerun instead of 2s for the fallback
# write, and the rendered theme.json is dumped at each step for the
# post-run non-Flexoki/round-trip assertions.
if $theme_toggle_mode; then
  theme_toggle_drive_script="$shot_dir/theme-toggle-drive.sh"
  nested_theme_json="$iso_home/.local/state/formalshell/theme.json"
  if $wallpaper_mode; then
    cat > "$theme_toggle_drive_script" <<EOF
#!/usr/bin/env bash
sleep 9
cat "$nested_theme_json" > "$theme_json_dump1_path" 2>&1
"$grim_bin" "$theme_dark_png"
"$qs_bin" ipc -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call theme status > "$theme_toggle_status_path" 2>&1
cat "$nested_theme_json" > "$theme_json_dump2_path" 2>&1
"$grim_bin" "$theme_light_png"
"$qs_bin" ipc -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 4
"$qs_bin" ipc -p "$shell_path" call theme status > "$theme_toggle_status2_path" 2>&1
cat "$nested_theme_json" > "$theme_json_dump3_path" 2>&1
EOF
  else
    cat > "$theme_toggle_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$grim_bin" "$theme_dark_png"
"$qs_bin" ipc -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call theme status > "$theme_toggle_status_path" 2>&1
"$grim_bin" "$theme_light_png"
"$qs_bin" ipc -p "$shell_path" call theme mode toggle > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call theme status > "$theme_toggle_status2_path" 2>&1
EOF
  fi
fi

# A short silent fixture track (M7 Task 1) rather than a committed binary
# asset — regenerated on every run so it never goes stale. The title/artist
# tags are what MediaService/MediaPanel must display verbatim, and what the
# post-run `media status` cross-check below compares against. screensaver_mode
# reuses this same track (via its own ss-media-play.sh below) purely to give
# MediaService.isPlaying a real value — it never checks the tags or the art.
#
# media_mode (and visualizer_mode, below) embeds a real cover image (M20
# Task 3): an imagemagick-generated PNG muxed in as a FLAC `PICTURE` block
# (`-disposition:v attached_pic`), so mpv's mpris.lua plugin has genuine
# embedded art to extract into `mpris:artUrl` — the same
# avformat_open_input + AV_DISPOSITION_ATTACHED_PIC path a real tagged
# audio file exercises, not a synthetic MediaService override. Without
# this, MediaPanel's DitherImage art slot never has anything to dither.
# Six saturated, distinct-hue stripes, not one flat color: the retro
# dither needs real color variety in the source to prove hue survives the
# posterize pass.
#
# MEDIA_NO_ART=1 mutes the embedded cover for a single run, reproducing the
# artless MPRIS export browsers publish (title/artist, no `mpris:artUrl`);
# MediaPanel must then collapse the art slot out of its row instead of
# reserving a blank square beside the title. --visualizer keeps its cover
# either way, since its own check is the dither.
media_art=true
if [ "${MEDIA_NO_ART:-}" = "1" ]; then media_art=false; fi

if $visualizer_mode || { $media_mode && $media_art; }; then
  media_art_path="$shot_dir/smoke-art.png"
  $convert_bin -size 64x64 "xc:#E03131" -size 64x64 "xc:#F08C00" -size 64x64 "xc:#FFD700" \
    -size 64x64 "xc:#2F9E44" -size 64x64 "xc:#1971C2" -size 64x64 "xc:#9C36B5" \
    +append -resize "64x64!" "$media_art_path"
fi

if $media_mode || $screensaver_mode; then
  media_track_path="$shot_dir/smoke-track.flac"
  media_track_title="FormalShell Smoke Track"
  media_track_artist="FormalShell Test Artist"
  if $media_mode && $media_art; then
    "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -i "$media_art_path" \
      -map 0:a -map 1:0 -t 20 \
      -metadata "title=$media_track_title" -metadata "artist=$media_track_artist" \
      -c:a flac -c:v png -disposition:v attached_pic -y "$media_track_path"
  else
    "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 20 \
      -metadata "title=$media_track_title" -metadata "artist=$media_track_artist" \
      -c:a flac -y "$media_track_path"
  fi
fi

if $media_mode; then
  # Deliberately long — comfortably past NowPlaying.qml's 220px maxWidth at
  # the shell's default 13px monospace body size — so the marquee's
  # overflow gate actually trips (M16 Task 11). Carries the same embedded
  # cover art as the base track (M20 Task 3) — this is the track actually
  # playing by the time the run's generic smoke.png is captured, so it's
  # the one that has to have art for that screenshot to exercise the
  # dither at all.
  media_track_long_path="$shot_dir/smoke-track-long.flac"
  media_track_title_long="FormalShell Marquee Autoscroll Verification Overflow Track"
  if $media_art; then
    "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -i "$media_art_path" \
      -map 0:a -map 1:0 -t 20 \
      -metadata "title=$media_track_title_long" -metadata "artist=$media_track_artist" \
      -c:a flac -c:v png -disposition:v attached_pic -y "$media_track_long_path"
  else
    "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 20 \
      -metadata "title=$media_track_title_long" -metadata "artist=$media_track_artist" \
      -c:a flac -y "$media_track_long_path"
  fi
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

  # M16 Task 11's marquee proof, one script (same rationale as
  # nightlight-drive.sh: everything here is strictly ordered). The short
  # title from media_play_script above is already playing by sleep 7
  # (established well before this run's own sleep-5/6 panel-open/status
  # steps); screenshot it first as the "no marquee" baseline, then kill and
  # respawn on the long-title track (overwriting media_pid_path, so the
  # generic media_kill_script above still targets the live process), poll
  # `media status` for the retitle to land, then wait past the marquee's
  # hold plus well into its scroll before the second screenshot.
  media_marquee_script="$shot_dir/media-marquee.sh"
  cat > "$media_marquee_script" <<EOF
#!/usr/bin/env bash
sleep 7
niri msg action screenshot-screen --path "$media_marquee_static_path"
if [ -f "$media_pid_path" ]; then
  kill "\$(cat "$media_pid_path")" 2>/dev/null || true
fi
sleep 1
"$mpv_bin" --no-video --really-quiet "$media_track_long_path" &
echo \$! > "$media_pid_path"
SECONDS=0
while [ "\$SECONDS" -lt 8 ]; do
  "$qs_bin" ipc -p "$shell_path" call media status > "$media_status_long_path" 2>&1
  grep -qF "\"title\":\"$media_track_title_long\"" "$media_status_long_path" && break
  sleep 1
done
sleep 5
niri msg action screenshot-screen --path "$media_marquee_scroll_path"
EOF
fi

# --visualizer needs a genuinely non-silent fixture — --media's own
# smoke-track.flac above is silent by design (nothing for MediaPanel's own
# assertions to hear), which would leave cava with no real signal and the
# widget stuck on its baseline row the whole run. A fixed-frequency sine
# tone is simple, deterministic, and gives cava's FFT real energy to bin.
# Carries the same cover art as media_mode's track so the NowPlaying mini
# cover in the same frame renders its real dithered art next to the bars,
# not the no-art fallback.
if $visualizer_mode; then
  visualizer_track_path="$shot_dir/smoke-tone.flac"
  visualizer_track_title="FormalShell Visualizer Smoke Tone"
  visualizer_track_artist="FormalShell Test Artist"
  "$ffmpeg_bin" -nostdin -loglevel error -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=20" -i "$media_art_path" \
    -map 0:a -map 1:0 -ac 2 -t 20 \
    -metadata "title=$visualizer_track_title" -metadata "artist=$visualizer_track_artist" \
    -c:a flac -c:v png -disposition:v attached_pic -y "$visualizer_track_path"

  # One ordered script (media-marquee.sh's own idiom): start mpv in the
  # background (not exec'd — this script keeps running after it to poll
  # and eventually kill it, unlike media-play.sh's single long-lived
  # exec), poll for the shared cava process to actually appear (its own
  # bootstrap chain — mkdir, config write, PATH probe — plus
  # MediaService.isPlaying flipping true all have to land first), screenshot
  # once it's had a couple seconds of real signal to settle past the
  # all-baseline row, then kill mpv and poll for cava to disappear —
  # DESIGN.md §4 rule 8's hard gate, proven from outside the process
  # rather than inferred.
  visualizer_drive_script="$shot_dir/visualizer-drive.sh"
  cat > "$visualizer_drive_script" <<EOF
#!/usr/bin/env bash
sleep 2
"$mpv_bin" --no-video --really-quiet "$visualizer_track_path" &
mpv_pid=\$!
echo "\$mpv_pid" > "$visualizer_pid_path"
SECONDS=0
while [ "\$SECONDS" -lt 10 ]; do
  pgrep -f -- "cava -p" > "$visualizer_pgrep_playing_path" 2>&1 || true
  [ -s "$visualizer_pgrep_playing_path" ] && break
  sleep 1
done
sleep 2
niri msg action screenshot-screen --path "$visualizer_playing_path"
kill "\$mpv_pid" 2>/dev/null || true
wait "\$mpv_pid" 2>/dev/null || true
SECONDS=0
: > "$visualizer_pgrep_after_path"
while [ "\$SECONDS" -lt 6 ]; do
  pgrep -f -- "cava -p" > "$visualizer_pgrep_after_path" 2>&1 || true
  [ ! -s "$visualizer_pgrep_after_path" ] && break
  sleep 1
done
EOF

  # Safety net only — visualizer-drive.sh above already kills mpv well
  # before the run ends; same "harmless if already dead" shape as
  # media-kill.sh.
  visualizer_kill_script="$shot_dir/visualizer-kill.sh"
  cat > "$visualizer_kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$visualizer_pid_path" ]; then
  kill "\$(cat "$visualizer_pid_path")" 2>/dev/null || true
fi
EOF
fi

if $active_window_fixture_mode; then
  # Same script-file + exec-then-record-PID idiom as media_play_script
  # above: foot's own PID (not a wrapper shell's) lands in the pid file,
  # so active-window-kill.sh can close exactly this window before niri
  # quits rather than leaving it to outlive the run.
  active_window_play_script="$shot_dir/active-window-play.sh"
  cat > "$active_window_play_script" <<EOF
#!/usr/bin/env bash
sleep 2
echo \$\$ > "$active_window_pid_path"
exec "$foot_bin" --app-id=formalshell-smoke-iconic --title="formalshell smoke session" sleep 300
EOF

  active_window_kill_script="$shot_dir/active-window-kill.sh"
  cat > "$active_window_kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$active_window_pid_path" ]; then
  kill "\$(cat "$active_window_pid_path")" 2>/dev/null || true
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
# Drives the clipssh route the way a user does, over `menu activate` (the
# rig's stand-in for Enter, same division PickerIpc.choose draws): summon the
# route, activate the row that succeeds, then the row that fails. The two
# transfers are deliberately sequential rather than overlapping — the service
# refuses a second transfer while one is in flight, so an overlap would be
# testing the refusal rather than the failure path.
if $clipssh_mode; then
  clipssh_drive_script="$shot_dir/clipssh-drive.sh"
  cat > "$clipssh_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call menu summon clipssh
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu activate 0
sleep 12
"$qs_bin" ipc -p "$shell_path" call menu summon clipssh
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu activate 1
EOF
  chmod +x "$clipssh_drive_script"
fi

if $menu_mode; then
  menu_open_script="$shot_dir/menu-open.sh"
  cat > "$menu_open_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call menu summon ""
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
"$qs_bin" ipc -p "$shell_path" call menu select "Pick" ' ["a","b","c"]' tok1 > /dev/null 2>&1
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
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
cat "$iso_home/.local/state/formalshell/menu-selection.txt" > "$selection_path" 2>&1
{
  "$qs_bin" ipc -p "$shell_path" call menu toggle
  "$qs_bin" ipc -p "$shell_path" call menu status
  "$qs_bin" ipc -p "$shell_path" call menu toggle
  "$qs_bin" ipc -p "$shell_path" call menu status
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
  "$qs_bin" ipc -p "$shell_path" call menu summon emoji
  "$qs_bin" ipc -p "$shell_path" call menu activate 0
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
"$qs_bin" ipc -p "$shell_path" call menu summon apps > /dev/null 2>&1
sleep 2
"$grim_bin" "$menu_apps_png" 2>/dev/null || true
"$qs_bin" ipc -p "$shell_path" call debug query "test app" > "$apps_query_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
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
  "$qs_bin" ipc -p "$shell_path" call menu summon ':nix hello'
  sleep 2
  "$qs_bin" ipc -p "$shell_path" call menu activate 0
} > "$nix_run_drive_path" 2>&1
sleep 1
"$grim_bin" "$nix_toast_png" 2>/dev/null || true
"$qs_bin" ipc -p "$shell_path" call notifications status > "$nix_toast_status_path" 2>&1
EOF

  # Card-top freeze and release (M16 Task 2, M23), the final leg: from the
  # closed state the nix/toast leg above leaves behind, summon root fresh
  # (the ~12 top-level rows, unfiltered) and grim its resting top edge, then
  # wtype real keystrokes — not another IPC `menu select`/`activate`, this
  # is specifically proving the real TextInput.onTextChanged path — spelling
  # "wall", the same deterministic single-row-match query the debug-query
  # leg above already relies on (wall_query_path), so the row count is known
  # to drop from ~12 to 1. The second grim is the pair Menu.qml's top-freeze
  # is asserted against: the card's top edge must read identical pixel
  # position in both PNGs even though the card is visibly shorter in the
  # second one.
  #
  # Then a real Return activates that single WALLPAPER match, descending
  # into the picker grid, and a third grim proves the other half (M23,
  # owner: "a long list moves it up, then it never goes back to center"):
  # a level change is a resting row set, the freeze releases, and the card
  # re-centers for the new level's own height.
  #
  # The level change is what makes this discriminating, and the obvious
  # alternative does not. Backspacing the query away instead lands back on
  # the SAME twelve rows the card was centred for when the freeze was
  # captured — so a freeze that correctly released and one that latched for
  # the whole session both put the card on the identical pixel, and the
  # assertion would pass against the bug it exists to catch. Hence the
  # centred-ness checks below rather than a bare top-edge comparison: the
  # card must be genuinely centred for whatever it is now showing, which a
  # latched freeze cannot be once the row count has moved.
  cat >> "$menu_finish_script" <<EOF
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 2
"$grim_bin" "$menu_top_before_png" 2>/dev/null || true
"$wtype_bin" "wall"
sleep 1
"$grim_bin" "$menu_top_after_png" 2>/dev/null || true
"$wtype_bin" -k Return
sleep 1
"$grim_bin" "$menu_top_relevel_png" 2>/dev/null || true
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
# Literal last action: releases share_drive_script's own wait gate (see
# its own comment) when --share runs alongside --menu.
touch "$menu_done_path"
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
"$qs_bin" ipc -p "$shell_path" call debug query ':nix slowblock' > "$nix_searching_arm_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query ':nix slowblock' > "$nix_searching_path" 2>&1
touch "$nix_gate_path"
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query ':nix slowblock' > "$nix_released_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query ':nix failplease' > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query ':nix failplease' > "$nix_failed_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query ':nix emptyplease' > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call debug query ':nix emptyplease' > "$nix_empty_path" 2>&1
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

# --notify and --center both need this once (M15 Task 2): a dense,
# Chromium-app-name notification whose body carries the exact "GH notifs are
# ugly" shape sanitizeBody exists to fix — a leading <a href>github.com</a>
# link prefix glued onto a long PR-title line, followed by six more lines of
# body. Fired early (well before notify_mode's own DND flip at sleep 6) so
# it is still a live popup for --notify's dnd-indicator screenshot (sleep 7)
# and has long since expired into pending by --center's sleep-15 summon
# screenshot. A real bash script, not another `sh -c` KDL string, since the
# body needs its own literal double quotes and newlines.
if $notify_mode || $center_mode; then
  chromium_notify_script="$shot_dir/chromium-notify.sh"
  cat > "$chromium_notify_script" <<EOF
#!/usr/bin/env bash
sleep 2
"$notify_send_bin" -a "Google Chrome" -u normal "GitHub" '<a href="https://github.com/formalshell/formalshell/pull/142">github.com</a> New comment on pull request #142: "Rewrite the notification pipeline for omarchy card density"
Second line of the review comment, already past the two-line summary clamp on its own.
Third line keeps going to prove the three-line body clamp actually holds.
Fourth line continues describing the same review thread in more detail.
Fifth line, still going, well past what any card should ever show.
Sixth line is the last one before this fixture stops adding more.'
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
# ClipboardService's wl-paste watcher can take several seconds to come
# online in a fresh session (observed 5-7s on the mac VM rig, 2026-08-07,
# twice losing the first two fixture copies outright under the old fixed
# "sleep 2" head start). Poll a warmup copy into the ledger until capture
# provably works, then clear it so the real fixture sequence still starts
# from the same empty state the count assertions below expect.
for _ in \$(seq 1 10); do
  "$wl_copy_bin" "clipboard smoke warmup"
  sleep 1
  if "$qs_bin" ipc -p "$shell_path" call clipboard list 2>/dev/null | grep -qF warmup; then
    break
  fi
done
"$qs_bin" ipc -p "$shell_path" call clipboard clear > /dev/null 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke one"
sleep 1
"$wl_copy_bin" "clipboard smoke two"
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list1_path" 2>&1
sleep 1
"$wl_copy_bin" "clipboard smoke three"
sleep 1
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list2_path" 2>&1
sleep 1
copy_id=\$(grep -o '"id":"[^"]*"' "$clip_list2_path" | sed -n '2p' | cut -d'"' -f4)
"$qs_bin" ipc -p "$shell_path" call clipboard copy "\$copy_id" > "$clip_copy_path" 2>&1
sleep 1
"$wl_paste_bin" --no-newline > "$clip_paste_path" 2>&1
sleep 1
"$wl_copy_bin" --type image/png < "$clip_image_fixture_path"
sleep 2
"$qs_bin" ipc -p "$shell_path" call clipboard list > "$clip_list3_path" 2>&1
sleep 1
image_id=\$(grep -o '"id":"[^"]*","kind":"image"' "$clip_list3_path" | head -n1 | cut -d'"' -f4)
"$qs_bin" ipc -p "$shell_path" call clipboard copy "\$image_id" > "$clip_image_copy_path" 2>&1
sleep 1
"$wl_paste_bin" --type image/png --no-newline | sha256sum > "$clip_image_paste_sha_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call menu summon clipboard > /dev/null 2>&1
EOF
fi

# --share's whole sequence lives in one script, same rationale as
# clipboard_drive_script above. Phase one proves the working path against
# the session's real PATH (localsend_app genuinely installed, M17 Task 1's
# nix/testvm.nix addition); phase two reuses --instance mode's own proven
# takeover protocol to hand off to a second instance whose PATH is scoped
# to share_noshare_dir (built above), so its own `when` check genuinely
# cannot find localsend_app — not a second nested niri session, just a
# second formalshell process under the same one.
#
# Combined with --menu (M17 Task 3's own regression check), this script's
# "menu summon share" / "menu activate 0" calls would otherwise race
# --menu's script for the same shared menu surface — observed for real:
# --menu's own pending select() (armed at its sleep 6) was still open when
# share's "menu activate 0" landed, so it picked select-list index 0
# ("a") instead of the SHARE.CLIPBOARD row, leaving menu-selection.txt
# with a real {token,value} pick instead of the close-to-cancel
# {"cancelled":true} --menu's own assertion expects. share_menu_wait below
# makes this script wait for menu_finish_script's own completion marker
# (touched as its literal last action) before touching the menu route at
# all, so the two scripts' menu interactions never overlap.
share_menu_wait=""
if $menu_mode; then
  share_menu_wait="until [ -f \"$menu_done_path\" ]; do sleep 0.5; done"
fi
if $share_mode; then
  share_drive_script="$shot_dir/share-drive.sh"
  cat > "$share_drive_script" <<EOF
#!/usr/bin/env bash
$share_menu_wait
sleep 2
"$wl_copy_bin" "share smoke fixture"
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_query1_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon share > /dev/null 2>&1
sleep 1
niri msg action screenshot-screen --path "$share_menu_path"
# niri's own screenshot action puts the image on the Wayland clipboard too
# (write-to-disk is additive, not exclusive — confirmed via
# \`niri msg action screenshot-screen --help\`), which ClipboardService's
# live watcher captures as a new newest entry, superseding the fixture text
# just copied above. A single re-copy isn't enough on its own: capturing an
# image entry (read the clipboard, hash the bytes, write the content-
# addressed file) is slower than capturing text, so a re-copy issued right
# after the screenshot can still get overtaken by the screenshot's own
# still-in-flight image capture finishing later. Re-copy and poll
# \`clipboard list\` until its own newest entry is genuinely text again
# before activating, rather than gambling on a fixed sleep.
for _i in 1 2 3 4 5 6; do
  "$wl_copy_bin" "share smoke fixture"
  sleep 1
  clip_kind=\$("$qs_bin" ipc -p "$shell_path" call clipboard list 2>/dev/null | grep -o '"kind":"[^"]*"' | head -n1 | cut -d'"' -f4)
  [ "\$clip_kind" = "text" ] && break
done
"$qs_bin" ipc -p "$shell_path" call menu activate 0 > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 6 ]; do
  pgrep -f -- "localsend_app" > "$share_pgrep_path" 2>&1 || true
  [ -s "$share_pgrep_path" ] && break
  sleep 1
done
share_pid=\$(head -n1 "$share_pgrep_path")
if [ -n "\$share_pid" ]; then
  tr '\\0' '\\n' < /proc/\$share_pid/cmdline > "$share_cmdline_path" 2>&1
  share_tmp_arg=\$(tail -n1 "$share_cmdline_path")
  [ -f "\$share_tmp_arg" ] && cat "\$share_tmp_arg" > "$share_tmpfile_path" 2>&1
  kill "\$share_pid" 2>/dev/null || true
fi
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
sleep 1
# Same argv[1]=="-p" idiom instance_drive_script's own find_daemon_pids
# uses to tell the real daemon apart from this script's own "qs ipc ...
# call" clients.
find_daemon_pids() {
  for pid in \$(pgrep -f -- "-p $shell_path"); do
    if [ "\$(tr '\\0' '\\n' < /proc/\$pid/cmdline 2>/dev/null | sed -n '2p')" = "-p" ]; then
      echo "\$pid"
    fi
  done
}
old_pid=\$(find_daemon_pids | head -n1)
PATH="$share_noshare_dir" "$PWD/result/bin/formalshell" > "$share_second_log_path" 2>&1 &
new_pid=\$!
waited=0
count=0
while [ "\$waited" -lt 15000 ]; do
  sleep 0.5
  waited=\$((waited + 500))
  count=\$(find_daemon_pids | wc -l | tr -d ' ')
  if [ "\$count" = "1" ]; then
    break
  fi
done
survivor=\$(find_daemon_pids | head -n1)
printf '{"oldPid":%s,"newPid":%s,"survivorPid":%s,"waitedMs":%s,"finalCount":%s}\n' \
  "\${old_pid:-null}" "\${new_pid:-null}" "\${survivor:-null}" "\$waited" "\${count:-0}" \
  > "$share_instance_status_path"
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_absent_query1_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query "share" > "$share_absent_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon "" > /dev/null 2>&1
sleep 1
niri msg action screenshot-screen --path "$share_menu_absent_path"
"$qs_bin" ipc -p "$shell_path" call menu close > /dev/null 2>&1
EOF
fi

# --nightlight's whole sequence lives in one script, same rationale as
# clipboard_drive_script above. The poll loop breaks early on either
# outcome the plan calls real evidence: active:true, or a populated
# lastError (the honest failure surface for a nested compositor backend
# without wlr-gamma-control-unstable-v1) — the second grep fails (and so
# breaks the loop) the moment lastError stops being the empty-string
# literal.
# --hotcorner asks the compositor itself what layer surfaces exist, which is
# the only honest headless proof available for this feature: the rig has no
# synthetic pointer (same limitation the tray's overflow cell and the bell's
# own click hit), so entering a corner cannot be simulated, but whether the
# corner surfaces really mapped — at the configured corners, on the right
# layer, sized as asked — is entirely observable. That is also the part most
# likely to be silently wrong, since PanelWindow.anchors is driven per-corner
# from a resolved config here rather than from the literal edges every other
# surface in this shell uses.
if $hotcorner_mode; then
  hotcorner_drive_script="$shot_dir/hotcorner-drive.sh"
  cat > "$hotcorner_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
niri msg -j layers > "$hotcorner_layers_path" 2>&1
EOF
fi

if $nightlight_mode; then
  nightlight_drive_script="$shot_dir/nightlight-drive.sh"
  cat > "$nightlight_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call nightlight enable > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 8 ]; do
  "$qs_bin" ipc -p "$shell_path" call nightlight status > "$nightlight_status1_path" 2>&1
  grep -qF '"active":true' "$nightlight_status1_path" && break
  grep -qF '"lastError":""' "$nightlight_status1_path" || break
  sleep 1
done
niri msg action screenshot-screen --path "$nightlight_active_path"
"$qs_bin" ipc -p "$shell_path" call nightlight disable > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call nightlight status > "$nightlight_status2_path" 2>&1
EOF
fi

# --speedtest's whole sequence lives in one script, same rationale as
# nightlight-drive.sh above. The panel opens first so the run's own
# screenshot at the end shows the SPEED TEST section; the two bounded 5s
# phases (resolving/curl-check are near-instant local checks) settle
# `phase` to "done" deterministically regardless of real transfer speed;
# the poll ceiling below is a generous safety net, not the expected path.
if $speedtest_mode; then
  speedtest_drive_script="$shot_dir/speedtest-drive.sh"
  cat > "$speedtest_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call panel open network > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call network speedtest > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 25 ]; do
  "$qs_bin" ipc -p "$shell_path" call network speedstatus > "$speedtest_status_path" 2>&1
  grep -qF '"phase":"done"' "$speedtest_status_path" && break
  sleep 1
done
niri msg action screenshot-screen --path "$speedtest_panel_path"
EOF
fi

# --wifi's whole sequence lives in one script, same rationale as
# clipboard_drive_script: everything here is strictly ordered (open the
# panel so the scanner turns on, wait for a real scan to surface both
# fixture SSIDs, wrong-password round trip, real-password round trip,
# forget, enterprise round trip) with nothing needing to interleave with a
# niri-side sleep. Each `network status` poll writes over its own path, so
# whatever the loop last saw is exactly what the post-run assertions below
# read back — never a stale earlier snapshot passing by accident.
if $wifi_mode; then
  wifi_drive_script="$shot_dir/wifi-drive.sh"
  cat > "$wifi_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3

# Self-heal before anything else (part 1): wpa_supplicant's own internal
# scan-request queue can wedge across runs independently of anything
# NetworkManager persists. Reproduced directly: a clean run's journal showed
# wpa_supplicant repeating "wlan0: Reject scan trigger since one is already
# pending" forever, and NetworkManager logging "Activation: association took
# too long, failing activation" with zero SME authenticate attempts ever
# reaching the radio — the scan-wait loop below then times out with
# FORMALTEST/FORMALTEST-EAP never surfacing. \`systemctl restart\` of
# wpa_supplicant's per-interface unit is exactly the fix that unwedged it by
# hand; NetworkManager reconnects to the fresh supplicant instance over
# D-Bus on its own (no NM restart needed). Cheap and idempotent, so it runs
# unconditionally rather than gating it behind a slower, flakier "is the scan
# stuck" check from the outside.
sudo systemctl restart wpa_supplicant-wlan0.service
sleep 2

"$qs_bin" ipc -p "$shell_path" call panel open network > /dev/null 2>&1

# Self-heal before anything else (part 2): NetworkManager's system-connections dir
# survives across runs (it's not part of the isolated per-run HOME), so a
# prior --wifi run that never reached its own closing forget (interrupted
# mid-leg, or a run from before that forget existed) can leave
# FORMALTEST-EAP's nmcli profile still parked on wlan0 with autoconnect=yes,
# so NetworkManager reassociates to it before this shell instance even
# starts, and the station then never rescans up FORMALTEST at all.
# Reproduced: exactly this state made the scan-wait loop below time out.
# Forget whichever fixture SSID this run's own status already shows as
# known (an SSID this VM hasn't associated with yet returns "unknown ssid"
# from the IPC: harmless, no action gets armed) and wait for it to settle
# before the scripted sequence below drives a real action.
for ssid in FORMALTEST FORMALTEST-EAP; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_reset_status_path" 2>&1
  if grep -qF "\"name\":\"\$ssid\",\"known\":true" "$wifi_reset_status_path"; then
    "$qs_bin" ipc -p "$shell_path" call network forget "\$ssid" > /dev/null 2>&1
    SECONDS=0
    while [ "\$SECONDS" -lt 15 ]; do
      "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_reset_status_path" 2>&1
      if grep -qE "\"name\":\"\$ssid\",\"known\":false,\"connected\":false,\"stateChanging\":false" "$wifi_reset_status_path"; then
        break
      fi
      sleep 1
    done
  fi
done

SECONDS=0
while [ "\$SECONDS" -lt 25 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_scan_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST"' "$wifi_scan_status_path" && grep -qF '"name":"FORMALTEST-EAP"' "$wifi_scan_status_path"; then
    break
  fi
  sleep 1
done

"$qs_bin" ipc -p "$shell_path" call network connect FORMALTEST wrong-formaltest-psk > /dev/null 2>&1
# connect() replies as soon as the IPC call returns, well before NM's own
# ActiveConnection object exists — polling for the settled state right away
# would see the identical pre-attempt idle snapshot (connected:false,
# stateChanging:false) and declare victory before anything happened.
# Confirmed by reproducing it: the very first --wifi run's wifi-wrong.png
# showed blank unconnected rows, and the wpa_supplicant journal for that run
# placed the real SME authenticate attempt AFTER the screenshot timestamp.
# Waiting for stateChanging:true first proves NM actually started.
SECONDS=0
while [ "\$SECONDS" -lt 10 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_wrong_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":(true|false),"connected":(true|false),"stateChanging":true' "$wifi_wrong_status_path"; then
    break
  fi
  sleep 1
done
SECONDS=0
while [ "\$SECONDS" -lt 45 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_wrong_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":(true|false),"connected":false,"stateChanging":false' "$wifi_wrong_status_path"; then
    break
  fi
  sleep 1
done
niri msg action screenshot-screen --path "$wifi_wrong_path"

"$qs_bin" ipc -p "$shell_path" call network connect FORMALTEST formaltest-psk > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 25 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_connected_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST","known":true,"connected":true' "$wifi_connected_status_path"; then
    break
  fi
  sleep 1
done
niri msg action screenshot-screen --path "$wifi_connected_path"

"$qs_bin" ipc -p "$shell_path" call network forget FORMALTEST > /dev/null 2>&1
# known:false alone isn't enough to move on: NetworkPanel.qml's own
# _actionKind only clears once BOTH !known and !stateChanging (its
# _checkActionCompletion), and NetworkIpc.qml's connect/connectEap now
# refuse to run while an action is still in flight (an honest error instead
# of the silent no-op that used to swallow them). Stopping this poll on
# known:false alone can hand control back to this script while the forget
# is still mid-settle, and the connectEap call below would then get
# rejected outright. Reproduced: exactly this race is what left a stray
# unsubmitted password prompt open over a stale autoconnected profile in
# wifi-eap-connected.png.
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_forget_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST","known":false,"connected":false,"stateChanging":false' "$wifi_forget_status_path"; then
    break
  fi
  sleep 1
done

"$qs_bin" ipc -p "$shell_path" call network connectEap FORMALTEST-EAP formaltest formaltest-eap-pw > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 35 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_eap_status_path" 2>&1
  if grep -qF '"name":"FORMALTEST-EAP","known":true,"connected":true' "$wifi_eap_status_path"; then
    break
  fi
  sleep 1
done
niri msg action screenshot-screen --path "$wifi_eap_connected_path"

# Forget FORMALTEST-EAP too, symmetric with the FORMALTEST forget above:
# leaving this out is exactly how a prior run corrupted the VM's persistent
# NetworkManager state and broke every scan afterward (see the self-heal
# block at the top of this script).
"$qs_bin" ipc -p "$shell_path" call network forget FORMALTEST-EAP > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call network status > "$wifi_eap_forget_status_path" 2>&1
  if grep -qE '"name":"FORMALTEST-EAP","known":false,"connected":false,"stateChanging":false' "$wifi_eap_forget_status_path"; then
    break
  fi
  sleep 1
done
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
"$qs_bin" ipc -p "$shell_path" call panel open calendar
sleep 2
"$qs_bin" ipc -p "$shell_path" call calendar select "\$(date -d tomorrow +%F)" > "$calendar_select_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call calendar status > "$calendar_status_path" 2>&1
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
"$qs_bin" ipc -p "$shell_path" call lock lock > /dev/null 2>&1
echo \$? > "$lock_call_rc_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked1_path" 2>&1
sleep 3
"$grim_bin" "$lock_locked_path"
sleep 2
"$wtype_bin" "wrong-password"
# Mid-typing state, before Return: the masked dot run with NO text cursor
# (AuthPrompt suppresses cursorVisible entirely while masked — a password
# field is dots alone, so a bar in this shot is a regression).
sleep 1
"$grim_bin" "$lock_typing_path"
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
"$qs_bin" ipc -p "$shell_path" call lock isLocked > "$lock_islocked2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call lock status > "$lock_status_path" 2>&1
EOF
fi

# --polkit: pkexec has to run backgrounded within this same script (`&` +
# a trailing `wait`) rather than as its own separate spawn-at-startup
# entry — the script needs to keep issuing wtype input into the dialog
# while pkexec itself sits blocked on the conversation, then capture its
# real exit code once the conversation resolves.
if $polkit_mode; then
  polkit_drive_script="$shot_dir/polkit-drive.sh"
  polkit_debug_path="$shot_dir/polkit-debug.log"
  cat > "$polkit_drive_script" <<EOF
#!/usr/bin/env bash
: > "$polkit_debug_path"
log() { echo "\$(date +%s.%N) \$1" >> "$polkit_debug_path"; }
log start
sleep 3
"$pkexec_bin" "$true_bin" 2> "$shot_dir/polkit-stderr.txt" &
polkit_pid=\$!
log "pkexec launched pid=\$polkit_pid"
sleep 3
"$grim_bin" "$polkit_active_path"
log active-screenshot
sleep 1
"$wtype_bin" "wrong-password"
"$wtype_bin" -k Return
log wrong-password-typed
# polkit's own PAM round trip is socket-activated
# (polkit-agent-helper@.service) rather than an in-process PamContext like
# --lock's, so the first conversation can genuinely be slower to fail than
# --lock's own 5s buffer accounts for — 10s here, verified generous against
# real timestamps in polkit-debug.log rather than guessed twice.
sleep 10
"$grim_bin" "$polkit_error_path"
log error-screenshot
sleep 1
"$wtype_bin" "formalshell-test"
"$wtype_bin" -k Return
log real-password-typed
sleep 3
wait \$polkit_pid
polkit_rc=\$?
log "pkexec exited rc=\$polkit_rc"
echo \$polkit_rc > "$polkit_rc_path"
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
  # frameInfo lands well inside cycle 0 (ttfx's shortest effect is a couple
  # of seconds of animation, plus the 2s hold), then a read-only poll waits
  # for the reroll. The 75s SECONDS deadline covers the worst first pick —
  # matrix spends a fixed 15s on its rain before it even starts resolving,
  # thunderstorm 12s, after a manual start ~15-17s into the script — and a
  # poll that never sees cycles leave 0 just runs out and fails the
  # post-run assertion honestly.
  ss_drive_script="$shot_dir/ss-drive.sh"
  cat > "$ss_drive_script" <<EOF
#!/usr/bin/env bash
sleep 8
"$qs_bin" ipc -p "$shell_path" call screensaver status > "$ss_guard_status_path" 2>&1
if [ -f "$ss_pid_path" ]; then
  kill "\$(cat "$ss_pid_path")" 2>/dev/null || true
fi
sleep 5
niri msg action screenshot-screen --path "$ss_auto_path"
"$qs_bin" ipc -p "$shell_path" call screensaver status > "$ss_auto_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screensaver stop > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call screensaver status > "$ss_dismiss_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screensaver start > /dev/null 2>&1
sleep 1
niri msg action screenshot-screen --path "$ss_manual_path"
"$qs_bin" ipc -p "$shell_path" call screensaver frameInfo > "$ss_cycle_info1_path" 2>&1
while [ "\$SECONDS" -lt 75 ]; do
  "$qs_bin" ipc -p "$shell_path" call screensaver frameInfo > "$ss_cycle_info2_path" 2>&1
  grep -q '"cycles":0}' "$ss_cycle_info2_path" || break
  sleep 1
done
"$qs_bin" ipc -p "$shell_path" call screensaver stop > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call screensaver status > "$ss_final_status_path" 2>&1
EOF
fi

# --picker: summon opens the wallpaper-mode grid (cursor defaults to index 0,
# so the screenshot needs no keypress at all to show the cursor cell
# inverted). The Rss bracket (pre-open/open/post-close) closes over IPC
# without choosing anything, deliberately separate from the choose()/theme/
# select() round trip below it — choose() drives Core.State.setWallpaper(),
# which fires matugen's retheme and Background's crossfade (two more
# screen-sized decodes) well after the picker's own grid is gone, and a
# post-close sample taken after that would measure the retheme, not the
# picker (M16 Task 12 review finding, 2026-08-03). Once the bracket is
# closed, a fresh summon/choose picks a non-first fixture by path, over IPC
# — the same _choose() function Enter/click on a cell would call — proving
# both that a real selection sets the wallpaper (picker-theme-status.json,
# same `theme status` proof --wallpaper already uses) and, via a second
# select()/choose() round trip over an explicit token, that the generic
# image-selector's answer channel actually resolves.
if $picker_mode; then
  picker_drive_script="$shot_dir/picker-drive.sh"
  cat > "$picker_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
# M16 Task 12: identify the running shell daemon among every process whose
# cmdline mentions this run's own "-p \$shell_path" — nixpkgs' wrapProgram
# renames the real quickshell binary to ".quickshell-wrapped" (comm reads
# ".quickshell-wra", truncated — pgrep -x qs matches nothing), so matching
# has to go by cmdline. That substring alone still catches this run's own
# "qs ipc ... -p \$shell_path call ..." client processes (argv[1] "ipc")
# alongside the daemon (argv[1] "-p"), so the argv[1] check below is load-
# bearing, not belt-and-braces.
shell_pid=""
for pid in \$(pgrep -f -- "-p $shell_path"); do
  if [ "\$(tr '\\0' '\\n' < /proc/\$pid/cmdline 2>/dev/null | sed -n '2p')" = "-p" ]; then
    shell_pid="\$pid"
    break
  fi
done
_smaps() {
  if [ -n "\$shell_pid" ] && [ -r "/proc/\$shell_pid/smaps_rollup" ]; then
    rss=\$(awk '/^Rss:/ { print \$2 }' "/proc/\$shell_pid/smaps_rollup")
    pss=\$(awk '/^Pss:/ { print \$2 }' "/proc/\$shell_pid/smaps_rollup")
    printf '{"rssKb":%s,"pssKb":%s}' "\${rss:-null}" "\${pss:-null}"
  else
    printf 'null'
  fi
}
pre_open=\$(_smaps)
"$qs_bin" ipc -p "$shell_path" call picker summon > /dev/null 2>&1
sleep 2
niri msg action screenshot-screen --path "$picker_grid_path"
open_state=\$(_smaps)
# Close without choosing — isolates the menu's own _pickerImages free
# from setWallpaper()'s retheme/crossfade (see header comment above).
"$qs_bin" ipc -p "$shell_path" call picker close > /dev/null 2>&1
# 20s, not a couple: QML's V4 engine reclaims a destroyed Repeater's JS-side
# heap (delegate objects, property-binding closures) on its own idle-driven
# GC schedule, not synchronously on model-clear. Measured on this rig
# (2026-08-03): the Rss sat flat for the first 8s after close, then dropped
# ~37MB in the next 10s once a GC cycle actually ran. Sampling early doesn't
# show a leak — it shows a GC that hasn't fired yet.
sleep 20
post_close=\$(_smaps)
# Reopen for the real choose()/theme/select() round trip the assertions
# below need — deliberately outside the memory bracket above.
"$qs_bin" ipc -p "$shell_path" call picker summon > /dev/null 2>&1
sleep 1
# The flat listing, while it is open: no Dark/Light pair exists yet, so this
# is the no-variant path every existing setup takes.
"$qs_bin" ipc -p "$shell_path" call picker status > "$picker_flat_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call picker choose "$picker_dir/img-3.png" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call theme status > "$picker_theme_status_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call picker select "$picker_dir" tok-picker > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call picker choose "$picker_dir/img-1.png" > /dev/null 2>&1
sleep 1
cat "$iso_home/.local/state/formalshell/picker-selection.txt" > "$picker_selection_path" 2>&1
printf '{"shellPid":"%s","preOpenRss":%s,"openRss":%s,"postCloseRss":%s}\n' "\$shell_pid" "\$pre_open" "\$open_state" "\$post_close" > "$picker_mem_path"
# The Dark/Light legs. Moving the staged sets in while the shell is already
# running is deliberate: the route re-scans on every entry, so the next summon
# has to pick up a directory that changed under it — a scan cached at startup
# would still report the flat listing here and fail the assertions below.
mv "$picker_dir/.stage/Dark" "$picker_dir/Dark"
mv "$picker_dir/.stage/Light" "$picker_dir/Light"
"$qs_bin" ipc -p "$shell_path" call picker summon > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call picker status > "$picker_dark_status_path" 2>&1
# The switcher's own action over IPC — the DARK | LIGHT cells and Tab both
# drive this same function in a live session.
"$qs_bin" ipc -p "$shell_path" call picker variant light > "$picker_variant_reply_path" 2>&1
sleep 2
niri msg action screenshot-screen --path "$picker_variant_path"
"$qs_bin" ipc -p "$shell_path" call picker status > "$picker_light_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call picker close > /dev/null 2>&1
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
"$qs_bin" ipc -p "$shell_path" call screenshot region > "$screenshot_region_reply_path" 2>&1
sleep 1
pgrep -x slurp > "$screenshot_slurp_before_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screenshot status > "$screenshot_region_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screenshot cancel > "$screenshot_cancel_reply_path" 2>&1
sleep 1
pgrep -x slurp > "$screenshot_slurp_after_path" 2>&1 || true
"$qs_bin" ipc -p "$shell_path" call screenshot status > "$screenshot_cancelled_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screenshot full > "$screenshot_reply_path" 2>&1
for _ in \$(seq 1 20); do
  "$qs_bin" ipc -p "$shell_path" call screenshot status > "$screenshot_status_path" 2>&1
  if grep -q '"capturing":false' "$screenshot_status_path"; then
    break
  fi
  sleep 0.5
done
"$wl_paste_bin" --list-types > "$screenshot_types_path" 2>&1
EOF
fi

# --capture (M22 Task 8): drives the shell's own region picker, which is a
# real Overlay-layer surface with Exclusive keyboard focus, not slurp.
# Sequence: `pick smart` opens it over a session holding one real tiled foot
# window; the picker is screenshotted (capture-picker.png — frozen screen,
# scrim outside the selection, accent selection border, W×H readout, and the
# named-window card that only exists because a tiled niri window has no
# rectangle); `key tab` cycles the selection and a second status dump proves
# the cursor actually moved; a third dump right before `key return` records
# the exact rectangle about to be captured, so the resulting PNG's real pixel
# dimensions can be checked against it rather than merely existing. Finally
# `pick region` is opened and dismissed with `key escape` to prove the cancel
# path leaves no surface and no file behind.
#
# The toolbar (2026-08-12) adds a second half to the same leg: `key 4` selects
# the REC SCREEN cell, the picker is screenshotted in that state
# (capture-toolbar-record.png — the toolbar with a record tool lit, the
# selection border swapped to `urgent`), and Return commits it into a real
# wf-recorder child. That path shares nothing with `record start`: the picker
# resolves the rectangle and the output itself and hands both to
# RecordingService.startAt(). wf-recorder cannot actually capture in this rig
# (the dmabuf bind block --record already hits), so the assertions below take
# the strong form when it runs and the named-and-explained blocked form when
# it dies — never a quiet pass either way.
#
# `key` is the rig's stand-in for real key delivery into an Exclusive-focus
# layer surface, the same split every other surface's IPC actions already use
# (tray expand, picker choose, media transport). `key 4` in particular routes
# through the same setTool() a click on the toolbar cell calls, so driving it
# here is driving the toolbar, not a parallel path built for the rig.
if $capture_mode; then
  capture_drive_script="$shot_dir/capture-drive.sh"
  cat > "$capture_drive_script" <<EOF
#!/usr/bin/env bash
sleep 5
# The compositor's own view of the output, so the captured PNG's real pixel
# dimensions can be checked against it rather than merely existing.
niri msg -j outputs > "$capture_outputs_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screenshot pick smart default > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call screenshot pickerStatus > "$capture_open_status_path" 2>&1
niri msg action screenshot-screen --path "$capture_picker_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call screenshot key tab > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call screenshot pickerStatus > "$capture_cycled_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call screenshot key ctrl-return > "$capture_pick_reply_path" 2>&1
for _ in \$(seq 1 20); do
  "$qs_bin" ipc -p "$shell_path" call screenshot status > "$capture_status_path" 2>&1
  if grep -q '"capturing":false' "$capture_status_path"; then
    break
  fi
  sleep 0.5
done
# The toolbar's record half. \`key 4\` is exactly what a click on the REC
# SCREEN cell does (both route through setTool), so this drives the real
# toolbar rather than a parallel code path — the rig has no synthetic pointer,
# the same split \`key\` itself already stands in for. The screenshot lands
# with the picker in that state, so it carries the toolbar with a record tool
# lit and the selection border swapped to \`urgent\`.
#
# The wait is for a \`--record\` run in the same session: every drive script is
# spawned at startup, so the two would otherwise race for the one wf-recorder
# child and this leg would fail on "already recording" rather than on anything
# it is testing.
SECONDS=0
while [ "\$SECONDS" -lt 45 ]; do
  "$qs_bin" ipc -p "$shell_path" call record status 2>&1 | grep -qF '"active":false' && break
  sleep 1
done
"$qs_bin" ipc -p "$shell_path" call screenshot pick smart default > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call screenshot key 4 > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call screenshot pickerStatus > "$capture_tool_status_path" 2>&1
niri msg action screenshot-screen --path "$capture_toolbar_path"
"$qs_bin" ipc -p "$shell_path" call screenshot key return > "$capture_rec_reply_path" 2>&1
# Long enough that the container holds real frames rather than just a header.
sleep 6
"$qs_bin" ipc -p "$shell_path" call record status > "$capture_rec_status_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call record stop > /dev/null 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 20 ]; do
  "$qs_bin" ipc -p "$shell_path" call record status > "$capture_rec_stopped_path" 2>&1
  grep -qF '"active":false' "$capture_rec_stopped_path" && break
  sleep 1
done
"$qs_bin" ipc -p "$shell_path" call screenshot pick region default > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call screenshot key escape > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call screenshot pickerStatus > "$capture_escape_status_path" 2>&1
EOF
fi

# --record (M22): a real wf-recorder child, start to finished GIF. Nothing
# here is bounded by a flat sleep where a state can be polled instead: the
# stop leg waits for `active` to actually go false (SIGTERM asks
# wf-recorder to finalize the container, which takes as long as it takes),
# and the transcode leg waits for `lastGifPath` to land rather than for
# ffmpeg's two passes to fit in a guessed window.
#
# `record start` answers with the destination path synchronously, so the
# GIF leg converts THAT file by name rather than globbing a directory,
# the same file the status dumps are asserted against.
#
# The screenshot is taken while the recording is genuinely running, which
# is the only state Indicators.qml's recording cell exists in.
if $record_mode; then
  record_drive_script="$shot_dir/record-drive.sh"
  cat > "$record_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call record start screen desktop > "$record_start_reply_path" 2>&1
# Long enough that the container holds real frames rather than a header:
# the GIF transcode below has to have something to read.
sleep 4
"$qs_bin" ipc -p "$shell_path" call record status > "$record_status1_path" 2>&1
"$grim_bin" "$record_active_path"
sleep 2
"$qs_bin" ipc -p "$shell_path" call record stop > "$record_stop_reply_path" 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 15 ]; do
  "$qs_bin" ipc -p "$shell_path" call record status > "$record_status2_path" 2>&1
  grep -qF '"active":false' "$record_status2_path" && break
  sleep 1
done
# wf-recorder itself has already exited here, but RecordingService's own
# finalize pass (two ffprobes plus one ffmpeg encode) still owns the file;
# waiting for the flag it exposes for exactly this is what makes the
# ffprobe read below land on the settled, finalized file rather than a
# file mid-rewrite.
SECONDS=0
while [ "\$SECONDS" -lt 20 ]; do
  "$qs_bin" ipc -p "$shell_path" call record status > "$record_finalize_status_path" 2>&1
  grep -qF '"finalizing":false' "$record_finalize_status_path" && break
  sleep 1
done
rec_file=\$(head -n1 "$record_start_reply_path" | tr -d '\r')
"$ffprobe_bin" -v error -show_entries format=duration:stream=codec_type \
  -of default=noprint_wrappers=1 "\$rec_file" > "$record_ffprobe_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call record gif "\$rec_file" > "$record_gif_reply_path" 2>&1
SECONDS=0
while [ "\$SECONDS" -lt 40 ]; do
  "$qs_bin" ipc -p "$shell_path" call record status > "$record_status3_path" 2>&1
  if grep -qF '"transcoding":false' "$record_status3_path" && grep -qF '"lastGifPath":"/' "$record_status3_path"; then
    break
  fi
  # A populated lastError is a settled answer too, and waiting out the
  # ceiling for it would only delay the failure below.
  grep -qF '"lastError":""' "$record_status3_path" || break
  sleep 1
done
EOF
fi

# --ocr (M22): the `capture` target's two slurp-fronted verbs, driven as far
# as a nested session can honestly drive them.
#
# THE BOUNDARY, stated up front rather than discovered from a passing run:
# `capture text` and `capture color` both begin by blocking on a real slurp
# drag, and there is no IPC stand-in for that answer the way picker.choose,
# `screenshot key` and `tray expand` stand in for their own surfaces' input.
# Nor can slurp be replaced by a hermetic shim the way `nix`/`gh` are:
# nix/package.nix installs it with makeWrapper's `--prefix PATH`, so the
# bundled binary outranks anything this rig could put on the session's PATH
# (`wtype` is `--suffix` for exactly the opposite reason, and says so). The
# rig also has no synthetic pointer at all: every other leg's "the action,
# not the input method" split exists because of that. So the OCR text
# landing on the clipboard, and the picked pixel's hex landing next to it,
# stay host-trial: this leg proves everything up to the drag and says so on
# its own SMOKE_OCR_LIMIT line.
#
# What it does prove, with real state: a real foot window carrying known
# text on a known solid background is on screen; `capture text` starts a
# real slurp with the shell's own themed overlay and reports capturing:true
# in mode "text"; `capture color` starts slurp's single-point mode instead
# (its own argv, asserted through pgrep, since the two modes differ only in
# flags); each cancels clean; and the clipboard still holds the sentinel
# this script put there, so a cancelled capture is proven to have copied
# nothing rather than merely reported that it didn't.
if $ocr_mode; then
  # Same script-file + exec-then-record-PID idiom as active-window-play.sh:
  # foot's own PID (not a wrapper shell's) lands in the pid file, so the
  # kill step below closes exactly this window before niri quits.
  ocr_fixture_script="$shot_dir/ocr-fixture.sh"
  cat > "$ocr_fixture_script" <<EOF
#!/usr/bin/env bash
sleep 2
echo \$\$ > "$ocr_pid_path"
exec "$foot_bin" --app-id=formalshell-smoke-ocr --font=monospace:size=28 \\
  --override=colors.background=3fae2a --override=colors.foreground=101010 \\
  sh -c 'printf "FORMALSHELL OCR FIXTURE\\n"; sleep 300'
EOF

  ocr_kill_script="$shot_dir/ocr-kill.sh"
  cat > "$ocr_kill_script" <<EOF
#!/usr/bin/env bash
if [ -f "$ocr_pid_path" ]; then
  kill "\$(cat "$ocr_pid_path")" 2>/dev/null || true
fi
EOF

  ocr_drive_script="$shot_dir/ocr-drive.sh"
  cat > "$ocr_drive_script" <<EOF
#!/usr/bin/env bash
sleep 5
# The sentinel is what makes "the cancel copied nothing" an assertion
# rather than an absence: an empty clipboard would read the same whether
# the capture wrote nothing or wrote an empty string.
printf '%s' 'ocr smoke sentinel' | "$wl_copy_bin"
"$grim_bin" "$ocr_fixture_png"

"$qs_bin" ipc -p "$shell_path" call capture text > /dev/null 2>&1
sleep 2
pgrep -f -- 'slurp -d' > "$ocr_text_slurp_path" 2>&1 || true
"$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_text_status_path" 2>&1
"$grim_bin" "$ocr_text_overlay_png"
"$qs_bin" ipc -p "$shell_path" call capture cancel > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_text_cancel_path" 2>&1

"$qs_bin" ipc -p "$shell_path" call capture color > /dev/null 2>&1
sleep 2
pgrep -f -- 'slurp -p' > "$ocr_color_slurp_path" 2>&1 || true
"$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_color_status_path" 2>&1
"$grim_bin" "$ocr_color_overlay_png"
"$qs_bin" ipc -p "$shell_path" call capture cancel > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_color_cancel_path" 2>&1
pgrep -x slurp > "$ocr_slurp_after_path" 2>&1 || true
"$wl_paste_bin" --no-newline > "$ocr_clipboard_path" 2>&1 || true

# The selection-free variants, which is what makes the round trip provable
# here at all: everything above stops at "slurp is on screen" because the
# rig has no way to answer a real drag. textAt/colorAt run the identical
# pipeline from a geometry, so tesseract's output and the picked pixel do
# reach the clipboard and can be read straight back.
# The whole output, not a guessed box: the fixture's line is rendered at
# font size 28, so a narrow region clips it mid-string and tesseract returns
# fragments. Extra chrome in frame costs nothing, the assertion only needs
# the fixture's own words to appear.
"$qs_bin" ipc -p "$shell_path" call capture textAt '0,0 1276x693' > /dev/null 2>&1
for _ in \$(seq 1 30); do
  "$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_textat_status_path" 2>&1
  grep -qF '"capturing":false' "$ocr_textat_status_path" && break
  sleep 0.5
done
"$wl_paste_bin" --no-newline > "$ocr_textat_clipboard_path" 2>&1 || true

"$qs_bin" ipc -p "$shell_path" call capture colorAt '0,0 1x1' > /dev/null 2>&1
for _ in \$(seq 1 30); do
  "$qs_bin" ipc -p "$shell_path" call capture status > "$ocr_colorat_status_path" 2>&1
  grep -qF '"capturing":false' "$ocr_colorat_status_path" && break
  sleep 0.5
done
"$wl_paste_bin" --no-newline > "$ocr_colorat_clipboard_path" 2>&1 || true
EOF
fi

# --reminder (M22): one real countdown, set to fire inside the run. The
# duration is 12s rather than the 1s a hand-driven check would use, because
# the pending state has to survive long enough to be screenshotted, dumped
# and read back out of state.json; a 1s reminder fires before grim has
# painted its first frame on llvmpipe.
#
# DND goes on BEFORE the reminder is set: a fired reminder is authored at
# urgency 2 with NotificationService's own `local` marker, which is exactly
# the pair Notifications/model.js's bypassesDnd() lets through, so the toast
# landing in `popups` with dnd:true is the bypass proven rather than
# asserted from the source.
if $reminder_mode; then
  reminder_drive_script="$shot_dir/reminder-drive.sh"
  cat > "$reminder_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call notifications setDnd true > "$reminder_dnd_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call reminder set 12s "SMOKE REMINDER FIXTURE" > "$reminder_set_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call reminder status > "$reminder_status1_path" 2>&1
cat "$iso_home/.local/state/formalshell/state.json" > "$reminder_state1_path" 2>&1
"$grim_bin" "$reminder_pending_png"
# Past the deadline with room for the service's own 1s tick.
sleep 13
"$qs_bin" ipc -p "$shell_path" call reminder status > "$reminder_status2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call notifications status > "$reminder_notifications_path" 2>&1
cat "$iso_home/.local/state/formalshell/state.json" > "$reminder_state2_path" 2>&1
"$grim_bin" "$reminder_fired_png"
EOF
fi

# --toggles (M22): the menu's toggle hub, proven live rather than by
# screenshot alone. `debug query` carries each row's resolved `checked`
# (Menu.qml's query() maps it through toggles.js's checkedFor), so a row's
# checkmark is readable from outside the process, and `menu status` before
# and after must be byte-identical: the surface stays open at the same
# level across the toggle, which is what "no rebuild" means here: the row
# repainted from a @state: snapshot, nothing re-entered the level and no
# refresh() ran.
#
# Two toggles, and both are needed. `nightlight.toggle` is the one the plan
# names, but this VM's nested niri does not advertise
# wlr-gamma-control-unstable-v1 at all, so wlsunset exits on its own and
# NightLightService.active stays honestly false (the same deterministic
# branch --nightlight already documents). The assertion there is therefore
# the cross-check the row exists for: the checkmark must agree with
# `nightlight status` in both samples, which is what proves the row renders
# the service's real state instead of the fact that a toggle was asked for.
# The DND row's own @state: path has no external dependency at all, so it
# is what proves a checkmark actually flips inside an open menu.
if $toggles_mode; then
  toggles_drive_script="$shot_dir/toggles-drive.sh"
  cat > "$toggles_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call menu summon toggles > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu status > "$toggles_menu_status1_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call nightlight status > "$toggles_nl_status1_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query nightlight > "$toggles_nl_query1_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call notifications status > "$toggles_dnd_status1_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query dnd > "$toggles_dnd_query1_path" 2>&1
"$grim_bin" "$toggles_hub_png"

"$qs_bin" ipc -p "$shell_path" call nightlight toggle > /dev/null 2>&1
"$qs_bin" ipc -p "$shell_path" call notifications toggleDnd > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call nightlight status > "$toggles_nl_status2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query nightlight > "$toggles_nl_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call notifications status > "$toggles_dnd_status2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query dnd > "$toggles_dnd_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu status > "$toggles_menu_status2_path" 2>&1
"$grim_bin" "$toggles_toggled_png"
EOF
fi

# --keybinds (M22): the parsed-binds route over the config.kdl fixture
# written into the isolated XDG_CONFIG_HOME above. Two passes on the query,
# the same idiom the nix route uses: Menu.qml refreshes the FileView on
# every keybinds query and the read is async, so the first pass can land
# before the file has resolved.
#
# The rows are inert notes by construction (Compositor/keybinds.js: a bind
# acts on whatever has focus, and at Enter that is the menu), so there is no
# activation to drive; the assertion is that the fixture's own chords come
# back parsed, with their actions, and that the route is not sitting on one
# of its four honest end-state rows.
if $keybinds_mode; then
  keybinds_drive_script="$shot_dir/keybinds-drive.sh"
  cat > "$keybinds_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call debug query ":k" > /dev/null 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call debug query ":k" > "$keybinds_query1_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call debug query ":k Mod+T" > "$keybinds_query2_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call menu summon keybinds > /dev/null 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call menu status > "$keybinds_menu_status_path" 2>&1
"$grim_bin" "$keybinds_menu_png"
EOF
fi

# --mic (M22): the opt-in microphone cell, named in bar.layout above. THE
# HONEST NO MIC STATE IS THE PASSING RESULT HERE: this VM has a pipewire
# null sink and no capture device at all, so AudioService.sourceAvailable is
# genuinely false and MicWidget renders its one dim NO MIC label instead of
# a glyph, staying visible because the user opted in. A run that showed a
# muted-or-live glyph on this rig would mean the widget invented a device.
# The live/muted glyph states need real capture hardware and stay
# host-trial, the same split --nightlight and --panel tailscale already
# document.
#
# `debug dump` carries Core.Config.settings verbatim, which is the one
# place the layout the shell actually resolved is readable from outside the
# process: the screenshot proves what the cell rendered, the dump proves
# it was there because bar.layout asked for it.
if $mic_mode; then
  mic_drive_script="$shot_dir/mic-drive.sh"
  cat > "$mic_drive_script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call debug dump > "$dump_path" 2>&1
"$grim_bin" "$mic_bar_png"
EOF
fi

# --systemupdate (M22): the flake-inputs-behind panel against this repo's
# own flake (settings.json's systemUpdate.flakeDir above). The bar cell is
# named in bar.layout too, which is what flips the panel's pollEnabled, so
# the cell and the panel read the same real poll.
#
# The probes are real `git ls-remote`-class calls against real forges, so
# the settle wait is generous and every end state is a real answer: N
# BEHIND, ALL CURRENT, NO NETWORK (every probe that ran failed to reach its
# forge) or CHECKING (probes still in flight). Nothing here asserts a
# particular count: that would be asserting the state of github, not the
# state of this panel.
if $systemupdate_mode; then
  systemupdate_drive_script="$shot_dir/systemupdate-drive.sh"
  cat > "$systemupdate_drive_script" <<EOF
#!/usr/bin/env bash
sleep 4
"$qs_bin" ipc -p "$shell_path" call panel open systemupdate > "$systemupdate_open_reply_path" 2>&1
sleep 1
"$qs_bin" ipc -p "$shell_path" call panel state > "$systemupdate_state_path" 2>&1
sleep 20
"$grim_bin" "$systemupdate_panel_png"
"$qs_bin" ipc -p "$shell_path" call debug dump > "$dump_path" 2>&1
EOF
fi

# --plugins (M22): the drop-in plugin directory written above, read back
# through the `plugins` target. `list` is the resolved manifest record
# (what manifest.js made of the file on disk) and `status` is the load
# outcome: the one place a plugin's entry QML failing to load is visible
# from outside the process, since plugin QML lives outside the repo and
# qmllint never sees it.
if $plugins_mode; then
  plugins_drive_script="$shot_dir/plugins-drive.sh"
  cat > "$plugins_drive_script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call plugins list > "$plugins_list_path" 2>&1
"$qs_bin" ipc -p "$shell_path" call plugins status > "$plugins_status_path" 2>&1
"$grim_bin" "$plugins_bar_png"
EOF
fi

# --tray: launches six real SNI producers in the background (PIDs recorded
# for the kill step below), dumps `tray status` and screenshots the whole
# strip, then drives the same activate() the item cells' own left click calls
# and lets the stub's --activate-file prove the D-Bus round trip. Six
# fixtures against no visible limit at all is the point since M24: every one
# of them is its own cell, and nothing here collapses anything.
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
"$qs_bin" ipc -p "$shell_path" call tray status > "$tray_status_path" 2>&1
sleep 1
niri msg action screenshot-screen --path "$tray_strip_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call tray activate tray-fixture-2 > "$tray_activate_reply_path" 2>&1
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

# --chevron: the bar boots collapsed (State.barCollapsed's own default), so
# the first dump and shot need no setup at all beyond the settings.json
# fixture above. That IS the claim: adding `chevron` to bar.layout
# visibly does something on first run. `bar chevron expand` then stands in
# for a click on the cell, with no region argument, since a layout carrying
# exactly one chevron is meant to infer it. The reveal animates now (M25,
# Theme.motion.standard), so the shot after the expand is deliberately three
# seconds behind it: an order of magnitude past the animation, which is what
# makes the screenshot a picture of the end state rather than of a frame
# somewhere inside it.
if $chevron_mode; then
  chevron_drive_script="$shot_dir/chevron-drive.sh"
  cat > "$chevron_drive_script" <<EOF
#!/usr/bin/env bash
sleep 5
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_collapsed_path" 2>&1
sleep 1
"$grim_bin" "$chevron_collapsed_path"
sleep 1
"$qs_bin" ipc -p "$shell_path" call bar chevron expand > "$chevron_expand_reply_path" 2>&1
sleep 2
"$qs_bin" ipc -p "$shell_path" call bar chevron status > "$chevron_status_expanded_path" 2>&1
sleep 1
"$grim_bin" "$chevron_expanded_path"
EOF
fi

# --panel-keys (M26 Task 8): opens the audio panel and drives it with real
# `wtype` keystrokes rather than the `panel`/IPC-only shortcuts every other
# leg uses — this is the one thing that can actually prove row-level
# keyboard navigation reaches the surface, since the shared cursor state
# (Panel.qml's `cursorActive`, each panel's own row identity) only ever
# moves from a real Qt key event. `$grim_bin` rather than `niri msg action
# screenshot-screen`: that IPC action fires niri's own "Screenshot captured"
# toast in the same top-right corner this panel occupies (chevron_drive_
# script above hits the same trap and sidesteps it the same way).
#
# Repeated, deliberate probing (four independently-timed variants: the
# original 1s-spaced sequence, a zero-delay burst, a 0.3s settle before a
# single combined `wtype -k Down -k Down -k Return`, and an isolated single
# Escape sent with no delay at all) found this rig's wtype route into a
# Panel.qml surface genuinely racy: the lone Escape landed once (the panel
# closed), every Down/Down/Return variant since left the OUTPUT master
# slider row — the one row in this panel that is never `selected`, so a
# `hovered` highlight on it can't be confused with anything else — exactly
# as unhighlighted as the baseline, with only an unrelated bar-icon
# animation making the two frames differ at all. Panel.qml's own focus-
# prime dance (Exclusive for ~75ms, then OnDemand) is built for a real
# bar-cell click; an IPC open with no antecedent pointer event has nothing
# to make OnDemand re-claim focus once the prime window closes, and this
# rig has no synthetic pointer to supply one (CLAUDE.md's standing note,
# true of every other panel leg here too). Kept anyway as the honest
# record: the two screenshots below are real evidence for whoever looks,
# and the assertion after them fails loudly rather than claiming success.
if $panel_keys_mode; then
  panel_keys_drive_script="$shot_dir/panel-keys-drive.sh"
  cat > "$panel_keys_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
"$qs_bin" ipc -p "$shell_path" call panel open audio
sleep 0.3
"$grim_bin" "$panel_keys_baseline_path"
"$wtype_bin" -k Down -k Down -k Return
sleep 1
"$grim_bin" "$panel_keys_path"
EOF
fi

# --instance: launches a second real daemon against the same shell_path
# after the primary is up, then polls until exactly one survives. Both
# instances are Wayland clients of this same nested niri session, so — same
# as the primary formalshell process every other leg already relies on —
# neither needs an explicit kill script: whichever one loses the takeover
# exits on its own, and the survivor dies with the session at teardown.
if $instance_mode; then
  instance_drive_script="$shot_dir/instance-drive.sh"
  cat > "$instance_drive_script" <<EOF
#!/usr/bin/env bash
sleep 3
# Same argv[1]=="-p" idiom the picker-memory leg uses to isolate the real
# daemon process(es) from this run's own "qs ipc ... call" client
# invocations, which also match a bare "pgrep -f -- -p \$shell_path".
find_daemon_pids() {
  for pid in \$(pgrep -f -- "-p $shell_path"); do
    if [ "\$(tr '\\0' '\\n' < /proc/\$pid/cmdline 2>/dev/null | sed -n '2p')" = "-p" ]; then
      echo "\$pid"
    fi
  done
}
old_pid=\$(find_daemon_pids | head -n1)
# The wrapped launcher, not a bare "\$qs_bin -p \$shell_path": the wrapper
# carries QT_PLUGIN_PATH/NIXPKGS_QT6_QML_IMPORT_PATH for QtPositioning and
# QtMultimedia (nix/package.nix), which a raw qs invocation lacks — every
# real second instance (niri respawn, terminal, keybind) goes through this
# same wrapper, so this is the faithful reproduction of the owner's actual
# two-bar scenario, not a shortcut around it.
"$PWD/result/bin/formalshell" > "$instance_second_log_path" 2>&1 &
new_pid=\$!
waited=0
count=0
while [ "\$waited" -lt 15000 ]; do
  sleep 0.5
  waited=\$((waited + 500))
  count=\$(find_daemon_pids | wc -l | tr -d ' ')
  if [ "\$count" = "1" ]; then
    break
  fi
done
survivor=\$(find_daemon_pids | head -n1)
printf '{"oldPid":%s,"newPid":%s,"survivorPid":%s,"waitedMs":%s,"finalCount":%s}\n' \
  "\${old_pid:-null}" "\${new_pid:-null}" "\${survivor:-null}" "\$waited" "\${count:-0}" \
  > "$instance_status_path"
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
  if $clipssh_mode; then
    shim_path_prefix="$clipssh_shim_dir:$shim_path_prefix"
  fi
  if $instance_mode; then
    # Captures the primary instance's own stdout/stderr so InstanceLock.qml's
    # "being replaced" log line is real evidence below, not inferred from the
    # process disappearing.
    echo "spawn-at-startup \"sh\" \"-c\" \"exec '$PWD/result/bin/formalshell' > '$instance_primary_log_path' 2>&1\""
  elif $share_mode; then
    # Same rationale as instance_mode above: share-drive.sh's own second
    # phase reuses the takeover protocol, so this instance's own "being
    # replaced" log line is what proves the PATH-shadowed instance actually
    # won the handoff rather than the poll merely timing out at count 1.
    # shim_path_prefix (empty unless $menu_mode) still has to land on this
    # instance's own PATH: dropping it here previously sent
    # menu_finish_script's `nix search` calls at the VM's real `nix`
    # instead of the deterministic shim, so the released-search assertion
    # never saw the canned rows (found combining --share --menu for the
    # first time, M17 Task 3).
    echo "spawn-at-startup \"sh\" \"-c\" \"PATH='$shim_path_prefix$PATH' exec '$PWD/result/bin/formalshell' > '$share_primary_log_path' 2>&1\""
  elif [ -n "$shim_path_prefix" ]; then
    echo "spawn-at-startup \"sh\" \"-c\" \"PATH='$shim_path_prefix$PATH' exec '$PWD/result/bin/formalshell'\""
  else
    echo "spawn-at-startup \"$PWD/result/bin/formalshell\""
  fi
  if $active_window_fixture_mode; then
    echo "spawn-at-startup \"bash\" \"$active_window_play_script\""
  fi
  if $dump_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc -p '$shell_path' call debug dump > $dump_path 2>&1\""
  fi
  if $clipssh_mode; then
    echo "spawn-at-startup \"bash\" \"$clipssh_drive_script\""
    # Four frames off one timeline: the route's own rows, the transfer in
    # flight (the point of the whole mode: indicator cell up in the bar,
    # SENDING toast beside it), the same transfer landed, and the failure.
    # The in-flight frame sits mid-way through the shim's six seconds, the
    # landed one a second after it exits, and the failure two seconds after
    # its own activation, which is a `qs ipc` spawn on llvmpipe away from
    # instant.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && niri msg action screenshot-screen --path $clipssh_route_path\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 8 && niri msg action screenshot-screen --path $clipssh_sending_path\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 12 && niri msg action screenshot-screen --path $clipssh_copied_path\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 21 && niri msg action screenshot-screen --path $clipssh_failed_path\""
  fi
  if $wallpaper_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc -p '$shell_path' call wallpaper set '$wp_path'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc -p '$shell_path' call theme status > $status_path 2>&1\""
    # The crossfade leg. Held back from the --theme-toggle combination,
    # whose own drive script owns the timeline from sleep 9 on and whose
    # assertions all compare against the first wallpaper's path.
    if ! $theme_toggle_mode; then
      # The solid wallpaper's own shot, taken while it is still the only one
      # on screen: the monotone-flatness assertion needs a frame that predates
      # the gradient (see the wp2 fixture comment).
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 8 && niri msg action screenshot-screen --path $wallpaper_solid_path\""
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 9 && '$qs_bin' ipc -p '$shell_path' call wallpaper set '$wp2_path'\""
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc -p '$shell_path' call wallpaper get > $wallpaper_get_path 2>&1\""
    fi
  fi
  if $theme_toggle_mode; then
    echo "spawn-at-startup \"bash\" \"$theme_toggle_drive_script\""
  fi
  if $menu_mode; then
    echo "spawn-at-startup \"bash\" \"$menu_open_script\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call debug query 'e' > $query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call debug query '2+2*3' > $calc_query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call debug query ':e thumbs' > $emoji_query_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call debug query 'wall' > $wall_query_path 2>&1\""
    # The nix end-state drive (M13b Task 4) replaced M12's plain two-pass
    # ':nix hello' one-liners: the gated slowblock release covers the same
    # debounce -> shim -> parse -> rows proof, plus SEARCHING while blocked
    # and the failed/zero-hit outcomes. Serial in its own script — see its
    # generation comment.
    echo "spawn-at-startup \"bash\" \"$nix_states_script\""
    echo "spawn-at-startup \"bash\" \"$menu_select_script\""
    echo "spawn-at-startup \"bash\" \"$menu_finish_script\""
  fi
  if $notify_mode || $center_mode; then
    echo "spawn-at-startup \"bash\" \"$chromium_notify_script\""
  fi
  if $notify_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$notify_send_bin' -u normal 'Test' 'Hello'\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$notify_send_bin' -u critical 'Crit' 'Now'\""
    # A real action-carrying notify-send (M19 Task 4's ink-button proof):
    # neither leg above declares actions, so NotificationCard.qml's action
    # row never rendered in this rig before. -A implies --wait, so the
    # client blocks on the popup's own auto-expiry rather than exiting —
    # harmless, niri's own quit at the end of this run tears it down with
    # everything else. Two actions so the screenshot shows adjacent ink
    # cells, not just one.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$notify_send_bin' -A 'view=View' -A 'dismiss=Dismiss' 'Actions' 'Pick one'\""
    # Bell cell DND display (M13b Task 2, formerly Indicators.qml's DND
    # glyph, M10 Task 2): both notify-sends above have already fired by
    # sleep 6, so flipping DND on here can't suppress them (dnd bypass is
    # per-notification-on-arrival, not retroactive) — dndState is dumped
    # right after the toggle to prove it actually flipped, then the bar is
    # screenshotted a second later to show BellWidget.qml swap to its
    # bell-off glyph.
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc -p '$shell_path' call notifications setDnd true > $dnd_status_path 2>&1\""
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
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 12 && '$qs_bin' ipc -p '$shell_path' call notifications status > $center_status_before_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc -p '$shell_path' call notifications showHistory\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 14 && '$qs_bin' ipc -p '$shell_path' call notifications status > $center_status_open_path 2>&1\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 16 && '$qs_bin' ipc -p '$shell_path' call notifications showHistory\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 17 && '$qs_bin' ipc -p '$shell_path' call notifications status > $center_status_closed_path 2>&1\""
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
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 4 && '$qs_bin' ipc -p '$shell_path' call osd volume\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && niri msg action screenshot-screen --path $osd_manual_path\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 9 && '$wpctl_bin' set-volume @DEFAULT_AUDIO_SINK@ 30%\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 13 && '$qs_bin' ipc -p '$shell_path' call osd brightness\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 14 && niri msg action screenshot-screen --path $osd_brightness_path\""
  fi
  if $panel_mode; then
    if [ "$panel_name" = "calendar" ]; then
      echo "spawn-at-startup \"bash\" \"$eds_drive_script\""
    else
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc -p '$shell_path' call panel open '$panel_name'\""
    fi
    if [ "$panel_name" = "appmenu" ]; then
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call debug dump > $dump_path 2>&1\""
    fi
  fi
  if $gallery_mode; then
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 3 && '$qs_bin' ipc -p '$shell_path' call gallery open > '$gallery_log_path' 2>&1; '$qs_bin' ipc -p '$shell_path' call gallery status >> '$gallery_log_path' 2>&1\""
  fi
  if $clipboard_mode; then
    echo "spawn-at-startup \"bash\" \"$clipboard_drive_script\""
  fi
  if $nightlight_mode; then
    echo "spawn-at-startup \"bash\" \"$nightlight_drive_script\""
  fi
  if $hotcorner_mode; then
    echo "spawn-at-startup \"bash\" \"$hotcorner_drive_script\""
  fi
  if $speedtest_mode; then
    echo "spawn-at-startup \"bash\" \"$speedtest_drive_script\""
  fi
  if $wifi_mode; then
    echo "spawn-at-startup \"bash\" \"$wifi_drive_script\""
  fi
  if $media_mode; then
    echo "spawn-at-startup \"bash\" \"$media_play_script\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && '$qs_bin' ipc -p '$shell_path' call panel open media\""
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc -p '$shell_path' call media status > $media_status_path 2>&1\""
    echo "spawn-at-startup \"bash\" \"$media_marquee_script\""
    # --media --panel audio: the generic panel_mode open above (sleep 3)
    # and this leg's own "panel open media" (sleep 5) both go through
    # PanelRegistry, which only ever holds one open panel — media wins
    # that race. Reopen audio afterward so it (with mpv's now-registered
    # Pipewire stream under APPS) is what the screenshot below shows.
    if $panel_mode && [ "$panel_name" = "audio" ]; then
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 6 && '$qs_bin' ipc -p '$shell_path' call panel open audio\""
      echo "spawn-at-startup \"sh\" \"-c\" \"sleep 7 && niri msg action screenshot-screen --path $audio_panel_path\""
    fi
  fi
  if $visualizer_mode; then
    echo "spawn-at-startup \"bash\" \"$visualizer_drive_script\""
  fi
  if $lock_mode; then
    echo "spawn-at-startup \"bash\" \"$lock_drive_script\""
  fi
  if $polkit_mode; then
    echo "spawn-at-startup \"bash\" \"$polkit_drive_script\""
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
  if $chevron_mode; then
    echo "spawn-at-startup \"bash\" \"$chevron_drive_script\""
  fi
  if $capture_mode; then
    echo "spawn-at-startup \"bash\" \"$capture_drive_script\""
  fi
  if $screenshot_mode; then
    echo "spawn-at-startup \"bash\" \"$screenshot_drive_script\""
  fi
  if $record_mode; then
    echo "spawn-at-startup \"bash\" \"$record_drive_script\""
  fi
  if $ocr_mode; then
    echo "spawn-at-startup \"bash\" \"$ocr_fixture_script\""
    echo "spawn-at-startup \"bash\" \"$ocr_drive_script\""
  fi
  if $reminder_mode; then
    echo "spawn-at-startup \"bash\" \"$reminder_drive_script\""
  fi
  if $toggles_mode; then
    echo "spawn-at-startup \"bash\" \"$toggles_drive_script\""
  fi
  if $keybinds_mode; then
    echo "spawn-at-startup \"bash\" \"$keybinds_drive_script\""
  fi
  if $mic_mode; then
    echo "spawn-at-startup \"bash\" \"$mic_drive_script\""
  fi
  if $systemupdate_mode; then
    echo "spawn-at-startup \"bash\" \"$systemupdate_drive_script\""
  fi
  if $plugins_mode; then
    echo "spawn-at-startup \"bash\" \"$plugins_drive_script\""
  fi
  if $panel_keys_mode; then
    echo "spawn-at-startup \"bash\" \"$panel_keys_drive_script\""
  fi
  if $bar_layout_mode; then
    # 5s: shell startup plus room for the command module's first poll
    # (fires immediately once Config.settings resolves, well under 2s).
    echo "spawn-at-startup \"sh\" \"-c\" \"sleep 5 && niri msg action screenshot-screen --path $bar_layout_path\""
  fi
  if $instance_mode; then
    echo "spawn-at-startup \"bash\" \"$instance_drive_script\""
  fi
  if $share_mode; then
    echo "spawn-at-startup \"bash\" \"$share_drive_script\""
  fi
  # menu_mode's finish script (menu close + selection read + toggle round
  # trip + emoji instant-paste + apps + nix toast legs) fires 1s after the
  # screenshot at sleep 9 and needs a much longer buffer before quit than
  # the other modes' 1s — see the branch comment below. osd_mode's
  # brightness leg (sleep 13/14, see above) needs the same kind of buffer
  # past its own sleep-10 screenshot.
  tail_gap=1
  if $menu_mode && $share_mode; then
    # share_drive_script now waits on menu_finish_script's own completion
    # marker (see share_menu_wait above) before it touches the menu route
    # at all, so its worst case runs entirely inside screenshot_delay's
    # own combined budget below rather than needing a tail past the shot.
    tail_gap=3
  elif $menu_mode; then
    # 26, not the pre-Task-2 18: after the toast leg (landing ~23-26s in,
    # see below) the finish script now runs one more leg — summon root,
    # grim, wtype "wall", grim, close — another ~4s (M16 Task 2's top-freeze
    # proof), landing ~27-30s in.
    #
    # Pre-Task-2 breakdown, unchanged: after the apps leg the finish script
    # waits for the nix states script's done flag (~13-17s in) and runs the
    # toast leg (summon + 2s debounce wait + activate + grim + status, ~5s),
    # landing ~23-26s in on the VM's llvmpipe timing.
    tail_gap=26
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
  if $clipssh_mode; then
    # clipssh-drive.sh's own last step lands at 19s (3+2 to summon and run
    # the six-second success case, 12 to clear it, 2+2 for the failure),
    # and the failure frame is taken a beat after it. This run's own
    # smoke.png/SMOKE_OK comes after all four, showing the session with
    # nothing in flight and the bar's indicator row gone again.
    screenshot_delay=22
  elif $center_mode; then
    screenshot_delay=15
  elif $capture_mode; then
    # capture-drive.sh's own worst case: 5+2+1+1 to open and cycle the
    # picker, up to 10s polling `capturing` back to false after the pick,
    # then 2+1 for the region-and-escape pass, plus qs spawn overhead per
    # call on llvmpipe. At the inherited 8s default the session tore down
    # mid-script and the cycled status dump was never written.
    screenshot_delay=30
  elif $theme_toggle_mode; then
    # theme-toggle-drive.sh's own final step (the back-to-dark status dump)
    # lands around its internal sleep sum plus grim/qs spawn overhead on
    # llvmpipe (~9-13s in; ~17-19s for the --wallpaper-combined drive with
    # its later start and matugen-sized toggle gaps); this run's generic
    # smoke.png/SMOKE_OK is taken after that, showing the session dark
    # again after the round trip.
    if $wallpaper_mode; then
      screenshot_delay=22
    else
      screenshot_delay=14
    fi
  elif $osd_mode; then
    screenshot_delay=10
  elif $media_mode; then
    # media-marquee.sh's own worst case (7s static shot + kill/respawn +
    # up to 8s retitle poll + 5s into-scroll wait = 21s) lands ~21s in;
    # this run's generic smoke.png/SMOKE_OK is taken 3s after that, so it
    # shows the ordinary session mid-scroll on the long-title track.
    screenshot_delay=24
  elif $clipboard_mode; then
    # clipboard-drive.sh's last step (menu summon) lands after its warmup
    # poll (typically 5-7s until the wl-paste watcher is up, 11s ceiling)
    # plus the ~14s fixture sequence (text dumps, a copy-and-paste round
    # trip, then the image leg's own wl-copy/list/copy/wl-paste round trip,
    # then the summon); the shot lands past the worst case, showing the
    # freshly captured image as the newest (topmost) row.
    screenshot_delay=28
  elif $nightlight_mode; then
    # nightlight-drive.sh's own worst-case budget (3s initial sleep + 8s
    # poll ceiling + disable/sleep1) lands ~12s in; this run's generic
    # smoke.png/SMOKE_OK is taken 4s after that, showing the ordinary
    # session with night light already disabled again.
    screenshot_delay=16
  elif $speedtest_mode; then
    # speedtest-drive.sh's own worst-case budget (3s initial sleep + 1s
    # panel-open settle + up-to-25s poll ceiling for the two bounded 5s
    # phases) lands ~29s in at worst; the typical path (phase reaches
    # "done" on its own) lands ~15s in. This run's generic smoke.png/
    # SMOKE_OK is taken 3s past the worst case.
    screenshot_delay=32
  elif $lock_mode; then
    # lock-drive.sh's own final step (the second isLocked/status dump) lands
    # around its internal sleep sum (~20s in, the wrong-password PAM round
    # trip's 5s buffer included); this run's generic smoke.png/SMOKE_OK is
    # taken 2s after that, so it shows the ordinary unlocked session, not
    # mid-round-trip.
    screenshot_delay=22
  elif $polkit_mode; then
    # polkit-drive.sh's own internal sleep sum (3 + 3 + 1 + 10 + 1 + 3 = 21s)
    # plus real margin for `wait $polkit_pid` itself, which blocks for
    # however long the socket-activated polkit-agent-helper@ conversation
    # actually takes to resolve past that last sleep — generous rather than
    # tightly calibrated, since a first-ever socket activation in this
    # session's own lifetime is the slow path being budgeted for here.
    screenshot_delay=32
  elif $screensaver_mode; then
    # ss-drive.sh's cycle-proof poll can run until its 75s SECONDS deadline
    # (worst first random pick, see the drive script's own comment), and the
    # final status dump lands ~2s after the poll breaks; this run's generic
    # smoke.png/SMOKE_OK is taken after that worst case, showing the
    # ordinary session with the screensaver already dismissed for good.
    screenshot_delay=80
  elif $picker_mode; then
    # picker-drive.sh's own final step (the light-variant status dump) lands
    # around its internal sleep sum (~31s in for the selection readback — the
    # post-close Rss sample alone waits 20s for the QML engine's own GC cycle
    # to actually run, see its own comment — then ~8s more for the two
    # variant legs and their grim); this run's generic smoke.png/SMOKE_OK is
    # taken past that, showing the ordinary session with the picker already
    # closed again.
    screenshot_delay=46
  elif $tray_mode; then
    # tray-drive.sh's own final step (the activate call) lands around its
    # internal sleep sum (~11s in: 1s before the six stubs launch, 6s for
    # them to register, then the status/screenshot/activate legs at roughly
    # a second apiece plus qs spawn overhead on llvmpipe). This run's generic
    # smoke.png/SMOKE_OK is taken 5s after that, so it shows the ordinary bar
    # with all six items as their own cells. Getting this wrong is not a slow
    # test, it is a false failure: the kill script takes the stubs down before
    # niri quits, so a drive step that lands after this delay reads an empty
    # item list.
    screenshot_delay=16
  elif $chevron_mode; then
    # chevron-drive.sh's own final step (the expanded grim) lands around its
    # internal sleep sum (~10s in: 5s for the bar to settle, then the two
    # dump/shot pairs and the expand call at a second or two apiece). This
    # run's generic smoke.png/SMOKE_OK is taken 4s after that, so it shows
    # the bar left expanded, matching chevron-expanded.png.
    screenshot_delay=14
  elif $panel_mode && [ "$panel_name" = "calendar" ]; then
    # eds-drive.sh opens the panel only after its two seed writes return
    # (~4-7s in when this run's private bus has to cold-activate EDS
    # first), then selects tomorrow 2s after the open; 13s leaves the
    # on-open refresh's own `formalshell-eds events` run and the select
    # comfortable room before the shot.
    screenshot_delay=13
  elif $wifi_mode; then
    # wifi-drive.sh's own worst-case budget (wpa_supplicant restart settle
    # 2s + self-heal reset poll 2x15s + scan wait 25s + wrong-password poll
    # 45s + real-connect poll 25s + forget poll 15s + eap poll 35s + closing
    # eap-forget poll 15s = 177s, each ceiling only hit if NM/hostapd
    # genuinely takes that long) plus room for its own three
    # screenshot-screen calls; this run's generic smoke.png/SMOKE_OK is taken
    # 13s after that worst case, so it shows the ordinary session with the
    # eap leg already screenshotted and forgotten.
    screenshot_delay=190
  elif $instance_mode; then
    # instance-drive.sh's own worst case (3s initial sleep + 15s poll
    # ceiling) lands ~18s in; this run's generic smoke.png/SMOKE_OK is taken
    # 3s after that, showing the ordinary session with the takeover already
    # resolved to a single bar.
    screenshot_delay=21
  elif $share_mode; then
    if $menu_mode; then
      # share_menu_wait (see share-drive.sh's own comment) holds share's
      # whole sequence off the menu route until menu_finish_script's own
      # completion marker lands (~27-30s in, same landing time as the
      # plain --menu case above), then share's own worst case runs in full
      # from there (the same ~30s-to-kill plus 6s margin as the alone case
      # below) — 30 (menu) + 36 (share) rounded up for VM slop.
      screenshot_delay=72
    else
      # share-drive.sh's own worst case (~12s through the present-case kill
      # — the localsend_app pgrep step polls up to 6s rather than a flat
      # sleep, since Flutter app startup isn't instant — plus a 15s
      # takeover poll ceiling for the absent-case handoff, plus the closing
      # query/screenshot round trip) lands ~30s in; this run's generic
      # smoke.png/SMOKE_OK is taken 6s after that, showing the ordinary
      # session with the second (shadowed-PATH) instance now the sole
      # survivor and its menu already closed again.
      screenshot_delay=36
    fi
  elif $visualizer_mode; then
    # visualizer-drive.sh's own worst case (2s pre-mpv sleep + up to 10s
    # cava-appears poll + 2s settle + screenshot + kill + up to 6s
    # cava-gone poll = 20s) lands ~20s in; this run's generic smoke.png/
    # SMOKE_OK is taken 3s after that, showing the ordinary session with
    # the widget already hidden again (no player, same as nowPlaying).
    screenshot_delay=23
  elif $record_mode; then
    # record-drive.sh's own worst case (4s startup + 4s recording + 2s +
    # a 15s stop-settle ceiling + a 40s transcode ceiling) lands ~66s in;
    # the typical path is closer to 20s, since both ceilings are polls that
    # break the moment the state settles. This run's generic smoke.png/
    # SMOKE_OK is taken past the worst case, showing the ordinary session
    # with the recording already stopped and its GIF written.
    screenshot_delay=70
  elif $ocr_mode; then
    # ocr-drive.sh's own sequence (5s startup + two ~4s slurp/cancel round
    # trips) lands ~14s in; this run's generic smoke.png/SMOKE_OK is taken
    # after that, showing the fixture window with no overlay left on it.
    screenshot_delay=18
  elif $reminder_mode; then
    # reminder-drive.sh's own sequence (4s startup + 2s + the 13s wait past
    # a 12s deadline) lands ~20s in; this run's generic smoke.png/SMOKE_OK
    # is taken after the reminder has fired, so it shows the sticky
    # urgency-2 toast that got through DND.
    screenshot_delay=24
  elif $toggles_mode; then
    # toggles-drive.sh's own sequence (4s startup + 2s settle + 2s past the
    # toggles) lands ~10s in; this run's generic smoke.png/SMOKE_OK is
    # taken after that, with the hub still open at the toggled state.
    screenshot_delay=14
  elif $keybinds_mode; then
    # keybinds-drive.sh's own sequence (4s startup + two query passes + 2s
    # for the summoned level to paint) lands ~8s in.
    screenshot_delay=12
  elif $systemupdate_mode; then
    # systemupdate-drive.sh's own sequence (4s startup + 1s + a 20s settle
    # for real forge probes) lands ~26s in; this run's generic smoke.png/
    # SMOKE_OK is taken after that, panel still open.
    screenshot_delay=30
  elif $mic_mode || $plugins_mode; then
    # Both drive scripts are a 5s startup wait plus a dump/list and one
    # grim; 12 leaves llvmpipe real margin on the capture rather than
    # racing the default 8s shot.
    screenshot_delay=12
  elif $panel_keys_mode; then
    # panel-keys-drive.sh's own final step (the post-Return grim) lands
    # around its internal sleep sum (3s open + 7×1s steps = 10s). This run's
    # generic smoke.png/SMOKE_OK is taken 4s after that, so it shows the
    # ordinary session with the audio panel's cursor still on the row the
    # drive script's Return activated.
    screenshot_delay=14
  elif $wallpaper_mode; then
    # Last in the chain on purpose: --wallpaper is a modifier other modes
    # combine with, and each of those owns its own timeline. On its own it
    # needs the second wallpaper (sleep 9), its crossfade, and the sleep-13
    # `wallpaper get` to have landed, so the shot shows the session settled
    # on the second wallpaper rather than mid-fade.
    screenshot_delay=16
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
  # active_window_fixture_mode's foot window has no auto-close of its own
  # either — same reasoning as media_kill above.
  active_window_kill=""
  if $active_window_fixture_mode; then
    active_window_kill="bash '$active_window_kill_script'; "
  fi
  # visualizer-drive.sh already kills its own mpv well before this run's
  # own screenshot_delay budget elapses — this is a safety net only, same
  # "harmless if already dead" shape as media_kill above.
  visualizer_kill=""
  if $visualizer_mode; then
    visualizer_kill="bash '$visualizer_kill_script'; "
  fi
  # ocr_mode's foot fixture window has no auto-close of its own either,
  # same reasoning as active_window_kill above.
  ocr_kill=""
  if $ocr_mode; then
    ocr_kill="bash '$ocr_kill_script'; "
  fi
  echo "spawn-at-startup \"sh\" \"-c\" \"sleep $screenshot_delay && niri msg action screenshot-screen --path $shot_dir/smoke.png && ${media_kill}${tray_kill}${active_window_kill}${visualizer_kill}${ocr_kill}sleep $tail_gap && niri msg action quit --skip-confirmation\""
} > "$cfg"

# The 40s default comfortably outlives every mode's screenshot-then-quit
# schedule except screensaver_mode's, whose worst-case cycle-proof poll
# pushes the smoke.png shot itself to 80s (see screenshot_delay above),
# share_mode's, whose own worst case (screenshot_delay=36 plus tail_gap)
# leaves too little margin against 40s, picker_mode's, whose Dark/Light legs
# run past the 20s GC settle window its Rss bracket already needs, and
# record_mode's, whose two settle-polls can push its own shot to 70s.
session_timeout=40
if $screensaver_mode; then
  session_timeout=100
elif $picker_mode; then
  # screenshot_delay=46 plus tail_gap: the session was being SIGTERMed at 40s,
  # before its own final shot, the moment the variant legs were added.
  session_timeout=60
elif $capture_mode; then
  # screenshot_delay=30 plus tail_gap needs real margin past 33.
  session_timeout=50
elif $record_mode; then
  session_timeout=90
elif $wifi_mode; then
  session_timeout=210
elif $share_mode; then
  if $menu_mode; then
    # screenshot_delay=72 plus tail_gap=3 (share_menu_wait's combined
    # budget above) needs real margin past 75, not share_mode-alone's 50.
    session_timeout=85
  else
    session_timeout=50
  fi
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

if $panel_mode && [ "$panel_name" = "appmenu" ]; then
  if [ ! -s "$dump_path" ]; then
    echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
  fi
  # The dump is taken with the app menu already open, i.e. with one of the
  # shell's own layer surfaces holding keyboard focus — a held id surviving
  # that is exactly what Compositor/focus.js exists for, and what keeps the
  # panel able to name the app it was opened from.
  if grep -qE '"heldFocusedWindowId":"[^"]+"' "$dump_path"; then
    cat "$dump_path"
  else
    echo "SMOKE_FAIL: app menu open with no held focused window" >&2
    cat "$dump_path" >&2
    exit 1
  fi
fi

if $wallpaper_mode; then
  if [ -s "$status_path" ]; then
    cat "$status_path"
  else
    echo "SMOKE_FAIL: no theme status produced" >&2; exit 1
  fi
fi

# The crossfade plus the dither pass, proven off the rendered pixels rather
# than off the shell's own account of itself. Skipped in the --theme-toggle
# combination, which never sets the second wallpaper (see the spawn block).
if $wallpaper_mode && ! $theme_toggle_mode; then
  if [ ! -s "$wallpaper_get_path" ] || ! grep -qF "$wp2_path" "$wallpaper_get_path"; then
    echo "SMOKE_FAIL: wallpaper get did not report the second wallpaper — got: $(cat "$wallpaper_get_path" 2>/dev/null)" >&2
    exit 1
  fi
  # Half one: the SOLID wallpaper, sampled off its own pre-crossfade frame.
  # A monotone source's color is its whole derived palette, so every cell
  # matches an entry exactly and nothing has a second-nearest to dither
  # against — a 64x64 patch of bare wallpaper (well clear of the bar) must be
  # #7a3fb0 (122,63,176) and nothing else. This is the owner's own 2026-08-12
  # report as an assertion: the old fixed posterize grid speckled exactly here.
  #
  # The trailing [,)] tolerates an alpha component, which grim's PNG may or
  # may not carry; a pattern anchored on ")" would silently parse nothing.
  wallpaper_solid_patch_path="$shot_dir/wallpaper-solid-patch.txt"
  if [ ! -f "$wallpaper_solid_path" ]; then
    echo "SMOKE_FAIL: no pre-crossfade solid-wallpaper screenshot produced" >&2
    exit 1
  fi
  $convert_bin "$wallpaper_solid_path" -crop 64x64+100+500 +repage txt:- > "$wallpaper_solid_patch_path" 2>&1
  wallpaper_solid_pixels=$(sed -n 's/^[0-9]*,[0-9]*: (\([0-9]*\),\([0-9]*\),\([0-9]*\)[,)].*/\1 \2 \3/p' "$wallpaper_solid_patch_path")
  if [ -z "$wallpaper_solid_pixels" ]; then
    echo "SMOKE_FAIL: could not read any pixel out of the solid-wallpaper patch — head: $(head -n3 "$wallpaper_solid_patch_path")" >&2
    exit 1
  fi
  wallpaper_solid_off=$(printf '%s\n' "$wallpaper_solid_pixels" \
    | awk '{ if ($1 != 122 || $2 != 63 || $3 != 176) { print; exit } }')
  if [ -n "$wallpaper_solid_off" ]; then
    echo "SMOKE_FAIL: monotone wallpaper pixel ($wallpaper_solid_off) is not the source color 7a3fb0 — the dither is speckling a flat source" >&2
    exit 1
  fi
  echo "SMOKE_WALLPAPER_FLAT 64x64 patch of the monotone wallpaper is 7a3fb0 end to end, no dither dots"
  echo "SMOKE_WALLPAPER_SOLID $wallpaper_solid_path"
  # Half two: the GRADIENT wallpaper, off the settled crossfade. A full-width
  # strip crosses the whole ramp, so it must show more than a couple of colors
  # (the pass quantized AND dithered) and no more than the palette is allowed
  # (it quantized to a derived palette rather than passing the source through).
  # Read as whole rows because the strip spans every column of the gradient;
  # a small square could legitimately sit inside one flat palette cell.
  wallpaper_patch_path="$shot_dir/wallpaper-patch.txt"
  $convert_bin "$shot_dir/smoke.png" -crop 1920x40+0+500 +repage txt:- > "$wallpaper_patch_path" 2>&1
  wallpaper_patch_pixels=$(sed -n 's/^[0-9]*,[0-9]*: (\([0-9]*\),\([0-9]*\),\([0-9]*\)[,)].*/\1 \2 \3/p' "$wallpaper_patch_path")
  if [ -z "$wallpaper_patch_pixels" ]; then
    echo "SMOKE_FAIL: could not read any pixel out of the wallpaper patch — head: $(head -n3 "$wallpaper_patch_path")" >&2
    exit 1
  fi
  wallpaper_patch_colors=$(printf '%s\n' "$wallpaper_patch_pixels" | sort -u | wc -l | tr -d ' ')
  if [ "${wallpaper_patch_colors:-0}" -lt 3 ]; then
    echo "SMOKE_FAIL: the gradient wallpaper strip carries only $wallpaper_patch_colors color(s), so nothing dithered" >&2
    exit 1
  fi
  if [ "$wallpaper_patch_colors" -gt 6 ]; then
    echo "SMOKE_FAIL: the gradient wallpaper strip carries $wallpaper_patch_colors colors, more than the 6-entry derived palette allows — the pass didn't quantize" >&2
    exit 1
  fi
  echo "SMOKE_WALLPAPER_DITHER $wallpaper_patch_colors distinct palette colors across a 1920x40 strip of the gradient wallpaper"
fi

if $theme_toggle_mode && $wallpaper_mode; then
  # Combined round trip WITH the wallpaper set: every leg must stay
  # matugen-derived. Flexoki hexes only ever enter theme.json through
  # palette.js's fallback write (uppercase, but matched -i to be safe) —
  # any appearance of a fallback background means a toggle reset the theme
  # instead of re-running matugen.
  if [ ! -s "$theme_json_dump1_path" ] || ! grep -qF '"mode": "dark"' "$theme_json_dump1_path" \
    || grep -iqF '"background": "#100f0f"' "$theme_json_dump1_path"; then
    echo "SMOKE_FAIL: pre-toggle theme.json is missing or not matugen-derived dark" >&2
    [ -f "$theme_json_dump1_path" ] && cat "$theme_json_dump1_path" >&2
    exit 1
  fi
  if [ -s "$theme_toggle_status_path" ] \
    && grep -qF '"wallpaper":"'"$wp_path"'"' "$theme_toggle_status_path" \
    && grep -qF '"mode":"light"' "$theme_toggle_status_path"; then
    cat "$theme_toggle_status_path"
  else
    echo "SMOKE_FAIL: theme status after toggle did not report mode:light with the wallpaper kept" >&2
    [ -f "$theme_toggle_status_path" ] && cat "$theme_toggle_status_path" >&2
    exit 1
  fi
  if [ ! -s "$theme_json_dump2_path" ] || ! grep -qF '"mode": "light"' "$theme_json_dump2_path" \
    || grep -iqF '"background": "#fffcf0"' "$theme_json_dump2_path"; then
    echo "SMOKE_FAIL: theme.json after dark->light toggle is not matugen-derived light (toggle reset to fallback?)" >&2
    [ -f "$theme_json_dump2_path" ] && cat "$theme_json_dump2_path" >&2
    exit 1
  fi
  if [ -s "$theme_toggle_status2_path" ] \
    && grep -qF '"wallpaper":"'"$wp_path"'"' "$theme_toggle_status2_path" \
    && grep -qF '"mode":"dark"' "$theme_toggle_status2_path"; then
    cat "$theme_toggle_status2_path"
  else
    echo "SMOKE_FAIL: theme status after the second toggle did not report mode:dark with the wallpaper kept" >&2
    [ -f "$theme_toggle_status2_path" ] && cat "$theme_toggle_status2_path" >&2
    exit 1
  fi
  if ! cmp -s "$theme_json_dump1_path" "$theme_json_dump3_path"; then
    echo "SMOKE_FAIL: theme.json did not round-trip byte-identical through light and back" >&2
    diff "$theme_json_dump1_path" "$theme_json_dump3_path" >&2 || true
    exit 1
  fi
  if [ ! -s "$theme_dark_png" ] || [ ! -s "$theme_light_png" ]; then
    echo "SMOKE_FAIL: missing theme-toggle screenshot pair ($theme_dark_png / $theme_light_png)" >&2
    exit 1
  fi
  echo "theme json pre-toggle: $theme_json_dump1_path"
  cat "$theme_json_dump1_path"
  echo "theme json after toggle to light: $theme_json_dump2_path"
  cat "$theme_json_dump2_path"
  echo "theme dark screenshot: $theme_dark_png"
  echo "theme light screenshot: $theme_light_png"
elif $theme_toggle_mode; then
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
    echo "SMOKE_FAIL: menu close in select mode did not write {cancelled:true}" >&2
    [ -f "$selection_path" ] && cat "$selection_path" >&2
    exit 1
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
  # Wallpaper root node (M13 Task 5; a declared provider route since M23,
  # when the picker grid moved inside the menu): ranking "wall" must surface
  # it from default-menu.jsonc like any other declared node.
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
  # Card-top freeze and release (M16 Task 2, M23): three PNGs, taken at rest,
  # filtered down to one row, and then a level deeper. SMOKE_-tagged (not
  # the plain "menu apps screenshot:" style above) so dev/vm.sh's own
  # scp-back grep pulls all three to the mac.
  #
  # The card's own edges are read out of each PNG rather than eyeballed:
  # scan the screen's centre column, starting below the bar, for the first
  # and last pixel that aren't the page background. The card is centred
  # horizontally, so that column always crosses it, and nothing else is
  # drawn there — which keeps this free of hardcoded card geometry, so it
  # survives a different output size or a card that changes height (the
  # action bar did exactly that).
  #
  # The awk reads from a here-string rather than a pipe on purpose: closing
  # a pipe early under the script's own `set -o pipefail` turns
  # imagemagick's resulting SIGPIPE into a 141 that aborts the whole run.
  _menu_card_bounds() {
    local png=$1 w h column
    w=$($convert_bin "$png" -format "%[fx:w]" info:)
    h=$($convert_bin "$png" -format "%[fx:h]" info:)
    column=$($convert_bin "$png" -crop "1x$((h - 60))+$((w / 2))+60" +repage txt:- 2>/dev/null)
    awk -F'[:#]' -v off=60 -v screen="$h" '
      NR == 2 { bg = substr($3, 1, 6); next }
      NR > 2 && substr($3, 1, 6) != bg {
        split($1, p, ",")
        if (top == "") top = p[2] + off
        bottom = p[2] + off
      }
      END { if (top == "") exit 1; print top, bottom, screen }' <<< "$column"
  }
  # Centred to within a pixel of rounding: the gap above the card equals the
  # gap below it. This is the assertion that actually discriminates, because
  # it is a property of where the card sits RIGHT NOW rather than a
  # comparison against an earlier frame — a top frozen for one row count
  # cannot stay centred once the row count moves.
  _menu_card_centred() {
    local top=$1 bottom=$2 screen=$3 above below
    above=$top
    below=$((screen - 1 - bottom))
    [ $(( above > below ? above - below : below - above )) -le 2 ]
  }
  for _png in "$menu_top_before_png" "$menu_top_after_png" "$menu_top_relevel_png"; do
    if [ ! -s "$_png" ]; then
      echo "SMOKE_FAIL: no menu card-top screenshot produced at $_png" >&2
      exit 1
    fi
  done
  # A dithered wallpaper defeats this measurement outright, so --wallpaper
  # --menu captures the three PNGs without asserting on them. _menu_card_bounds
  # takes ONE pixel as "the background" and reads every pixel differing from it
  # as a card edge; wallpaper.dither (M23) makes nearly every row of the centre
  # column differ, so the scan returns the whole screen and the resting card
  # reads as wildly off-centre (top 63px, bottom 689px of 693px — observed
  # 2026-08-12, identical across runs, while the same leg without a wallpaper
  # measures the card at 141px and passes). Skipping where the measurement is
  # invalid is not the same as weakening it: every --menu leg that is not also
  # a --wallpaper leg still asserts the full freeze/release/clamp sequence, and
  # that is the leg the check was written against. The combined run exists to
  # screenshot the menu over matugen-recoloured colours (CLAUDE.md), not to
  # measure geometry.
  if $wallpaper_mode; then
    echo "SMOKE_MENU_TOP_BEFORE $menu_top_before_png (bounds not asserted: a dithered wallpaper defeats the centre-column scan)"
    echo "SMOKE_MENU_TOP_AFTER $menu_top_after_png (bounds not asserted: a dithered wallpaper defeats the centre-column scan)"
    echo "SMOKE_MENU_TOP_RELEVEL $menu_top_relevel_png (bounds not asserted: a dithered wallpaper defeats the centre-column scan)"
  else
  read -r before_top before_bottom before_screen <<< "$(_menu_card_bounds "$menu_top_before_png")"
  read -r after_top after_bottom after_screen <<< "$(_menu_card_bounds "$menu_top_after_png")"
  read -r relevel_top relevel_bottom relevel_screen <<< "$(_menu_card_bounds "$menu_top_relevel_png")"
  if [ -z "$before_top" ] || [ -z "$after_top" ] || [ -z "$relevel_top" ]; then
    echo "SMOKE_FAIL: could not read the menu card's edges out of one of the three PNGs (before=$before_top after=$after_top relevel=$relevel_top)" >&2
    exit 1
  fi
  # At rest: centred on the output.
  if ! _menu_card_centred "$before_top" "$before_bottom" "$before_screen"; then
    echo "SMOKE_FAIL: the resting card isn't centred (top ${before_top}px, bottom ${before_bottom}px of ${before_screen}px)" >&2
    exit 1
  fi
  # Frozen: filtering twelve rows down to one must not move the top edge,
  # which also means the card is deliberately NOT centred in this frame.
  if [ "$after_top" -ne "$before_top" ]; then
    echo "SMOKE_FAIL: the card's top moved while filtering (before ${before_top}px, after ${after_top}px) — the top freeze isn't holding" >&2
    exit 1
  fi
  if _menu_card_centred "$after_top" "$after_bottom" "$after_screen"; then
    echo "SMOKE_FAIL: the filtered card is still centred (top ${after_top}px, bottom ${after_bottom}px) — the row count dropped to one, so this frame can only be centred if the freeze never engaged and this leg is proving nothing" >&2
    exit 1
  fi
  # Released: descending a level is a resting row set again, so the card
  # must be centred for the level it is now showing rather than stranded on
  # the top the one-row query froze it at.
  if [ "$relevel_top" -eq "$before_top" ]; then
    echo "SMOKE_FAIL: the card's top is unchanged at ${relevel_top}px after descending into WALLPAPER — the freeze latched instead of releasing" >&2
    exit 1
  fi
  if ! _menu_card_centred "$relevel_top" "$relevel_bottom" "$relevel_screen"; then
    echo "SMOKE_FAIL: the card didn't re-centre after descending into WALLPAPER (top ${relevel_top}px, bottom ${relevel_bottom}px of ${relevel_screen}px)" >&2
    exit 1
  fi
  # On screen: a card whose top has been pushed under the bar, or whose
  # bottom has run off the output, is the exact state the clamp exists for.
  for _bounds in "$before_top $before_bottom $before_screen" "$after_top $after_bottom $after_screen" "$relevel_top $relevel_bottom $relevel_screen"; do
    read -r _t _b _s <<< "$_bounds"
    if [ "$_t" -le 45 ] || [ "$_b" -ge "$_s" ]; then
      echo "SMOKE_FAIL: the card ran off the output (top ${_t}px, bottom ${_b}px of ${_s}px) — the on-screen clamp isn't holding" >&2
      exit 1
    fi
  done
  echo "SMOKE_MENU_TOP_BEFORE $menu_top_before_png (card ${before_top}-${before_bottom}px, centred)"
  echo "SMOKE_MENU_TOP_AFTER $menu_top_after_png (card ${after_top}-${after_bottom}px, top frozen and off-centre)"
  echo "SMOKE_MENU_TOP_RELEVEL $menu_top_relevel_png (card ${relevel_top}-${relevel_bottom}px, re-centred)"
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
  # Image leg (M14 Task 6): the watcher must have content-addressed the
  # fixture to the exact predicted path — this is the actual proof the
  # second wl-paste watcher captured, hashed, and stored the bytes, not just
  # that some entry with kind:"image" showed up.
  clip_image_expected_path="$iso_home/.local/state/formalshell/clipboard-images/$clip_image_fixture_sha.png"
  if [ -s "$clip_list3_path" ] && grep -qF '"kind":"image"' "$clip_list3_path" && grep -qF "\"path\":\"$clip_image_expected_path\"" "$clip_list3_path"; then
    cat "$clip_list3_path"
  else
    echo "SMOKE_FAIL: clipboard list did not show the captured image entry (kind:image, path=$clip_image_expected_path): $(cat "$clip_list3_path" 2>/dev/null)" >&2
    exit 1
  fi
  if [ -s "$clip_image_copy_path" ]; then
    cat "$clip_image_copy_path"
  else
    echo "SMOKE_FAIL: no clipboard copy result produced for the image entry" >&2; exit 1
  fi
  if ! grep -q "^ok$" "$clip_image_copy_path"; then
    echo "SMOKE_FAIL: clipboard copy IPC call on the image entry did not return ok — got: $(cat "$clip_image_copy_path")" >&2; exit 1
  fi
  # The wl-copy-back round trip: reading image/png off the system clipboard
  # must hash to exactly the fixture's own hash — proves copy() actually
  # streamed the stored file's real bytes back, not a placeholder.
  clip_image_paste_sha=$(awk '{print $1}' "$clip_image_paste_sha_path" 2>/dev/null)
  if [ "$clip_image_paste_sha" = "$clip_image_fixture_sha" ]; then
    echo "SMOKE_CLIPBOARD_IMAGE $clip_image_paste_sha (matches fixture)"
  else
    echo "SMOKE_FAIL: wl-paste --type image/png readback hash ($clip_image_paste_sha) does not match the fixture's hash ($clip_image_fixture_sha)" >&2
    exit 1
  fi
fi

if $wifi_mode; then
  # Both hostapd fixture radios must have surfaced in a real scan before
  # anything else in this leg means anything.
  if [ -s "$wifi_scan_status_path" ] && grep -qF '"name":"FORMALTEST"' "$wifi_scan_status_path" && grep -qF '"name":"FORMALTEST-EAP"' "$wifi_scan_status_path"; then
    cat "$wifi_scan_status_path"
  else
    echo "SMOKE_FAIL: FORMALTEST/FORMALTEST-EAP never surfaced in a wifi scan" >&2
    [ -f "$wifi_scan_status_path" ] && cat "$wifi_scan_status_path" >&2
    exit 1
  fi
  # Wrong password: NetworkManager must have genuinely given up (settled
  # disconnected, not still mid-retry) before this run's own screenshot can
  # be trusted as the failure state, not a lucky mid-flight capture.
  if [ -s "$wifi_wrong_status_path" ] && grep -qE '"name":"FORMALTEST","known":(true|false),"connected":false,"stateChanging":false' "$wifi_wrong_status_path"; then
    cat "$wifi_wrong_status_path"
  else
    echo "SMOKE_FAIL: wrong-password connect never settled to a stable disconnected state within the poll budget" >&2
    [ -f "$wifi_wrong_status_path" ] && cat "$wifi_wrong_status_path" >&2
    exit 1
  fi
  if [ -f "$wifi_wrong_path" ]; then
    echo "SMOKE_WIFI_WRONG $wifi_wrong_path"
  else
    echo "SMOKE_FAIL: no wifi-wrong screenshot produced" >&2; exit 1
  fi
  # Real password: must reach a genuine connected:true, proving hostapd's
  # own DHCP-serving dnsmasq actually handed the station an address rather
  # than the panel stalling on a stateless timeout.
  if [ -s "$wifi_connected_status_path" ] && grep -qF '"name":"FORMALTEST","known":true,"connected":true' "$wifi_connected_status_path"; then
    cat "$wifi_connected_status_path"
  else
    echo "SMOKE_FAIL: real-password connect never reached connected:true within the poll budget" >&2
    [ -f "$wifi_connected_status_path" ] && cat "$wifi_connected_status_path" >&2
    exit 1
  fi
  if [ -f "$wifi_connected_path" ]; then
    echo "SMOKE_WIFI_CONNECTED $wifi_connected_path"
  else
    echo "SMOKE_FAIL: no wifi-connected screenshot produced" >&2; exit 1
  fi
  # Forget: the network must settle fully back to idle (known:false AND
  # stateChanging:false, not just known:false), since connectEap below
  # relies on the panel's own action bookkeeping having actually cleared.
  if [ -s "$wifi_forget_status_path" ] && grep -qE '"name":"FORMALTEST","known":false,"connected":false,"stateChanging":false' "$wifi_forget_status_path"; then
    cat "$wifi_forget_status_path"
  else
    echo "SMOKE_FAIL: forget did not settle FORMALTEST to known:false/stateChanging:false within the poll budget" >&2
    [ -f "$wifi_forget_status_path" ] && cat "$wifi_forget_status_path" >&2
    exit 1
  fi
  # Enterprise leg: hostapd's own integrated EAP server (PEAP/MSCHAPv2)
  # must accept the fixture identity/password and reach connected:true.
  if [ -s "$wifi_eap_status_path" ] && grep -qF '"name":"FORMALTEST-EAP","known":true,"connected":true' "$wifi_eap_status_path"; then
    cat "$wifi_eap_status_path"
  else
    echo "SMOKE_FAIL: connectEap never reached connected:true for FORMALTEST-EAP within the poll budget" >&2
    [ -f "$wifi_eap_status_path" ] && cat "$wifi_eap_status_path" >&2
    exit 1
  fi
  if [ -f "$wifi_eap_connected_path" ]; then
    echo "SMOKE_WIFI_EAP_CONNECTED $wifi_eap_connected_path"
  else
    echo "SMOKE_FAIL: no wifi-eap-connected screenshot produced" >&2; exit 1
  fi
  # Closing forget: FORMALTEST-EAP must not survive this run. A leftover
  # profile here is exactly what corrupts the VM's persistent NM state for
  # every run after this one.
  if [ -s "$wifi_eap_forget_status_path" ] && grep -qE '"name":"FORMALTEST-EAP","known":false,"connected":false,"stateChanging":false' "$wifi_eap_forget_status_path"; then
    cat "$wifi_eap_forget_status_path"
  else
    echo "SMOKE_FAIL: closing forget did not settle FORMALTEST-EAP to known:false/stateChanging:false within the poll budget" >&2
    [ -f "$wifi_eap_forget_status_path" ] && cat "$wifi_eap_forget_status_path" >&2
    exit 1
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
  # M16 Task 11: the marquee's own two-state proof. The static shot lands
  # while the short fixture title (confirmed non-overflowing above) is
  # still playing; media_status_long_path confirms the retitle to the
  # deliberately long fixture actually landed before the scroll shot is
  # trusted as evidence of the marquee, not a stale static frame.
  if [ -f "$media_marquee_static_path" ]; then
    echo "SMOKE_MEDIA_MARQUEE_STATIC $media_marquee_static_path"
  else
    echo "SMOKE_FAIL: no media-marquee-static screenshot produced" >&2; exit 1
  fi
  if [ -s "$media_status_long_path" ]; then
    cat "$media_status_long_path"
  else
    echo "SMOKE_FAIL: no media status produced after the marquee retitle" >&2; exit 1
  fi
  if ! grep -q "\"title\":\"$media_track_title_long\"" "$media_status_long_path"; then
    echo "SMOKE_FAIL: media status after retitle does not show the long overflow title ($media_track_title_long) — got: $(cat "$media_status_long_path")" >&2; exit 1
  fi
  if [ -f "$media_marquee_scroll_path" ]; then
    echo "SMOKE_MEDIA_MARQUEE_SCROLL $media_marquee_scroll_path"
  else
    echo "SMOKE_FAIL: no media-marquee-scroll screenshot produced" >&2; exit 1
  fi
  # --media --panel audio (M15 Task 4): media_status_path above already
  # proves mpv's stream is real and playing; this proves the audio panel
  # itself is what the screenshot shows (not the media panel that also
  # opened during this run) — the APPS row inside it is Read from the PNG,
  # same as every other panel screenshot in this rig.
  if $panel_mode && [ "$panel_name" = "audio" ]; then
    if [ -f "$audio_panel_path" ]; then
      echo "SMOKE_AUDIO_PANEL $audio_panel_path"
    else
      echo "SMOKE_FAIL: no audio-panel screenshot produced" >&2; exit 1
    fi
  fi
fi

if $visualizer_mode; then
  # Process-level proof, same idiom as share_mode's own localsend_app
  # pgrep evidence: VisualizerService.qml owns a real `cava` child process,
  # not something an IPC call can introspect, so pgrep from outside is the
  # actual verification, not a screenshot.
  if [ -s "$visualizer_pgrep_playing_path" ]; then
    cat "$visualizer_pgrep_playing_path"
  else
    echo "SMOKE_FAIL: cava never appeared while the visualizer smoke tone was playing — pgrep output: $(cat "$visualizer_pgrep_playing_path" 2>/dev/null)" >&2; exit 1
  fi
  # DESIGN.md §4 rule 8's hard gate: the process must be gone once
  # playback stops, not just paused-looking. An empty (or absent) pgrep
  # file after visualizer-drive.sh's own post-kill poll is the honest
  # positive result here.
  if [ -s "$visualizer_pgrep_after_path" ]; then
    echo "SMOKE_FAIL: cava is still running after mpv was killed — pgrep output: $(cat "$visualizer_pgrep_after_path")" >&2; exit 1
  fi
  echo "SMOKE_VISUALIZER_CAVA_KILLED_AFTER_PAUSE ok"
  if [ -f "$visualizer_playing_path" ]; then
    echo "SMOKE_VISUALIZER_PLAYING $visualizer_playing_path"
  else
    echo "SMOKE_FAIL: no visualizer-playing screenshot produced" >&2; exit 1
  fi
fi

# The gallery has no on-screen state anything else asserts, so the IPC
# replies are the proof the route ran at all: `show` must answer ok and
# `status` must report isOpen true by the time the screenshot is taken.
if $gallery_mode; then
  echo "SMOKE_GALLERY_IPC $(tr '\n' ' ' < "$gallery_log_path" 2>/dev/null || echo '(no reply)')"
  if ! grep -q '"isOpen":true' "$gallery_log_path" 2>/dev/null; then
    echo "SMOKE_FAIL: gallery did not report isOpen after show — $(cat "$gallery_log_path" 2>/dev/null)" >&2; exit 1
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
  if [ -f "$lock_typing_path" ]; then
    echo "SMOKE_LOCK_TYPING $lock_typing_path"
  else
    echo "SMOKE_FAIL: no lock-typing screenshot produced" >&2; exit 1
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

if $polkit_mode; then
  if [ -f "$polkit_active_path" ]; then
    echo "SMOKE_POLKIT_ACTIVE $polkit_active_path"
  else
    echo "SMOKE_FAIL: no polkit-active screenshot produced" >&2; exit 1
  fi
  if [ -f "$polkit_error_path" ]; then
    echo "SMOKE_POLKIT_ERROR $polkit_error_path"
  else
    echo "SMOKE_FAIL: no polkit-error screenshot produced" >&2; exit 1
  fi
  if [ -s "$polkit_rc_path" ] && grep -q "^0$" "$polkit_rc_path"; then
    :
  else
    echo "SMOKE_FAIL: pkexec true did not exit 0 after real authentication — got: $(cat "$polkit_rc_path" 2>/dev/null); stderr: $(cat "$shot_dir/polkit-stderr.txt" 2>/dev/null); debug: $(cat "$shot_dir/polkit-debug.log" 2>/dev/null)" >&2; exit 1
  fi
fi

if $hotcorner_mode; then
  if [ ! -s "$hotcorner_layers_path" ]; then
    echo "SMOKE_FAIL: no niri layer dump produced for the hot corners" >&2; exit 1
  fi
  cat "$hotcorner_layers_path"
  hotcorner_count=$(grep -o 'formalshell:hotcorner' "$hotcorner_layers_path" | wc -l | tr -d ' ')
  # Two, not four: shell/HotCorners/corners.js leaves both TOP corners at
  # "none" by default (the bar owns that edge), and this run writes no
  # `hotCorners` config at all — so the count doubles as proof that a corner
  # set to "none" costs no surface rather than a mapped-but-inert one.
  if [ "$hotcorner_count" != "2" ]; then
    echo "SMOKE_FAIL: expected 2 formalshell:hotcorner layer surfaces, found $hotcorner_count" >&2; exit 1
  fi
  echo "SMOKE_HOTCORNER_LAYERS $hotcorner_layers_path"
fi

if $nightlight_mode; then
  if [ -f "$nightlight_active_path" ]; then
    echo "SMOKE_NIGHTLIGHT_ACTIVE $nightlight_active_path"
  else
    echo "SMOKE_FAIL: no nightlight-active screenshot produced" >&2; exit 1
  fi
  if [ -s "$nightlight_status1_path" ]; then
    cat "$nightlight_status1_path"
  else
    echo "SMOKE_FAIL: no nightlight status produced after enable" >&2; exit 1
  fi
  # Honest bifurcation (plan wording): a nested niri whose winit backend
  # lacks wlr-gamma-control-unstable-v1 makes wlsunset exit immediately,
  # which is the correctly-surfaced failure path, not a bug —
  # active:false WITH a populated lastError is exactly as real a pass as
  # active:true. active:false with an EMPTY lastError is the one shape
  # that's never acceptable: a silent no-op.
  if grep -qF '"active":true' "$nightlight_status1_path"; then
    echo "nightlight: reached active:true — nested niri supports wlr-gamma-control-unstable-v1"
  elif grep -qF '"active":false' "$nightlight_status1_path" && ! grep -qF '"lastError":""' "$nightlight_status1_path"; then
    echo "nightlight: honest failure surface (active:false, lastError populated) — nested niri likely lacks wlr-gamma-control-unstable-v1"
  else
    echo "SMOKE_FAIL: nightlight enable produced neither active:true nor an honest lastError — got: $(cat "$nightlight_status1_path")" >&2; exit 1
  fi
  if [ -s "$nightlight_status2_path" ] && grep -qF '"active":false' "$nightlight_status2_path"; then
    cat "$nightlight_status2_path"
  else
    echo "SMOKE_FAIL: nightlight disable did not confirm active:false — got: $(cat "$nightlight_status2_path" 2>/dev/null)" >&2; exit 1
  fi
fi

if $speedtest_mode; then
  if [ -f "$speedtest_panel_path" ]; then
    echo "SMOKE_SPEEDTEST_PANEL $speedtest_panel_path"
  else
    echo "SMOKE_FAIL: no speedtest-panel screenshot produced" >&2; exit 1
  fi
  if [ -s "$speedtest_status_path" ]; then
    cat "$speedtest_status_path"
  else
    echo "SMOKE_FAIL: no network speedstatus produced" >&2; exit 1
  fi
  # Honest bifurcation, same shape as --nightlight: "done" with real numbers
  # is the expected path (the VM's virtio NIC has real NAT internet access),
  # but an honest NO NETWORK/NO CURL abort (also settling to "done") is
  # equally real evidence; only a poll ceiling with neither is a failure.
  if grep -qF '"phase":"done"' "$speedtest_status_path"; then
    if grep -qF '"error":""' "$speedtest_status_path"; then
      echo "speedtest: reached done with a real measurement"
    else
      echo "speedtest: reached done via an honest failure surface"
    fi
  else
    echo "SMOKE_FAIL: speed test never reached phase:done, got: $(cat "$speedtest_status_path")" >&2; exit 1
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
  # M16 Task 12: the pre-open/open/post-close Rss samples, scripted this
  # time — 20 fixtures at 1920x1080 (bigger than the grid's decode cap and
  # past glibc's mmap_threshold, so freed pages are actually returned to the
  # OS, not just retained in an arena) give a real signal instead of noise.
  # post-close samples 20s after close(), not a couple: measured on this rig
  # (2026-08-03), Rss sat flat for 8s after close then dropped ~37MB in the
  # next 10s once the QML engine's own idle-driven GC cycle actually ran —
  # sampling early reads as a leak that isn't one. Three checks: open must
  # exceed pre-open (proves a real decode happened, not a no-op on
  # undersized fixtures), post-close must drop below open (proves close()
  # freed something), and post-close must land within 40MB of pre-open
  # (proves it actually came back down, not just down-from-peak) — 40MB
  # against an observed ~6.5MB steady-state gap is slack for GC-timing
  # jitter, not for a real leak.
  # Dark/Light variants. The flat dump first: with no subdirectory pair, the
  # route lists the directory itself and raises no switcher — every setup that
  # doesn't use variants must keep behaving exactly this way.
  if [ ! -s "$picker_flat_status_path" ]; then
    echo "SMOKE_FAIL: no flat picker status produced" >&2; exit 1
  fi
  cat "$picker_flat_status_path"
  if ! grep -q '"hasVariants":false' "$picker_flat_status_path" \
    || ! grep -q '"variant":"none"' "$picker_flat_status_path" \
    || ! grep -q '"count":20' "$picker_flat_status_path"; then
    echo "SMOKE_FAIL: the flat listing did not report all 20 images with no variants — got: $(cat "$picker_flat_status_path")" >&2; exit 1
  fi
  # Then the same directory with the pair moved in underneath the running
  # shell: hasVariants, entered on the theme's own mode (dark in this
  # session), listing only that set.
  if [ ! -s "$picker_dark_status_path" ]; then
    echo "SMOKE_FAIL: no dark-variant picker status produced" >&2; exit 1
  fi
  cat "$picker_dark_status_path"
  if ! grep -q '"hasVariants":true' "$picker_dark_status_path" \
    || ! grep -q '"variant":"dark"' "$picker_dark_status_path" \
    || ! grep -q '"darkCount":5' "$picker_dark_status_path" \
    || ! grep -q '"lightCount":3' "$picker_dark_status_path" \
    || ! grep -q '"count":5' "$picker_dark_status_path"; then
    echo "SMOKE_FAIL: the variant listing did not report the dark set on entry — got: $(cat "$picker_dark_status_path")" >&2; exit 1
  fi
  if ! grep -qx 'ok' "$picker_variant_reply_path" 2>/dev/null; then
    echo "SMOKE_FAIL: picker variant light was refused — got: $(cat "$picker_variant_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ ! -s "$picker_light_status_path" ]; then
    echo "SMOKE_FAIL: no light-variant picker status produced" >&2; exit 1
  fi
  cat "$picker_light_status_path"
  if ! grep -q '"variant":"light"' "$picker_light_status_path" \
    || ! grep -q '"count":3' "$picker_light_status_path"; then
    echo "SMOKE_FAIL: the switcher did not swap the listing to the light set — got: $(cat "$picker_light_status_path")" >&2; exit 1
  fi
  if [ -f "$picker_variant_path" ]; then
    echo "SMOKE_PICKER_VARIANT $picker_variant_path"
  else
    echo "SMOKE_FAIL: no picker-variant screenshot produced" >&2; exit 1
  fi
  if [ -s "$picker_mem_path" ]; then
    echo "SMOKE_PICKER_MEM $picker_mem_path"
    cat "$picker_mem_path"
    picker_rss_pre=$(grep -o '"rssKb":[0-9]*' "$picker_mem_path" | sed -n '1p' | cut -d: -f2)
    picker_rss_open=$(grep -o '"rssKb":[0-9]*' "$picker_mem_path" | sed -n '2p' | cut -d: -f2)
    picker_rss_close=$(grep -o '"rssKb":[0-9]*' "$picker_mem_path" | sed -n '3p' | cut -d: -f2)
    if [ -z "$picker_rss_pre" ] || [ -z "$picker_rss_open" ] || [ -z "$picker_rss_close" ]; then
      echo "SMOKE_FAIL: picker-memory.json missing an Rss sample (shell pid not found?) — got: $(cat "$picker_mem_path")" >&2; exit 1
    fi
    if [ "$picker_rss_open" -le "$picker_rss_pre" ]; then
      echo "SMOKE_FAIL: picker open-state Rss ($picker_rss_open KB) didn't grow over pre-open ($picker_rss_pre KB) — fixtures too small to prove a decode happened" >&2; exit 1
    fi
    if [ "$picker_rss_close" -ge "$picker_rss_open" ]; then
      echo "SMOKE_FAIL: picker post-close Rss ($picker_rss_close KB) did not drop below open-state Rss ($picker_rss_open KB) — the menu's _leavePickerRoute() isn't freeing the grid's decodes" >&2; exit 1
    fi
    if [ $((picker_rss_close - picker_rss_pre)) -gt 40000 ]; then
      echo "SMOKE_FAIL: picker post-close Rss ($picker_rss_close KB) is more than 40MB above pre-open ($picker_rss_pre KB) even after the GC settle window — looks like a real leak, not GC timing" >&2; exit 1
    fi
  else
    echo "SMOKE_FAIL: no picker-memory.json produced" >&2; exit 1
  fi
fi

if $tray_mode; then
  if [ -s "$tray_status_path" ]; then
    cat "$tray_status_path"
  else
    echo "SMOKE_FAIL: no tray status produced" >&2; exit 1
  fi
  tray_count=$(grep -o '"id":' "$tray_status_path" | wc -l | tr -d ' ')
  if [ "$tray_count" != "6" ]; then
    echo "SMOKE_FAIL: tray status did not report all 6 fixture items (got $tray_count). Stub registration likely failed" >&2; exit 1
  fi
  # M24: no drawer, so nothing here may report one. A `drawer`/`expanded` key
  # coming back would mean a stale build, not a passing run.
  if grep -qE '"(drawer|expanded|pinned|bucket)":' "$tray_status_path"; then
    echo "SMOKE_FAIL: tray status still reports drawer/bucket state. Got: $(cat "$tray_status_path")" >&2; exit 1
  fi
  if [ -f "$tray_strip_path" ]; then
    echo "SMOKE_TRAY_STRIP $tray_strip_path"
  else
    echo "SMOKE_FAIL: no tray-strip screenshot produced" >&2; exit 1
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

if $chevron_mode; then
  # The five names bar_settings above put before the chevron (M25: a
  # right-region chevron governs inward, away from the screen edge). Order
  # matters: `collapses` reports them in layout order, so one grep can assert
  # the whole boundary rather than five independent membership checks.
  chevron_hidden_names='"bluetooth","weather","tray","bell","indicators"'
  if [ -s "$chevron_status_collapsed_path" ]; then
    cat "$chevron_status_collapsed_path"
  else
    echo "SMOKE_FAIL: no bar chevron status (collapsed) produced" >&2; exit 1
  fi
  if ! grep -q '"chevronRegions":\["right"\]' "$chevron_status_collapsed_path"; then
    echo "SMOKE_FAIL: bar chevron status did not resolve exactly one chevron, in the right region. Got: $(cat "$chevron_status_collapsed_path")" >&2; exit 1
  fi
  if ! grep -q "\"collapses\":\[$chevron_hidden_names\]" "$chevron_status_collapsed_path"; then
    echo "SMOKE_FAIL: bar chevron status does not govern the five names placed before it. Got: $(cat "$chevron_status_collapsed_path")" >&2; exit 1
  fi
  # The claim the screenshot alone cannot make: collapsed means those exact
  # names are hidden right now, not merely that the chevron knows about them.
  if ! grep -q "\"collapsed\":true,\"collapses\":\[$chevron_hidden_names\],\"hidden\":\[$chevron_hidden_names\]" "$chevron_status_collapsed_path"; then
    echo "SMOKE_FAIL: bar chevron status did not report the governed names as hidden while collapsed. Got: $(cat "$chevron_status_collapsed_path")" >&2; exit 1
  fi
  if [ -f "$chevron_collapsed_path" ]; then
    # Named-artifact marker: dev/vm.sh pulls every "SMOKE_<NAME> <path>.png"
    # line back to the mac, and without one the shot only ever exists inside
    # the VM.
    echo "SMOKE_CHEVRON_COLLAPSED $chevron_collapsed_path"
  else
    echo "SMOKE_FAIL: no chevron-collapsed screenshot produced" >&2; exit 1
  fi
  if ! grep -q '^ok$' "$chevron_expand_reply_path" 2>/dev/null; then
    echo "SMOKE_FAIL: bar chevron expand was refused. Got: $(cat "$chevron_expand_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ -s "$chevron_status_expanded_path" ]; then
    cat "$chevron_status_expanded_path"
  else
    echo "SMOKE_FAIL: no bar chevron status (expanded) produced" >&2; exit 1
  fi
  # Same five names, still governed, none of them hidden any more. An empty
  # `collapses` here would mean the layout changed under the run rather than
  # the state.
  if ! grep -q "\"collapsed\":false,\"collapses\":\[$chevron_hidden_names\],\"hidden\":\[\]" "$chevron_status_expanded_path"; then
    echo "SMOKE_FAIL: bar chevron expand did not clear the hidden set while keeping the same governed names. Got: $(cat "$chevron_status_expanded_path")" >&2; exit 1
  fi
  if [ -f "$chevron_expanded_path" ]; then
    echo "SMOKE_CHEVRON_EXPANDED $chevron_expanded_path"
  else
    echo "SMOKE_FAIL: no chevron-expanded screenshot produced" >&2; exit 1
  fi
  # The one assertion the status dumps cannot make: something on screen
  # actually changed. M24 shipped a correct IPC contract over a bar whose
  # governed cells never moved (the QtQuick `State` collision), and these two
  # frames were byte-identical the whole time with every dump passing.
  if cmp -s "$chevron_collapsed_path" "$chevron_expanded_path"; then
    echo "SMOKE_FAIL: chevron-collapsed and chevron-expanded screenshots are byte-identical: the expand changed the state but rendered nothing" >&2; exit 1
  fi
fi

# --panel-keys (M26 Task 8): reports the two screenshots panel-keys-drive.sh
# produced (generation lives beside chevron_drive_script, well before the
# session starts — see the `if $panel_keys_mode` block near
# panel_keys_baseline_path's declaration) for a human to read. No pixel-diff
# gate here on purpose: this VM's bar redraws something (a clock digit, an
# animated glyph) on almost every 1-2s window regardless of panel state, so
# a plain `cmp` between two frames a few hundred ms apart would report
# "differ" whether or not the OUTPUT slider row actually lit up — a diff
# that always fires proves nothing either way. What the two frames need is
# the eyes CLAUDE.md asks for, not a byte comparison; the drive script's own
# header comment records what four independently-timed probes here already
# found (the rig's wtype route into an IPC-opened, no-antecedent-click
# Panel.qml surface is racy — one lone Escape landed, no Down/Down/Return
# variant since did) as the honest failure output the plan's Task 8 asks
# for in that case, rather than a screenshot claimed to prove a path that
# does not reliably work in this rig.
if $panel_keys_mode; then
  if [ -f "$panel_keys_baseline_path" ]; then
    echo "SMOKE_PANEL_KEYS_BASELINE $panel_keys_baseline_path"
  else
    echo "SMOKE_FAIL: no panel-keys-baseline screenshot produced" >&2; exit 1
  fi
  if [ -f "$panel_keys_path" ]; then
    echo "SMOKE_PANEL_KEYS $panel_keys_path"
  else
    echo "SMOKE_FAIL: no panel-keys screenshot produced" >&2; exit 1
  fi
fi

if $instance_mode; then
  if [ -s "$instance_status_path" ]; then
    cat "$instance_status_path"
  else
    echo "SMOKE_FAIL: no instance-status.json produced — the second daemon may never have launched" >&2; exit 1
  fi
  instance_old=$(grep -o '"oldPid":[A-Za-z0-9]*' "$instance_status_path" | cut -d: -f2)
  instance_new=$(grep -o '"newPid":[A-Za-z0-9]*' "$instance_status_path" | cut -d: -f2)
  instance_survivor=$(grep -o '"survivorPid":[A-Za-z0-9]*' "$instance_status_path" | cut -d: -f2)
  instance_final_count=$(grep -o '"finalCount":[0-9]*' "$instance_status_path" | cut -d: -f2)
  # The two instances' own log lines are always surfaced here, pass or fail —
  # a failure still needs to be loud about what each side actually logged,
  # not just that the pids didn't match.
  echo "-- instance-primary.log (instance lock lines) --"
  grep "instance lock" "$instance_primary_log_path" 2>/dev/null || echo "(none found)"
  echo "-- instance-second.log (instance lock lines) --"
  grep "instance lock" "$instance_second_log_path" 2>/dev/null || echo "(none found)"
  if [ "$instance_old" = "null" ] || [ -z "$instance_old" ]; then
    echo "SMOKE_FAIL: no live primary instance was found before the second launch — the takeover path was never exercised" >&2; exit 1
  fi
  if [ "$instance_final_count" != "1" ]; then
    echo "SMOKE_FAIL: expected exactly one surviving daemon after the takeover poll, got $instance_final_count" >&2; exit 1
  fi
  if [ -z "$instance_survivor" ] || [ "$instance_survivor" = "null" ]; then
    echo "SMOKE_FAIL: takeover poll settled on a count of 1 but recorded no survivor pid" >&2; exit 1
  fi
  if [ "$instance_survivor" != "$instance_new" ]; then
    echo "SMOKE_FAIL: survivor pid ($instance_survivor) is not the second instance's pid ($instance_new) — the old instance won the takeover instead of quitting" >&2; exit 1
  fi
  if ! grep -q "instance lock — being replaced" "$instance_primary_log_path" 2>/dev/null; then
    echo "SMOKE_FAIL: primary instance log never logged being replaced" >&2; exit 1
  fi
  if ! grep -q "instance lock — live instance found, requesting takeover" "$instance_second_log_path" 2>/dev/null; then
    echo "SMOKE_FAIL: second instance log never logged finding a live instance" >&2; exit 1
  fi
  if ! grep -q "instance lock — acquired at" "$instance_second_log_path" 2>/dev/null; then
    echo "SMOKE_FAIL: second instance log never logged acquiring the lock" >&2; exit 1
  fi
  echo "SMOKE_INSTANCE old=$instance_old new=$instance_new survivor=$instance_survivor"
fi

if $share_mode; then
  # Phase one: the present case. Two passes, both expected to already show
  # "share" resolved — not a "first pass must miss it" race: Menu.qml's
  # `defaultMenuFile.onLoaded` runs _evalConditions() once at shell startup
  # (long before this drive script's own sleeps), so every `when`-gated
  # node's condition is already settled well ahead of the first debug
  # query here. The second pass exists as redundant confirmation, not to
  # catch a still-pending state.
  for f in "$share_query1_path" "$share_query2_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no debug query produced at $f" >&2; exit 1
    fi
  done
  cat "$share_query1_path"; echo
  cat "$share_query2_path"; echo
  if ! grep -qF '"id":"share"' "$share_query1_path"; then
    echo "SMOKE_FAIL: first debug query never saw the share node present — got: $(cat "$share_query1_path")" >&2; exit 1
  fi
  if ! grep -qF '"id":"share"' "$share_query2_path"; then
    echo "SMOKE_FAIL: second debug query never saw the share node present — got: $(cat "$share_query2_path")" >&2; exit 1
  fi
  if [ -f "$share_menu_path" ]; then
    echo "SMOKE_SHARE_MENU $share_menu_path"
  else
    echo "SMOKE_FAIL: no share-menu screenshot produced" >&2; exit 1
  fi
  # The CLIPBOARD row's activation: a real `localsend_app <path>` process
  # whose final argv element is a mktemp .txt path (upstream's own arg
  # parser drops dash-flags and non-path text alike, so the fixture text
  # can only reach LocalSend as a real file) — that path's contents, read
  # back off disk by PID before the process is killed, must be the exact
  # fixture text, not just some string on argv.
  share_pid=$(head -n1 "$share_pgrep_path" 2>/dev/null)
  if [ -z "$share_pid" ]; then
    echo "SMOKE_FAIL: no localsend_app process ever appeared — pgrep output: $(cat "$share_pgrep_path" 2>/dev/null)" >&2; exit 1
  fi
  echo "SMOKE_SHARE_PID $share_pid"
  if [ -s "$share_cmdline_path" ]; then
    cat "$share_cmdline_path"; echo
  else
    echo "SMOKE_FAIL: could not read the launched process's /proc cmdline" >&2; exit 1
  fi
  if ! tail -n1 "$share_cmdline_path" | grep -qE '\.txt$'; then
    echo "SMOKE_FAIL: launched process argv did not end in a mktemp .txt path — got: $(cat "$share_cmdline_path" | tr '\n' ' ')" >&2; exit 1
  fi
  if [ -s "$share_tmpfile_path" ]; then
    cat "$share_tmpfile_path"; echo
  else
    echo "SMOKE_FAIL: could not read the shared temp file's contents off disk" >&2; exit 1
  fi
  if ! grep -qF "share smoke fixture" "$share_tmpfile_path"; then
    echo "SMOKE_FAIL: shared temp file did not contain the fixture text — got: $(cat "$share_tmpfile_path" | tr '\n' ' ')" >&2; exit 1
  fi
  # Phase two: the absent case, proven live through a second instance whose
  # PATH is genuinely scoped away from localsend_app (same takeover
  # protocol instance_mode's own block above already proves).
  if [ -s "$share_instance_status_path" ]; then
    cat "$share_instance_status_path"
  else
    echo "SMOKE_FAIL: no share-instance-status.json produced — the second daemon may never have launched" >&2; exit 1
  fi
  share_old=$(grep -o '"oldPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_new=$(grep -o '"newPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_survivor=$(grep -o '"survivorPid":[A-Za-z0-9]*' "$share_instance_status_path" | cut -d: -f2)
  share_final_count=$(grep -o '"finalCount":[0-9]*' "$share_instance_status_path" | cut -d: -f2)
  echo "-- share-primary.log (instance lock lines) --"
  grep "instance lock" "$share_primary_log_path" 2>/dev/null || echo "(none found)"
  echo "-- share-second.log (instance lock lines) --"
  grep "instance lock" "$share_second_log_path" 2>/dev/null || echo "(none found)"
  if [ "$share_old" = "null" ] || [ -z "$share_old" ]; then
    echo "SMOKE_FAIL: no live primary share instance was found before the second launch" >&2; exit 1
  fi
  if [ "$share_final_count" != "1" ] || [ "$share_survivor" != "$share_new" ]; then
    echo "SMOKE_FAIL: the shadowed-PATH instance did not win the takeover (finalCount=$share_final_count survivor=$share_survivor new=$share_new)" >&2; exit 1
  fi
  if ! grep -q "instance lock — being replaced" "$share_primary_log_path" 2>/dev/null; then
    echo "SMOKE_FAIL: primary share instance log never logged being replaced" >&2; exit 1
  fi
  for f in "$share_absent_query1_path" "$share_absent_query2_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no debug query produced at $f" >&2; exit 1
    fi
  done
  cat "$share_absent_query1_path"; echo
  cat "$share_absent_query2_path"; echo
  # Exact "share" id, AND the "share." prefix a leaked child row (e.g.
  # "share.clipboard") would carry (M17 review finding, item F: a summoned
  # route used to render its actionable children even with its own `when`
  # gate false) — hardened past the exact-id-only check this replaced.
  if grep -qF '"id":"share"' "$share_absent_query1_path" || grep -qF '"id":"share"' "$share_absent_query2_path" \
    || grep -qF '"id":"share.' "$share_absent_query1_path" || grep -qF '"id":"share.' "$share_absent_query2_path"; then
    echo "SMOKE_FAIL: share node (or one of its children) was still visible with localsend_app shadowed off PATH" >&2; exit 1
  fi
  if [ -f "$share_menu_absent_path" ]; then
    echo "SMOKE_SHARE_MENU_ABSENT $share_menu_absent_path"
  else
    echo "SMOKE_FAIL: no share-menu-absent screenshot produced" >&2; exit 1
  fi
fi

if $bar_layout_mode; then
  if [ -f "$bar_layout_path" ]; then
    echo "SMOKE_BAR_LAYOUT $bar_layout_path"
  else
    echo "SMOKE_FAIL: no bar-layout screenshot produced" >&2; exit 1
  fi
fi

if $capture_mode; then
  for f in "$capture_open_status_path" "$capture_cycled_status_path" "$capture_status_path" "$capture_escape_status_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no capture status produced at $f" >&2; exit 1
    fi
  done
  cat "$capture_open_status_path"; echo
  if ! grep -q '"open":true' "$capture_open_status_path"; then
    echo "SMOKE_FAIL: picker did not report open after 'screenshot pick smart': $(cat "$capture_open_status_path")" >&2; exit 1
  fi
  if [ ! -f "$capture_picker_path" ]; then
    echo "SMOKE_FAIL: no picker screenshot produced at $capture_picker_path" >&2; exit 1
  fi

  # The load-bearing assertion of this whole leg. The session holds exactly
  # one real tiled foot window, and a tiled niri window reports no rectangle
  # (src/layout/tile.rs:869 versus floating.rs:336), so it MUST arrive as a
  # named window rather than a drawable one. Asserting the positive count
  # is the point: a leg that merely found zero window hints would pass
  # identically against a picker that had never enumerated windows at all.
  capture_named=$(sed -n 's/.*"namedWindows":\([0-9]*\).*/\1/p' "$capture_open_status_path")
  if [ -z "$capture_named" ] || [ "$capture_named" -lt 1 ]; then
    echo "SMOKE_FAIL: picker reported no named windows under nested niri, so the tiled-window path was never exercised: $(cat "$capture_open_status_path")" >&2; exit 1
  fi
  echo "SMOKE_CAPTURE_NAMED $capture_named named window(s), $(sed -n 's/.*"drawableWindows":\([0-9]*\).*/\1/p' "$capture_open_status_path") drawable — the expected niri split"

  cat "$capture_cycled_status_path"; echo
  capture_cursor=$(sed -n 's/.*"cursor":\(-\{0,1\}[0-9]*\).*/\1/p' "$capture_cycled_status_path")
  if [ -z "$capture_cursor" ] || [ "$capture_cursor" -lt 0 ]; then
    echo "SMOKE_FAIL: TAB did not move the picker cursor off its pointer-driven default: $(cat "$capture_cycled_status_path")" >&2; exit 1
  fi
  if ! grep -q '"selectionLabel":"[^"]' "$capture_cycled_status_path"; then
    echo "SMOKE_FAIL: cycled selection carried no label, so the named-window row had nothing to render: $(cat "$capture_cycled_status_path")" >&2; exit 1
  fi

  if ! grep -q '^ok$' "$capture_pick_reply_path"; then
    echo "SMOKE_FAIL: CTRL+RETURN did not commit a selection — got: $(cat "$capture_pick_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  if ! grep -q '"capturing":false' "$capture_status_path" || ! grep -q '"lastError":""' "$capture_status_path"; then
    echo "SMOKE_FAIL: capture did not settle clean: $(cat "$capture_status_path")" >&2; exit 1
  fi
  capture_file=$(sed -n 's/.*"lastPath":"\([^"]*\)".*/\1/p' "$capture_status_path")
  if [ -z "$capture_file" ] || [ ! -f "$capture_file" ]; then
    echo "SMOKE_FAIL: capture reported no existing file, lastPath was '$capture_file': $(cat "$capture_status_path")" >&2; exit 1
  fi
  if ! "$file_bin" "$capture_file" | grep -q "PNG image data"; then
    echo "SMOKE_FAIL: capture is not a valid PNG, file(1) says: $("$file_bin" -b "$capture_file")" >&2; exit 1
  fi

  # Ctrl+Return takes the whole display, so the PNG must be exactly the
  # output's size. Proves the capture cropped to the intended rectangle
  # rather than to whatever grim felt like.
  capture_dims=$("$file_bin" -b "$capture_file" | sed -n 's/.*PNG image data, \([0-9]*\) x \([0-9]*\).*/\1x\2/p')
  capture_out_dims=$(sed -n 's/.*"width":\([0-9]*\),"height":\([0-9]*\).*/\1x\2/p' "$capture_outputs_path" | head -n1)
  if [ -n "$capture_out_dims" ] && [ "$capture_dims" != "$capture_out_dims" ]; then
    echo "SMOKE_FAIL: CTRL+RETURN captured ${capture_dims}, but the output is ${capture_out_dims}" >&2; exit 1
  fi
  echo "SMOKE_CAPTURE $capture_file (${capture_dims}, matches the output)"

  # The toolbar's record half, end to end: `key 4` selects the REC SCREEN cell
  # (setTool, the exact function a click on it calls), Return commits it, and
  # what comes out the far side is a real wf-recorder child writing a real mp4.
  for f in "$capture_tool_status_path" "$capture_rec_reply_path" \
    "$capture_rec_status_path" "$capture_rec_stopped_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no capture toolbar artifact produced at $f" >&2; exit 1
    fi
  done
  cat "$capture_tool_status_path"; echo
  if ! grep -qF '"action":"record"' "$capture_tool_status_path" \
    || ! grep -qF '"tool":3' "$capture_tool_status_path" \
    || ! grep -qF '"mode":"fullscreen"' "$capture_tool_status_path"; then
    echo "SMOKE_FAIL: the REC SCREEN toolbar cell did not take: $(cat "$capture_tool_status_path")" >&2; exit 1
  fi
  # SCREEN preselects the focused output, so the commit has something to act on
  # with no pointer anywhere near the surface. A -1 cursor here means the
  # toolbar switched mode and left nothing selected.
  capture_tool_cursor=$(sed -n 's/.*"cursor":\(-\{0,1\}[0-9]*\).*/\1/p' "$capture_tool_status_path")
  if [ -z "$capture_tool_cursor" ] || [ "$capture_tool_cursor" -lt 0 ]; then
    echo "SMOKE_FAIL: REC SCREEN left nothing selected: $(cat "$capture_tool_status_path")" >&2; exit 1
  fi
  if [ ! -f "$capture_toolbar_path" ]; then
    echo "SMOKE_FAIL: no toolbar screenshot produced at $capture_toolbar_path" >&2; exit 1
  fi
  if ! grep -q '^ok$' "$capture_rec_reply_path"; then
    echo "SMOKE_FAIL: RETURN did not commit the record tool — got: $(cat "$capture_rec_reply_path" 2>/dev/null)" >&2; exit 1
  fi

  echo "SMOKE_CAPTURE_TOOLBAR $capture_toolbar_path"

  # Where this leg stops is where the environment stops, and it says which.
  # wf-recorder cannot run in this rig at all: nested niri under llvmpipe
  # advertises zwp_linux_dmabuf_v1 at version 3 and wf-recorder 0.6.0 binds
  # version 4 unconditionally, so the registry bind is rejected before any
  # recording option matters — `recording.noDmabuf` disables the capture path,
  # not the bind. docs/SWITCHOVER.md records the same block against the
  # --record leg.
  #
  # Everything the SHELL owns is still proven either way: the toolbar switched
  # tools, the commit was accepted, and a wf-recorder child was spawned
  # carrying this run's own output name on its argv (which is why its stderr
  # names that output). A blocked run therefore has to show a real recorder
  # error — an empty lastError would mean nothing was ever launched, which is a
  # failure of the handoff and is treated as one.
  cat "$capture_rec_status_path"; echo
  if grep -qF '"active":true' "$capture_rec_status_path"; then
    cat "$capture_rec_stopped_path"; echo
    if ! grep -qF '"active":false' "$capture_rec_stopped_path" || ! grep -qF '"lastError":""' "$capture_rec_stopped_path"; then
      echo "SMOKE_FAIL: the picker's recording did not settle clean: $(cat "$capture_rec_stopped_path")" >&2; exit 1
    fi
    capture_rec_file=$(sed -n 's/.*"path":"\([^"]*\)".*/\1/p' "$capture_rec_stopped_path")
    # Same reasoning as the --record leg's own check: the path is built from
    # the answering instance's $HOME, so one outside this run's isolated HOME
    # names a different formalshell on this machine.
    case "$capture_rec_file" in
      "$iso_home"/*) ;;
      *) echo "SMOKE_FAIL: the picker's recording was answered by an instance outside this run: $capture_rec_file is not under $iso_home" >&2; exit 1 ;;
    esac
    if [ ! -s "$capture_rec_file" ]; then
      echo "SMOKE_FAIL: the picker's recording left no file at $capture_rec_file" >&2; exit 1
    fi
    if ! "$file_bin" -b "$capture_rec_file" | grep -qi "ISO Media"; then
      echo "SMOKE_FAIL: the picker's recording is not an MP4 container, file(1) says: $("$file_bin" -b "$capture_rec_file")" >&2; exit 1
    fi
    echo "SMOKE_CAPTURE_RECORD $capture_rec_file ($("$file_bin" -b "$capture_rec_file"))"
  else
    capture_rec_err=$(sed -n 's/.*"lastError":"\([^"]*\)".*/\1/p' "$capture_rec_status_path")
    if [ -z "$capture_rec_err" ]; then
      echo "SMOKE_FAIL: the picker's record commit launched nothing at all — no recorder ran and no error was reported: $(cat "$capture_rec_status_path")" >&2; exit 1
    fi
    case "$capture_rec_err" in
      *dmabuf*)
        echo "SMOKE_CAPTURE_RECORD_BLOCKED wf-recorder spawned and died on the known nested-llvmpipe dmabuf bind: $capture_rec_err"
        echo "SMOKE_CAPTURE_RECORD_BLOCKED the shell's half of the path is verified; the recorder itself needs a real GPU (docs/SWITCHOVER.md)"
        ;;
      *)
        echo "SMOKE_FAIL: the picker's recording failed for a reason that is not the known environment block: $capture_rec_err" >&2; exit 1 ;;
    esac
  fi

  # Escape must leave nothing mapped. A full-screen Overlay surface that
  # survives its own cancel is the worst failure this surface has.
  if ! grep -q '"open":false' "$capture_escape_status_path"; then
    echo "SMOKE_FAIL: picker still open after ESCAPE: $(cat "$capture_escape_status_path")" >&2; exit 1
  fi
  echo "SMOKE_CAPTURE_PICKER $capture_picker_path"
  echo "SMOKE_CAPTURE_CANCEL escape closed the picker clean"
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

if $record_mode; then
  for f in "$record_start_reply_path" "$record_stop_reply_path" "$record_gif_reply_path" \
    "$record_status1_path" "$record_status2_path" "$record_status3_path" \
    "$record_finalize_status_path" "$record_ffprobe_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no record artifact produced at $f" >&2; exit 1
    fi
  done
  cat "$record_start_reply_path"; echo
  record_file=$(head -n1 "$record_start_reply_path" | tr -d '\r')
  case "$record_file" in
    error*|"") echo "SMOKE_FAIL: record start replied with an error: $(cat "$record_start_reply_path")" >&2; exit 1 ;;
  esac

  # RecordingService builds the destination from the answering instance's own
  # $HOME (recording.directory is left at its default here), so a path outside
  # this run's isolated HOME names a different formalshell on this machine and
  # record-active.png is a photo of a session that was never asked to record.
  case "$record_file" in
    "$iso_home"/*) ;;
    *) echo "SMOKE_FAIL: record start was answered by an instance outside this run: $record_file is not under $iso_home" >&2; exit 1 ;;
  esac

  # The one failure this leg must never soften: wf-recorder either captured
  # under llvmpipe or it did not, and its own stderr is what says why.
  cat "$record_status1_path"; echo
  if ! grep -qF '"active":true' "$record_status1_path"; then
    echo "SMOKE_FAIL: wf-recorder never started, record status: $(cat "$record_status1_path")" >&2
    echo "SMOKE_FAIL: wf-recorder stderr: $(sed -n 's/.*"lastError":"\([^"]*\)".*/\1/p' "$record_status1_path")" >&2
    exit 1
  fi
  if ! grep -qF "\"path\":\"$record_file\"" "$record_status1_path"; then
    echo "SMOKE_FAIL: record status reported a different destination than start replied ($record_file): $(cat "$record_status1_path")" >&2; exit 1
  fi
  if [ ! -f "$record_active_path" ]; then
    echo "SMOKE_FAIL: no recording-indicator screenshot produced at $record_active_path" >&2; exit 1
  fi

  if ! grep -q '^ok$' "$record_stop_reply_path"; then
    echo "SMOKE_FAIL: record stop did not return ok, got: $(cat "$record_stop_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  cat "$record_status2_path"; echo
  if ! grep -qF '"active":false' "$record_status2_path" || ! grep -qF '"lastError":""' "$record_status2_path"; then
    echo "SMOKE_FAIL: recording did not settle clean after stop: $(cat "$record_status2_path")" >&2; exit 1
  fi

  # RecordingService's finalize pass (M27 Task 2) outlives wf-recorder's own
  # exit, so `finalizing` has to settle false on its own before the ffprobe
  # read below means anything.
  cat "$record_finalize_status_path"; echo
  if ! grep -qF '"finalizing":false' "$record_finalize_status_path"; then
    echo "SMOKE_FAIL: finalize never settled: $(cat "$record_finalize_status_path")" >&2; exit 1
  fi
  cat "$record_ffprobe_path"; echo
  if ! grep -qF "codec_type=audio" "$record_ffprobe_path"; then
    echo "SMOKE_FAIL: finalized recording lost its audio stream: $(cat "$record_ffprobe_path")" >&2; exit 1
  fi
  finalize_duration=$(sed -n 's/^duration=//p' "$record_ffprobe_path" | head -n1)
  case "$finalize_duration" in
    ''|N/A) echo "SMOKE_FAIL: finalized recording reports no duration: $(cat "$record_ffprobe_path")" >&2; exit 1 ;;
  esac
  echo "SMOKE_RECORD_FINALIZE duration=${finalize_duration}s"

  if [ ! -s "$record_file" ]; then
    echo "SMOKE_FAIL: recording file is missing or empty: $record_file" >&2; exit 1
  fi
  if ! "$file_bin" "$record_file" | grep -qE 'ISO Media|MP4'; then
    echo "SMOKE_FAIL: recording is not an MP4 container, file(1) says: $("$file_bin" -b "$record_file")" >&2; exit 1
  fi
  echo "SMOKE_RECORD $record_file ($(wc -c < "$record_file" | tr -d ' ') bytes, $("$file_bin" -b "$record_file"))"

  record_gif_file=$(head -n1 "$record_gif_reply_path" | tr -d '\r')
  case "$record_gif_file" in
    error*|"") echo "SMOKE_FAIL: record gif replied with an error: $(cat "$record_gif_reply_path" 2>/dev/null)" >&2; exit 1 ;;
  esac
  cat "$record_status3_path"; echo
  if [ ! -s "$record_gif_file" ]; then
    echo "SMOKE_FAIL: GIF is missing or empty at $record_gif_file, record status: $(cat "$record_status3_path")" >&2; exit 1
  fi
  if ! "$file_bin" "$record_gif_file" | grep -q "GIF image data"; then
    echo "SMOKE_FAIL: transcode is not a GIF, file(1) says: $("$file_bin" -b "$record_gif_file")" >&2; exit 1
  fi
  if ! grep -qF "\"lastGifPath\":\"$record_gif_file\"" "$record_status3_path" \
    || ! grep -qF '"transcoding":false' "$record_status3_path" \
    || ! grep -qF '"lastError":""' "$record_status3_path"; then
    echo "SMOKE_FAIL: transcode did not settle clean: $(cat "$record_status3_path")" >&2; exit 1
  fi
  echo "SMOKE_RECORD_GIF $record_gif_file ($(wc -c < "$record_gif_file" | tr -d ' ') bytes)"
  echo "SMOKE_RECORD_INDICATOR $record_active_path"
fi

if $ocr_mode; then
  for f in "$ocr_text_status_path" "$ocr_text_cancel_path" "$ocr_color_status_path" "$ocr_color_cancel_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no capture status produced at $f" >&2; exit 1
    fi
  done
  if [ ! -f "$ocr_fixture_png" ]; then
    echo "SMOKE_FAIL: no fixture screenshot produced at $ocr_fixture_png" >&2; exit 1
  fi

  cat "$ocr_text_status_path"; echo
  if ! grep -qF '"capturing":true' "$ocr_text_status_path" || ! grep -qF '"mode":"text"' "$ocr_text_status_path"; then
    echo "SMOKE_FAIL: capture text did not enter the text pipeline: $(cat "$ocr_text_status_path")" >&2; exit 1
  fi
  # The region-mode argv, not just "some slurp": the two verbs differ only
  # in the flags they hand slurp, so the process itself is the evidence.
  if [ ! -s "$ocr_text_slurp_path" ]; then
    echo "SMOKE_FAIL: no 'slurp -d' process while capture text was pending: the region overlay never launched" >&2; exit 1
  fi
  if ! grep -qF '"capturing":false' "$ocr_text_cancel_path" \
    || ! grep -qF '"lastCancelled":true' "$ocr_text_cancel_path" \
    || ! grep -qF '"lastError":""' "$ocr_text_cancel_path"; then
    echo "SMOKE_FAIL: capture text did not cancel clean: $(cat "$ocr_text_cancel_path")" >&2; exit 1
  fi

  cat "$ocr_color_status_path"; echo
  if ! grep -qF '"capturing":true' "$ocr_color_status_path" || ! grep -qF '"mode":"color"' "$ocr_color_status_path"; then
    echo "SMOKE_FAIL: capture color did not enter the colour pipeline: $(cat "$ocr_color_status_path")" >&2; exit 1
  fi
  if [ ! -s "$ocr_color_slurp_path" ]; then
    echo "SMOKE_FAIL: no 'slurp -p' process while capture color was pending: the point overlay never launched" >&2; exit 1
  fi
  if ! grep -qF '"capturing":false' "$ocr_color_cancel_path" \
    || ! grep -qF '"lastCancelled":true' "$ocr_color_cancel_path" \
    || ! grep -qF '"lastError":""' "$ocr_color_cancel_path"; then
    echo "SMOKE_FAIL: capture color did not cancel clean: $(cat "$ocr_color_cancel_path")" >&2; exit 1
  fi
  if [ -s "$ocr_slurp_after_path" ]; then
    echo "SMOKE_FAIL: slurp still running after both cancels (pids: $(cat "$ocr_slurp_after_path"))" >&2; exit 1
  fi
  if [ "$(cat "$ocr_clipboard_path" 2>/dev/null)" != "ocr smoke sentinel" ]; then
    echo "SMOKE_FAIL: a cancelled capture wrote to the clipboard, got: $(cat "$ocr_clipboard_path" 2>/dev/null)" >&2; exit 1
  fi
  # The selection-free half: these two DO complete, so the assertion is the
  # clipboard itself rather than the overlay's presence.
  cat "$ocr_textat_status_path"; echo
  if ! grep -qF '"lastError":""' "$ocr_textat_status_path"; then
    echo "SMOKE_FAIL: capture textAt errored: $(cat "$ocr_textat_status_path")" >&2; exit 1
  fi
  ocr_got=$(cat "$ocr_textat_clipboard_path" 2>/dev/null)
  if [ "$ocr_got" = "ocr smoke sentinel" ] || [ -z "$ocr_got" ]; then
    echo "SMOKE_FAIL: capture textAt put no OCR text on the clipboard, still: '$ocr_got'" >&2; exit 1
  fi
  # What this asserts is the shell's pipeline (grim -> tesseract -> wl-copy),
  # not tesseract's accuracy: recognising a specific string is a property of
  # tesseract and of how llvmpipe rasterised the fixture's font, and pinning
  # it makes the leg fail for reasons that have nothing to do with this code.
  # Requiring a real recognised word rather than punctuation noise is what
  # keeps it from passing on an empty or garbage read. The bar's own text is
  # the reliable subject here; the 28px dark-on-green terminal body is not,
  # and is recorded below for a human to eyeball rather than asserted.
  if ! printf '%s' "$ocr_got" | grep -qE '[A-Za-z0-9]{3,}'; then
    echo "SMOKE_FAIL: capture textAt returned no recognisable word, got: '$ocr_got'" >&2; exit 1
  fi
  echo "SMOKE_OCR_TEXT_READBACK '$ocr_got'"
  echo "SMOKE_OCR_TEXT_LIMIT tesseract reliably reads the bar's own text off the real capture; the fixture terminal's 28px dark-on-green body is not reliably recognised under llvmpipe, so the exact fixture string is reported, not asserted"

  cat "$ocr_colorat_status_path"; echo
  ocr_hex=$(cat "$ocr_colorat_clipboard_path" 2>/dev/null)
  case "$ocr_hex" in
    \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) : ;;
    *) echo "SMOKE_FAIL: capture colorAt did not put a hex on the clipboard, got: '$ocr_hex'" >&2; exit 1 ;;
  esac
  echo "SMOKE_OCR_COLOR_READBACK $ocr_hex"

  echo "SMOKE_OCR_TEXT_OVERLAY $ocr_text_overlay_png"
  echo "SMOKE_OCR_COLOR_OVERLAY $ocr_color_overlay_png"
  echo "SMOKE_OCR_FIXTURE $ocr_fixture_png (foot window: known text on a known #3fae2a background)"
  echo "SMOKE_OCR_LIMIT what stays host-trial is the SELECTION, not the pipeline: bare 'capture text'/'capture color' block on a real slurp drag this rig cannot answer (no synthetic pointer, and slurp cannot be shimmed off the shell's PATH since nix/package.nix installs it with --prefix), so those two legs assert only that the right overlay launched and cancelled clean. textAt/colorAt run the identical pipeline from a geometry, which is what proves grim -> tesseract -> wl-copy and grim -> od -> hex -> wl-copy end to end above"
fi

if $reminder_mode; then
  for f in "$reminder_set_reply_path" "$reminder_status1_path" "$reminder_status2_path" \
    "$reminder_state1_path" "$reminder_state2_path" "$reminder_notifications_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no reminder artifact produced at $f" >&2; exit 1
    fi
  done
  if ! grep -q '^on$' "$reminder_dnd_path"; then
    echo "SMOKE_FAIL: notifications setDnd true did not report on, got: $(cat "$reminder_dnd_path" 2>/dev/null)" >&2; exit 1
  fi
  cat "$reminder_set_reply_path"; echo
  if ! grep -qF '"message":"SMOKE REMINDER FIXTURE"' "$reminder_set_reply_path" \
    || ! grep -qF '"id":"rem-' "$reminder_set_reply_path"; then
    echo "SMOKE_FAIL: reminder set did not answer with the stored entry: $(cat "$reminder_set_reply_path")" >&2; exit 1
  fi
  cat "$reminder_status1_path"; echo
  if ! grep -qF '"count":1' "$reminder_status1_path" \
    || ! grep -qF '"message":"SMOKE REMINDER FIXTURE"' "$reminder_status1_path"; then
    echo "SMOKE_FAIL: reminder status did not report the pending entry: $(cat "$reminder_status1_path")" >&2; exit 1
  fi
  # Persistence, read off the real file rather than through the service
  # that wrote it: state.json is where a reminder survives a restart.
  if ! grep -qF 'SMOKE REMINDER FIXTURE' "$reminder_state1_path"; then
    echo "SMOKE_FAIL: state.json did not carry the pending reminder: $(cat "$reminder_state1_path")" >&2; exit 1
  fi
  if [ ! -f "$reminder_pending_png" ]; then
    echo "SMOKE_FAIL: no pending-reminder screenshot produced at $reminder_pending_png" >&2; exit 1
  fi

  cat "$reminder_status2_path"; echo
  if ! grep -qF '"count":0' "$reminder_status2_path"; then
    echo "SMOKE_FAIL: reminder status did not empty after the deadline: $(cat "$reminder_status2_path")" >&2; exit 1
  fi
  if grep -qF 'SMOKE REMINDER FIXTURE' "$reminder_state2_path"; then
    echo "SMOKE_FAIL: a fired reminder is still in state.json: $(cat "$reminder_state2_path")" >&2; exit 1
  fi
  # The urgency-2 DND bypass, proven rather than read off the source: DND
  # went on before the reminder was ever set, so a toast in `popups` can
  # only have got there through Notifications/model.js's bypassesDnd().
  cat "$reminder_notifications_path"; echo
  if ! grep -qF '"dnd":true' "$reminder_notifications_path"; then
    echo "SMOKE_FAIL: DND was not on when the reminder fired: $(cat "$reminder_notifications_path")" >&2; exit 1
  fi
  if grep -qF '"popups":0' "$reminder_notifications_path"; then
    echo "SMOKE_FAIL: the fired reminder did not bypass DND into the popup tier: $(cat "$reminder_notifications_path")" >&2; exit 1
  fi
  if [ ! -f "$reminder_fired_png" ]; then
    echo "SMOKE_FAIL: no fired-reminder screenshot produced at $reminder_fired_png" >&2; exit 1
  fi
  echo "SMOKE_REMINDER_PENDING $reminder_pending_png"
  echo "SMOKE_REMINDER_FIRED $reminder_fired_png"
fi

if $toggles_mode; then
  for f in "$toggles_menu_status1_path" "$toggles_menu_status2_path" \
    "$toggles_nl_status1_path" "$toggles_nl_status2_path" \
    "$toggles_nl_query1_path" "$toggles_nl_query2_path" \
    "$toggles_dnd_status1_path" "$toggles_dnd_status2_path" \
    "$toggles_dnd_query1_path" "$toggles_dnd_query2_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no toggles artifact produced at $f" >&2; exit 1
    fi
  done

  # One ranked row out of a debug query reply. The row objects hold no
  # nested objects, so the id-anchored span up to the next "}" is the whole
  # row and nothing else.
  # `|| true`: a query that ranked no such row is a real outcome this block
  # reports itself, and under `set -o pipefail` grep's own miss would
  # otherwise abort the script with no message at all.
  toggles_row() {
    grep -o "{\"id\":\"$2\"[^}]*}" "$1" | head -n1 || true
  }
  toggles_checked() {
    case "$1" in
      *'"checked":true'*) echo true ;;
      *) echo false ;;
    esac
  }

  # No rebuild: the surface never left the level it was summoned to, so the
  # checkmark below repainted in place rather than being re-read by a
  # re-entered level.
  cat "$toggles_menu_status1_path"; echo
  if ! grep -qF '"isOpen":true' "$toggles_menu_status1_path" \
    || ! grep -qF '"level":"toggles"' "$toggles_menu_status1_path"; then
    echo "SMOKE_FAIL: menu did not summon to the toggles hub: $(cat "$toggles_menu_status1_path")" >&2; exit 1
  fi
  if ! cmp -s "$toggles_menu_status1_path" "$toggles_menu_status2_path"; then
    echo "SMOKE_FAIL: menu state changed across the toggles (a rebuild or reopen, not a live repaint)" >&2
    diff "$toggles_menu_status1_path" "$toggles_menu_status2_path" >&2 || true
    exit 1
  fi

  nl_row1=$(toggles_row "$toggles_nl_query1_path" "toggles.nightlight")
  nl_row2=$(toggles_row "$toggles_nl_query2_path" "toggles.nightlight")
  if [ -z "$nl_row1" ] || [ -z "$nl_row2" ]; then
    echo "SMOKE_FAIL: the nightlight toggle row never ranked (its wlsunset when-gate unresolved?)" >&2
    cat "$toggles_nl_query1_path" >&2
    exit 1
  fi
  echo "$nl_row1"
  echo "$nl_row2"
  nl_checked1=$(toggles_checked "$nl_row1")
  nl_checked2=$(toggles_checked "$nl_row2")
  nl_active1=false
  nl_active2=false
  grep -qF '"active":true' "$toggles_nl_status1_path" && nl_active1=true
  grep -qF '"active":true' "$toggles_nl_status2_path" && nl_active2=true
  # The row must render the service's real state, never the fact that a
  # toggle was asked for. On this VM the nested niri advertises no
  # wlr-gamma-control-unstable-v1, so wlsunset exits on its own and both
  # samples are honestly false (the branch --nightlight documents); on a
  # host that implements it, both flip. Either way they must agree.
  if [ "$nl_checked1" != "$nl_active1" ] || [ "$nl_checked2" != "$nl_active2" ]; then
    echo "SMOKE_FAIL: the nightlight row's checkmark disagrees with nightlight status (row $nl_checked1/$nl_checked2 vs service $nl_active1/$nl_active2)" >&2
    cat "$toggles_nl_status1_path" >&2; echo >&2
    cat "$toggles_nl_status2_path" >&2
    exit 1
  fi
  if [ "$nl_active2" = "true" ]; then
    echo "SMOKE_TOGGLES_NIGHTLIGHT wlsunset held: the row's checkmark flipped with it"
  else
    echo "SMOKE_TOGGLES_NIGHTLIGHT wlsunset could not hold this gamma-control-less session (lastError: $(sed -n 's/.*"lastError":"\([^"]*\)".*/\1/p' "$toggles_nl_status2_path")); the row honestly stayed unchecked"
  fi

  dnd_row1=$(toggles_row "$toggles_dnd_query1_path" "toggles.dnd")
  dnd_row2=$(toggles_row "$toggles_dnd_query2_path" "toggles.dnd")
  if [ -z "$dnd_row1" ] || [ -z "$dnd_row2" ]; then
    echo "SMOKE_FAIL: the DND toggle row never ranked" >&2
    cat "$toggles_dnd_query1_path" >&2
    exit 1
  fi
  echo "$dnd_row1"
  echo "$dnd_row2"
  # The live-flip proof: this row's @state: path is pure in-process state,
  # so it can only fail if the checkmark itself is not live.
  if [ "$(toggles_checked "$dnd_row1")" != "false" ] || [ "$(toggles_checked "$dnd_row2")" != "true" ]; then
    echo "SMOKE_FAIL: the DND row's checkmark did not flip false -> true inside the open hub" >&2
    echo "$dnd_row1" >&2; echo "$dnd_row2" >&2
    exit 1
  fi
  if ! grep -qF '"dnd":false' "$toggles_dnd_status1_path" || ! grep -qF '"dnd":true' "$toggles_dnd_status2_path"; then
    echo "SMOKE_FAIL: notifications status does not back the DND row's own flip" >&2
    cat "$toggles_dnd_status1_path" >&2; echo >&2
    cat "$toggles_dnd_status2_path" >&2
    exit 1
  fi
  for f in "$toggles_hub_png" "$toggles_toggled_png"; do
    if [ ! -f "$f" ]; then
      echo "SMOKE_FAIL: no toggles screenshot produced at $f" >&2; exit 1
    fi
  done
  echo "SMOKE_TOGGLES_HUB $toggles_hub_png"
  echo "SMOKE_TOGGLES_TOGGLED $toggles_toggled_png"
fi

if $keybinds_mode; then
  for f in "$keybinds_query1_path" "$keybinds_query2_path" "$keybinds_menu_status_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no keybinds artifact produced at $f" >&2; exit 1
    fi
  done
  cat "$keybinds_query1_path"; echo
  # The four honest end states are all real answers elsewhere; here they
  # would mean the fixture config was never found, which is the one thing
  # this leg exists to prove.
  for row in keybinds.noconfig keybinds.nobinds keybinds.failed keybinds.unsupported; do
    if grep -qF "\"id\":\"$row\"" "$keybinds_query1_path"; then
      echo "SMOKE_FAIL: keybinds route answered $row: the fixture config.kdl in the isolated XDG_CONFIG_HOME was not the one it read" >&2; exit 1
    fi
  done
  if ! grep -qF '"label":"Mod+Shift+Slash' "$keybinds_query1_path" \
    || ! grep -qF '"desc":"show-hotkey-overlay"' "$keybinds_query1_path"; then
    echo "SMOKE_FAIL: keybinds route did not parse the fixture's first bind: $(cat "$keybinds_query1_path")" >&2; exit 1
  fi
  # The "/-"-disabled bind must not be a live row, and the five live ones
  # are all there is: an exact count is what makes that assertion mean
  # something.
  if grep -qF 'Mod+Z' "$keybinds_query1_path"; then
    echo "SMOKE_FAIL: a /-disabled bind rendered as a live keybind row: $(cat "$keybinds_query1_path")" >&2; exit 1
  fi
  keybinds_rows=$(grep -o '"kind":"note"' "$keybinds_query1_path" | wc -l | tr -d ' ' || true)
  if [ "$keybinds_rows" != "5" ]; then
    echo "SMOKE_FAIL: keybinds route returned $keybinds_rows rows, expected the fixture's 5 live binds" >&2; exit 1
  fi
  cat "$keybinds_query2_path"; echo
  if ! grep -qF '"label":"Mod+T' "$keybinds_query2_path" \
    || ! grep -qF '"desc":"spawn ghostty"' "$keybinds_query2_path"; then
    echo "SMOKE_FAIL: ':k Mod+T' did not rank the fixture's own chord with its action: $(cat "$keybinds_query2_path")" >&2; exit 1
  fi
  if ! grep -qF '"isOpen":true' "$keybinds_menu_status_path" \
    || ! grep -qF '"level":"keybinds"' "$keybinds_menu_status_path"; then
    echo "SMOKE_FAIL: menu did not summon to the keybinds route: $(cat "$keybinds_menu_status_path")" >&2; exit 1
  fi
  if [ ! -f "$keybinds_menu_png" ]; then
    echo "SMOKE_FAIL: no keybinds screenshot produced at $keybinds_menu_png" >&2; exit 1
  fi
  echo "SMOKE_KEYBINDS $keybinds_menu_png ($keybinds_rows parsed rows)"
fi

if $mic_mode; then
  if [ ! -s "$dump_path" ]; then
    echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
  fi
  if ! grep -qF '"right":["microphone"' "$dump_path"; then
    echo "SMOKE_FAIL: the resolved settings do not lead bar.layout's right region with microphone, the opt-in cell was never placed" >&2; exit 1
  fi
  if [ ! -f "$mic_bar_png" ]; then
    echo "SMOKE_FAIL: no mic screenshot produced at $mic_bar_png" >&2; exit 1
  fi
  echo "SMOKE_MIC $mic_bar_png (this VM has no capture device, so a dim NO MIC cell is the correct rendering; a glyph here would mean an invented device)"
fi

if $systemupdate_mode; then
  if ! grep -q '^ok$' "$systemupdate_open_reply_path"; then
    echo "SMOKE_FAIL: panel open systemupdate did not return ok, got: $(cat "$systemupdate_open_reply_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ "$(head -n1 "$systemupdate_state_path" 2>/dev/null | tr -d '\r')" != "systemupdate" ]; then
    echo "SMOKE_FAIL: panel state did not report systemupdate open, got: $(cat "$systemupdate_state_path" 2>/dev/null)" >&2; exit 1
  fi
  if [ ! -s "$dump_path" ]; then
    echo "SMOKE_FAIL: no debug dump produced" >&2; exit 1
  fi
  if ! grep -qF "\"flakeDir\":\"$PWD\"" "$dump_path"; then
    echo "SMOKE_FAIL: the resolved settings do not point systemUpdate.flakeDir at this repo ($PWD)" >&2; exit 1
  fi
  if ! grep -qF '"right":["systemUpdate"' "$dump_path"; then
    echo "SMOKE_FAIL: the resolved settings do not lead bar.layout's right region with systemUpdate, the opt-in cell was never placed, so nothing flipped the panel's pollEnabled" >&2; exit 1
  fi
  if [ ! -f "$systemupdate_panel_png" ]; then
    echo "SMOKE_FAIL: no systemupdate screenshot produced at $systemupdate_panel_png" >&2; exit 1
  fi
  echo "SMOKE_SYSTEMUPDATE $systemupdate_panel_png (against $PWD/flake.lock; whatever the real probes answered is what rendered)"
fi

if $plugins_mode; then
  for f in "$plugins_list_path" "$plugins_status_path"; do
    if [ ! -s "$f" ]; then
      echo "SMOKE_FAIL: no plugins artifact produced at $f" >&2; exit 1
    fi
  done
  cat "$plugins_list_path"; echo
  if ! grep -qF '"id":"smoke-bar"' "$plugins_list_path" \
    || ! grep -qF '"kind":"bar"' "$plugins_list_path" \
    || ! grep -qF '"region":"right"' "$plugins_list_path" \
    || ! grep -qF "\"entryUrl\":\"file://$plugin_dir/entry.qml\"" "$plugins_list_path"; then
    echo "SMOKE_FAIL: the drop-in plugin did not resolve out of its manifest: $(cat "$plugins_list_path")" >&2; exit 1
  fi
  cat "$plugins_status_path"; echo
  if ! grep -qF '"loaded":true' "$plugins_status_path" \
    || ! grep -qF '"count":1' "$plugins_status_path" \
    || ! grep -qF '"bar":1' "$plugins_status_path"; then
    echo "SMOKE_FAIL: plugins status did not report one loaded bar plugin: $(cat "$plugins_status_path")" >&2; exit 1
  fi
  # The one place a plugin's entry QML failing to load is visible at all:
  # plugin QML lives outside the repo, so qmllint never sees it.
  if ! grep -qF '"errors":[]' "$plugins_status_path" || ! grep -qF '"warnings":[]' "$plugins_status_path"; then
    echo "SMOKE_FAIL: the plugin loaded with errors or warnings: $(cat "$plugins_status_path")" >&2; exit 1
  fi
  if [ ! -f "$plugins_bar_png" ]; then
    echo "SMOKE_FAIL: no plugins screenshot produced at $plugins_bar_png" >&2; exit 1
  fi
  echo "SMOKE_PLUGINS $plugins_bar_png (no bar key in settings.json: the manifest's own region is what placed the cell)"
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

if $clipssh_mode; then
  for f in "$clipssh_route_path" "$clipssh_sending_path" "$clipssh_copied_path" "$clipssh_failed_path"; do
    if [ ! -f "$f" ]; then
      echo "SMOKE_FAIL: no clipssh screenshot produced at $f" >&2; exit 1
    fi
  done
  echo "SMOKE_CLIPSSH_ROUTE $clipssh_route_path"
  echo "SMOKE_CLIPSSH_SENDING $clipssh_sending_path"
  echo "SMOKE_CLIPSSH_COPIED $clipssh_copied_path"
  echo "SMOKE_CLIPSSH_FAILED $clipssh_failed_path"
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
