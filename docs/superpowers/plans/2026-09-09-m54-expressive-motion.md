# M54: morphs, caelestia's shape and curves on this shell

**Date:** 2026-09-09
**Status:** implemented 2026-09-09 on `m54-expressive-motion`, oldest
first: 1c5b61c (this plan), 57993c6 (the tokens, `Anim`/`CAnim` and
`Deform`), 70b0bf6 (`Shoulders` and the bar's gap), 2a50c7f (Presence, the
panels, the centre, the OSD and the handoff), a046072 (the launcher),
b3a75b7 (the bar and the workspace pill), b9b67f7 (toasts, tooltips,
controls, the old tokens gone). Task 7 is the docs commit carrying this
line.

**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(architecture, IPC and config from the 2026-07-27 spec). This plan amends
DESIGN.md §1 "Motion" and M53 D1; the spec is silent on curves and on how
a card meets the bar.

Where the shipped code deviates from the task text, on purpose:

- Task 3 (D9): the handoff is one eased parameter with the frame's rect
  interpolated off it, not four animations over x, y, width and height.
  That keeps the destination live, so content settling its height a frame
  late moves where the card is going, and an animation writing those four
  properties would break the bindings that read them.
- Task 3 (D6): the joined shape reaches `barMargin` plus the border row
  past the card's own rect, so the fillets land on the bar's line rather
  than short of it. The frame's rect is untouched, so the handoff, the
  content and `panel state` measure what they always did.
- Task 3 (D6): the notification centre and the OSD keep `Card`. Each sits
  a `screenPadding` clear of the output's own edge, meets no line, and has
  nothing for a fillet to run out to.
- Task 4 (D8): the launcher's level swap has no out half. A route is
  resolved by the keystroke that asks for it, so the body has already
  changed by the time an out fade could play, and fading from there took
  the arriving level off screen and brought it straight back.
- Task 6 (D10): the toast stack lays out on each card's `implicitHeight`
  rather than its drawn height. Reading the drawn height retargets every
  neighbour's y once a frame and leaves the pile crawling after the card
  that grew.
- Tasks 3 and 4 (D11): `panel_emerge.sh` and `menu_unfold.sh` moved their
  probes to the card's own centre column and stopped comparing against the
  settled frame. The first now asks whether a probe differs from the closed
  output, the second whether its mean brightness clears the scrim. The
  deform is still unwinding for a beat after the travel, so a probe inside
  the card is not byte-identical to the settled one for most of an open;
  the centre column is the one line the matrix never moves sideways, being
  centred on the anchored edge's midpoint.
- Task 3: `bar_position.sh` asserted a `bar chevron status` shape M52
  (78ee367) changed, `collapsed`/`hidden` for `chevron`/`open`, one of the
  two stale legs M53's own status paragraph names. Repaired in place.
- Task 3: `--bar-position bottom --panel audio` still fails on a race that
  predates this branch; `--bar-position` with `--panel` is on M53's list of
  combinations that cannot share a session.

## Owner's ask (2026-09-09, after M53 landed)

"Make our shell match caelestia's animations. Caelestia is beautiful
because everything morphs, we just have basic curves." Then, on a draft of
this plan that changed the curves alone: "caelestia has morphing
animations, i dont just want curves." M53 (same day) had kept Emil
Kowalski's OutQuint/InOutQuart at 100 to 250ms on the grounds of a Vercel
identity (M53 D1) and no shape morph. Both are reversed by this plan; M53
D2 to D10 stand and are what the morphs run on.

## What caelestia's morph is (read at ce84c7b, 2026-09-09, GPLv3: mechanics and values only, no ported code)

Four mechanics make a caelestia panel read as morphing out of the bar
rather than appearing beside it:

1. **One shape.** Every panel background is a rounded rect inside one
   signed-distance field with the screen border and the bar
   (`Caelestia.Blobs`, a compiled QSG material: `BlobGroup`,
   `BlobInvertedRect` for the border, a `BlobRect` per panel, a circular
   smooth-min of radius `border.smoothing` joining them). A panel's edge
   meets the bar through a concave fillet, so the bar and the card are
   one silhouette at every frame of the open.
2. **Velocity deform.** `BlobRect` samples its own scene position every
   frame, takes the velocity, and targets a stretch along the direction
   of travel with a compress across it, `R(θ)·diag(s, 1/s)·Rᵀ`,
   `s = 1 + min(speed · deformScale, 0.35)` with `deformScale` =
   `deformAmount / 10000` per px/s (`deformAmount` 0.1 for the launcher
   and dashboard, 0.15 for a popout, 0.25 for the OSD). Each matrix
   component is an underdamped spring, stiffness 200, damping 16
   (implicit), snapped to identity under 0.002. The matrix is applied
   about the rect's centre to the panel's contents too
   (`launcher.transform: Matrix4x4 { matrix: launcherBg.deformMatrix }`).
   A card arriving squashes into its rest and springs back.
3. **Spatial curves that overshoot.** `Anim {}` is Material 3
   Expressive's `expressiveDefaultSpatial`, cubic-bezier(0.38, 1.21,
   0.22, 1) over 500ms; the y control point above 1 carries a card a few
   pixels past rest and back. Opacity and colour never overshoot
   (`effects` family). The whole table:

   | token | cubic-bezier | ms | what caelestia puts on it |
   | --- | --- | --- | --- |
   | `expressiveFastSpatial` | (0.42, 1.67, 0.21, 0.90) | 350 | small chrome geometry: a scale on hover or press |
   | `expressiveDefaultSpatial` | (0.38, 1.21, 0.22, 1.00) | 500 | the default `Anim {}`: every open/close (`offsetScale`), every `implicitWidth`/`implicitHeight`, x, y, radius, rotation |
   | `expressiveSlowSpatial` | (0.39, 1.29, 0.35, 0.98) | 650 | a popout detaching into a centred window |
   | `expressiveFastEffects` | (0.31, 0.94, 0.34, 1.00) | 150 | the out half of a content swap |
   | `expressiveDefaultEffects` | (0.34, 0.80, 0.34, 1.00) | 200 | opacity, hover fills, the in half of a swap |
   | `expressiveSlowEffects` | (0.34, 0.88, 0.34, 1.00) | 300 | colour (`CAnim`), scrims |
   | `emphasized` | (0.05, 0, 0.133, 0.06, 0.167, 0.4) then (0.208, 0.82, 0.25, 1, 1, 1) | 400 | the workspace pill's edges |
   | `emphasizedDecel` | (0.05, 0.7, 0.10, 1.00) | 500 | a notification's x as it arrives |

4. **One surface that resizes.** A popout switching content is one
   `ClipWrapper` whose `x`, `y` and `implicitWidth` carry Behaviors and
   whose contents crossfade; the launcher's list carries `Behavior on
   implicitWidth`/`implicitHeight` while open, so results filtering
   changes the card's size live; a closing wrapper breaks its size binding
   first. This shell has had this since M53 (the handoff, the unfold, the
   size gates); it runs on curves too small and too short to read.

What transfers and how, under the pure QML/JS rule (CLAUDE.md): (1) as a
`QtQuick.Shapes` outline with the fillets drawn as arcs, since the join
this shell needs is card-to-bar, one edge, not an arbitrary SDF union;
(2) verbatim, in a QML `FrameAnimation`; (3) verbatim, through
`Easing.BezierSpline`; (4) is already here and gets the new clocks. What
does not transfer: the SDF itself (a compiled material) and Material's
ripple (`StateLayer`), which stays out under the shadcn chrome rule.

## Findings (recon 2026-09-09 at c5040c6)

- `shell/Core/Theme.qml:291-327` `Theme.motion` carries five durations
  (100/130/180/120/250) and three Qt enum easings (`OutQuint`,
  `InOutQuart`). Qt's enum curves cannot overshoot; `Easing.BezierSpline`
  with `easing.bezierCurve: [c1x, c1y, c2x, c2y, 1, 1]` can, and takes a
  y above 1 (Qt 6.8 docs, PropertyAnimation `easing.bezierCurve`).
- Every animation site spells `NumberAnimation { duration: Theme.motion.X;
  easing.type: Theme.motion.Y }` by hand (26 colour Behaviors in
  Theme.qml, 22 sites in Panel.qml, 18 in Bar.qml, 16 in Menu.qml, 15 in
  Toasts.qml; the inventory is appended below). caelestia's answer is a
  primitive, and it is the only way a curve that is two properties
  instead of one stays a one-line change.
- The bar draws one 1px line, the edge facing inward
  (`shell/Surfaces/Bar/Bar.qml:704-721`), not a ring; a panel's `Card`
  (`shell/Components/Panel.qml:820-826`) is a full ring hanging under it,
  emerging from a clip band at the bar's inner line. Both windows are
  `WlrLayer.Top`. So the join is: the bar's line opens a gap where a card
  hangs, and the card's outline has no edge on that side and two concave
  shoulders where it meets the line. Two windows, one rect, read from
  `PanelRegistry`.
- `Presence` already carries `emerge`, `unfold` and `fade`; every clock
  inside it is 250ms or less on a curve that spends half its time in its
  last tenth (`dev/smoke.d/panel_emerge.sh:20`), so what the owner sees is
  the card already there.
- The handoff (`Panel.qml:463-470`) pauses `standard` then travels on
  `emphasized` InOutQuart: 380ms, no settle.
- Six smoke legs sample frames at times derived from the 250ms clock
  (`panel_emerge.sh`, `menu_unfold.sh`, `panel_handoff.sh`,
  `chevron_quiet.sh`, `workspaces.sh`, `tooltip_travel.sh`). M53 D8 keeps
  them read-only; this plan changes the clock they read, so it may retime
  their sampling (not their assertions) and names each one.
- `FrameAnimation` (QtQuick, Qt 6.4+; Quickshell pins Qt 6.8) gives
  `frameTime` per rendered frame, which is all the deform needs.

## Locked decisions

- D1 (amends M53 D1) The curves are Material 3 Expressive's, the table
  above verbatim. Spatial motion overshoots, effects never do. The chrome
  (shadcn) is untouched: a border, a radius and a colour token are not a
  curve. "Nothing overshoots or bounces" leaves DESIGN.md.
- D2 Two families, and the property picks the family. `spatialFast`,
  `spatial`, `spatialSlow` for x, y, width, height, implicitWidth,
  implicitHeight, margins, scale, radius, rotation, an emerge, a morph
  progress, a cursor's y, a contentY. `effectsFast`, `effects`,
  `effectsSlow` for opacity, colour, blur and any progress that only
  drives alpha. `emphasized` for the workspace pill alone,
  `emphasizedDecel` for a toast's arrival. `reveal` 400 stays for the
  wallpaper and palette crossfades and the lock's blank and wake, on
  `effectsSlow`'s curve.
- D3 The old names go. `fast`, `standard`, `surface`, `surfaceExit`,
  `slide`, `zoom`, `easing`, `easingInOut`, `emphasizedEasing`,
  `revealEasing` are deleted from `Theme.motion`, not aliased. No compat
  shim (CLAUDE.md).
- D4 One primitive, `shell/Components/Anim.qml`: a `NumberAnimation` with
  `property string kind: "spatial"` whose `duration`, `easing.type` and
  `easing.bezierCurve` resolve from `Theme.motion` by kind. `CAnim` is the
  `ColorAnimation` on `effectsSlow`. A surface file writes `Behavior on x
  { Anim {} }`, `Behavior on opacity { Anim { kind: "effects" } }`,
  `Behavior on color { CAnim {} }` and never a duration or curve of its
  own. `MoveTransition`/`AddTransition`/`RemoveTransition` are rewritten
  on it.
- D5 `motion.enabled=false` still means instant, and now also undeformed:
  `Tokens.motionTokens` zeroes every duration, the curves are constants,
  and `Deform` holds identity. `tst_theme_tokens.qml` and
  `tests/stubs/qs/Core/Theme.qml` change with the key set (this plan
  changes the key set, which M53 D7 forbade for M53's own scope).
- D6 The joined shape. `shell/Components/Shoulders.qml` is a
  `QtQuick.Shapes` `Shape` (CurveRenderer) drawing an edge-anchored card:
  the three free edges with `Theme.radiusXl` corners, the anchored edge
  open, and outside each of its two end corners a concave quarter arc of
  the same radius running out to the bar's line, the 1px `border` stroke
  following that whole outline and the `card` fill inside it at
  `theme.surfaceOpacity`. It takes `edge`, `radius` and the card's rect
  and replaces `Card` as the frame of every edge-anchored surface: the
  panels, the chevron's and the tray's second bars, the notification
  centre and the OSD. A modal (polkit, plugin overlay), the tooltip and
  the launcher keep `Card`. The bar's inward line (`Bar.qml:715-721`)
  becomes two segments with a gap of the joined card's width plus two
  radii, both gap edges on `spatial`, read from a `PanelRegistry.join`
  rect the open surface publishes (x, width along the bar, null when
  nothing hangs). `theme.radius` 0 (retro) draws square shoulders of
  width 0, which is the current picture.
- D7 The deform. `shell/Components/Deform.qml` is a `QtObject` holding a
  `FrameAnimation` that runs only while `active` (the consumer binds the
  Behaviors' `running` and Presence's `!settled`), samples the target
  item's scene x, y and its width and height each frame, and integrates
  caelestia's mechanics verbatim: velocity from the sample delta over
  `frameTime`, size velocity folded in as travel of the free edge, target
  `R(θ)·diag(s, 1/s)·Rᵀ` with `s = 1 + min(speed · amount / 10000, 0.35)`
  and a 5px/s dead band, three springs at stiffness 200 and implicit
  damping 16, identity under 0.002. It exposes `matrix` (a `matrix4x4`
  centred on the anchored edge's midpoint, so a card squashes into the
  bar rather than about its own centre) and `amount` (0.15 default;
  0.25 on the OSD, 0.1 on the launcher). The consumer sets
  `transform: Matrix4x4 { matrix: deform.matrix }` on the item holding
  both frame and contents. `motion.enabled=false` pins identity.
- D8 Presence on the new clocks. `emerge`: travel on `spatial` both ways,
  the contents on `effects` behind it, the deform running under it.
  `unfold`: the card on `effectsFast`, the morph on `spatial`, deform
  0.1. `fade` (tooltip, bar reveal, polkit, plugin overlay): opacity on
  `effects`, scale from 0.97 on `spatialFast`, no slide.
- D9 The handoff is one animation on `spatial`: x, y, width and height
  from A's rect to B's together, the contents crossfading on `effects`
  over the first 200ms of the same clock, no pause, the deform running,
  the shoulders travelling with the frame and the bar's gap following.
  500ms end to end, one settle.
- D10 Sizes follow content live (caelestia 4, M53 D2 stands): a panel
  whose section count changes, the launcher's list under a query, a
  toast expanding, all on `spatial` while open; a closing surface still
  freezes its size first.
- D11 Rig legs: a leg whose sampling times derive from the old clock is
  retimed to the new one (`t0 + fraction · duration`, never a hard-coded
  ms), its assertions untouched; a leg that measured the card's rect
  against the compositor's layer list is unaffected (the window is the
  same). Every retimed leg is named in its task and its PNGs read. New
  legs: `--shoulders` (the bar's gap and the card's arcs in one crop, open
  and closed, and the join pixel-aligned) and `--deform` (a burst of
  frames through an open showing the card's height past rest on at least
  one frame and identity on the last).
- D12 Idle cost stays zero (M50, M53 D9): the FrameAnimation is off at
  rest, the gap Behaviors are gated on a join existing, every gate that
  exists stays.
- D13 Keyboard first (M53 D4, D10 stand): the cursor's travel takes
  `spatialFast`; key repeat still retargets.

## Tasks

Each task is one subagent, sequential, verification run and read before
its commit, on branch `m54-expressive-motion`. The uncommitted-work rule
from `~/.claude/CLAUDE.md` goes into every subagent prompt verbatim.

### Task 1: tokens, the primitive and the deform

- `shell/Theme/tokens.js`: `MOTION_BASE` becomes `{ spatialFast: 350,
  spatial: 500, spatialSlow: 650, effectsFast: 150, effects: 200,
  effectsSlow: 300, emphasized: 400, reveal: 400, marqueePxPerSec: 30,
  marqueeHoldMs: 2000 }`; `motionTokens(enabled)` zeroes the eight
  durations; `MOTION_CURVES` holds the bezier arrays from the table (each
  `[c1x, c1y, c2x, c2y, 1, 1]`, `emphasized` two segments) and
  `motionCurve(kind)` returns one. Deform constants live here too
  (`DEFORM = { maxStretch: 0.35, deadBand: 5, stiffness: 200, damping:
  16, epsilon: 0.002 }`).
- `shell/Core/Theme.qml:265-327` and `tests/stubs/qs/Core/Theme.qml`:
  `Theme.motion` is the durations plus `curves` plus
  `pulseDuration`/`pulseEasing`/`marquee*`; header comment rewritten for
  the two families. `Theme.qml:81-106`'s colour Behaviors take `reveal`
  on `effectsSlow`'s curve through one inline `component`.
- `shell/Components/Anim.qml` (D4), `CAnim.qml`, `Deform.qml` (D7);
  `MoveTransition` (`spatial`), `AddTransition` (`effects`),
  `RemoveTransition` (`effectsFast`) on the primitive; `qmldir`.
- Tests: `tst_theme_tokens.qml` pins the eight durations, the zeroing,
  every curve ending in `1, 1` and every spatial curve carrying a y above
  1; new `tst_anim.qml` (kind resolves duration and curve, lands at rest
  under `motion.enabled=false`) and `tst_deform.qml` (a driven item moved
  50px in one frame yields a matrix with `m11 > 1` along x, decays to
  identity, holds identity with motion off).
- Verify: `dev/vm-lock.sh just vm-test`, `just lint`.

### Task 2: the shoulders and the bar's gap

- `shell/Components/Shoulders.qml` (D6) and a gallery row for it in
  `Surfaces/Gallery` against the live theme, all four edges.
- `shell/Core/PanelRegistry.qml`: `join` (edge, along-axis x, width,
  screen) published by the surface that owns it, null otherwise.
- `shell/Surfaces/Bar/Bar.qml:704-721`: the inward line as two
  `Rectangle`s whose inner ends follow `join` on `spatial`, gated on a
  join existing, meeting again at rest closed.
- `dev/smoke.d/shoulders.sh` `--shoulders` per D11.
- Verify: `dev/vm-lock.sh just vm-smoke --gallery`, `--shoulders`; read
  the crops; the arc's endpoint and the line's end share a pixel column.

### Task 3: Presence, the panels and the handoff

- `shell/Components/Presence.qml` per D8, on `Anim`.
- `shell/Components/Panel.qml`: `Shoulders` as the frame, `Deform` on
  the clipper's inner item, `join` published while open or handing over,
  every clock on the primitive, the handoff per D9.
- `Surfaces/Panels/*.qml`, `Notifications/Center.qml`, `Osd/Osd.qml`,
  the tray's and chevron's second bars: `Shoulders`, `Deform`, every
  remaining literal on the primitive.
- Rig: `panel_emerge.sh`, `panel_handoff.sh`, `chevron_quiet.sh` retimed
  per D11; `dev/smoke.d/deform.sh` `--deform`.
- Verify: `dev/vm-lock.sh just vm-smoke --panel-emerge`, then
  `--panel-handoff`, `--chevron-quiet`, `--center`, `--osd`, `--deform`,
  `--shoulders --panel network` singly; read every PNG.

### Task 4: the launcher

- `Surfaces/Menu/Menu.qml`, `MenuActionBar.qml`, `views/*.qml`: the
  unfold per D8 with `Deform` at 0.1, the open card's width and height on
  `spatial` (D10), the cursor on `spatialFast`, every crossfade on
  `effects`, the level swap as caelestia's loader swap (out on
  `effectsFast`, swap, in on `effects`).
- Rig: `menu_unfold.sh` retimed per D11.
- Verify: `dev/vm-lock.sh just vm-smoke --menu-unfold`, then `--menu`,
  `--emoji`, `--picker` singly.

### Task 5: the bar

- `Surfaces/Bar/Bar.qml`, `widgets/*.qml`, `Components/Cell.qml`,
  `CellLabel.qml`, `Rail.qml`: cell widths and rails on `spatial`, the
  workspace pill's two edges on `emphasized` with the trailing edge at
  twice the clock (caelestia's `ActiveIndicator`), hover fills on
  `effects`, the bar's own reveal per D8.
- Rig: `workspaces.sh` retimed per D11.
- Verify: `dev/vm-lock.sh just vm-smoke --workspaces`, then `--chevron`,
  `--bar-layout`, `--tray-overflow` singly.

### Task 6: toasts, tooltips, controls and the rest

- `Surfaces/Notifications/Toasts.qml`: arrival on `emphasizedDecel`,
  leave on `spatial`, stack moves on `spatial`, `Deform` 0.15, a toast's
  height on `spatial` when it expands (D10).
- `Components/Tooltip.qml`, `TooltipGroup.qml`, `Button.qml`,
  `Switch.qml`, `Segmented.qml`, `Input.qml`, `WheelScroll.qml`,
  `MarqueeText.qml`, `Capture/RegionPicker.qml`, `Lock/LockSurface.qml`,
  `Screensaver.qml`, `Polkit`, `Plugins`: every remaining site on the
  primitive by D2. After this task `rg "easing.type:" shell` matches
  only `Anim.qml`, `CAnim.qml`, `Theme.qml` and the pulse.
- Rig: `tooltip_travel.sh` retimed per D11.
- Verify: `dev/vm-lock.sh just vm-test`, `just lint`, `dev/vm-lock.sh
  just vm-smoke --notify`, then `--panel network --tooltip-travel`,
  `--capture`, `--lock`, `--gallery` singly.

### Task 7: the rulebook

- `docs/DESIGN.md` §1 "Motion" rewritten: the two families and the eight
  names, the joined shape, the deform; "The identity is Vercel's, so
  nothing overshoots or bounces" goes; the amendment dated and attributed
  to the owner. §3 gains `Shoulders` and `Deform` in the component table.
- `CLAUDE.md` chrome-defaults bullet and the M53 plan's status line get
  one sentence each pointing here; `dev/smoke.d/README.md` lists the two
  new legs; this plan's status line carries the commit list.

## Appendix: every animation site at c5040c6 (read-only inventory, 2026-09-09)

Zero literal durations outside the token source; one literal easing,
`Components/MarqueeText.qml:135` `Easing.Linear`, the marquee carve-out
that stays. Sites by file, with the clock and curve each reads today, for
the task that sweeps it:

| file:line | property | duration | easing | what |
|---|---|---|---|---|
| Components/AddTransition.qml:9-16 | opacity | standard | easing | positioner add |
| Components/RemoveTransition.qml:13-19 | opacity | surfaceExit | easing | positioner remove |
| Components/MoveTransition.qml:14-19 | x,y | standard | easingInOut | positioner move |
| Components/Presence.qml:94-108 | `_progress` | surface/surfaceExit | easing | enter/exit pose |
| Components/Presence.qml:116-121 | `_morphProgress` | emphasized/surface | easing | unfold morph |
| Components/Cell.qml:160,173 | foreground, dimForeground | fast | easing | ink crossfade |
| Components/Cell.qml:346,350 | color, border.color | fast | easing | fill crossfade |
| Components/Cell.qml:365 | opacity | fast | easing | hover wash |
| Components/Cell.qml:401 | `_presence` | surface/surfaceExit | easing | open mark |
| Components/Icon.qml:57 | `_cross` | fast | easing | glyph crossfade |
| Components/Input.qml:65 | implicitHeight | standard | easingInOut | caption growth |
| Components/Input.qml:82,105,148 | opacity, border.color, opacity | fast | easingInOut | ring, border, caption |
| Components/Panel.qml:186 | `_followY` | standard | easing | cursor scroll follow |
| Components/Panel.qml:438 | `_contentAlpha` | standard | easing | handoff crossfade |
| Components/Panel.qml:461-471 | Pause + `_travel` | standard, emphasized | easingInOut | handoff travel |
| Components/Panel.qml:652 | Presence emerge | via Presence | easing | drawer |
| Components/Panel.qml:686,699 | `_morphHeight`, `_morphWidth` | emphasized | easingInOut | size morph |
| Components/Panel.qml:838,843 | frame x, y | emphasized | easingInOut | card travel |
| Components/Panel.qml:1021-1033 | cursorHalo x,y,w,h | fast | easing | row cursor |
| Components/Segmented.qml:107 | pill x | standard | easingInOut | selection pill |
| Components/Segmented.qml:141 | opacity | fast | easing | hover wash |
| Components/Switch.qml:74,88 | border.color, knob x | fast, standard | easingInOut | ring, knob |
| Components/Tooltip.qml:99 | `_cross` | fast | easing | text crossfade |
| Components/Tooltip.qml:183 | Presence fade | via Presence | easing | card |
| Components/Tooltip.qml:196,200,208 | x, y, width | standard | easingInOut | travel between anchors |
| Components/Track.qml:96 | width | standard | easingInOut | fill glide |
| Components/WheelScroll.qml:43 | `_glide` | standard | easing | wheel glide |
| Core/Theme.qml:81-106 (26) | color | reveal | revealEasing | palette crossfade |
| Surfaces/Background/Background.qml:231 | opacity | reveal | revealEasing | wallpaper crossfade |
| Surfaces/Bar/Bar.qml:564 | `_progress` | surface/surfaceExit | easing | cell slot open/close |
| Surfaces/Bar/Bar.qml:663 | Presence fade | via Presence | easing | strip reveal |
| Surfaces/Bar/Bar.qml:800,805 | centerRegion x,y | standard | easingInOut | re-centring |
| Surfaces/Bar/Bar.qml:836-851 | rightRegion x,y,w,h | standard | easingInOut | region box |
| Surfaces/Bar/Bar.qml:867,872 | rightRail x,y | standard | easingInOut | rail slide |
| Surfaces/Bar/TrayMenu.qml:315 | opacity | fast | easing | hint fade |
| Surfaces/Bar/widgets/ActiveWindow.qml:63,68,123 | implicitWidth/Height, `_cross` | standard, fast | easingInOut, easing | cell size, title |
| Surfaces/Bar/widgets/{Airpods,Audio,Battery,Bell,Clock,CommandModule,Dualsense,Github,KeyboardLayout,Mic,Monitor,NowPlaying,PluginBarModule,QmlModule,SystemUpdate,Usage,Weather,Workspaces}Widget/… (18 files) | implicitWidth (and Height on Clock:42, NowPlaying:92) | standard | easingInOut | cell resize |
| Surfaces/Bar/widgets/NowPlaying.qml:180 | `_cross` | fast | easing | title crossfade |
| Surfaces/Bar/widgets/Tray.qml:191 | Timer interval | standard + 32 | none | refit wait |
| Surfaces/Bar/widgets/Workspaces.qml:196,281 | dot width, pill growth | fast | easing | hover |
| Surfaces/Bar/widgets/Workspaces.qml:203 | dot color | emphasized | emphasizedEasing | under the pill |
| Surfaces/Bar/widgets/Workspaces.qml:210-214 | opacity sequence | standard, emphasized | easing | urgent pulse |
| Surfaces/Bar/widgets/Workspaces.qml:264 | pill opacity | surface/surfaceExit | easing | pill across outputs |
| Surfaces/Bar/widgets/Workspaces.qml:302,307 | pill `lead`, `trail` | standard, emphasized | emphasizedEasing | pill edges |
| Surfaces/Capture/RegionPicker.qml:699-711 | `_selX/Y/W/H` | standard | easingInOut | selection box |
| Surfaces/Capture/RegionPicker.qml:1108,1112 | toolFill x, width | standard | easingInOut | tool fill |
| Surfaces/Lock/LockSurface.qml:97 | `_wakeOpacity` | reveal | easing | blank/wake |
| Surfaces/Lock/LockSurface.qml:121-139 | `_contentOpacity`, `_contentRise` | surface | easing | entrance |
| Surfaces/Menu/Menu.qml:1706-1728 | `_levelEnterOpacity`, `_levelEnterX` | standard | easing | level enter |
| Surfaces/Menu/Menu.qml:2153 | Presence unfold | via Presence | easing | card |
| Surfaces/Menu/Menu.qml:2177,2181,2197 | `_morphWidth`, `_morphHeight`, `_morphRowsHeight` | emphasized | easingInOut | card size |
| Surfaces/Menu/Menu.qml:2640-2643 | transitions | via components | | row list |
| Surfaces/Menu/Menu.qml:2667 | rowCursor y | fast | easing | cursor |
| Surfaces/Menu/Menu.qml:2725,3035,3071 | opacity | fast | easing | empty state, previews |
| Surfaces/Menu/MenuActionBar.qml:117,143 | move, opacity | standard | easingInOut, easing | segments |
| Surfaces/Menu/MenuRow.qml:185 | opacity | fast | easing | hover wash |
| Surfaces/Menu/views/MonitorView.qml:1643-1708 | y, cursor y, opacity | standard, fast | easingInOut, easing | process table |
| Surfaces/Notifications/Center.qml:387 | Presence emerge right | via Presence | easing | drawer |
| Surfaces/Notifications/Center.qml:406 | `_morphHeight` | emphasized | easingInOut | card height |
| Surfaces/Notifications/Center.qml:637,709,846 | section/row `_presence` | emphasized, standard | easingInOut | collapse |
| Surfaces/Notifications/Center.qml:681,748 | row y | standard | easingInOut | row slide |
| Surfaces/Notifications/Toasts.qml:397 | stack height | standard | easingInOut | pile |
| Surfaces/Notifications/Toasts.qml:436-442 | cardFrame x,y,width | standard | easingInOut | expand |
| Surfaces/Notifications/Toasts.qml:461 | `presence` | emphasized | easing | arrive/leave |
| Surfaces/Notifications/Toasts.qml:502,556 | opacity | standard | easingInOut | content, peek |
| Surfaces/Osd/Osd.qml:103 | Presence emerge bottom | via Presence | easing | pill |
| Surfaces/Panels/BluetoothPanel.qml:587,612; NetworkPanel.qml:1208 | opacity | fast | easing | hover reveals |
| Surfaces/Panels/CalendarPanel.qml:257,369,450 | `_swapProgress`, translate, opacity | standard, fast | easing | month swap, dot |
| Surfaces/Panels/PowerPanel.qml:300; TailscalePanel.qml:363 | opacity loop | pulseDuration | pulseEasing | pulse (stays) |
| Surfaces/Plugins/PluginOverlay.qml:79,162 | Presence fade, opacity | surface | easing | overlay |
| Surfaces/Polkit/PolkitDialog.qml:154,229 | Presence fade, `_morphHeight` | surface, emphasized | easing, easingInOut | dialog |
| Surfaces/Screensaver/Screensaver.qml:581 | opacity | reveal | easing | fade |

Geometry that still snaps (no Behavior), each taking `spatial` in the
task that owns the file (D10): `Bar.qml:757,760` `leftRegion.width/
height` (the one region of three without one); `MediaPanel.qml:255`
`Cover.width`; `Menu.qml:2524` `breadcrumbRow.height`, `Menu.qml:2588`
`variantRow.height`, `Menu.qml:3100` `emojiCaption.height`.
