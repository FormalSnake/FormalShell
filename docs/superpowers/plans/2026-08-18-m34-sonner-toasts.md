# FormalShell M34: configurable toast position + sonner-style stack

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. Runs after M33;
> do not start implementation while another workflow holds the tree or
> the VM.

**Origin, owner ask (2026-08-18):** "make through nix and the config
file the notification position configurable. By default I want bottom
right. Also, I want it to be react sonner style. It must look way
cleaner, must smoothly stack, hover shows all of the ones that appeared
at the same time, way compacter too."

**State today (verified, do not re-derive):**
`shell/Surfaces/Notifications/Toasts.qml` (165 lines): one PanelWindow
per screen, hard-anchored top-right under the bar, a plain `Column` of
full-size cards at `panelGap` spacing, enter = fade + 6px slide, removal
is INSTANT (Repeater destroys the delegate with the model row), hover
pauses expiry per card via `NotificationService.setPopupHovered`,
identical repeats grouped by `Model.groupEntries`, whole surface
suppressed while the center is open. `NotificationCard` is shared with
the center.

**Sonner mechanics, translated into the house language** (the reference
is Emil Kowalski's sonner; DESIGN.md §4 wins on every conflict):

- Sonner's collapsed stack scales older toasts down behind the newest.
  Owner amendment (2026-08-18): "in this case the stack does need
  scale, but make it consistent with pixel sizes so that it looks like
  it fits in." So the depth effect ships, but NEVER as a fractional
  render transform (a 2px border under `scale(0.95)` rasterizes at
  1.9px and reads blurry, the opposite of this shell): each level
  behind the front card is a real card SIZED narrower by an integer
  token step per level (symmetric inset, e.g. `Theme.space.lg` per
  side per level, resolved through tokens), horizontally centered on
  the front card, offset toward the screen edge by a fixed peek so
  only its edge sliver shows, its content not rendered (a sliver of
  card, not a squeezed layout). Borders stay exactly `borderWidth` on
  every level — that is the "consistent with pixel sizes" contract,
  and it is the checkable. At most 2 levels peek; further popups exist
  only in the count the expanded stack reveals. No shadow, no blur,
  radius 0. This is a dated, surface-scoped exception to §4.2's
  no-scale reading, recorded in DESIGN.md by Task 3 (precedent: the
  screensaver's §4.6 carve-out), and it sanctions stepped SIZING only —
  fractional `transform: scale` stays banned everywhere.
- Hover anywhere on the stack EXPANDS it: the collapsed pile reflows
  into today's full Column (every live popup as a full card, `panelGap`
  gaps), animated by interruptible `Behavior`s on y/height inside the
  90-140ms band with `Theme.motion.easing`. Pointer leaving collapses
  it back. While expanded, every visible popup's expiry pauses (the
  existing `setPopupHovered` per-member machinery, applied stack-wide),
  which is exactly "hover shows all of the ones that appeared at the
  same time".
- Sonner uses transitions-not-keyframes so rapid additions retarget
  smoothly; the QML equivalent (already house law, §4.4) is Behaviors
  on single scalars. New toasts arriving mid-animation must retarget,
  never queue or snap.
- Exit becomes animated: fade + slide toward the anchored edge, faster
  is fine but still in-band; the delegate must survive until its exit
  finishes (Panel.qml's visible-until-opacity-0 hold; a departing-item
  holder around the Repeater model). `motion.enabled: false` collapses
  enter, exit, expand, and collapse to instant swaps.
- "Way compacter": toasts get a compact rendering — one meta row
  (`APP / 2M AGO`, §2.10), summary at `body`, body text clamped to one
  line, image slot down from 40x40 to the caption-height slot, actions
  as bare labels; the card narrows one width step
  (`popupWidthNarrow`). The center's own cards DO NOT change: this is
  a NotificationCard `compact` mode (or a sibling ToastCard if the
  shared file fights it — implementer's call, named in the commit),
  and the center keeps today's rendering byte-identical.

## Constraints

- **Position key**: `notifications.position`, values `top-right`,
  `bottom-right`, `bottom-left`, `top-left`. Shipped default
  `bottom-right` (the owner's default; the no-config smoke expectation
  moves with it). Documented in Config.qml's header block like every
  key. Top positions clear the bar (`barHeight + panelGap`); bottom
  positions use `panelGap` from the bottom edge. Stacking direction
  follows the anchor: the newest toast sits nearest the anchored
  corner, older cards peek away from it; the enter/exit slide comes
  from the anchored side edge (§4.2's "right-anchored surfaces slide
  in from the right" generalized). A pure
  `Notifications/model.js` helper (`positionSpec(name)` returning
  anchors/margins/growth/slide axis, invalid names falling back to the
  default) carries the mapping, with `tests/tst_notifications_model.qml`
  fixtures over all four names plus garbage input.
- **Center suppression stays unconditional** while the center is open,
  whatever the position: one rule, no corner-collision math, costs
  nothing when they no longer overlap.
- Critical sticky popups (expiresAt 0) keep their full-bleed urgent
  card and never expire; collapsed, a critical popup always wins the
  front slot over newer normals (urgency outranks recency at a glance).
- Group counts (`Model.groupEntries`) unchanged.
- The `notifications` IPC target grows `expand <on|off>` driving the
  same expanded state hover sets — the rig has no synthetic pointer,
  and the chevron's `expand` verb is the named precedent for an IPC
  stand-in for a pointer action.
- Every duration/distance is a `Theme.motion`/`Theme.space` token; no
  new literals. No timer or process runs while no popup is live.
- Nix side (orchestrator, after the milestone): the owner's
  `mixins/formalshell.nix` gains `notifications.position =
  "bottom-right"` explicitly, self-documenting even while it matches
  the shipped default.

### Task 1: position key and spec

**Files:** modify `shell/Core/Config.qml` (header doc),
`shell/Notifications/model.js`, `shell/Surfaces/Notifications/Toasts.qml`,
`tests/tst_notifications_model.qml`.

**Produces:** `positionSpec` + tests; Toasts.qml anchors, margins,
column growth and slide axis all resolved through it; shipped default
bottom-right. No stack-visual changes yet — full cards, today's
Column, so this task is verifiable alone: `just vm-test`, `just
vm-lint`, `just vm-smoke --notify` (Read the PNG: both toasts now
bottom-right, full cards). Commit
(`feat(notifications): configurable toast position`).

### Task 2: the sonner stack

**Files:** modify `shell/Surfaces/Notifications/Toasts.qml`,
`shell/Components/NotificationCard.qml` (compact mode) or a new
`ToastCard.qml`, `shell/Ipc/NotificationsIpc.qml` (or wherever the
`notifications` target lives — read it first), `shell/Notifications/model.js`
if the front-slot/peek ordering earns a pure helper (it does:
`stackOrder(entries)` with critical-wins-front, plus tests).

**Produces:** offset-peek collapsed stack, hover/IPC expand with
stack-wide expiry pause, animated retargeting enter/exit with the
departing-item hold, compact toast rendering, center rendering
untouched. Verify: `just vm-test`, `just vm-lint`, `just vm-smoke
--notify` (the leg fires normal then critical: collapsed stack shot —
critical full-bleed card in front, one peek sliver behind), plus an
added leg step driving `notifications expand on` and screenshotting the
expanded pile (`toasts-expanded.png`), `notifications expand off`
restores. Read every PNG. Commit
(`feat(notifications): sonner-style toast stack`).

### Task 3: smoke expectations, docs

**Files:** `dev/smoke-niri.sh` (--notify/--center legs' anchor
assumptions and comments), `CLAUDE.md` (the --notify/--center blurbs
describe top-right anchoring and the center-overlap rationale — update
both), `docs/DESIGN.md` (§Notifications translation: collapsed
offset-peek idiom, compact toast card, position key; §4 untouched),
`docs/USAGE.md`, `docs/ARCHITECTURE.md`.

**Produces:** docs and legs consistent with bottom-right default and
the stack; full regression `just vm-test`, `just vm-lint`, `just
vm-smoke --notify --center`, plain `just vm-smoke`; tree clean, pushed.
Commit (`docs: m34 sonner toasts`).

## Review checkpoint

After Task 3: motion-band compliance (grep new durations — everything
inside fast/standard, zero blur/bounce anywhere, no `transform` scale —
the stack's depth is stepped integer sizing, and a zoomed screenshot of
the collapsed stack must sample every level's border at exactly
`borderWidth` pixels), reduced-motion
collapse verified (`motion.enabled: false` renders end-states
instantly), the departing-item hold leaks no delegates (dismiss 10
toasts fast, popup count returns to zero), center cards byte-identical
to pre-M34, suppression honest, position fallback on garbage input,
IPC expand errors on bad args, smoke evidence real (re-run --notify
--center, Read the PNGs), commits pushed.
