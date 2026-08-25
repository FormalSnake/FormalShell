# M45: lock, greeter, picker, polkit, console, capture, hot corners, sweep

**Date:** 2026-08-25
**Status:** approved, pre-implementation
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
("Lock and greeter", "Picker", "Depth", "Configuration"); `docs/DESIGN.md`
§3, §5. Spec wins on conflict.
**Builds on:** M41 to M44. Task 3 (the sweep) runs only after M42, M43 and
M44 have all merged, since it deletes what their unported files still read.

## Why

The remaining surfaces are the modal ones (lock, greeter, polkit, picker,
console, capture) plus the bar widgets with no panel, and the compatibility
mapping from M41 D3 that let everything keep compiling. Dither becomes the
opt-in the owner asked for, and hot corners get the arbitrary action the
owner asked for on 2026-08-25.

## Scope

In: `Surfaces/Lock/*`, `greeter/*` (shares `AuthPrompt`),
`Components/AuthPrompt.qml`, `Surfaces/Background/Background.qml`,
`Surfaces/Gallery/*` (the picker), `Surfaces/Polkit/PolkitDialog.qml`,
`Console/*` surface bits, `Surfaces/Capture/RegionPicker.qml` chrome,
`Surfaces/HotCorners/*` + `HotCorners/corners.js`, `Surfaces/Plugins/PluginOverlay.qml`,
the bar widgets `Tray`, `Indicators`, `Chevron`, `Visualizer`,
`KeyboardLayout`, `CommandModule`, `QmlModule`, `PluginBarModule`,
`Components/{Cell,Theme,MetaLabel,DogEar}` cleanup, `tokens.js` spacing
prune, settings defaults, rig legs, docs. Out: screensaver (unchanged by
spec), niri (M46).

## Locked decisions

- D1: M42 D1's exit checks on every file touched.
- D2: lock and greeter share `AuthPrompt`: wallpaper (plain by default),
  a 0.5 black scrim, a centred column with the clock in `displayLarge` x3
  mono `semibold` tabular, the date as a `SectionLabel`, one `Input`
  (`popupWidthNarrow`) with the ring while focused, `Wrong password` as its
  error state; fingerprint and blank-after timers unchanged.
  `lock.dither` (default false) and `wallpaper.dither` (default flips to
  false) gate `DitherImage` on the lock backdrop and the background; the
  components stay, the OSD/pending uses are already gone.
  `LockSurface.qml`'s header comment about `ScreencopyView` stays.
- D3: picker grid per spec "Picker": `radiusMd` thumbnails with a 1px
  `border`, ring cursor, `Dark | Light` as a segmented control (reuse
  M43's local one by promoting it to `Components/Segmented.qml` if M43
  built one, else build it here).
- D4: polkit is a centred `Card` `radiusXl` over the scrim with the
  request text sans, the `Input`, `outline` Cancel and `default` Authenticate
  buttons. Console keeps its terminal; only the shell-drawn edge (if any)
  uses tokens. Capture's region picker draws its selection outline in
  `primary` 2px and its labels in mono on `popover` chips.
- D5: hot corners: `hotCorners.<corner>` accepts, besides `none`,
  `screensaver` and `lock`, any launcher action string (`@ipc:<target>.<fn>[:<arg>]`
  or a command line spawned via the compositor backend, exactly the
  strings `Menu/actions.js` already resolves; reuse its resolver, do not
  write a second one). `docs/USAGE.md` gets a `hotCorners` section with
  the four keys, the defaults and two examples.
- D6: the sweep deletes `Cell`'s `accent`/`ink`/`standalone`/`pending`
  props, `Theme.fontFamily`, `MetaLabel.qml`, `DogEar.qml`, spacing steps
  nothing reads (`rg` proves each), and rewrites every remaining reader
  (bar widgets without panels, plugin overlay, capture) onto the new API.
  `tst_cell_states.qml` loses the mapped-prop cases.

## Tasks

### Task 1: lock, greeter, background

D2. Files: `Lock.qml`, `LockSurface.qml`, `AuthPrompt.qml`, `greeter/*`
QML that styles the prompt, `Background.qml`, `Config` defaults, tests,
`docs/USAGE.md` (`lock.dither`, `wallpaper.dither` default). Verify
`just vm-smoke --lock` and `--wallpaper` ported to `dev/smoke.sh` (the
wallpaper leg's dither assertions become conditional on the setting; with
the default off it asserts the solid fixture paints flat), `just vm-greeter`
if it runs on the Hyprland VM, PNGs read.
Commit: `feat(lock): shadcn auth prompt, dither opt-in`.

### Task 2: picker, polkit, console, capture, hot corners

D3, D4, D5. Files listed above plus `corners.js`, `Menu/actions.js` reuse,
tests (`tst_hot_corners*`, picker tests). Verify `--picker`, `--hotcorner`,
`--console` on `dev/smoke.sh` (port what is missing), PNGs read.
Commit: `feat(surfaces): picker, polkit, capture and hot corner actions`.

### Task 3: the sweep (after M42, M43, M44 merge)

D6. Verify `rg -n 'accent:|ink:|standalone:|pending:' shell` shows only
non-Cell uses, `rg -n 'Theme.fontFamily\b|MetaLabel|DogEar' shell tests`
empty, `just test`, `just vm-lint`, base `just vm-smoke` and `--tray`
(port), `--bar-layout` (port), `--chevron` (port) PNGs read.
Commit: `refactor(components): drop the ledger compatibility props`.

## Done when

Three commits in, every file under `shell/` passes D1, the listed rig legs
are green with PNGs read, `hotCorners` accepts an action string with a
test, `just test` and `just vm-lint` pass.
