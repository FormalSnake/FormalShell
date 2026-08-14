# FormalShell M25: anchor the chevron, animate the reveal

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-14), hours after M24 shipped:** "Make it smooth
open. And also, does omarchy do this in reverse or not? as a macos user it
kinda feels weird that it opens to the left and not to the right, as that way
the chevron shifts position."

Two changes: the chevron stops moving, and the reveal animates.

## Context: why the chevron moves today, and what omarchy actually does

M24's rule is "the chevron collapses every entry after it in its region". In
the right region, which is anchored to the screen edge, the governed group
therefore sits *outboard* of the chevron. Revealing it grows the region
leftward, so the chevron and every always-visible cell slide left. That is the
shift the owner is objecting to.

Omarchy's tray drawer is the reverse on both counts, read from
`shell/plugins/bar/widgets/Tray.qml` at `8b70f01`:

```qml
readonly property int drawerBlockWidth: root.allItems.length > 0
  ? expandIcon.implicitWidth + root.drawerExtent : 0
implicitWidth: pinnedWidth + drawerBlockWidth
```

`drawerBlockWidth` does not depend on `revealProgress`, so the widget's width
is constant and opening the drawer reflows nothing at all. The pinned
(always-visible) icons are placed outboard of the drawer block at a fixed x
and never move; the drawer opens inward into permanently reserved space; only
the chevron travels, right to left across that gap, over 600ms.

**We take the anchoring, not the reservation.** Omarchy reserves the hidden
group's full width forever, which is affordable for a handful of tray icons
and not for a bar chevron governing six widgets: the bar would stay exactly as
wide as if nothing were hidden, erasing the density win M23/M24 exist for.
Note also that omarchy's own chevron still slides, so copying it would not
even fix the owner's complaint.

The arrangement where the chevron genuinely never moves is to flip which side
it governs, so the governed group sits *inboard* and grows into empty bar:

```
RIGHT REGION, | = screen edge

M24 (governs what follows):
  collapsed          [bat][vol][net][bel][>] |
  expanded  [bt][ts][wx][gh][ai][tray][<]... |     everything slides left

M25 (governs what precedes):
  collapsed              [>][bat][vol][net][bel] |
  expanded  [bt][ts][wx][gh][ai][tray][<][bat][vol][net][bel] |
                          ^ chevron x unchanged, pinned cells unchanged
```

## Constraints

- All CLAUDE.md hard rules stand: radius 0, no blur, no shadows, border
  width 2, fontconfig `monospace` alias, Nerd Font glyphs, pure QML/JS.
- ⚠️ Targeted `Edit` only on any file carrying Nerd Font codepoints.
- ⚠️ Any file reaching the `State` singleton while importing QtQuick must
  `import qs.Core as Core` and use `Core.State`. QtQuick exports its own
  `State` type and the bare name silently reads back undefined. This is what
  made M24 ship rendering-dead.
- `Cell` now owns its own pointer target (`interactive: true`, `onClicked`,
  `containsPointer`). Do NOT add a `MouseArea` to a Cell.
- Do not touch `Bar.qml`'s `PanelWindow`, anchors, or exclusion zone.

## Task 1 — The chevron governs its inward side

**`shell/Bar/layout.js`.** Replace the "everything after it" rule with a
region-aware one: the chevron governs the entries on the side away from its
region's anchored edge, so the anchored edge stays put.

| Region | Anchored edge | Chevron governs |
| --- | --- | --- |
| `right` | screen right | entries BEFORE it |
| `left` | screen left | entries AFTER it |
| `center` | centered | entries AFTER it |

`center` keeps M24's direction because a centered region reflows from both
ends whatever you do, so there is no edge to protect; say so in the comment
rather than leaving it looking like an oversight.

Update in step:
- the `collapsible` annotation, which is now "on the governed side of the
  region's chevron" rather than "later in the array",
- `collapsedNames`, same,
- the dead-chevron drop rule: today it drops a chevron with nothing *after*
  it; it must now drop one with nothing on its *governed* side, so a
  right-region chevron placed first is the dead case and a left-region
  chevron placed last is.

**Tests, `tests/tst_bar_layout.qml`.** The existing chevron cases encode the
old direction and will fail; rewrite rather than delete them, and add: a
right-region chevron marks only what precedes it; a left-region chevron marks
only what follows it; a right-region chevron placed first is dropped with its
warning; a left-region chevron placed last is dropped; a center-region chevron
still governs what follows.

## Task 2 — Glyph direction follows the governed side

**`shell/Surfaces/Bar/widgets/ChevronWidget.qml`.** The file currently argues
at length that direction must NOT mirror per region, because the governed
group was always to the chevron's right. Task 1 invalidates that reasoning, so
rewrite the comment rather than leaving a stale argument in place.

The rule stays "the glyph points where the group moves on the next click",
which is now region-dependent: in a right region collapsed points left (the
group appears to the left), expanded points right (it folds back that way);
mirrored in left and center regions.

## Task 3 — Smooth open

**`shell/Surfaces/Bar/Bar.qml`, the region delegate.** Today a collapsed entry
is `visible: false`, so the group appears and disappears in one frame. Animate
the width instead:

```qml
clip: true
width: entryLoader.modelData.collapsible
    ? (entryLoader._collapsedAway ? 0 : entryLoader.implicitWidth)
    : entryLoader.implicitWidth
Behavior on width {
    NumberAnimation { duration: Theme.motion.standard; easing.type: Easing.OutCubic }
}
```

Three things this has to get right:

1. **A fully collapsed cell must not contribute Row spacing.** `Row` puts
   `spacing` between every *visible* child, so a zero-width visible child
   still costs a gap, and six of them would leave ~48px of dead bar. Gate
   `visible` on the animated width, not on `_collapsedAway`.
2. **A widget's own `shown` still wins.** A Battery with no battery, a Tray
   with no items, an Indicators with nothing active must stay hidden whether
   the chevron is open or shut. Keep the existing `shown` term and AND the
   width term onto it. Read the delegate's header comment at `Bar.qml:288-306`
   before touching this: never read the loaded item's built-in `visible`.
3. **`Theme.motion.standard` is already 0 when motion is disabled** (see
   `shell/Theme/tokens.js`'s `motionTokens`), and a zero-duration animation
   lands on the same end state, so honoring the setting needs no extra branch.
   Do not hardcode a duration and do not reach for `reveal`, which paces
   full-screen surfaces.

Watch for a binding loop between `visible` and `width`; if one appears, drive
`visible` off the animation's running state instead and say which you used.

## Task 4 — Verification and docs

- `dev/smoke-niri.sh --chevron`: the fixture layout must move the chevron to
  match the new rule (`chevron` after the governed group in the right region).
  Assert the same two `bar chevron status` dumps as today, since the IPC
  contract is unchanged, and keep both screenshots.
- Add one assertion that is new and cheap: the collapsed and expanded
  screenshots must differ (they always have), and the run must still pass with
  `settings.json` carrying no `bar` key at all.
- Update `docs/DESIGN.md` §3's chevron sentences, `Config.qml`'s schema
  comment, `ChevronWidget.qml`'s header, and the `--chevron` bullet text for
  `CLAUDE.md` (report it, do not edit that file).
- `docs/SWITCHOVER.md`'s chevron row needs its claim updated: it currently
  says the two screenshots "differ by exactly those cells plus the glyph
  direction", which stays true, but the anchoring claim should be added.

## Acceptance

- `just vm-build`, `vm-test`, `vm-lint` green, output read.
- `vm-smoke --chevron` green, both PNGs read, and the chevron cell must be at
  the same x in both.
- A `settings.json` with no `bar` key renders exactly today's arrangement.
