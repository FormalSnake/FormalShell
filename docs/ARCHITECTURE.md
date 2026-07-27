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

`shell/shell.qml` is the entry point (`//@ pragma ShellId formalshell`). It
instantiates a `Variants` over `Quickshell.screens`, spawning one `Bar` per
connected output, plus a top-level `Ipc` scope for debug/introspection.

## Tree layout

```
shell/
  shell.qml                  ShellRoot; Variants over Quickshell.screens -> Bar/Background per screen
  Core/
    State.qml                 singleton — state.json (wallpaper, mode), FileView+JsonAdapter
    Theme.qml                 singleton — Theme.color live off theme.json, Flexoki fallback statics
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
  Ipc/
    DebugIpc.qml               IpcHandler target "debug", function dump(): string
    ThemeIpc.qml               IpcHandler target "theme", retheme()/mode()/status()
    WallpaperIpc.qml           IpcHandler target "wallpaper", set()/get()
  Surfaces/
    Bar/
      Bar.qml                  PanelWindow; three-region RowLayout
      widgets/
        Workspaces.qml          Repeater over CompositorService.workspaces
        ActiveWindow.qml        focused window's appId + title
    Background/
      Background.qml            per-screen PanelWindow on WlrLayer.Background; shows State.wallpaper
tests/
  tst_niri_reducer.qml         qmltestrunner tests for reducer.js
  tst_matugen_builder.qml      qmltestrunner tests for Theme/matugen.js
  tst_palette.qml              qmltestrunner tests for Theme/palette.js
dev/
  smoke-niri.sh                 nested-niri build+screenshot(+debug dump)(+wallpaper) loop
  smoke-hyprland.sh             same, nested Hyprland
nix/
  package.nix                   stdenvNoCC derivation wrapping `qs -p`
  hm-module.nix                 home-manager module (programs.formalshell)
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
`JSON.stringify({ compositor, available, workspaces, windows, focusedWindowId, focusedWorkspaceId })`
read straight off `CompositorService`. This is the textual verification hook
used by both smoke scripts (`qs ipc --any-display -p <path> call debug dump`)
and by hand during backend development — it's the fastest way to confirm a
backend is wired correctly without reading a screenshot.

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
