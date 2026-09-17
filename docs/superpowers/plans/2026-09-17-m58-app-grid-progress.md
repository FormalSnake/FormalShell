# M58: the launcher's app grid, and the media panel's progress that stalls

**Date:** 2026-09-17
**Status:** in progress on `m58-app-grid` (worktree `../FormalShell-m58`).
**Spec:** this file; the 2026-08-25 and 2026-07-27 specs and `docs/DESIGN.md`
win where it is silent.

## Owner's ask (2026-09-17)

"Similar to the emoji grid, a grid like app view option that is disabled by
default but enabled on my system. It must cleanly still show the app name,
similar to what macOS does. I want to see my app icons basically." And: "in
the now playing panel when I keep it open to look at it, the progress bar
doesn't progress properly until I reopen the bar."

## Decisions

**G1 The key.** `menu.appGrid` (bool, default false), read through
`Config.get`, documented in `Config.qml`'s header and `docs/USAGE.md`. The
owner's own nix config turns it on; the shell's default stays the list.

**G2 What becomes a grid.** The launcher's app results only: the root level
with an empty query (the frecency-ordered apps) and an app search. Every
other row kind (commands, settings routes, the calculator, files) keeps its
row. When a result set mixes apps with other kinds, the apps draw as a grid
block and the rest as rows under it, in the order the ranking already gave
them; the ranking itself does not change.

**G3 The cell.** macOS Launchpad's reading: the app's icon large, its name
under it, centred, `body` size, one line, elided on the right, with the full
name in the shell's `Tooltip` when it was cut.
The icon resolves the way rows already resolve it (`shell/Menu/icons.js`),
with the same fallback glyph. The cell is the emoji and wallpaper grids'
own cell contract (cursor ring, `accent` hover, `radiusMd`), not a new one.
Columns come from the card's width and a fixed cell width so the grid
reflows with `popupWidth` rather than stretching cells.

**G4 Keyboard and pointer.** The same two-dimensional cursor the emoji grid
has: arrows move by cell, Enter launches, typing filters, Tab and the action
bar behave as they do on a row (the secondary actions an app row offers
must stay reachable from a cell). Wheel scrolls the grid; `menu status`
reports `scrollTop` and the cursor as it does for the picker.

**G5 IPC and the rig.** `menu status` says which view the level drew
(`view: "appGrid"`), so a leg can tell without reading pixels. A new leg
`--app-grid` pins `menu.appGrid` true in the settings fixture, opens the
launcher, and proves: the view, a cell for a known desktop entry with its
name under its icon in the frame, arrow keys moving the cursor across and
down by a column count read off `menu status`, a search narrowing the grid,
Enter launching through the same path a row takes, and with the key absent
the launcher still drawing rows.

**B1 The progress that stalls.** The owner's steps are ground truth: the
media panel left open, a track playing, the progress track and the elapsed
time stop advancing (or advance wrongly) until the panel is reopened. Find
the cause before changing anything; candidates to rule in or out, none
assumed: `MediaService`'s 1s `Timer` (`running: root.isPlaying`) against a
player whose `isPlaying` or `activePlayer` changed under it, a binding on
`position` broken by an imperative write during a seek or a track change,
M56's per-frame `positionChanged` clock in `MediaPanel.qml` fighting the
1s one, the progress `Slider`'s own value binding being severed by a drag,
and `MprisPlayer.position` semantics in Quickshell's C++ (read the source).
Reproduce it in the rig first (an mpv MPRIS fixture, the panel held open
for 20s or more across a track change, a seek and a pause/resume, `media
status` position sampled against the frame's own progress fill), fix the
cause, and leave a leg assertion that fails without the fix.

## Tasks

One subagent per task, in order, each ending on its own verification with
the output read, then one commit. Every VM command goes through
`dev/vm-lock.sh`, background ones included: another session shares the VM.

### Task 1: the progress that stalls (B1)

Verify: `just test`, `dev/vm-lock.sh just vm-lint`, the reworked or new leg
green twice, `--media` and `--lyrics` green.

### Task 2: the app grid (G1 to G5)

Load `frontend-design`, `better-ui`, `better-layout`, `better-typography`,
`better-accessibility` and `emil-design-eng` first; `docs/DESIGN.md` wins
over them. Keep the grid in its own file under `shell/Surfaces/Menu/views/`
with the smallest possible hooks in `Menu.qml`: another session is moving
`Menu.qml` onto `Components/Drawer.qml` (M57 Task 6 and 7) and will merge
over this. Verify: `just test`, lint, `--app-grid` green twice with the
PNGs read, `--menu`, `--emoji`, `--picker`, `--keybinds` green.

### Task 3: the record

`CLAUDE.md`'s leg list, `docs/USAGE.md`, `docs/DESIGN.md` if the grid adds
a rung, this plan's Status and deviations. Then merge to main, push, turn
`menu.appGrid` on in the owner's nix config, rebuild the hosts.

## Evidence

**B1, the progress that stalls.** Reproduced by `--media-progress`
(`dev/smoke.d/media_progress.sh`): the panel opened once over a real mpv and
never touched again, the drawn fill measured off the frame and compared with
the position `media status` reports. `media status` was never wrong, which is
why IPC alone could not see this: the panel knew the position and drew a
different one.

The cause is `Track.qml`'s `Behavior on width` on the fill, whose own header
says it is for a level set in steps. The media panel's progress is swept, and
with the lyrics pane up `MediaPanel.qml`'s per-frame `positionChanged` moves
the target again before the animation has been ticked, so it restarts from
zero every frame and the fill stops where it stood. Any moment the per-frame
clock stops (a pause, the panel closing) the fill snaps forward, which is the
reopen the owner was doing.

Before, with lyrics synced and the panel held open: position 29.2 -> 213.5
over 50s, drawn fill frozen at 0.0660 of the track the whole way (the seek to
203s wanted 0.5076). Without lyrics the 1s clock left it within 0.006.
After (`swept: true` on the progress track): drawn tracks want within 0.006
at all eighteen samples, 0.5031 against a wanted 0.5077 after the seek.
