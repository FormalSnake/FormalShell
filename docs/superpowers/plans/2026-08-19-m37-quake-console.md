# FormalShell M37: quake console

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Origin, owner ask (2026-08-19):** omarchy quattro's Quake console
(`default/hypr/qconsole.lua`, 83987718 — a dimmed special workspace
covering the top half, seeded with the default agent, bound to a key
that works from any workspace), "i want the quake console".

## Constraints

- The console is a real **compositor window** (a terminal), never a
  shell surface: the shell is pure QML/JS and has no terminal
  emulator. The shell owns the spawn, the placement and the toggle;
  the terminal owns everything inside the frame.
- Omarchy gets its overlay free from a Hyprland special workspace.
  niri has no special workspace and **no hide primitive at all**
  (`niri msg action` in the testvm, niri 26.04: no minimize, no
  scratchpad), so hiding means parking the window on another
  workspace. That is the whole design difference between the two
  backends, and it stays inside the backend contract.
- **State is derived, never stored.** Visible = the console window
  reports the focused workspace. That survives a shell restart, a
  compositor-side move, and the user parking it themselves, with no
  state.json key to drift. The window id lives in memory only for the
  in-flight spawn.
- Toggle is one rule with three arms: no window → spawn, wait for the
  map, float, place, focus; window on the focused workspace → park it;
  window anywhere else (parked, or a workspace you walked away from)
  → bring it here, float, place, focus. The third arm is what makes
  the bind work "anywhere you want" rather than only where the console
  was opened.
- The session persists across a hide. Killing and respawning the
  terminal would be trivially simpler and would throw away the running
  agent, which is the point of the feature.
- Spawn/map/place follows the webcam-overlay path already proven in
  `RecordingService` (`shell/Services/RecordingService.qml:560-660`):
  spawn with a known app id, poll `CompositorService.windows` for it,
  float, settle-poll `rect`, then place. Honest unavailable states per
  CLAUDE.md: a compositor that cannot park, a command that opens no
  matching window, a `console.command` of `[]` — each gets its own
  notification and no half-placed window left behind.
- No new blur, no radius, no shadow: the console is the terminal's own
  window, so DESIGN.md's surface rules do not apply to its contents,
  and the shell adds no chrome around it.

## Config (`~/.config/formalshell/settings.json`)

- `console.command` (array of strings, default `["ghostty",
  "--class=dev.formalshell.console"]`) — argv, no shell interpolation.
  It must make the terminal announce `console.appId`; every emulator
  spells that flag differently (`foot --app-id`, `alacritty --class`,
  `kitty --class`, `ghostty --class`), which is why this is argv and
  not a command name.
- `console.appId` (string, default `"dev.formalshell.console"`) — what
  the shell matches the mapped window against. Change it with the
  flag above or the console never finds its own window.
- `console.share` (number, default `0.5`, clamped `0.2..1`) — share of
  the usable height the console covers, measured from under the bar.

## IPC

`console` target: `toggle()`, `show()`, `hide()`, `status()` (JSON:
`{available, appId, windowId, visible, spawning}`). Unknown state is
never faked: `windowId` is `""` when no console window exists.

### Task 1: backend parking contract

**Files:** modify `shell/Compositor/BackendBase.qml`,
`shell/Compositor/niri/NiriBackend.qml`,
`shell/Compositor/hyprland/HyprlandBackend.qml`,
`shell/Compositor/CompositorService.qml`; create
`shell/Console/park.js`; create `tests/tst_console_park.qml`.

**Produces:** `windowParkingAvailable` (false on the null backend),
`parkWindow(id)`, `unparkWindow(id)` — both leave focus alone, so the
service decides when to focus. niri: `MoveWindowToWorkspace
{window_id, reference, focus:false}`, park target chosen by
`park.js`'s pure `parkTarget(workspaces, windows, focusedWorkspaceId,
focusedOutputName, consoleId)` (an empty workspace on the focused
output, else any non-focused one, else `""` = cannot park); niri
always keeps a trailing empty workspace, so `""` is the
single-workspace-single-output edge only. Hyprland: the park is
`special:formalshell-console` (`hl.dsp.window.move({window=…,
workspace="special:formalshell-console"})` on Lua, `movetoworkspacesilent
special:formalshell-console,<selector>` legacy) and unpark targets the
focused workspace id the same way. Verify: `just vm-test`,
`just vm-lint`. Commit (`feat(compositor): window parking`).

### Task 2: ConsoleService, config, IPC

**Files:** create `shell/Services/ConsoleService.qml`,
`shell/Console/geometry.js`; modify `shell/Services/qmldir`,
`shell/Core/Config.qml` (key docs), `shell/shell.qml`; create
`shell/Ipc/ConsoleIpc.qml`, `tests/tst_console_geometry.qml`.

**Produces:** the three-arm toggle above; `geometry.js`'s pure
`consoleGeometry(screen, barHeight, share, margin)` → the absolute
logical box (full width less a margin either side, top edge under the
bar, height `share` of what is left), so a rescaled output re-places
correctly on the next show instead of freezing at first-map size
(omarchy hit the same thing and fixed it with a gap rule); the map
poll and settle poll cloned from RecordingService's two timers, with
its 5s bounds and its give-up notification shape. Verify:
`just vm-test`, `just vm-lint`. Commit (`feat(console): quake
console`).

### Task 3: smoke leg and docs

**Files:** modify `dev/smoke-niri.sh`, `dev/vm.sh` (artifact pull),
`CLAUDE.md` (smoke list), `docs/USAGE.md`.

**Produces:** `dev/smoke-niri.sh --console`, with a settings fixture
pointing `console.command` at foot (`["foot", "--app-id=formalshell-console"]`,
already in the testvm for the tray stub's sake) and `console.appId` to
match. Three `console toggle` calls off one timeline:
`console-open.png` (foot dropped down over the top half, bar intact
above it), `console-parked.png` plus a `status` dump asserting
`visible:false`, then a third toggle whose `status` must report the
**same `windowId` as the first** — the session-survives-a-hide claim,
and the one assertion that a spawn-and-kill implementation would fail.
USAGE documents the keys, the IPC target, and the niri/Hyprland bind
(`Mod+Plus`, the shortcut the ask names). Verify: `just vm-smoke
--console` — Read all three PNGs. Commit (`feat(console): smoke leg`).

## Review checkpoint

After Task 3: whole diff read, all three PNGs read, park/unpark
asserted against a real niri (Err replies on the shared request socket
are silently dropped by design, so the screenshots are the only proof
the action shapes are right).
