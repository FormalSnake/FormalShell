# M51: caelestia-grade motion in FormalShell's own grammar

**Date:** 2026-08-31
**Status:** implemented 2026-08-31. Tasks 1 to 7 landed on
`m51-motion-polish`, oldest first: dd59286 (motion tokens v2), a765de6
(Presence, Panel/Tooltip/OSD), 2e8b322 (Menu/Center/Polkit/PluginOverlay),
d45509c (size morphs), 2c7ae8c (centre rows, chevron, Input/Switch), 176b353
(palette crossfade), cefe85d (lock entrance).

Not this plan's: a combined smoke session that pairs `--menu` with other
legs (`--menu --center --polkit`, `--menu --toggles`, `--toggles --center`)
can fail a menu assert (`a root query for 'e' grouped into 0 heading(s)`,
sections empty). Verified 2026-08-31 on main 58561d6 with no M51 changes,
from a detached baseline worktree, and reproduced at d04867b by the peer
session, so it predates the emoji commit. The peer's paired statuses
narrow it: at t0+2 root reports 18 rows in two sections, and after `menu
filter e` the same level (level null both times) reports 0 rows, so the
tree was built and the ranked root search returned nothing under combined
load; `--menu` and `--polkit` both run t0=3. The assert itself only
exists since 025f7cb (2026-08-27). Every leg passes alone, and Tasks 3
and 4 re-verified their legs individually. Menu-sharing combinations run
their legs individually until the rig race is fixed.

A second combined-session race, same standing: `--theme-toggle
--wallpaper` fails `general:col.active_border does not carry the
wallpaper primary 91d5ad. Got: custom type: ff266a49 0deg`, byte-identical
at 2c7ae8c (before the palette crossfade) and at 176b353 (after), so the
border carries a stale palette under combined load regardless of M51.
Both legs pass alone; Task 6 verified them individually.
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook; Task 1 amends its
§1 Motion paragraph and this plan records why.

## Owner's ask (2026-08-31)

"Make my shell match the polish the caelestia shell has, while keeping mostly
my design language and feature set."

## What caelestia does, and what transfers

caelestia-dots/shell is GPLv3: patterns and values only, no ported code. Its
feel comes from mechanics, not from any single animation:

1. Nothing ever unmaps. One persistent layer surface per output holds every
   drawer as an Item, so everything can animate out. FormalShell already has
   the equivalent: every summonable surface stays mapped until its close fade
   settles (`Components/Panel.qml:296` and six hand-rolled copies), so exits
   are structurally free here too. The single-surface architecture itself
   does not transfer; our per-surface windows plus that idiom already do the
   job, and the frame's exclusion zones depend on them.
2. Asymmetric enter and exit. Enter lands on a decelerating curve, exit is
   shorter. FormalShell uses one duration both ways today.
3. Container morphs. Panel size changes animate through Behaviors on
   implicit size, cascading through the layout; content loaders stay alive
   through the whole close animation; a closing surface freezes its size
   first so the collapse never fights a remeasure.
4. Color never snaps. Their base rect color-animates everywhere. FormalShell
   has two ColorAnimations in the whole shell; a theme mode toggle recolours
   every surface in one frame while the wallpaper crossfades over 400ms.
5. Anchored transforms. Popouts scale and slide from the edge that owns
   them, so motion says where a surface came from.

What does not transfer, banned by `docs/DESIGN.md` §5 or foreign to the
language: M3 shape morphing, the SDF blob border, press ripples, elevation
shadows, spring overshoot curves, 500ms spatial durations.

## Findings (audit 2026-08-31)

1. The token system is real and consumed in 40 files
   (`shell/Theme/tokens.js:223` MOTION_BASE, `shell/Core/Theme.qml:197`).
   Easing is a deliberate OutQuint for enter/exit and InOutQuart for
   in-place moves. Motion is on/off only (`motion.enabled`).
2. Enter is opacity plus a 4px slide. The owner already ruled 4px "read as
   not animating at all" when the toasts were amended (`docs/DESIGN.md:189`).
3. Instant with no carve-out: the chevron glyph swap
   (`shell/Surfaces/Bar/widgets/ChevronWidget.qml:74`), the launcher's level
   change (`Menu.qml` `_enterLevel`), the centre's row list (plain
   Repeaters), `Input`'s focus and error states, `Switch`'s track colour.
4. Nothing animates container size: the launcher card, panels and the
   centre jump height on content change.
5. The OSD is an opacity-only fade, the one summonable surface with no
   slide at all.
6. The lock surface has no entrance; its content appears with the surface.

## Locked decisions

- D1 Restraint stays. No overshoot, no ripple, no shadow, no shape morph.
  The polish budget goes to asymmetric enter/exit, anchor-origin zoom, size
  morphs and the palette crossfade. Chrome durations stay under 300ms;
  `reveal` keeps 400 for the two palette-scale moments.
- D2 The surface recipe, shadcn's own motion grammar (fade, zoom from ~0.97,
  a small slide from the anchor): enter is opacity 0 to 1, scale
  `motion.zoom` (0.97) to 1 with the transform origin on the anchored edge,
  and a `motion.slide` (8px, up from 4) travel toward rest, over
  `motion.surface` (180ms) on OutQuint. Exit reverses everything over
  `motion.surfaceExit` (120ms) on OutQuint. Behaviors, not sequential
  animations, so a re-toggle retargets mid-flight instead of restarting.
- D3 Modal surfaces (launcher, polkit, plugin overlay) zoom from centre with
  no slide; their scrim fades on the same clock. Anchored surfaces (panels,
  tooltip, centre, OSD) use the edge origin and the slide.
- D4 One primitive owns the recipe: `Components/Presence.qml`, wrapping
  open state, opacity, scale, slide and the `shown` flag the window's
  `visible` binds to. The seven hand-rolled copies of that bookkeeping
  adopt it.
- D5 Size morphs run only while a surface is fully open, on
  `motion.emphasized` with InOutQuart, and a closing surface freezes its
  size (binding broken, current value pinned) before the exit starts.
- D6 `Theme.color.*` animate at the token source over `motion.reveal`, so a
  mode toggle, a matugen recolour and a preset swap crossfade the whole
  shell in step with the wallpaper. Behaviors sleep between changes, so
  idle cost is zero (M50's constraint stands).
- D7 `motion.enabled=false` keeps meaning instant: durations 0, zoom 1,
  slide 0. No new settings keys in this plan.
- D8 Existing carve-outs stand: list cursors jump, toasts travel their own
  width, the workspace pill keeps its two-edge stretch on `emphasized`.
- D9 Smoke legs that sample mid-animation or assert stability (workspaces at
  80ms, chevron's frame diff, toggles' surface stability, notify's constant
  layer size) are read before any task touches their surface and stay green
  unmodified. Editing a leg to make a task pass is a defect.

## Tasks

Each task is one subagent, sequential. A task ends with its verification
commands run and their output read (PNGs opened, not assumed), then one
commit staging only the paths it touched (never `git add -A`). VM commands
go through `dev/vm-lock.sh`.

### Task 1: motion tokens v2

- `shell/Theme/tokens.js` MOTION_BASE: `slide` 4 to 8, add `surface` 180,
  `surfaceExit` 120, `zoom` 0.97. `motionTokens(false)` zeroes the new
  durations and neutralises the transforms (zoom 1, slide 0).
- `shell/Core/Theme.qml` exposes them beside the existing motion tokens.
- `docs/DESIGN.md` §1 Motion rewritten to state the D2/D3 recipe, the D5
  morph rule and the D6 crossfade, keeping the carve-out prose.
- Tests: extend the tokens unit test for the new keys both enabled and
  disabled.
- Verify: `dev/vm-lock.sh just vm-test` and read the token test output.

### Task 2: Presence, then Panel, Tooltip, OSD

- New `Components/Presence.qml` per D2/D4, with a small qmltest for its
  lifecycle (open, settle, close, `shown` drops only after the exit).
- `Components/Panel.qml` adopts it for every popout: origin on the bar
  edge (`bar.position` decides), slide from that edge.
- `Components/Tooltip.qml`: fade plus zoom from the anchor side, no slide
  beyond its existing 6px offset geometry.
- `Surfaces/Osd/Osd.qml`: gains the full recipe, rising from the bottom
  edge; its hide timer keeps its own schedule. The value `Track` gets a
  `fast` fill Behavior so a held volume key sweeps instead of stepping.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --panel network --tooltip --osd` and read the PNGs.

### Task 3: Menu, Centre, Polkit, PluginOverlay

- `Surfaces/Menu/Menu.qml` adopts Presence with the modal recipe (D3).
  Level and route changes get a directional content entrance: the incoming
  list starts at opacity 0 offset 8px (from the right going deeper, from
  the left going back) and settles over `standard` on OutQuint; no outgoing
  phase, so fast typing never queues animations.
- `Notifications/Center.qml` adopts Presence anchored to its screen edge.
- `Polkit/PolkitDialog.qml`, `Plugins/PluginOverlay.qml`: modal recipe,
  scrim on the same clock.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --menu --center --polkit` and read the PNGs.

### Task 4: size morphs

- Launcher card, `Components/Panel.qml` card and the centre animate
  implicit height changes per D5 (Behavior active only while fully open,
  frozen on close, content clipped during the morph).
- Read `dev/smoke.d/toggles.sh` first (D9): its surface-stability assert
  must hold with the morph in place, since the end state is unchanged and
  the leg samples settled frames.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --menu --toggles --center` and read the PNGs.

### Task 5: centre rows and the micro gaps

- `Notifications/Center.qml` rows get the toasts' presence treatment:
  height plus opacity on add and remove, reflow on `standard` InOutQuart,
  matching `Toasts.qml`'s slot mechanics.
- `ChevronWidget.qml`: the glyph flip animates (crossfade or quarter-turn,
  `fast`), so the one instant piece of the collapse interaction joins it.
- `Components/Input.qml`: border colour and ring opacity transition on
  `fast` for focus, blur and error.
- `Components/Switch.qml`: track colour on `fast` beside the existing
  thumb slide.
- `Components/Track.qml`: fill width on `fast` where it does not already.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --center --chevron --notify` and read the PNGs (chevron's two frames
  must still differ).

### Task 6: palette crossfade

- `shell/Core/Theme.qml`: the exposed `Theme.color.*` properties animate
  palette changes per D6. Implementation must keep them assignable from
  the existing palette pipeline without re-evaluating at idle; verify no
  binding loop with `hoverFill`/`surface()` helpers.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --theme-toggle --wallpaper` and `--retro --gallery` as a second session,
  read the PNGs (end states identical to today's).
- Perf gate: the smoke run's SMOKE_MEM line stays in its M50 band.

### Task 7: lock entrance

- `Lock/LockSurface.qml`: the clock, date and input column fades in with
  an 8px rise on surface creation, `surface` duration, per output. Enter
  only; unlock stays instant (the session lock is released, nothing to
  animate against). Greeter shares whatever LockSurface gives it for free.
- Nested sessions only, per the lock-screen rule.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --lock` and read the PNG.

### Task 8: sweep and coherence

- One session over the token-change minimum plus the touched surfaces:
  `dev/vm-lock.sh just vm-smoke --menu --notify --panel network` then
  `--workspaces --osd --center` as a second session; read every PNG.
- `docs/DESIGN.md` read end to end against the shipped behaviour; any
  drift fixed here.
