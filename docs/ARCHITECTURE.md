# Architecture

## Process model

FormalShell is a single QuickShell process, launched as:

```
qs -p <store-path>/share/formalshell
```

(the nix package wraps this as the `formalshell` binary — `nix/package.nix`;
the home-manager module runs it as a `systemd --user` service bound to
`graphical-session.target` — `nix/hm-module.nix`). There is no compiled
companion binary and nothing runs under Node/npm/bun: all logic is QML/JS,
including the niri IPC client, which talks to niri's Unix sockets directly
via `Quickshell.Io.Socket`.

A second, separate entry point (`greeter/greeter.qml`, wrapped as the
`formalshell-greeter` binary — `nix/greeter-package.nix`) runs before any
user session exists, launched by greetd as its `default_session` instead of
by a user's systemd. `nix/greeter-package.nix` copies `shell/` verbatim and
layers `greeter.qml` on top of it, so `import qs.Core`/`qs.Components`
resolve to the one real `Core`/`Components` tree, never a second copy — but
it is a genuinely different process: `Quickshell.Services.Greetd` instead of
compositor sockets or `Quickshell.Services.Pam`, no `WlSessionLock` (greetd
already isolates the greeter into its own disposable compositor with no
other client ever attached, so there's nothing for a lock primitive to
exclude), and no `Core.State` reference at all (the `greeter` system
account's `$HOME` has no real `state.json` to read, and must not get one
written to it — see the file's own header comment).

`shell/shell.qml` is the entry point (`//@ pragma ShellId formalshell`). It
instantiates a `Variants` over `Quickshell.screens`, spawning one `Bar`, one
`Background`, and one `Toasts` popup stack per connected output; a single
non-per-screen `Menu`, `Center` (notification history), `Osd`, and one
instance each of the seven `Panels/*.qml` popouts including `MediaPanel`
(they open/show on the focused screen at summon/trigger time rather than
living on every output); one `Lock` (its `WlSessionLock` manages its own
per-output surfaces internally — no `Variants` loop needed here) and one
`Screensaver` (which *does* need its own `Variants` over
`Quickshell.screens`, since a plain overlay layer has no such auto-multi-
output primitive); one `ImagePicker`; and the `Ipc` handlers
(debug/theme/wallpaper/menu/notifications/osd/panel/clipboard/media/lock/
screensaver/picker).

## Tree layout

```
shell/
  shell.qml                  ShellRoot; Variants over Quickshell.screens -> Bar/Background per screen
  Core/
    State.qml                 singleton — state.json (wallpaper, mode), FileView+JsonAdapter
    Theme.qml                 singleton — Theme.color live off theme.json, Flexoki fallback statics
    Config.qml                 singleton — read-only watched settings.json (menu.customPowerButtons, …)
    qmldir
  Theme/
    matugen.js                 pure JS, .pragma library — merged matugen TOML config builder
    palette.js                 pure JS, .pragma library — theme.json validate() + Flexoki fallback()
    ThemeEngine.qml             singleton — serialized matugen Process queue
    templates/
      theme.json.tmpl           matugen template rendering theme.json
      niri-border.kdl.tmpl      matugen template rendering the niri layout{} border fragment
    qmldir
  Compositor/
    BackendBase.qml           the CompositorBackend contract (base component)
    CompositorService.qml     singleton facade; picks a backend, forwards everything
    qmldir
    niri/
      reducer.js               pure JS: niri EventStream -> contract state
      NiriBackend.qml           two-socket JSON IPC client; applyThemeFragment() reloads config
    hyprland/
      HyprlandBackend.qml       Quickshell.Hyprland wrapper, usingLua dual dispatch
  Components/
    Cell.qml                    the shared ledger cell — selected/accent/hovered, bottom+right hairline
                                 rules only (shared-rule contract, see below), default-property content
    MetaLabel.qml                uppercase/letterspaced/dim caption Text for meta rows
    Panel.qml                    the shared per-widget popout: ledger frame anchored under its opening
                                  bar cell (anchorX real, -1 falls back to the bar's right region),
                                  WlrLayershell top layer, keyboard OnDemand, closes on Escape/click-outside
    qmldir
  Menu/
    model.js                     pure JS, .pragma library — parseJsonc()/buildTree()/visibleChildren()
    search.js                    pure JS, .pragma library — tiered fuzzy score()/rank()
    providers.js                 pure JS, .pragma library — appsProvider()/applyProviders()/customPowerButtonEntries()/clipboardProvider()
    default-menu.jsonc           shipped default tree (apps, system/power, theme, clipboard)
  Clipboard/
    history.js                   pure JS, .pragma library — add()/remove()/clear()/sanitize(), 300-entry cap, dedup-to-front
  Calendar/
    progress.js                  pure JS, .pragma library — yearFraction()/lifeFraction()/resolveOverride()
    ics.js                       pure JS, .pragma library — RFC 5545 VEVENT reader (unfold, DTSTART parse, no RRULE expansion)
  Weather/
    openmeteo.js                 pure JS, .pragma library — buildUrl()/parseResponse() with typed failure shapes
  Media/
    applemusic.js                 pure JS, .pragma library — URL construction, response parsing, cache-key/prune-decision logic
  Screensaver/
    effect.js                     pure JS, .pragma library — frameState(): matrix-rain column/glyph/decay stepping off a frame counter
  Services/
    AudioService.qml            singleton — Quickshell.Services.Pipewire default-sink volume/mute, changed() signal
    BrightnessService.qml       singleton — brightnessctl-backed backlight, no polling loop (refresh()/set()/step())
    ClipboardService.qml        singleton — wl-paste --watch capture, drives Clipboard/history.js, writes clipboard.json
    LocationService.qml         singleton — QtPositioning PositionSource (geoclue2), settings.json lat/lon override
    CalendarEventsService.qml   singleton — reads Calendar/ics.js over a khal/vdir-style directory (calendar.icsDir)
    MediaService.qml             singleton — Quickshell.Services.Mpris active-player pick, transport verbs, honest available:false
    AppleMusicArtService.qml     singleton — opt-in (media.appleMusicArt), curl-driven iTunes Search + amp-api editorialVideo, cached MP4s
    IdleService.qml               singleton — one shared IdleMonitor (respectInhibitors:true), screensaver.timeoutSeconds
    qmldir
  Notifications/
    model.js                    pure JS, .pragma library — three-tier reducer (popups/pending/past), DND bypass rule
    NotificationService.qml     singleton — owns NotificationServer, drives model.js, live-Notification side map
    qmldir
  Ipc/
    DebugIpc.qml                IpcHandler target "debug", function dump(): string, query(q): string
    ThemeIpc.qml                IpcHandler target "theme", retheme()/mode()/status()
    WallpaperIpc.qml            IpcHandler target "wallpaper", set()/get()
    MenuIpc.qml                 IpcHandler target "menu", toggle()/summon()/close()/refresh()/ping()/select()/input()
    NotificationsIpc.qml        IpcHandler target "notifications", dndState()/toggleDnd()/setDnd()/showHistory()/clear()/clearPending()/markAllSeen()/dismissAll()/invokeLast()
    OsdIpc.qml                  IpcHandler target "osd", volume()/brightness()/media()/close()/state()
    PanelIpc.qml                 IpcHandler target "panel", open(name)/close()/toggle(name)/state() — registry maps name -> Panel instance
    ClipboardIpc.qml             IpcHandler target "clipboard", list()/copy(id)/remove(id)/clear()
    MediaIpc.qml                  IpcHandler target "media", playPause()/next()/previous()/status()
    LockIpc.qml                   IpcHandler target "lock", lock()/isLocked()/status() — no unlock(), see its own header comment
    ScreensaverIpc.qml            IpcHandler target "screensaver", start()/stop()/status()
    PickerIpc.qml                 IpcHandler target "picker", summon()/select(dir,token)/choose(path)/close()/status()
  Surfaces/
    Bar/
      Bar.qml                  PanelWindow; three-region Row (left/center/right), height tracks the tallest cell present
      widgets/
        Workspaces.qml          Repeater over CompositorService.workspaces
        ActiveWindow.qml        focused window's appId + title
        Clock.qml                center region: TIME meta label + live clock, opens the calendar panel
        AudioWidget.qml          volume glyph + %, panel-open accent dot
        Battery.qml               BAT / NN% meta idiom, hidden entirely when isLaptopBattery is false
        NetworkWidget.qml         connection-state glyph, panel-open accent dot
        BluetoothWidget.qml       adapter-state glyph, panel-open accent dot
        WeatherWidget.qml         thermometer glyph + WEATHER label, panel-open accent dot
        NowPlaying.qml             note glyph + elided title + panel-open accent dot, hidden entirely with no MPRIS player
    Background/
      Background.qml            per-screen PanelWindow on WlrLayer.Background; shows State.wallpaper
    Menu/
      Menu.qml                  keyboard-exclusive top-layer window; jsonc -> tree -> cond batch -> rank/browse -> cells
      MenuRow.qml                Cell subtype: icon+label, confirm-gate swap, ▸/✓ trailing indicator
    Panels/
      AudioPanel.qml             Pipewire output/input node sliders (PwObjectTracker), MUTE toggle cells
      CalendarPanel.qml          month grid + year/life-progress bar + TODAY events section
      NetworkPanel.qml           WIRED/WI-FI grouped connections, 5-segment mono signal bar, connect/disconnect
      BluetoothPanel.qml         adapter state + paired devices, or a dim "NO ADAPTER" cell
      PowerPanel.qml              AC/battery row + keyboard-navigable power-profile picker (Up/Down/Enter)
      WeatherPanel.qml            current-conditions header + FORECAST ledger off LocationService + open-meteo
      MediaPanel.qml               album art + NOW PLAYING meta row + flat progress cell + hover-invert transport cells
      AnimatedAlbumArt.qml         opt-in muted looping video, active only while open and MediaService.isPlaying
    Notifications/
      Toasts.qml                 per-screen PanelWindow, Overlay layer; top-right popup column off NotificationService.popups
      Center.qml                  single-instance PanelWindow, Top layer; right-anchored PENDING/EARLIER sections + DND cell
      NotificationCard.qml        shared Cell: meta row (app name/relative time) + summary/body, critical = accent fill
    Osd/
      Osd.qml                     single-instance PanelWindow, Overlay layer, bottom-center; icon|label|value, no keyboard focus
    Lock/
      Lock.qml                    WlSessionLock wrapper + both PamContexts (password, parallel fingerprint) + idle-blank/resume-guard state
      LockSurface.qml              per-output Component WlSessionLock instantiates itself; blurred-wallpaper backdrop, oversized clock, one input cell
    Screensaver/
      Screensaver.qml              one controller Item (IdleService x MediaService guard) + per-monitor Variants overlay, Canvas-drawn matrix rain
    Picker/
      ImagePicker.qml               ledger image grid (Panel.qml subtype); wallpaper mode + generic select() mode over the same grid
greeter/
  greeter.qml                  greetd entry point (Quickshell.Services.Greetd); no WlSessionLock,
                               no Core.State reference — see the file's own header comment
tests/
  tst_niri_reducer.qml         qmltestrunner tests for reducer.js
  tst_matugen_builder.qml      qmltestrunner tests for Theme/matugen.js
  tst_palette.qml              qmltestrunner tests for Theme/palette.js
  tst_menu_model.qml            qmltestrunner tests for Menu/model.js
  tst_menu_search.qml           qmltestrunner tests for Menu/search.js
  tst_notifications_model.qml   qmltestrunner tests for Notifications/model.js
  tst_clipboard_history.qml     qmltestrunner tests for Clipboard/history.js
  tst_calendar_progress.qml     qmltestrunner tests for Calendar/progress.js
  tst_calendar_ics.qml          qmltestrunner tests for Calendar/ics.js
  tst_openmeteo.qml             qmltestrunner tests for Weather/openmeteo.js
  tst_applemusic.qml            qmltestrunner tests for Media/applemusic.js
  tst_screensaver_effect.qml    qmltestrunner tests for Screensaver/effect.js
dev/
  smoke-niri.sh                 nested-niri build+screenshot(+debug dump)(+wallpaper)(+menu)(+notify)(+center)(+osd)(+panel <name>)(+clipboard)(+media)(+lock)(+screensaver)(+picker) loop, dbus-run-session isolated
  smoke-hyprland.sh             same, nested Hyprland
nix/
  package.nix                   stdenvNoCC derivation wrapping `qs -p`; also installs formalshell-lock-before-sleep,
                                 the exit-0-always wrapper around `qs ipc call lock lock`
  greeter-package.nix            stdenvNoCC derivation wrapping `qs -p` at greeter/greeter.qml; copies
                                 shell/ verbatim and layers greeter.qml on top, no lock-before-sleep companion
  hm-module.nix                 home-manager module (programs.formalshell); wires formalshell-lock-before-sleep
                                 to a systemd --user oneshot bound to sleep.target (programs.formalshell.systemd.lockBeforeSleep)
  nixos-module.nix               nixosModules.formalshell — security.pam.services.formalshell-lock,
                                 services.geoclue2 (+ agent), NetworkManager/bluez/upower/
                                 power-profiles-daemon/pipewire, each an mkDefault-guarded sub-option
  nixos-greeter-module.nix       nixosModules.formalshell-greeter — services.greetd wired to the
                                 formalshell-greeter package under a wlroots compositor, generalizing
                                 the hand-rolled rig M8 Task 2 built directly in nix/testvm.nix
```

Every widget under `Surfaces/` reads only `Theme` and `CompositorService` —
never a backend directly, and never a raw compositor socket. That boundary is
what lets `Bar.qml` and its widgets be identical on niri and Hyprland.

## The CompositorBackend contract

Defined once, in `shell/Compositor/BackendBase.qml`, and referenced verbatim
by every backend and by the facade:

```qml
// BackendBase.qml — QtObject base every backend extends
readonly property bool available          // backend detected its compositor and is connected
property var workspaces: []               // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
property var windows: []                  // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool }]
property var outputs: []                  // [{ name:string, x:int, y:int, width:int, height:int, scale:real }]
property string focusedWindowId: ""
property string focusedWorkspaceId: ""
property string focusedOutputName: ""
signal configReloaded(bool failed)
function focusWorkspace(id) {}
function focusWindow(id) {}
function closeWindow(id) {}
function spawn(argv) {}                   // argv: list<string>, no shell interpolation
function powerOffMonitors() {}
function powerOnMonitors() {}
function applyThemeFragment() {}          // niri-only; no-op on backends without one
```

`CompositorService` (the singleton facade, `import qs.Compositor`) exposes
the identical property/method surface, delegating to whichever backend is
active, plus:

- `readonly property string compositor` — `"niri" | "hyprland" | "unknown"`,
  detected via `Quickshell.env("NIRI_SOCKET")` then
  `Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")`. (Env-based detection is
  sufficient inside nested test sessions; walking `/proc/net/unix` by socket
  owner, the way DMS's `CompositorService.qml:927` does, is a hardening
  follow-up, not built yet.)
- `readonly property var ext` — `{ overview: { available:bool, isOpen:bool,
  toggle() } }`, all-defaults-false when the active backend doesn't support
  an overview.

When no compositor is detected, the facade falls back to a bare
`BackendBase {}` instance (`available: false`, empty lists) so the shell
still builds and runs with nothing wired up — this is what makes Task 2's
placeholder bar buildable before any backend existed.

Ids are **opaque strings everywhere above this line**. The one place that
changes is each backend's own IPC boundary: niri's `NiriBackend.qml`
converts a string id back with `Number(id)` only inside the wire-format
request payload it sends to niri's socket; Hyprland window ids are hex
addresses and are kept verbatim. Nothing else in the tree parses, compares
numerically, or assumes stability of an id.

## Reducer data flow (niri)

niri requires two separate socket connections — the event stream socket
monopolizes its connection, so requests go over a second one:

```
niri socket (NIRI_SOCKET)
  eventSocket: write "EventStream" once on connect
    -> SplitParser, one JSON object per line
    -> skip the initial {"Ok":"Handled"} ack line
    -> JSON.parse(line)                                    (shell/Compositor/niri/NiriBackend.qml)
    -> Reducer.reduce(state, event)                         (shell/Compositor/niri/reducer.js, pure)
    -> copy normalized fields onto NiriBackend's contract properties
    -> CompositorService picks them up via property delegation
    -> Bar widgets re-render (property bindings, no manual signal wiring)

  requestSocket: write(JSON.stringify(actionPayload) + "\n")
    used by focusWorkspace/focusWindow/closeWindow/spawn/powerOffMonitors/powerOnMonitors
```

`reducer.js` is a `.pragma library` module: `initialState()` returns the
zeroed contract shape, `reduce(state, event)` is a pure function (no
mutation of its input — `tests/tst_niri_reducer.qml` asserts this directly)
that pattern-matches on the event's single top-level key (`WorkspacesChanged`,
`WorkspaceActivated`, `WindowClosed`, `WindowFocusChanged`, `OverviewOpenedOrClosed`,
`ConfigLoaded`, …) and returns a new state. **Unknown event keys return the
state unchanged** — niri's forward-compatibility mandate, so a newer niri
adding event types doesn't break the reducer. Both sockets reconnect on
error/close via a 2s `Timer`.

Hyprland has no equivalent hand-rolled reducer: `HyprlandBackend.qml` reads
`Quickshell.Hyprland`'s own reactive `workspaces`/`toplevels`/`monitors`
models directly and maps them onto the same contract shapes, so there's no
event stream or JSON parsing to test in isolation.

## Debug IPC

`shell/Ipc/DebugIpc.qml` registers `IpcHandler { target: "debug" }` with
`function dump(): string` returning
`JSON.stringify({ compositor, available, workspaces, windows, focusedWindowId, focusedWorkspaceId, configLoaded, audio: {volume, muted, available}, brightness: {available, percent} })`
read straight off `CompositorService`/`Core.Config`/`AudioService`/
`BrightnessService`. This is the textual
verification hook used by both smoke scripts (`qs ipc --any-display -p <path>
call debug dump`) and by hand during backend development — it's the fastest
way to confirm a backend is wired correctly without reading a screenshot.
`function query(q: string): string` ranks `q` against the live menu tree
(`Menu.qml#query()` → `search.js#rank()`) and returns the JSON result array,
verifying the model/provider/scorer pipeline without keyboard injection
(nested test sessions can't inject keystrokes into the surface itself).

## Theme engine data flow

```
Core.State (state.json: wallpaper, mode)
  |  Connections { onWallpaperChanged / onModeChanged -> ThemeEngine.retheme() }
  v
Theme.ThemeEngine (running/pending queue; a retheme() mid-run just sets pending)
  |  reads ~/.config/matugen/config.toml + ~/.config/formalshell/matugen.d/*.toml (one `cat` Process)
  |  Theme.matugen.js#buildConfig() -> matugen-merged.toml (spec merge order)
  |  Process: matugen image <wallpaper> -m <mode> -c matugen-merged.toml --prefer darkness|lightness
  |    (no wallpaper set: skip matugen, write Theme.palette.js#fallback() as theme.json directly)
  v
matugen renders templates/theme.json.tmpl + templates/niri-border.kdl.tmpl
  -> <state-dir>/{theme.json,niri-border.kdl}.tmp
  |  atomic `mv` into place on success
  v
$XDG_STATE_HOME/formalshell/theme.json          $XDG_STATE_HOME/formalshell/niri-border.kdl
  |  FileView watch (Core/Theme.qml)               |  niri `include`s this path from its own config
  v                                                  v
Theme.color.* properties update live              CompositorService.applyThemeFragment()
  -> every Bar/widget token recolors                -> niri: LoadConfigFile action reloads the
     (plain property bindings, no restart)              running config, border colors apply live
```

`Core/Theme.qml` parses `theme.json`, validates it with `palette.js#validate()`,
and falls back to `palette.js#fallback()` (the Flexoki statics) on absence or
invalid content — so `Theme.color.*` is always a fully-populated 6-color
object, matugen-driven or not. `Surfaces/Background/Background.qml` is the
one other consumer of `State.wallpaper` directly: a per-screen
`WlrLayershell.layer: WlrLayer.Background` surface showing the image, or a
flat `Theme.color.background` fill when unset.

`ThemeEngine` writes every file itself via a small `sh -c` `Process` rather
than `FileView.setText()`: `FileView` silently skips both the write and its
`saved()` signal when the new text is byte-identical to what's already on
disk, which two back-to-back `retheme()` runs for the same wallpaper/mode
routinely produce.

## Menu data flow

```
shell/Menu/default-menu.jsonc                 ~/.config/formalshell/menu.jsonc
  |  FileView (Menu.qml)                        |  FileView (Menu.qml, same bounded-retry pattern)
  v                                              v
Model.parseJsonc() -> defaultObj              Model.parseJsonc() -> userObj
  \                                             /
   \--------------- Model.buildTree(defaultObj, userObj) --------------/
                       |  dotted-id hierarchy, per-key user-over-default merge,
                       |  hidden:true drops a node+subtree, kind inferred from
                       |  action/target/provider/else-submenu
                       v
                 Providers.applyProviders(tree, { apps: appsProvider })
                       |  expands every "provider" node's children in-place
                       |  (DesktopEntries.applications.values -> kind:"app" nodes)
                       |  Config.get("menu.customPowerButtons") merged into the
                       |  default object first, via Providers.customPowerButtonEntries()
                       v
                 { rootIds, nodes }             (recomputed reactively: Config.settings
                                                  change, DesktopEntries change, jsonc reload)
                       |
                       |  on open()/level-descend only (never per-keystroke):
                       v
              one Process per when/checked condition -> _condResults cache
                       |
        +--------------+---------------------------+
        v                                           v
Model.visibleChildren(nodes, id, condResults)   Search.rank(nodes, query, condResults)
  level browsing, self-pruning empty submenus      whole-tree fuzzy scoring (see search.js's
  and links recursively                            five tiers), depth/decl-order tie-break, cap 40
        \                                           /
         \-----------------------------------------/
                       v
              Surfaces/Menu/MenuRow.qml  (a Cell: icon+label, ▸/✓ trailing
                                           indicator, confirm-gate swap)
```

**Cell shared-rule contract.** `Components/Cell.qml` draws only its own
bottom and right hairline rule (`Theme.color.rule`, `Theme.borderWidth`
thick) — the container arranging a grid of cells (`Menu.qml`'s `ListView`,
future bar/panel grids) is responsible for the outer top/left rule, so
adjacent cells never double up a shared border. This is what makes
DESIGN.md's "cells not cards, one hairline between neighbors" rule hold
structurally rather than by convention: every row on every M4+ surface goes
through `Cell`, so a `Rectangle`-with-border appearing outside `Components/`
is drift, not a new pattern.

## Notification data flow

```
Quickshell.Services.Notifications.NotificationServer  (NotificationService.qml)
  onNotification: notification => { notification.tracked = true; ... }
    |  server.cpp mutates the SAME Notification object in place on a
    |  replaces_id update rather than emitting a new `notification` — the
    |  handler above runs exactly once per id; per-property *Changed signals
    |  (appName/summary/body/urgency/actions/image) resync the model entry
    |  on every later replace instead
    v
Notifications/model.js  (.pragma library, pure — state in, state out)
  add(state, notif, now, opts)
    |  dnd && !bypassesDnd(notif) -> straight to pending
    |  else -> popups (capped at 4, overflow pushes oldest to pending;
    |          expiresAt = 0 (sticky) for urgency:critical, else now+6000)
    v
  { popups, pending, past, dnd }        1s Timer -> expire()   (popup timeout -> pending)
                                         60s Timer -> prunePast() (past entries >15min -> dropped)
        |                                       |
        v                                       v
Surfaces/Notifications/Toasts.qml       Surfaces/Notifications/Center.qml
  per-screen, Overlay layer, top-right    single instance, Top layer, right-anchored
  reads .popups                           reads .pending then .past (PENDING/EARLIER sections)
  dismiss -> dismissPopup() (seen, ->past) dismiss -> dismissOne() (dropped outright)
                                           open() -> markAllSeen() on close
```

`bypassesDnd(notif)` is Omarchy's narrow rule, encoded as one pure function
with tests on both sides (`tests/tst_notifications_model.qml`):
`notif.urgency === 2 && notif.senderIsNotifySend === true`, where
`senderIsNotifySend` is set by `NotificationService` from the sender's literal
app name (`notification.appName === "notify-send"`), never inferred from
urgency alone — a chat app marking its own messages critical does not bypass.

`NotificationService` keeps live `Notification` objects OUT of the reducer
state (which is plain JS data, safe to keep around after the server destroys
the notification) in a `_live` side map keyed by id, so `dismissPopup()`/
`invokeAction()` can still reach the real object while it's alive; a
`_selfClosing` flag distinguishes a close WE triggered (already applied to
the model) from a sender-initiated `CloseNotification` or action-implicit
close (never applied, so `closed` has to call `Model.dismissOne` itself).

## OSD trigger graph

```
AudioService.changed()  (any volume/mute change on the default sink —
  |                       ours, wpctl, pavucontrol, hardware keys)
  v
Osd.qml: Connections { onChanged: showVolume() }
  |
  |  IpcHandler target "osd" (OsdIpc.qml) — every other trigger, no
  |  automatic signal exists for these:
  +-- volume()      -> osd.showVolume()                     (manual re-show)
  +-- brightness()  -> BrightnessService.refresh(); osd.showBrightness()
  +-- media(text)   -> osd.showMedia(text)
  +-- close()       -> osd.close()
  v
Osd.qml: kind = "volume"|"brightness"|"media", hideTimer restarts (1.6s)
  -> visible = kind !== ""
  -> icon|label|value Cells re-render off AudioService/BrightnessService
     properties directly (no local copy — a still-open card tracks live
     changes, e.g. a second wpctl call while the card is showing)
```

Column widths (`_iconWidth`/`_labelWidth`/`_valueWidth`) are computed once
off a hidden calibration `Item` (every glyph/label the card can ever show,
rendered at the live font) rather than off whatever value happens to be
showing — this is the no-jitter contract: volume ticking 3% → 97% or a long
media title swapping in never reflows the card.

`BrightnessService` has no polling loop by design (`brightnessctl -m`
queried once at startup, re-read straight from each `set()`/`step()` reply),
so a hardware brightness key is expected to call `brightnessctl` itself and
then poke the OSD to catch up: `brightnessctl set 5%+ && qs ipc call osd
brightness`. On the mac VM rig, where the guest has a pipewire virtual sink
but no backlight device, `AudioService.available` is honestly `true` and
`BrightnessService.available` is honestly `false` — the brightness leg of
`dev/smoke-niri.sh --osd` still proves the surface renders that kind
correctly (`BRIGHTNESS` label, `0%`, empty fill), not that hardware exists.
One VM-specific gotcha: the guest's null-audio-sink volume persists across
nested niri sessions (pipewire itself isn't restarted between runs), so a
`wpctl set-volume … 30%` that re-sets an already-30% sink is a no-op —
`AudioService.changed` only fires on an actual value change, so a repeat
`--osd` run's auto-show leg can legitimately capture nothing new. This isn't
a bug in the trigger; it's a property of testing against durable state.

## Panel host + `panel` IPC data flow

One shared `Components/Panel.qml` is instantiated once per panel kind in
`shell.qml` (`audioPanelInstance`, `calendarPanelInstance`, …), each binding
its backend directly — `Quickshell.Services.Pipewire`,
`Quickshell.Networking`, `Quickshell.Bluetooth`, `Quickshell.Services.UPower`,
or (for `WeatherPanel`) the shell's own `LocationService` plus a direct
open-meteo fetch — rather than going through an intervening Services
wrapper, the same "panel binds its backend directly" pattern
`AudioPanel.qml` established first. A bar widget (`AudioWidget.qml`, …)
opens its panel two ways:

```
click on the bar cell                          qs ipc call panel open/toggle <name>
  -> panel.open(cell's own screen-relative x)     -> PanelIpc.qml: registry[name].open()
     (anchorX real, computed within the            (no click happened, so anchorX stays
      widget's own window — Wayland gives           unset — Panel.qml falls back to the
      no cross-window global coordinates)            bar's right region, Theme.spacing.md in)
  v                                               v
Panel.qml: isOpen = true, forceActiveFocus() on its full-screen backdrop MouseArea
  -> frame positions at (anchorX, barHeight), sized to its content's implicitHeight
     (capped at 60% of screen height, Flickable scrolls beyond that)
  -> click outside the frame, or Escape, closes it (backdrop's onClicked / Keys.onEscapePressed)
```

`shell/Ipc/PanelIpc.qml` (`target: "panel"`) is a spec addendum this repo's
own M6 plan records rather than a conflict with `docs/superpowers/specs/2026-07-27-formalshell-design.md`'s
§IPC list: per-widget popouts otherwise have no summon path for compositor
keybinds, and no way to be verified headlessly in the smoke rig.
`registry: { audio: audioPanelInstance, calendar: …, … }` is wired once in
`shell.qml`; `open(name)`/`toggle(name)` look the instance up and call its
own `open()`/`toggle()`, `close()` closes whichever panel is currently open
(scans the registry for `isOpen`), `state()` returns that same panel's name
or `""`. An unknown name returns `"error: unknown panel '<name>'"` from both
`open()` and `toggle()` — never a silent no-op.

## Clipboard data flow

```
wl-paste --type text --watch sh -c '… cat; printf "\0"'   (ClipboardService.qml, long-running Process)
  |  NUL-delimited stdout (clipboard text can itself contain newlines)
  |  a capture is skipped — no NUL emitted at all — when wl-paste itself
  |  sets CLIPBOARD_STATE=sensitive (its own x-kde-passwordManagerHint signal)
  v
Clipboard/history.js#add(state, entry, now)   (.pragma library, pure)
  |  sanitize() drops empty/whitespace-only text (the nil/clear watch-event shape)
  |  re-copying existing content moves that entry to the front, keeping its
  |  original id, instead of inserting a duplicate
  |  300-entry cap drops the oldest
  v
$XDG_STATE_HOME/formalshell/clipboard.json      (FileView + JsonAdapter, same
                                                  pattern as Core/State.qml)
  |
  +-- Ipc/ClipboardIpc.qml (target "clipboard"): list()/copy(id)/remove(id)/clear()
  |
  +-- Menu/providers.js#clipboardProvider(): one menu row per entry, newest
        first; selecting a row runs `qs ipc --any-display -p <selfPath> call
        clipboard copy <id>` — the exact same self-targeting invocation a
        CLI caller would use, so the menu row is the IPC verb, not a second
        code path
```

## Location → Weather chain

```
Services/LocationService.qml
  QtPositioning.PositionSource (geoclue2 D-Bus backend), left continuously
  `active` with a repeating updateInterval — never a one-shot update() — so
  an early inaccurate geoclue fix is just replaced by the next one instead
  of freezing in (the spec cites PR #2914's lesson by name for this)
    |
    |  settings.json's location.latitude/location.longitude, when BOTH are
    |  present, override geoclue entirely (root._hasOverride) — the
    |  documented fallback for geoclue's own known failure modes, and the
    |  path exercised in the test VM, which has no Wi-Fi radio to associate
    |  with in the first place
    v
  available / latitude / longitude              (all live property bindings)
    |
    v
Surfaces/Panels/WeatherPanel.qml
  "NO LOCATION" cell when !LocationService.available
  otherwise: Weather/openmeteo.js#buildUrl(lat, lon) -> XMLHttpRequest ->
  parseResponse(status, bodyText) -> { ok:true, current, forecast[] } or
  { ok:false, error: "network_error"|"http_error"|"malformed_json"|"missing_fields" }
    |
    v
  header meta row (condition label + temperature + glyph) + a FORECAST
  ledger (one row per daily period, glyph + weekday + high/low mono temps
  pinned right); an "UNAVAILABLE" cell carrying the `error` code replaces
  the ledger on any fetch failure — never a stale or fabricated forecast
```

`WeatherPanel.qml` owns its own `XMLHttpRequest` directly (no separate
`WeatherService`), the same "panel drives its own fetch" pattern
`AudioPanel`/`NetworkPanel` already establish for their respective
quickshell modules.

## MPRIS → panel chain

```
Quickshell.Services.Mpris.players.values
  |
  v
Services/MediaService.qml
  activePlayer = first isPlaying:true player, else players[0], else null
  available / title / artist / album / artUrl / identity / isPlaying /
  canGoNext / canGoPrevious / canSeek / position / length
    |  (position doesn't emit positionChanged on ordinary playback ticks —
    |   quickshell's own doc'd workaround: a 1s Timer re-emits it while
    |   isPlaying so any binding that reads position advances at all)
    |
    +-- Surfaces/Bar/widgets/NowPlaying.qml
    |     visible: MediaService.available (hidden entirely otherwise —
    |     not a "nothing playing" lie); click toggles MediaPanel
    |
    +-- Surfaces/Panels/MediaPanel.qml
    |     album art cell (static Image off artUrl) + NOW PLAYING / <app>
    |     meta row + title/artist + flat accent-fill progress cell
    |     (draggable to seek when canSeek) + hover-inverted transport cells
    |     |
    |     v
    |   Loader { source: "AnimatedAlbumArt.qml" }
    |     active only when isOpen && isPlaying && AppleMusicArtService's
    |     animatedArtUrl !== "" — the static Image above is the permanent
    |     fallback under every other condition
    |
    +-- Ipc/MediaIpc.qml (target "media"): playPause()/next()/previous()/status()
          calls MediaService directly — MediaPanel's own transport cells
          also call MediaService directly, this exists for compositor
          keybinds and headless smoke verification, same division of
          labour WallpaperIpc/ThemeIpc have over their own singletons

Services/AppleMusicArtService.qml   (opt-in: media.appleMusicArt, off by default)
  onCacheKeyChanged (artist+album) -> _schedule()
    |  disabled or no artist/album -> animatedArtUrl = "" (no network at all)
    |  cache hit (including a cached miss) -> animatedArtUrl set/cleared, no network
    |  cache miss -> 1.5s debounce -> _lookup()
    v
  _lookup(): disk cache file test -> _search(): Media/applemusic.js#searchUrl()
    -> curl iTunes Search -> parseSearchResult()
    -> (first time) _fetchToken(): scrape web-player page -> asset bundle -> JWT
    -> _fetchEditorialVideo(): amp-api editorialVideo (undocumented, curl
       Authorization: Bearer <token>) -> parseEditorialVideo()
    -> _fetchMaster()/_fetchVariant(): m3u8 playlists -> pickVariant()/extractMp4Url()
    -> _download(): curl to a per-lookup temp file -> atomic mv into
       ~/.cache/formalshell/applemusic-art/<cacheKey>.mp4
    |  every step's failure (parse error, http error, missing token, no
    |  match) falls back to _store(key, "") — a cached MISS, so a track
    |  without animated art is never re-fetched every play — never an
    |  uncaught error
    v
  animatedArtUrl (file:// or "") -> MediaPanel's AnimatedAlbumArt.qml Loader
```

`Media/applemusic.js` (pure, `.pragma library`, TDD'd first —
`tests/tst_applemusic.qml`) owns every URL-building, response-parsing, and
cache-key/prune-decision function; `AppleMusicArtService.qml` is pure
side-effect orchestration around it, one fresh `Process` per `curl`/`find`/
`mv` call (never a shared/reused instance, so overlapping lookups for
different tracks never clobber each other's stdout) gated by a `_serial`
counter bumped on every reschedule so a slow in-flight lookup for a track
the user has since skipped past can never overwrite a newer result.

## Lock screen / PAM flow

```
Ipc/LockIpc.qml (target "lock") lock()
  |  reads lockScreen.locked straight back after calling lock() — catches
  |  WlSessionLock::realizeLockTarget()'s silent fail-open paths (no
  |  ext-session-lock-v1 support, no surface, no WlSessionLockSurface) that
  |  would otherwise report "ok" while the session stayed unlocked
  v
Surfaces/Lock/Lock.qml  (one Item wrapping WlSessionLock + both PamContexts;
                          see its own header comment for why a bare
                          PamContext can't be a WlSessionLock's direct child)
  lock(): sessionLock.locked = true; idleMonitor.enabled = true (imperative,
          not bound to `locked` — WlSessionLock only emits lockStateChanged()
          on its *unlock* path, verified against session_lock.cpp)
    |
    v
  WlSessionLock instantiates one LockSurface per output on its own
    (no manual Variants loop, unlike every other multi-output surface here)
    |
    v
  Surfaces/Lock/LockSurface.qml
    blurred backdrop: Image { source: Core.State.wallpaper } (hidden) feeding
      a MultiEffect { blurEnabled: true } — DESIGN.md's ONE blur exception
      in the whole shell (a ScreencopyView-based capture crashes the shell
      outright instead, see the file's header comment — never reintroduce it)
    oversized clock (Theme.font.display) + date + one bordered Cell {
      selected: authError !== "" } wrapping a password TextInput
    onAccepted -> Lock.qml#submitPassword(password)
    onPositionChanged/Keys.onPressed -> Lock.qml#wake() (clears a resume-guard trip)

  PamContext { config: "formalshell-lock" }         PamContext { config: lock.fingerprintPamService }
    password conversation, the sole unlock path        parallel conversation, only started when a
    onCompleted(Success) -> _unlock()                  reader is enrolled (empty string = never starts,
    onCompleted(else) -> authError =                   the only "enrolled" this shell can express —
      _resultError(result)  (WRONG PASSWORD /           no Fprintd binding); shares no state with the
      PAM ERROR / ACCOUNT LOCKED)                       password PamContext, so a pending scan never
                                                          blocks or disables the password field

  blanked: sessionLock.locked && (idleMonitor.isIdle || _resumeGuardActive)
    idleMonitor: dedicated IdleMonitor, respectInhibitors:false (a locked
      screen should blank regardless of an app-held inhibitor), timeout =
      lock.blankAfterSeconds (default 30)
    _resumeGuardActive: a 1s tickTimer compares Date.now() gaps — a jump
      much larger than one interval means the wall clock moved further than
      monotonic time would explain (suspend, or a stepped clock) — set true
      on that gap, cleared by real activity or idleMonitor.isIdle going false
```

A real deployment needs `security.pam.services.formalshell-lock = { };`
declared system-side (`nix/testvm.nix`'s own copy is the reference) — the
home-manager module alone cannot create a PAM service, only NixOS/system
config can. The `lock-before-sleep` contract (spec §8) is a separate,
narrower path: `nix/package.nix`'s `formalshell-lock-before-sleep` wraps
`qs ipc call lock lock` in `|| true; exit 0`, and `nix/hm-module.nix` binds
it to a `systemd --user` oneshot on `sleep.target` — so a lock failure can
never block suspend, verified directly by running the wrapper with no shell
instance up at all and reading `$?`.

## Idle → screensaver trigger graph

```
Services/IdleService.qml  (singleton, always-on, session-wide)
  one shared IdleMonitor, respectInhibitors:true (an app-held idle-inhibit
    or the compositor's own input-idle folding already keeps the whole
    session non-idle — no polling of our own needed)
  timeout = screensaver.timeoutSeconds (default 300) — armed exactly ONCE,
    after Core.Config.loaded first resolves, never re-bound live: a live
    binding recreates IdleMonitor's underlying ext_idle_notification_v1
    object a moment after startup (settings.json loads asynchronously) and
    that recreation was reproduced silently and permanently breaking
    isIdle propagation to QML for the rest of the process's life — a stale
    settings edit needing a shell restart is the accepted trade for idle
    detection actually working
    |
    v
  isIdle                                    (this is a DIFFERENT IdleMonitor
    |                                         instance from Lock.qml's own —
    |                                         that one is on-demand and
    |                                         respectInhibitors:false on
    |                                         purpose; see its header comment)
    v
Surfaces/Screensaver/Screensaver.qml  (one controller Item)
  _autoWant = IdleService.isIdle && !_suppressed
              && (!guardMediaPlayback || !MediaService.isPlaying)
    |  live, not edge-triggered: a track starting/ending mid-idle-stretch
    |  flips this immediately either way (spec §10's guard is a standing
    |  condition, not a one-time check)
  active = _forced || _autoWant
    |
    +-- Ipc/ScreensaverIpc.qml (target "screensaver"): start() sets _forced
    |     true; stop() sets _forced false AND _suppressed true (held until
    |     IdleService.isIdle next drops to false — i.e. real activity —
    |     so one dismissal doesn't get instantly re-triggered by the same
    |     idle stretch, but the NEXT idle cycle still fires normally)
    |
    v
  Variants over Quickshell.screens -> one PanelWindow per output
    (WlrLayer.Overlay, keyboardFocus OnDemand while visible)
    |  Canvas, repainted every 90ms off Screensaver/effect.js#frameState()
    |    (pure: columns/rows/frame-counter in, {char, brightness} grid out —
    |     TDD'd first, tests/tst_screensaver_effect.qml)
    |  drawn in Theme.font.family + Theme.color.accent — no spawned terminal
    |    windows, a themed matrix-rain effect on a plain Canvas
    |  any real key or pointer movement -> stop() (a MouseArea baseline
    |    swallows the single spurious positionChanged Qt fires the instant
    |    the surface becomes visible under an already-stationary cursor —
    |    reproduced directly: without it, an auto-triggered screensaver
    |    dismissed itself instantly and never re-triggered for the rest of
    |    the session)
    v
  onActiveChanged: active && lockAfterSeconds > 0 -> lockChainTimer (optional
    chain into Lock.qml#lock() after continuing to show that much longer;
    0, the default, disables the chain outright)
```

## Picker answer-channel handshake

```
Ipc/PickerIpc.qml (target "picker")
  summon()              -> picker.openWallpaper()
  select(dir, token)    -> picker.openSelect(dir, token)
  choose(path)           -> picker.choose(path)   (same action Enter/click use)
  close()                -> picker.close()
  status()               -> JSON.stringify(picker.status())
    |
    v
Surfaces/Picker/ImagePicker.qml  (a Panel.qml subtype — reuses the shared
                                   ledger popout, no bar cell of its own,
                                   anchorX:-1 falls back to the bar's right
                                   region same as every other IPC-only panel)
  openWallpaper(): _mode = "wallpaper"; _directory = picker.directory setting
  openSelect(dir, token): _mode = "select"; _directory = dir (or the
    setting, if dir is empty); _selectToken = token
    |
    v
  _scan(): `find <_directory> -maxdepth 1 -type f \( -iname *.png -o ... \)`
    over a Process (Quickshell has no directory-listing QML type, same
    technique CalendarEventsService already uses) -> _images[]
    |
    v
  Grid of Cell delegates, one per image, `selected: index === _cursor`;
  Left/Right/Up/Down move _cursor in 2D through Panel's shared keyPressed
  hook, Enter/click both call choose(path)
    |
    v
  choose(path):
    mode "wallpaper" -> Core.State.setWallpaper(path)   (the exact call
                         WallpaperIpc's set() makes — ThemeEngine's retheme
                         pipeline runs through the one trigger path, never
                         duplicated here)
    mode "select"    -> _writeSelectionFile({ token, value: path })
    root.close()
    |
    v (mode "select" only, and only if a request was actually pending)
  $XDG_STATE_HOME/formalshell/picker-selection.txt
    written via a Process (never FileView.setText(), which silently skips
    both the write and its saved() signal when the new text is
    byte-identical to what's already on disk)
    |
    +-- onIsOpenChanged: closing without ever choosing (Escape,
          click-outside, or PanelRegistry preempting this panel for
          another one) still resolves the caller's poll loop, writing
          { token, cancelled: true } instead
```

This is the exact request/answer handshake `Menu/MenuIpc.qml`'s
`select()`/`input()` already established (see `Menu.qml`'s header comment
for the full rationale: an `IpcHandler` call is synchronous request/
response, so the UI's eventual answer can't ride back on the call that
opened it) — reused rather than reinvented, correlated the same way by a
caller-supplied token.

## Greeter / greetd flow

```
services.greetd  (nixosModules.formalshell-greeter)
  default_session.command = <sessionScript>   (a module-generated wrapper,
                                                not formalshell-greeter itself)
    |
    v
sessionScript  (nix/nixos-greeter-module.nix)
  exports XDG_RUNTIME_DIR/HOME/XDG_CONFIG_HOME/WAYLAND_DISPLAY/extraEnvironment
    (greetd's worker.rs resets the session environment to PAM's own envlist
     — nothing this module's systemd units export reaches the script for
     free, confirmed by reading greetd's own Rust source, not the nixpkgs
     module)
  backgrounds compositorPackage (default pkgs.sway), waits for its Wayland
    socket, THEN runs formalshell-greeter in the FOREGROUND — greetd-ipc(7):
    "the session will start after the greeter process terminates", which is
    what lets the script know the exact moment that happens, for
    postGreeterCommand and verification alike (never an async compositor
    `exec` line racing that signal)
    |
    v
greeter/greeter.qml  (Quickshell.Services.Greetd; no WlSessionLock — greetd
                       already isolates this process into its own disposable
                       compositor with no other client ever attached, so
                       there's nothing for a lock primitive to exclude here)
  Connections { target: Greetd }
    onAuthMessage(message, error, responseRequired, echoResponse)
      -> _promptMessage/_promptEcho/_awaitingResponse drive the one input
         cell's meta label and TextInput.echoMode
    onAuthFailure(message) -> authError = message (inverts the input cell,
      shows greetd's own PAM string verbatim — e.g. "pam_authenticate:
      AUTH_ERR" — no second mapping table like Lock.qml's PamResult, since
      greetd hands back plain text, not an enum)
    onError(message) -> authError = message, UNLESS authError is already
      set: greetd (0.10.3) unconditionally follows every auth_error with a
      cancel_session it can no longer deliver, and the resulting "unable to
      send message: Connection refused" must never clobber the real
      onAuthFailure text already showing (a confirmed, fixed defect, 0757fc2)
    onReadyToLaunch() -> Greetd.launch(sessionCommand, [], true)
      ("Performing animations and such should be done *before* calling
       launch" — Greetd::launch's own doc; nothing here to animate)
    |
    v (successful auth)
greetd starts sessionCommand as the real user's session (from
  greeter.sessionCommand in settings.json when run loose, or the static
  settings.json nixos-greeter-module.nix writes for the `greeter` account
  when deployed via the module); formalshell-greeter exits,
  sessionScript's postGreeterCommand runs (a verification hook a normal
  login ignores), the module's compositor is torn down
```

`Quickshell.Services.Greetd` exposes no session/user enumeration at all
(confirmed against greetd's own `connection.cpp` —
`create_session`/`cancel_session`/`post_auth_message_response`/
`start_session` is the entire wire protocol), so unlike the lock screen
there is deliberately no picker here: typing a username into the one input
cell is the same free-text conversation step the password prompt already
is, just started by this process instead of a display manager.
`dev/smoke-greeter.sh` (`just vm-greeter`) drives the whole chain above with
real `wtype` keystrokes across the `test` -> `greeter` system-account
boundary rather than an IPC shortcut, the same "verify the action, not the
input method" reasoning `LockIpc.qml`'s missing `unlock()` already
establishes.

## Adding a backend

1. Create `shell/Compositor/<name>/<Name>Backend.qml`. QML can't literally
   `extend` `BackendBase` as its root type (its properties are read-only),
   so every backend is a duck-typed `Scope` (needs a default `children`/`data`
   property to nest `Socket`/`Timer`/etc. children — plain `QtObject` doesn't
   have one) that declares the exact same property/signal/function names as
   the contract.
2. Populate `workspaces`/`windows`/`outputs`/`focused*` from whatever IPC or
   Quickshell module the compositor exposes, normalizing every id to a
   string at the boundary.
3. Implement the six action functions against that compositor's real
   dispatch mechanism.
4. Wire detection into `CompositorService.qml`'s `compositor` property and
   its backend-selection block.
5. Verify with a nested smoke script mirroring `dev/smoke-niri.sh`: build,
   launch nested, screenshot, and (if the compositor has an IPC CLI) assert
   the `debug dump` JSON has `available: true` and ≥1 workspace.
