# M53: continuous motion, the Vercel OS

**Date:** 2026-09-09
**Status:** implemented 2026-09-09. Tasks 1 to 8 landed on
`m53-continuous-motion`, oldest first: 0b67449 (tokens, transitions,
primitives), 0a3b7fa (bar), 99b49de (panel geometry and the keyboard
path), b167743 (panel handoff), f21bdfd (keyed lists, cursor travel),
d6394d0 (launcher and centre seams), aa8349f (modals, lock, picker),
05d0062 (tooltip group). Task 9 is the docs commit carrying this line.
D1 (the Vercel identity, nothing overshooting) is reversed by the owner
on 2026-09-09: the curves and the shape live in
`docs/superpowers/plans/2026-09-09-m54-expressive-motion.md`, and D2 to
D10 are what they run on.

Addendum 2026-09-09, after the owner rebuilt a real host on the branch:
"nothing really looks different. In caelestia there are nice morph
animations, here panels still open the same way." The M51 recipe this plan
kept (fade, 0.97 zoom, an 8px slide, 180ms) is too small to register, and
most of what there was never reached the screen at all: a surface maps its
window on the tick it opens, the compositor takes a good part of the enter
to put that surface up, and the animation had run out behind it. So the
open itself became the morph. `Presence` grew two modes beside `fade`.
`emerge` is the drawer every anchored surface now takes (the panels, the
chevron's and the tray's second bars with them, the notification centre and
the OSD): the card sits its own extent behind the edge it hangs off, cut at
that edge by a clip, and travels out on `emphasized` with no fade and no
zoom while its contents come up behind it. `unfold` is the launcher: the
card is drawn at its search row on `fast` and its height carries the level
under the rule on `emphasized`, revealed by the growing edge rather than
pushed into place. Polkit and the plugin overlay keep the modal zoom, the
tooltip and the bar keep `fade`, and every mode now waits on the surface
being mapped before its clock starts. D1 to D10 stand; what changed is the
surface recipe M51 D2/D4 set, which D5's handoff is untouched by (it still
bypasses Presence). `dev/smoke.d/panel_emerge.sh` and
`dev/smoke.d/menu_unfold.sh` sample the two opens frame by frame.

Where the shipped code deviates from the task text, on purpose:

- Task 2: a positioner `add` Transition animates the child's own
  `opacity`, which drops its binding and left cells stuck invisible on the
  first `--bar-layout` run. `Rail` carries `move` only; every arrival in the
  shell fades through a Behavior on a property of its own instead.
- Task 4 (D5): two Wayland surfaces cannot commit a frame together, so two
  frames on one trajectory drew a doubled edge a frame's travel apart
  (160px in the rig). The handoff is two phases instead: the contents
  crossfade on the old rect on `standard`, the old window is cut, and the
  one card left travels on `emphasized`. 380ms end to end, the one gesture
  over the 250 ceiling, and it reads as one card.
- Task 5 (D4): the launcher's cursor is a rectangle in the view's
  contentItem, not the ListView `highlight`: a `MenuRow` carries its section
  band inside the delegate, so a highlight sized to `currentItem` would
  swallow the heading. `highlightMoveDuration: 0` stays for the scroll
  follow at key-repeat speed.
- Task 7: the lock's `AuthPrompt` column takes no Behavior of its own. It
  is centred and frameless, so the field's own height ramp re-centring the
  block frame by frame is the morph; a second one would only slide it.

Not this plan's, found by its runs and left as they are (D8): `--bar-position`
asserts a `bar chevron status` shape M52 (78ee367) changed, and
`--screenshot`'s drive calls `screenshot region` with no argument while
`ScreenshotIpc.region` has required one since 08d9067; both fail on `main`
before this branch. Combinations that cannot share a session, run singly:
`--gallery --chevron`, `--chevron --bar-layout`, `--panel <name>` with
`--panel-at`, `--bar-position` with `--panel`, `--capture --screenshot`, and `--tooltip`
with `--toggles` (the hub is a launcher route covering the output, so the
panel header the tooltip parks on is gone). Task 9's second session ran
as `--panel network --tooltip` and `--toggles` on their own.
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` §1 Motion is the rulebook; Task 9
amends it and this plan records why. M51
(`docs/superpowers/plans/2026-08-31-m51-motion-polish.md`) shipped the
surface recipe this plan builds on; its decisions stand except D8, amended
below.

## Owner's ask (2026-09-09)

"Make my shell feel as smooth and well animated as caelestia. Caelestia
focuses a lot on morphing animations everywhere, I just want my shell to
not be as mouse based as caelestia (I am a keyboard user)." Then: "what I
want my shell to be is what if Vercel designed an OS. Caelestia has their
polish but they follow Material You. Vercel acquired shadcn because it
follows their language so much."

## What caelestia does, and what transfers this time

caelestia-dots/shell is GPLv3: mechanics and values only, no ported code.
Read at its `main` on 2026-09-09. Its feel comes from three habits, not
from Material's curves:

1. Every geometry change is a Behavior. Wrappers bind `implicitWidth` and
   `implicitHeight` to their content and carry `Behavior on` both, enabled
   while the surface is open, frozen (binding broken) on close. The
   dashboard's tab indicator is one rectangle with `Behavior on x` and
   `Behavior on implicitWidth`; its pages are a Flickable whose `contentX`
   has a Behavior. Nothing that moves or resizes does so in one frame.
2. Content swaps fade. A loader that changes its component fades out,
   swaps, fades in; an empty state fades and scales in over the list it
   replaces; a mode change is a state with a crossfade.
3. Surfaces are one item that never unmaps, so a panel replacing another
   is a size change of one shape, not two surfaces crossing.

What it uses that this shell does not: M3's expressive spatial curves
(`expressiveDefaultSpatial` overshoots to 1.21, `Anim {}` defaults to
500ms) and M3 chrome. The owner's identity is Vercel and shadcn, so the
curves stay Emil Kowalski's: OutQuint (`cubic-bezier(0.23, 1, 0.32, 1)`)
for anything entering, exiting or responding, InOutQuart
(`cubic-bezier(0.77, 0, 0.175, 1)`) for anything travelling or resizing on
screen. Nothing bounces. Chrome durations stay at or under `emphasized`
250. What Vercel does that caelestia does not, and this plan takes: the
shared-layout habit (Framer's `layout` prop: a highlight, a tab pill or a
tooltip that travels between triggers instead of appearing at the next
one), `AnimatePresence` on list rows (rows fade in, displaced rows slide),
and a command menu whose list never rebuilds under the cursor.

## Findings (audit 2026-09-09, four read-only passes, vetted at ef3befa)

Tokens are clean: zero literal durations in `shell/`, four easing tokens,
`motion.enabled=false` still means instant. What snaps is geometry and
content, everywhere the M51 recipe did not reach:

1. Not one `Transition {}` exists in `shell/` (`rg 'Transition \{'` is
   empty), so every positioner reflows in one frame: the bar's three
   regions, tray and indicators are bare `Rail` Grids
   (`shell/Components/Rail.qml:11`), every panel list is a `Repeater` in a
   `Column`, the launcher's breadcrumb and action bar are `Row`s.
2. The launcher's model is a fresh JS array per keystroke
   (`shell/Surfaces/Menu/Menu.qml:797` `_displayRows`, consumed at
   `:2403`), which is a model reset: rows never move, they are rebuilt.
   The process table does the same off a 2s poll
   (`shell/Surfaces/Menu/views/MonitorView.qml:1576`, `:114`).
3. The cursor is one `Rectangle` per row switched by `visible`
   (`shell/Surfaces/Menu/MenuRow.qml:175`, `MonitorView.qml:1606`,
   `shell/Components/Panel.qml:148` for panel rows), and the list's own
   follow is a hard jump (`Menu.qml:2416` `highlightMoveDuration: 0`).
   Arrow keys, the owner's most frequent input, move nothing.
4. Panel A to panel B is two windows crossing: `Panel.qml:253` closes A
   and opens B in one tick, A exiting on `surfaceExit` while B enters on
   `surface`, both zooming from the bar edge's centre
   (`Panel.qml:435` `transformOrigin: presence.transformOrigin`), and a
   keyboard open carries no anchor at all (`shell/Ipc/PanelIpc.qml:53`
   `toggle(name)` passes none), so every `panel toggleAt` lands at the far
   end of the bar (`shell/Components/geometry.js:30`).
5. The panel morph is half wired: `_frameY` and `_ownerShift` read the
   target `_frameHeight` (`Panel.qml:206`, `:214`) while `frame.height`
   reads the animated `_morphHeight` (`:427`), so on a bottom, left or
   right bar the card detaches from its edge for 250ms; `frame.width`
   (`:426`) has no morph at all, and `frame.x`/`y` have no Behavior.
6. Arrowing past the visible rows of a tall panel never scrolls
   (`Panel.qml:148` `moveCursor` writes `cursorIndex` only; nothing writes
   `contentFlickable.contentY`). A correctness bug before a motion one.
7. Icons swap glyphs in one frame (`shell/Components/Icon.qml:20`, 19 live
   ternary consumers, e.g. `AudioWidget.qml:44`); the chevron alone
   crossfades (`ChevronWidget.qml:88`). `Segmented`'s selection is a
   per-segment fill (`shell/Components/Segmented.qml:98`). Cell fills and
   borders snap by contract (`shell/Components/Cell.qml:282`).
8. Bar cells appear and vanish in one frame (`shell/Surfaces/Bar/Bar.qml:538`
   `visible: entryLoader._shown && ...`, twelve widgets flip `shown`), the
   region boxes bind to un-animated widths (`Bar.qml:705`, `:719`, `:737`),
   six width-varying cells lack the `Behavior on implicitWidth` their
   twelve siblings carry (`BellWidget.qml:62`, `MicWidget.qml:51`,
   `KeyboardLayoutWidget.qml:51`, `CommandModule.qml:133`,
   `QmlModule.qml:31`, `PluginBarModule.qml:79`), and the two morphing
   cells swap their text under the morph (`ActiveWindow.qml:102`,
   `NowPlaying.qml:87`).
9. Two animations restart instead of retargeting:
   `CalendarPanel.qml:244` `monthSwapAnim.restart()` with `from: 0` (a
   held bracket strobes the grid) and the level entrance
   (`Menu.qml:1567`, acceptable, not key-repeatable). `KeyCatcher` never
   reads `event.isAutoRepeat` (`shell/Components/KeyCatcher.qml:32`), so
   Hyprland's 25/s repeat reaches every consumer as fresh presses.
10. Seams inside surfaces: the level entrance covers four items, not the
    breadcrumb, segmented, preview or action bar (`Menu.qml:2292`, `:2356`,
    `:2718`, `:2811`); a query flipping to the emoji or wallpaper grid
    bypasses it (`Menu.qml:590`, `:1536`); the rows area snaps to its new
    height under the card's 250ms morph (`Menu.qml:2393` vs `:2018`); the
    empty state pops (`:2442`); the centre's section wrappers toggle
    `visible` above rows that collapse smoothly (`Center.qml:589`, `:597`);
    `Input`'s error caption grows the card in one frame (`Input.qml:34`)
    and neither polkit nor the lock column morphs; `PluginOverlay` has no
    scrim (`PluginOverlay.qml:105`); the region picker's Tab-cycle
    teleports the selection rectangle (`RegionPicker.qml:761`) and its
    mode tabs are a snapping fill (`:990`); the lock's blank and wake are
    hard cuts (`LockSurface.qml:137`, `:155`, `:185`).
11. Tooltips: one `Tooltip` window per cell, each with its own 400ms delay
    (`Tooltip.qml:64`, `Cell.qml:238`), so walking the bar pays the delay
    at every cell. Pointer-only; ranked last.
12. Cohesion: `emphasizedEasing` is OutQuint (`shell/Core/Theme.qml:298`)
    while DESIGN.md and Theme's own comment at `:311` call the move curve
    InOutQuart; `Switch.qml:78` and `Track.qml:85` move on `fast`.
    `NetworkPanel.qml:130` keys its dedupe on the raw `signalStrength`, so
    a 1% tick re-sorts rows under the user, and `_wifiRows` (`:122`) maps
    and sorts while the panel is closed.

Already right, leave alone: `Toasts.qml` end to end, `Center.qml`'s row
pool and collapse, `Presence.qml`, the OSD retrigger, `MarqueeText`, the
urgent pulse, Theme's 27 colour Behaviors, and the lock entrance.

## Locked decisions

- D1 Identity is Vercel and shadcn, not Material You. Easings stay
  `Theme.motion.easing` (OutQuint) for enter, exit, content and cursor
  response and `easingInOut` (InOutQuart) for every travel and size morph;
  `emphasizedEasing` becomes InOutQuart so the doc, the comment and the
  token agree. No overshoot, no spring, no shape morph, no ripple, no
  shadow. No duration above `emphasized` 250 in chrome; `reveal` 400 keeps
  its two palette moments and gains the lock's blank/wake.
- D2 The layout rule. Anything whose x, y, width or height changes while
  it is on screen animates the change: a positioner carries `move` and
  `add` Transitions, an item carries a `Behavior`, and a container whose
  size follows animated children rides the same clock as they do. Moves
  and morphs run `standard` on `easingInOut`; a whole-surface morph
  (panel handoff, card height) runs `emphasized`. A closing surface still
  freezes its size first (M51 D5).
- D3 The content rule. A swap of what one slot draws crossfades on `fast`:
  icon glyphs, cell labels under a width morph, the launcher's empty
  state, the clipboard preview, a calendar month. A ternary that switches
  which colour token a fill or border binds crossfades on `fast` too;
  Cell's "fills snap" contract is withdrawn.
- D4 Keyboard travel, amending M51 D8. A list cursor is one item that
  travels on `fast` with OutQuint, drawn by the view's own highlight in a
  ListView and by one rectangle per list elsewhere. A one-step move
  travels; a wrap, a filter reset and a level change snap, since nothing
  meaningful connects the two positions. Toasts and the workspace pill
  keep their M51 D8 carve-outs. Everything the keyboard drives is a
  retargeting Behavior, never a restarting animation, so key repeat glides
  instead of stuttering; `KeyCatcher` exposes `repeating` for the one
  consumer that must skip on repeat.
- D5 Panel handoff. Opening B while A is open is one card: A's frame and
  B's frame run the same rect trajectory (A's rect to B's rect, x, y,
  width and height on `emphasized` `easingInOut`) while A's content fades
  out and B's fades in on `standard`, Presence bypassed on both. Since
  both are `card` fill with the same border, two crossfading frames on one
  trajectory read as one card moving. A panel's zoom origin is the cell
  that opened it, and `toggle`/`toggleAt` resolve the cell's centre from
  the same layout they already resolve the name from.
- D6 Lists never reset. The launcher's rows and the process table sync a
  keyed `ListModel` by their stable id (insert, remove, move) and carry
  `add` (opacity on `standard`), `displaced`/`move` (y on `standard`
  `easingInOut`) and `remove` (opacity on `surfaceExit`) Transitions. A
  diff touching more than 64 rows, or a level change, resets instead:
  motion explains a change, it does not narrate a rebuild. Panel lists
  keep `Repeater` in `Column` and take the positioner Transitions.
- D7 `motion.enabled=false` keeps meaning instant. Every new duration reads
  a token; no new settings keys. `tst_theme_tokens.qml` pins the token
  values and `tests/stubs/qs/Core/Theme.qml` the key set; neither changes.
- D8 Rig legs are read, not edited (M51 D9 stands). A task may add a new
  leg under `dev/smoke.d/README.md`'s contract; it never edits an existing
  one to pass. Menu-sharing combinations run their legs individually (the
  M51 rig race).
- D9 Idle cost stays zero (M50). A Behavior on a value that changes per
  frame is gated on the surface being open and settled, the wifi dedupe
  key buckets `signalStrength` to the nearest 10, and closed panels stop
  deriving rows (`root.isOpen ? ... : []`, `AudioPanel.qml:62`'s idiom).
- D10 Pointer-only polish (press scale, tooltip travel) ranks last and
  ships only in Task 8, after everything a keystroke touches.

## Tasks

Each task is one subagent, sequential, on `m53-continuous-motion`. A task
ends with its verification commands run and their output read (PNGs
opened, not assumed), then one commit staging only the paths it touched
(never `git add -A`). VM commands go through `dev/vm-lock.sh`. A task that
finds the code drifted from a citation stops and reports rather than
improvising.

### Task 1: tokens, transitions and the primitives

- `shell/Core/Theme.qml`: `emphasizedEasing: Easing.InOutQuart`; fix the
  `tokens.js:219` comment (the marquee gate lives in `MarqueeText.qml:36`).
- New `shell/Components/MoveTransition.qml` (a `Transition` root:
  `NumberAnimation { properties: "x,y"; duration: Theme.motion.standard;
  easing.type: Theme.motion.easingInOut }`) and
  `shell/Components/AddTransition.qml` (opacity 0 to 1 on `standard`,
  `easing`), registered in `qmldir`, so every positioner in the shell
  writes `move: MoveTransition {}` / `add: AddTransition {}` and no file
  spells a duration.
- `shell/Components/Icon.qml`: re-based on `Item` with two `Text` slots; a
  `name` change moves the old glyph to the second slot and crossfades on
  `fast`; the second slot stays `visible: false` until the first change.
  Public surface (`name`, `size`, `color`, geometry) unchanged; the audit
  found no consumer setting a Text-only property. `ChevronWidget.qml:88`
  drops its hand-rolled pair for the primitive's.
- `shell/Components/Segmented.qml`: one selection rectangle outside the
  `Repeater`, `x: padding + index * _segmentWidth`, `Behavior on x` on
  `standard` `easingInOut`. `tst_segmented.qml` updated to walk the new
  tree; the assertions it makes (fill colour, border, concentric radius)
  stay.
- `shell/Components/KeyCatcher.qml`: `readonly property bool repeating`,
  set from `event.isAutoRepeat` before each dispatch.
- `shell/Components/Switch.qml:78`, `Track.qml:85`: `standard`.
- `shell/Components/Cell.qml:282`: `Behavior on color` and `Behavior on
  border.color` on the fill on `fast`; the ink (`foreground`,
  `dimForeground` at `:140`, `:155`) follows through a ColorAnimation.
  The panel mark (`:322`) draws on `presence`'s clock (opacity plus an
  along-axis scale) instead of `visible`.
- Tests: `tst_icon_crossfade.qml` (name change: old slot fades, new slot
  rises, instant under `motion.enabled=false`), `tst_keycatcher.qml` gains
  a repeat case, `tst_segmented.qml` updated.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --gallery --chevron`, read the PNGs (the chevron's two frames still
  differ).

### Task 2: the bar

- `shell/Components/Rail.qml`: `move: MoveTransition {}`, `add:
  AddTransition {}`. Covers the three regions, the tray and indicators.
- `shell/Surfaces/Bar/Bar.qml:456-570` cell delegate: its own presence,
  opacity 0 to 1 and an along-axis size term gated on `_shown`, on
  `surface`/`surfaceExit`; `visible` stays the outer term and never reads
  a measured width (the `:520` cycle warning stands).
- `Bar.qml:705`, `:719`, `:727`, `:737`: `Behavior on x`/`width` on the
  region boxes and the right rail offset, `standard` `easingInOut`, gated
  on `bar._revealed` like `animateSize`.
- The six cells without a width Behavior take their siblings'
  `Behavior on implicitWidth { enabled: root.animateSize }`.
- `Workspaces.qml:28`: `Behavior on implicitWidth` on the root Cell; the
  dot `Row` (`:138`) takes the transitions; the pill (`:228`) fades on
  `surfaceExit` when focus leaves the output and enters on `surface` at
  its slot.
- `ActiveWindow.qml:102` and `NowPlaying.qml:87`: the label crossfades on
  `fast` under the width morph (two slots, the same pattern Icon now
  carries; `MarqueeText` restarts on the measured width as today).
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --workspaces --chevron --bar-layout`, then `--media --notify` as a
  second session; read every PNG (the workspaces burst frames must still
  differ, `tray_overflow`'s dots toggle still reads off `tray status`).

### Task 3: panel geometry and the keyboard path

- `shell/Components/Panel.qml`: `_frameY` and `_ownerShift` read
  `_morphHeight` (and the owner's); a `_morphWidth` twin of
  `_morphHeight` under the same `presence.settled && isOpen` gate feeds
  `frame.width` and `_frameX`; `Behavior on x`/`y` on `frame` under the
  same gate; `transform: Scale` with `origin.x`/`origin.y` at the opening
  cell's centre clamped into the frame (falls back to the edge centre
  with no anchor), replacing `transformOrigin`.
- `shell/Ipc/PanelIpc.qml:38-58`: `toggle(name)` and `toggleAt(n)` resolve
  the cell's along-axis centre from the layout they already run and pass
  it as the anchor, on the output the bar cell lives on.
- Cursor scroll-follow: rows report their y (or `cursorIndex * rowPitch`
  where rows are uniform) and `contentFlickable.contentY` animates on
  `standard` `easing` to keep the cursor row inside the viewport.
- `shell/Components/WheelScroll.qml:39`: `Behavior on contentY` on
  `standard` `easing`, `enabled: !flickable.dragging &&
  !flickable.flicking`.
- `CalendarPanel.qml:242`: the month swap becomes a `_swapProgress`
  Behavior carrying opacity and an 8px x offset signed by the step
  direction; no `restart()`.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --panel network --panel-at 2 --panel-keys`, then `--bar-position bottom
  --panel audio` and `--bar-position left --panel calendar` as their own
  sessions; read every PNG and `panel state`.

### Task 4: the panel handoff

- `shell/Core/PanelRegistry.qml` records the outgoing frame rect (window
  coordinates on the shared output) when `open()` replaces `current`.
  The outgoing panel keeps `presence` at 1, animates its frame to the
  incoming rect on `emphasized` `easingInOut` and fades its content on
  `standard`, then unmaps; the incoming panel starts at the outgoing rect
  with `presence` forced to 1, animates to its own rect on the same clock,
  and fades its content in on `standard`. Both windows already cover the
  output, so the frames are plain Items and the trajectory is two
  Behaviors. Presence is bypassed only for a handoff between two panels
  on the same output; a plain open or close keeps the M51 recipe.
- Owned panels (`owner`, the tray menu over the second bar) are not a
  handoff.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --panel-at 2 --panel-at 3` if the rig accepts two, else `--panel-at 2`
  and a new leg `dev/smoke.d/panel_handoff.sh` sampling one frame 80ms
  into `panel toggle audio` while `network` is open and asserting exactly
  one card is visible (`panel state` names one panel, the frame differs
  from both rest frames). Read the PNGs.

### Task 5: the launcher list and the cursor

- `Menu.qml`: rows and the process table sync a keyed `ListModel` by `id`
  (D6) with `add`, `displaced`, `move` and `remove` Transitions from the
  shared components; `rowSections` moves onto the row object so a section
  band no longer depends on index. The reset threshold is 64 rows or a
  level change. The picker and emoji grids keep their array models (a
  grid re-rank is a reset by nature).
- Cursor (D4): `MenuRow.qml:175` and `MonitorView.qml:1606` drop the
  per-row cursor rectangle; the views draw `highlight` with
  `highlightMoveDuration: Theme.motion.fast`,
  `highlightMoveVelocity: -1`, `highlightResizeDuration: 0`, and
  `highlightFollowsCurrentItem` handles the scroll follow. A wrap
  (`_moveCursor`, `Menu.qml:1604`) and a filter reset snap: set
  `highlightMoveDuration` to 0 for that one assignment and restore it
  after (`Qt.callLater`).
- `Panel.qml`'s row cursor: one rectangle per content column bound to the
  cursor row's y and height with `Behavior on y` on `fast` `easing`;
  the rows' own `cursor` fill goes.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --menu`, then `--processes`, then `--panel-keys`, each its own session
  (the M51 rig race); read every PNG and `menu status`.

### Task 6: seams inside the launcher and the centre

- `Menu.qml`: the level entrance moves onto one wrapper `Item` holding
  everything under `searchRule` (breadcrumb, segmented, views, preview,
  action bar) and the four per-view copies go; `_playLevelEnter(1)` also
  fires when `_isGrid`, `_isEmojiGrid` or `_isAppView` flip; the rows area
  height rides a `_morphRowsHeight` on the card's own Behavior; the empty
  state crossfades on `fast` against the list; the clipboard preview's
  `Text`/`Image` crossfade on `fast`; `MenuActionBar.qml:52`'s `Row` takes
  the transitions.
- `Center.qml:589`, `:597`: the section wrappers take the rows'
  `_presence` height and opacity scalar so a label collapses with its
  last row.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --menu`, `--emoji`, `--clipboard`, `--center --notify`, each its own
  session; read every PNG.

### Task 7: modals, the lock and the picker

- `Input.qml:104`: the error caption fades on `fast` and the height change
  rides a Behavior; `PolkitDialog.qml:208` and `AuthPrompt.qml`'s column
  take the D5 size morph (gated on `presence.settled && open`).
- `PluginOverlay.qml:105`: the scrim, copied from `PolkitDialog.qml:191`.
- `LockSurface.qml:137`, `:155`, `:185`: blank and wake crossfade on
  `reveal` opacity both ways, `Screensaver.qml:581`'s pattern; the
  entrance rise stays a creation-time one-shot.
- `RegionPicker.qml:761`: `Behavior` on the selection rect's x, y, width
  and height on `standard` `easingInOut`, `enabled: !dragging`; the four
  scrim rects and the readout follow because they bind to it; the mode
  tabs (`:990`) take one travelling fill on `standard` `easingInOut`.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --polkit --plugins`, `--lock`, `--capture --screenshot`, each its own
  session; read every PNG (the lock leg must still show the real
  `AUTH_ERR`).

### Task 8: the tooltip group (pointer-only, last)

- One `Tooltip` per output instead of one per cell: `Cell.qml:238` asks a
  per-output group to show for its item; within 500ms of the last hide the
  delay is 0 and the card's `_anchorRect` retargets with `Behavior on
  x`/`y`/`width` on `standard` `easingInOut`, so it travels to the next
  cell; past the grace window it is the M51 recipe from the new cell.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --panel network --tooltip`; read the PNGs.

### Task 9: sweep and the rulebook

- `docs/DESIGN.md` §1 Motion rewritten for D1 to D6 (the layout rule, the
  content rule, cursor travel, the panel handoff), the `Cell` and
  `Segmented` rows in §2 updated, "List cursors jump" withdrawn.
- One combined session over the token-change minimum plus the touched
  surfaces: `dev/vm-lock.sh just vm-smoke --workspaces --osd --center`,
  then `--panel network --tooltip --toggles`; read every PNG; SMOKE_MEM
  stays in M50's band.
- This plan's status line updated with the landed commits.
