# M57: the join, polished: the seam, the walls, the nested bud, the modal bud, one size morph

**Date:** 2026-09-17
**Status:** implemented 2026-09-17 on `main`, oldest first:
abfd4dd (motionScale and the `--join` leg), 84e854b (the seam painted once,
D1), cd9fdd1 (plan addendum, the osd as a drawer), 98ceea1 (walls, D2),
1f99cc4 (the wall's own row and pivot), 87a2987 (the nested bud, D3),
e825de0 (one drawer, D4), bbf7dca (the modal bud off the top line, D5),
58fe164 (darken not blur, D6), d16c89c (`--menu-emerge`, `--polkit`'s own
sample), d7f108b (the osd as a drawer, D8), 74fad90 (the nested bud's border
under the deform), db8d973 (one size morph, D7), 3859fdc (`--panel-morph`),
5ac0bbd (`--join`/`--menu-emerge`/`--panel-morph` on any layout), 694a67e
(`--join` reads its own dump), 94520b9 (the frame follows the size morph),
8ec46ea (the walled corner takes the ring's own radius), 89bc200 (the docs
for it). This commit is Task 8, the record.

Where the shipped code deviates from the task text, on purpose:

- Task 5 (D4): the size morph (D7) ended up in its own component,
  `Components/SizeMorph.qml`, rather than folded into the drawer itself;
  Panel, Center, Menu, Polkit and PluginOverlay each carry a `SizeMorph`
  beside their `Drawer` rather than one object doing both jobs.
- Task 5: the extraction carried `depth()`'s existing `+ borderWidth` row
  (M57 D1's own seam fix) into `drawer.js` unchanged; there was no spare
  pixel in the ring's own band to give back by shrinking it.
- D2: the walled corner's own radius follows the frame ring's
  (`Theme.frameRadius`, read live off `FrameGeometry.frameGeometry`) rather
  than being squared off, an owner-layout finding made after the first cut
  landed square (8ec46ea, 89bc200): squaring it off covered the wedge of
  band the ring's own corner curves in by, which two translucent surfaces
  turned into a visibly lighter triangle in the corner.
- D4/D5: `releaseAt` and the deform's own squash both scale down by how
  deep the line lies against the card's own size across it
  (`Drawer.qml`'s `_releaseAt` and `deformAmount` scaling), so a
  centre-floating card releases earlier and squashes less than a panel a
  `barMargin` off the bar rather than carrying the same figures regardless
  of depth.
- D8: the OSD's window became a band along the bottom edge rather than the
  whole output, and its fill went from opaque to the same translucent
  `card` fill every other drawer uses, with its own `ignore_alpha = 0.2`
  blur rule in the example config, since one silhouette across two windows
  cannot be opaque on one side of the seam.
- `--frame` in the rig pins `frame.thickness` to 10 for a wider band to
  read pixels off, rather than the 6 the owner runs on a real host.
- A shallow-shape ghost of the ring's own corner arc is visible for the
  first frame or two of a walled emerge before the run-out reaches full
  depth; a known leftover of `filletRadius`'s own depth cap, not chased
  down here.
- `--menu-emerge`'s own settle figure: open-to-rest measured 525ms before
  this branch (the unfold) and 539ms after (the emerge), inside the "don't
  make the animation any slower" the owner asked for.

**Spec:** the 2026-08-25 spec and DESIGN.md §1 "Motion" / §2 (M54 D6, the
2026-09-14 metamorphosis). This plan amends both; Task 8 writes the
amendment into DESIGN.md.

## Owner's ask (2026-09-17)

"The mitosis effect we have in the shell looks really nice, but there's some
polishing issues: the border of when the panel and edge are still connected
are misaligned by a pixel. Opening a panel near the edge clips instead of
properly morphing from multiple sides. Nested panels like the system tray or
the hidden items don't do mitosis, it looks buggy and sizes are often
mismatched. I want the launcher panel to do mitosis from the top of the
screen and move to the center. Don't make the animation any slower, and make
the overlay just darken instead of blur." Then: "for the launcher, do the
same principle with any other panel that floats in the middle if it exists."
Then: "also make it so that all panels when they suddenly resize, like wifi
or now playing, that they are all smoothly animated. This must be DRY."
Then: "things like the volume popup also needs proper metamorphosis ofc."

## What the rig showed (2026-09-17, `--join`, every clock at 1000%)

`debug motionScale <percent>` (Core/Theme.qml `motionScale`, Ipc/DebugIpc.qml)
stretches every clock so a screencopy lands inside the attached pose; the
`--join` leg samples three opens with it. Frames in `artifacts/join-*.png`.

- **The seam.** While attached, the hairline's own row reads `17171B` across
  the whole gap against `151519` for the bar above it and the card below it.
  The bar's fill runs through that row and `Shoulders`' fill starts ON it
  (`v = 0`), so the row is two translucent `card` fills deep. On a host with
  blur and a wallpaper that is a visible line across the top of every
  attached card. The fill's fillets are also tangent to `v = 0` while the
  stroke's are tangent to `v = borderWidth / 2` with radius `r + bw/2`, so
  the two arcs are not concentric: the stroke runs up to half a pixel outside
  the fill along the fillet.
- **The edge.** `panel open network` with no cell rests `screenPadding` (12)
  off the screen's end and the fillet wants `radiusXl` (14): the far fillet is
  cut by the output's own edge.
- **Nested.** A 380px weather panel opened from a cell in the chevron's 145px
  second bar joins the owner's far edge with its own full width: the card and
  both fillets hang out past either end of the bar they are meant to bud
  from, and the far fillet is cut by the screen as above.

## Locked decisions

**D1, the line's row is painted once.** `shoulders.js` `outline()` takes the
attach factor and starts the FILL `borderWidth * attach` in from the line
(the stroke stays where it is, `near + borderWidth / 2`). Attached, the fill
starts under the line's row and the fill's fillet is concentric with the
stroke's (same centre, radius `r` against `r + bw/2`); let go, the fill is
the card's own rect exactly as today. `geometry.js` `frameAlong` rounds to a
whole pixel, so a cell with a half-pixel centre never puts the card's sides
and the gap's ends on a pixel boundary.

**D2, walls.** A side of the card resting closer than `radius` to where its
line ends (the output's edge, or the frame ring's inner line when
`frame.thickness` is on) is *walled*: attached, the silhouette runs out to
that wall instead of drawing a fillet that cannot fit. The far corner on a
walled side is a concave fillet past the far edge, against the wall (the
near fillet's own construction turned a quarter); the corner between the
line and the wall takes the corner those two lines meet in, which against a
frame ring is `frame.radius` (2026-09-17, read off the owner's own layout:
squaring it off there covers the wedge of band the ring's corner curves in
by, and two translucent surfaces make that a lighter triangle; the ring gives
its arc up over the same span, Frame/geometry.js's `gone`) and square against
a bare output edge. On the attach clock the walled
side pulls in from the wall by its resting room exactly as the near edge
pulls off the line by `neck`, that side's border comes up with `1 - attach`
the way the near edge's does, and all four corners arrive at the card's own
convex radius together. A walled side publishes a second join on the wall's
own edge (`PanelRegistry.setJoin`/`clearJoin` keyed by owner AND edge), so a
frame ring opens its line there; with no ring the shape runs `radius` past
the output so the deform's squash never opens a sliver at the screen edge.
Which sides are walled is decided from the card's RESTING rect, never the
live one. `Shoulders` grows by the wall fillet on the far side only when a
side is walled; consumers that never wall (Center.qml) are untouched.

**D3, a nested card buds from what its owner can give.** With `target` set
(a card hanging off another panel), the span it may join on is the owner's
far edge less the owner's own corner radius at either end. Attached, the
silhouette's rect along the line is the card's rect clamped into that span,
fillets included; on the attach clock it widens to the card's own rect. The
join is published from the clamped rect, so the owner's `farGap` and the
silhouette cannot disagree. Panel's `clipper` takes the silhouette's own
range along the line while `attach > 0` and the rect is clamped, so the
contents are revealed by the widening rather than drawn outside the bud. A
span too short for two fillets and a sliver of card (`< 4 * radius`) does
not join: the card emerges plain from under the owner's edge, clipped to the
owner's span. The same clamp applies against the screen's own line as a
backstop, which D2 normally pre-empts.

**D4, one drawer.** `Components/Drawer.qml` owns what Panel.qml and
Center.qml each assemble by hand today: `Presence` (emerge), `Joint`,
`Deform`, the clipper at the line, the translated frame, the deformed item,
`Shoulders`, and a default slot for the contents inside the card's padding.
Inputs: `open`, `edge`, the resting rect, where the line is, `joined`,
`target`, `owner`, `screen`, `radius`, `color`, `bypass`, `mapped`. Panel and
Center move onto it with no visual change (every existing leg still passes).

Owner, 2026-09-17: "it must be DRY and dynamic." So a consumer states two
things, the edge it comes out of and its resting rect, and the drawer
derives the rest from the output and `Theme.edgeInset`: where that edge's
line is (bar, ring or the output's own edge), the depth back to it, which
sides are walled (D2), the span a target gives (D3). No surface carries its
own join arithmetic, and a surface that moves, resizes or changes edge at
runtime (`bar.position`, `frame.thickness`, a second bar growing) is
followed without being told.

**D5, centre-floating cards bud off the top line.** Menu.qml (every route),
PolkitDialog.qml and PluginOverlay.qml use `Drawer` with `edge: "top"`: the
line is the top bar's hairline, the frame ring's top line, or the output's
top edge, and `depth` is the card's resting top less that line. The card
comes out from under the line on `spatial`, the silhouette running from the
line to the card's far edge, and lets go at `releaseAt` on `spatialFast`:
the near edge pulls off the line down to the card's own top. No fade, no
zoom, no unfold. `Presence`'s `unfold` mode is deleted with its last
consumer, and `fade` stays for tooltips and the bar. Nothing is slower: the
travel is `spatial` (500), what the unfold already ran on, and the let-go
overlaps its tail.

The scrim stays plain black at 0.5 on `presence`'s own pose, except over the
band the line belongs to (`Theme.edgeInset.top`, nothing when the top edge
has no bar and no ring): that band's share is `* (1 - attach)`, so the card
buds off a lit bar and the bar dims as the card lets go.

**D8, the OSD is a drawer too.** Osd.qml already emerges from the bottom
edge; it moves onto `Drawer` with `edge: "bottom"` and joins the line there
(a bottom bar's hairline, the ring's bottom line, the output's bottom edge),
attached for the travel and let go at rest like every other card. It keeps
its own timing and its no-focus, click-through surface. Toasts are not part
of this: they arrive on `emphasizedDecel` from off screen as a stack, not
out of a line.

**D6, darken, not blur.** The modal namespaces (`formalshell:menu`,
`formalshell:polkit`, the plugin overlay's) take `ignore_alpha = 0.6` in
`docs/examples/hyprland/formalshell.conf`: the 0.5 scrim falls under it and
only darkens, the 0.85 card stays over it and keeps its blur. USAGE.md notes
that `theme.surfaceOpacity` under 0.6 loses the card's blur on those three.
`tests/tst_hyprland_layerrules.qml` pins it. The owner's own Hyprland config
in `~/.config/nix` gets the same value in Task 9.

**D7, one size morph.** Panel, Center and Menu each carry their own
`_morphHeight`/`_morphWidth` and Behavior. One component
(`Components/SizeMorph.qml` or the Drawer itself, whichever reads better
once D4 exists) owns the rule: track the target while open, freeze on close,
travel on `spatial`, armed from `mapped` rather than `settled` (Menu.qml's
own finding: content lands a tick after open, and a Behavior gated on
settled lets that jump through). Task 7 reproduces the Wi-Fi and now-playing
snaps under `motionScale` FIRST and fixes what it finds in that one place;
no per-panel Behavior is added anywhere.

## Tasks

One subagent per task, sequential, on `main`. Each ends with its
verification run and read, then one commit (conventional, lowercase, no
body, no trailers). VM commands go through `dev/vm-lock.sh` (another agent
shares the VM). `git add` new files before any build.

### Task 1: the instrument (done with this plan)

`Theme.motionScale`, `debug motionScale`, `dev/smoke.d/join.sh` sampling
cases a (far-end panel), b (second bar), c (child of the second bar).

### Task 2: the seam (D1)

`shoulders.js`, `Shoulders.qml`, `geometry.js`, `tests/tst_shoulders.qml`,
`tests/tst_panel_geometry.qml`. `--join` asserts, on an attached frame of
case a, that the line's row inside the gap is byte-equal to the bar's own
fill two rows up, and `--shoulders` still passes.

### Task 3: walls (D2)

`shoulders.js`, `Shoulders.qml`, `Joint.qml`, `PanelRegistry.qml`,
`Panel.qml`, `FrameRing.qml` if its per-edge lookup needs the new key,
unit tests. `--join` asserts on case a that the column at the output's last
pixel carries card fill from the line down to the card's far edge while
attached and bare desktop at rest; `--join --frame` read by eye for the
ring's gap.

### Task 4: the nested bud (D3)

`Joint.qml`, `Panel.qml`, unit tests. `--join` asserts on case c that no
attached frame paints card fill outside the owner's span in the band between
the owner's far edge and the child's resting top, and that the rest frame is
the full card. `--tray` / `--tray-overflow` / `--chevron` / `--chevron-quiet`
still pass; read the tray item's menu off the tray's second bar at
`motionScale 1000` by eye.

### Task 5: the drawer (D4)

Extract, move Panel and Center onto it. `just test`, then `--panel-emerge`,
`--panel-handoff`, `--deform`, `--shoulders`, `--center`, `--panel-anchor`,
`--bar-position left --panel network`, `--join`.

### Task 6: the modal bud, the scrim, the layerrules (D5, D6)

Menu, Polkit, PluginOverlay; `Presence` loses `unfold`; `--menu-unfold`
becomes `--menu-emerge` (the card out of the top line, attached mid-flight,
a plain card at its old resting rect at rest, the bar's band undimmed while
attached); `--menu`, `--picker`, `--clipboard`, `--polkit`, `--plugins`,
`--keybinds`, `--emoji` still pass.

### Task 6b: the OSD (D8)

Osd.qml onto `Drawer`, bottom edge. `--osd` still passes, and a
`motionScale 1000` sample of one `osd` call shows the pill attached to the
bottom line mid-flight and a plain pill at rest.

### Task 7: one size morph (D7)

Reproduce first, fix in one place, a leg that samples a Wi-Fi panel whose
list changes height under `motionScale` and reads a height strictly between
the two rests.

### Task 8: the record

DESIGN.md §1 Motion and §2, USAGE.md, CLAUDE.md's leg list (`--join`,
`--menu-emerge`), `dev/smoke.d/README.md` if the contract moved, this plan's
status line.

### Task 9: push and the hosts

Push `main`; `~/.config/nix`: the modal `ignore_alpha`, `nix flake update
formalshell`, rebuild every host that carries the shell.
