# M50: a smooth shell on the e1504g

**Date:** 2026-08-26
**Status:** Tasks 1 to 4 landed 2026-08-26 (fd29a33, d701b39, 11f5684,
f3815de), g815 rebuilt onto them; the e1504g rebuild waits for the
machine to come back online (Task 5).
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook.

## Owner's ask (2026-08-26)

"Fully optimize the whole shell. I don't want lag or high usage, just a
smooth system. Especially on the lower end e1504g."

## Baseline, measured on the live e1504g (i3-N305, 7.5 GB, 1920x1080@60)

Read off the running `formalshell.service` over ssh, nothing driven:

| what | value |
| --- | --- |
| shell CPU, media paused, nothing open | 1.6% of one core (16 ticks / 10 s) |
| shell CPU, media playing (visualizer + marquee live) | 6 to 13%, mean ~8% |
| RSS / swapped | 209 MB / 172 MB |
| threads | 39 |
| lifetime thread split (14 min) | main 34 s, pooled 15 s, render 12 s, D-Bus 5 s, pixmap reader 4 s |
| subprocesses in 20 s idle | `tailscale status` x1, dualsense sysfs `sh` x1 |
| mapped layers at idle | wallpaper, bar, two 4x4 hot corners |

Three audits (polling, rendering, services/JS) over `shell/` found no
`layer.enabled`, shader, blur or shadow anywhere, every summonable surface
unmapping when closed, and every heavy service ref-counted. What is left is
a short list of things that run while nothing needs them.

## After Tasks 1 to 4, g815 (the strong host, e1504g still offline)

Same reads, same idle state (no player, nothing open), old build then new:

| what | before | after |
| --- | --- | --- |
| shell CPU, idle | 18 ticks / 10 s | 14 ticks / 10 s |
| subprocesses in 20 s idle | tailscale x1, dualsense sysfs x1 | dualsense sysfs x1 |
| mapped layers | bar x2, hot corners x4, wallpaper x2 | unchanged |
| RSS | 917 MB at 5 h uptime | 834 MB fresh |

Idle was already cheap on both hosts; the wins here land where the
baseline could not see them: bursts of Hyprland events (one publication
per burst, none for a no-op), music with animated Apple Music art (no
hidden mapped panel, no video decode, no 8 fps readback), a configured
keyboard layout cell (no `hyprctl` every 2 s per bar), and icon decodes
that no longer block the render thread. The e1504g numbers land here once
it is reachable again.

Not this plan's: `HyprlandBackend.qml:409/413` assigns `outputsState`,
which `BackendBase` declares but this backend never inherits, so the
journal logs "Cannot assign to non-existent property" at every outputs
read and the display panel's failed state can never show (present in the
previous build's journal too).

## Findings, ranked by measured or evident cost

1. `MediaPanel.qml:56` `keepMapped: AnimatedCoverFrameSource.active`. While
   an Apple Music track with animated art plays, the CLOSED media panel
   stays mapped as a full-size layer surface rendering a `Video`, and
   `AnimatedAlbumArt.qml:45` reads the frame back with `grabToImage` every
   120 ms, all to feed a 16 px cover in the bar. Video decode plus a hidden
   window plus a GPU readback at 8 fps, on an iGPU, for as long as music
   plays. `media.appleMusicArt` is on for this owner.
2. `Menu.qml:612-639` rebuilds the whole launcher tree (JSONC merge, every
   provider, `Frecency.order`, `Quickshell.iconPath` per app, `matchWindows`
   over apps x windows) on every `CompositorService.windows` change while
   the launcher is closed, and `HyprlandBackend.qml:43` republishes
   `windows` as a fresh array on every Hyprland event, browser title changes
   included. Handed to the peer session for the Menu half (its files);
   this plan takes the backend half.
3. `KeyboardLayoutWidget.qml:58` spawns `hyprctl devices -j` and parses it
   every 2 s, once per bar (so once per monitor), forever. Hyprland emits
   `activelayout` on its event socket; Quickshell exposes it as
   `Hyprland.rawEvent` (pinned 43d4fa9, `ipc/connection.hpp:119`).
4. `Components/Picture.qml:31` defaults `asynchronous: false`, so every
   icon in the bar (active window on every focus change), every launcher
   row and the notification cards decode on the render thread. `Tray.qml`'s
   icon `Image` has the same gap; the trace shows a tray icon (`parsecd.png`)
   re-read twice in 10 s.
5. `NotificationService.qml:210` ticks every second for the whole session
   to expire popups, with none live nearly all the time.
6. `CalendarEventsService.qml:96-105` runs its ics `cat` pipeline and the
   `formalshell-eds` CLI at boot and every 5 min with no `calendar.icsDir`
   configured and no calendar surface open.
7. 16 panels are instantiated eagerly in `shell.qml:136-151` (578 object
   declarations, ~2500 bindings, none behind a Loader). Five of them host the
   data their bar cells read (`pollEnabled` and the values), so a lazy
   version needs those services hoisted first. Deferred, see the last
   section.

## Locked decisions

- D1 Cut work, never fidelity. Every change here removes something that
  ran while nothing displayed it. No frame-rate caps, no lower decode sizes,
  no shortened animations: the bar looks identical before and after.
- D2 The animated bar cover becomes opt-in, `media.animatedBarCover`
  (default false). Off, the bar's mini cover is the static art and
  `AnimatedCoverFrameSource.active` is `panelWants` alone: the decode, the
  grab timer and `keepMapped` exist only while the media panel is open. On,
  today's M35 behaviour, unchanged. A knob with one reader is justified
  here because M35 was an explicit owner request and this reverses its
  default; the owner turns it back on where the machine can afford it.
- D3 Keyboard layout state moves into `Services/KeyboardLayoutService.qml`,
  a singleton every bar reads: one `hyprctl devices -j` at boot (and on
  `configreloaded`, where Hyprland can change the layout list), then
  `activelayout` events update it in place. No timer.
- D4 `HyprlandBackend.windows` and `workspaces` become plain properties
  published from one `Qt.callLater` slot, so a burst of events (Hyprland
  sends several per action) produces one publication, and a publication
  whose JSON shape equals the last one is dropped. Consumers keep the same
  property names and shapes.
- D5 `Picture.asynchronous` defaults true. Call sites that need a
  synchronous decode say so themselves (none found; RegionPicker's frozen
  frame is a bare `Image`).
- D6 The popup expiry timer runs only while `_state.popups.length > 0`. The
  60 s past-prune stays as is.
- D7 `CalendarEventsService` does nothing until `calendar.icsDir` or
  `calendar.eds` is configured; the 5 min timer runs on the same condition.
- D8 The peer session in this checkout (wallpaper picker performance) owns
  `Surfaces/Menu/Menu.qml`, `Menu/*.js` and `Services/ThumbnailService.qml`
  for this pass. This plan touches none of them.

## Tasks

Each task is one subagent, sequential. A task ends with its verification
commands run and read, then one commit staging ONLY the paths it touched
(the tree carries a peer's in-flight edits; never `git add -A`, never
`just build`/`just lint` since they stage everything). VM commands go
through `dev/vm-lock.sh`.

### Task 1: the four small gates (findings 4, 5, 6)

- `shell/Components/Picture.qml`: `property bool asynchronous: true`.
  `tests/tst_picture.qml:89` flips to `true`.
- `shell/Surfaces/Bar/TrayMenu.qml:324` and `shell/Surfaces/Bar/widgets/Tray.qml`
  icon `Image`s: `asynchronous: true`.
- `shell/Notifications/NotificationService.qml:210`: `running:
  root._state.popups.length > 0`.
- `shell/Services/CalendarEventsService.qml`: `readonly property bool
  _configured: root.icsDir !== "" || root.edsEnabled`; `refresh()` returns
  early when not configured (clearing any stale events), the Timer's
  `running` is `_configured`.
- Verify: `dev/vm-lock.sh just vm-test` (read tst_picture, tst_notification*,
  tst_calendar* results), `dev/vm-lock.sh just vm-smoke --notify --tray`
  and Read both PNGs.

### Task 2: KeyboardLayoutService (finding 3, D3)

- New `shell/Services/KeyboardLayoutService.qml` singleton (add to
  `Services/qmldir`): `layout` (same shape `Keyboard.*` helpers consume),
  `answered`, a `Process` running `hyprctl devices -j` on completion and on
  `Hyprland.rawEvent` name `configreloaded`, and on `activelayout` an
  in-place update of the active layout from `event.data`
  (`KEYBOARDNAME,LAYOUTNAME`) through a pure helper in the existing
  `Keyboard` js module (add `applyActiveLayout(layout, data)` with a unit
  test in `tests/`).
- `KeyboardLayoutWidget.qml` loses its Timer and Process and binds to the
  service. The widget's header comment about N pollers goes with it.
- Verify: `dev/vm-lock.sh just vm-test`, `dev/vm-lock.sh just vm-smoke
  --bar-layout` (the leg that resolves a user layout; add `keyboardLayout`
  to its fixture if absent) and Read the PNG.

### Task 3: HyprlandBackend publication (finding 2, D4)

- `shell/Compositor/hyprland/HyprlandBackend.qml`: `workspaces` and
  `windows` become `property var` set by `_publish()`; `Connections` on
  `Hyprland.toplevels`/`Hyprland.workspaces` (`valuesChanged`) and on
  `Hyprland.rawEvent` schedule it with `Qt.callLater(_publish)`. `_publish`
  maps as today, compares `JSON.stringify` against the last published
  string, assigns only on change. The staleness comment on `rect` stays.
- Verify: `dev/vm-lock.sh just vm-test` (compositor model tests),
  `dev/vm-lock.sh just vm-smoke --workspaces --console --capture` (pill
  travel, quake console window id, picker window rects) and Read the PNGs
  and the run's JSON.

### Task 4: the animated bar cover goes opt-in (finding 1, D2)

- `shell/Services/AnimatedCoverFrameSource.qml`: `readonly property bool
  barEnabled: Config.get("media.animatedBarCover", false)`; `active` is
  `panelWants || (barEnabled && _barWanters > 0)`.
- `shell/Surfaces/Panels/MediaPanel.qml:56`: `keepMapped:
  AnimatedCoverFrameSource.barEnabled && AnimatedCoverFrameSource.active`.
- `shell/Surfaces/Bar/widgets/NowPlaying.qml`: unchanged wiring (the
  refcount still registers; the gate decides). Header comment gains the
  knob.
- `docs/DESIGN.md` §2 item 12 and the settings reference (wherever
  `media.appleMusicArt` is documented) gain `media.animatedBarCover`.
- Verify: `dev/vm-lock.sh just vm-test`, `dev/vm-lock.sh just vm-smoke
  --media --panel media` and Read the PNGs; `hyprctl layers` in the run's
  JSON shows no `formalshell:panel` layer while the panel is closed.

### Task 5: deploy and re-measure (owner's machine, no subagent)

Push, `nix flake update formalshell` in `~/.config/nix`, rebuild e1504g,
then the same reads as the baseline table (per-thread ticks over 10 s with
media paused and playing, RSS, execve trace over 20 s). Numbers go into
this file under the baseline.

## Deferred: lazy panels (finding 7)

11 of the 16 panels (AppMenu, Audio, Calendar, Network, Bluetooth,
Airpods, Dualsense, Power, Media, Display, Monitor) expose nothing to their
bar cell beyond `isOpen`/`toggleFrom`, so a `PanelSlot` (a Loader that
forwards `isOpen`, `open`, `close`, `toggle`, `openFrom`, `toggleFrom` and
loads on first use) could host them without touching a consumer. The
other five (Weather, Usage, Tailscale, SystemUpdate, Github) carry their
cell's data and polling and would need that hoisted into services first.
Estimated gain: ~600 objects and ~2500 bindings less at startup, a few MB
and a few hundred ms on the N305. Decide after Task 5's numbers.
