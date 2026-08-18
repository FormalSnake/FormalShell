# FormalShell design language

References: **Omarchy 4 ("quattro" branch)** — `github.com/basecamp/omarchy`
— is the close reference for the whole system: its token vocabulary, its
control states, its floating-surface chrome, its craft details (the lock
field, the panel section headers, the breathing pulse). **`https://www.mek.gallery/`**
(screenshot studied 2026-07-27) is a deliberate accent layered on top — "a
classic ASCII style OS" — contributing ruled tables, uppercase meta rows,
and fg/bg inversion for selection to the surfaces where FormalShell reads as
a table of information (menu, panel device lists, the picker grid). DankMaterialShell
(DMS) contributes **feature ideas only** (media panel shape, notification
center layout) — never look. Everything is monospace, radius 0, unblurred,
unshadowed. **We reimplement**: every rule below is read from omarchy's
source and rebuilt as our own QML — no omarchy file is ever copied verbatim,
so no attribution header applies to this reimplementation (the existing
DankMaterialShell attribution rule is unaffected and still governs real
ports from DMS).

**What this supersedes.** The previous revision of this document inverted
the hierarchy: mek.gallery's "ruled ledger grid" (cells fused edge-to-edge,
sharing hairline rules, no gaps anywhere) was the *base* language for every
surface, and omarchy was cited only as the functional/IPC reference. That is
wrong for the visual language specifically. Concretely, this revision changes:

- Surfaces are no longer edge-to-edge cell grids with zero gaps by default.
  Floating chrome (menu, panels, notifications, OSD, tooltips) is an
  omarchy-style **card**: a single bordered rectangle, `Style.gapsOut`-style
  margin from the bar/screen edge, internal padding, radius 0. The "shared
  hairline rule, no gap" idiom survives *inside* a card's content — rows of
  a panel's device list, a menu's item list — not between top-level surfaces.
- The interactive-state model goes from three ad hoc states
  (`hover`/`focus` merged, `selected`, default) to omarchy's four named
  states (`normal`, `hover-cursor`, `selected`, `focus`) with independent
  fill and border alpha per state, matching Task 2's implementation target.
- Borders become **specs** (color + optional gradient + per-side widths),
  not a single scalar `Theme.borderWidth`.
- Type and spacing become **scale roots** (`fontBaseSize`, `spacingScale`)
  that every token derives from by multiplier, not a hand-picked pixel per
  token.
- The bar's individual widgets are no longer required to fuse into one
  continuous ruled strip; omarchy's bar is discrete modules with a small
  gap between them, each its own hover/pressed affordance. FormalShell's
  three-region layout (left/center/right) stays — that's a functional
  decision the spec already made — but the *rendering* of each cell adopts
  omarchy's control-state chrome instead of forced adjacency.
- ASCII-OS ornament (box-drawing corner marks, ruled tables, uppercase
  letter-spaced meta rows, fg/bg inversion) is now named as an **accent**,
  applied where a surface is naturally tabular (menu rows, panel device
  lists, picker grid, notification center rows) — not a mandate that every
  pixel of chrome look like a ledger.

No feature, IPC target, provider, or state machine changes. This is a
rewrite of *how things are drawn*, not what they do.

## Revision 2026-08-07: warm ink hierarchy (the mek ramp)

Owner ask: next to mek.gallery the shell "just looks high contrasty".
Measured from mek.gallery's shipped CSS (fetched 2026-08-07), the
reference is not high contrast. It is a six-step warm ramp (canvas
#eee9dc, panel #d9d2c1, fills rgba(99,96,89,0.08), hairlines #b6b1a3,
meta inks #9c9587 and #636059, content ink #2e2e2e) with exactly one
loud color (#0099ff), 1px rules, 6px corner marks on cards, and dithered
1-bit imagery. FormalShell's failure was never temperature (Flexoki is
already warm paper); it was a compressed ramp: borders drawn as
foreground alphas shout as loudly as content, and selection is a photo
negative instead of the accent. This revision changes:

- **Ink hierarchy becomes law (§1.4, new).** Loudness on any surface is
  strictly content ink (`foreground`) > meta (`foregroundDim`) > faint
  (`foregroundFaint`, new role) > rules and borders (`rule`). Structural
  rules and control borders always draw the `rule` token at alpha 1.0;
  the state table's border-alpha column is retired (§1.1). Fill alphas
  are unchanged.
- **The palette grows 8 → 12 roles (§1.5, new).** `foregroundFaint`,
  `warning`, `onWarning`, `onUrgent`. theme.json stays the entire
  theming contract: matugen's template re-spreads Material roles so the
  ramp survives wallpaper theming, and any other engine (pywal, a
  hand-written file) rendering the same keys themes the shell
  identically; the per-key Flexoki fallback keeps pre-expansion
  theme.json files valid.
- **Selection inverts through accent, never a photo negative (§2.2).**
  The cursor row, current picker cell, and bar-cell hover invert to
  `{ bg: accent, fg: onAccent }` (`{ bg: urgent, fg: onUrgent }` on
  urgent-carrying rows). The plain foreground/background swap is retired
  shell-wide. §1.1's bar-cell amendment stands as a directive (hover is
  an inversion, not a tint), now rendered through accent.
- **Ornament (§2 items 7-8, new).** 6px corner marks become the one
  sanctioned ornament on floating-card outer chrome; ordered Bayer
  dither becomes the sanctioned texture for track remainders and pending
  fills. Scanline/CRT effects stay banned.
- **Spacing discipline (§1.3).** Every gap, padding, and row height is a
  `Theme.space`/`Theme.fontSize` token; sibling surfaces use the same
  token for the same structural element; a between-groups gap is at
  least twice the within-group gap.

Verified contrast (WCAG 2, both modes) for the new and changed pairs:
dark ramp 11.98 (fg) / 5.19 (dim) / 2.61 (faint) / 1.80 (rule); light
ramp 12+ / 4.97 / 2.64 / 1.55. Dark `onAccent` flips to ink (#100F0F on
#4385BE is 4.86:1, beating paper's failing 3.83:1); light keeps paper on
accent (6.36:1). Warning pairs: 5.77:1 dark, 4.69:1 light. Ink on urgent
is 4.42:1, the best available over Flexoki red 400, large-text AA only.
`foregroundFaint` (2.6:1) is legal for ornament and faint/disabled meta
only, never content ink. No feature, IPC, or layout-structure change;
drawn output only.

## Revision 2026-08-09: the mek grammar (live-site study)

Owner ask: match mek.gallery's look and feel, not just its palette. The
live site was driven in a real browser on 2026-08-09 (the site ships a
`darkreader-lock` opt-out, so the first naive capture was a Dark Reader
recolor and was discarded) and measured from computed styles and pixel
samples across home, /about, /pixel, /dev, and the PROJECTS dropdown. The
ramp is unchanged from the 2026-08-07 capture: canvas #eee9dc, panel step
#d9d2c1, 1px hairlines #b6b1a3, faint meta #9c9587, meta ink #636059,
content ink #2e2e2e, one loud blue #0099ff (links only, always
underlined, 137 uses), fill tint rgba(99,96,89,0.08). What the study adds
is grammar this document does not yet encode, plus one correction to it:

- **The dog-ear fold mark replaces the corner squares (§2 item 7,
  rewritten).** A scan of the live DOM for 4-8px square elements returns
  zero: the 6px corner marks the 2026-08-07 block cites are gone from the
  site. Cards and ledger cells carry a small folded-corner triangle at
  the top-left instead. That one point of the 2026-08-07 revision is
  superseded, one fold mark at one corner is what ships; the rest of that
  block stands.
- **Card title-bar band (§2 item 9, new).** Every floating card opens
  with a one-row band: uppercase meta label plus trailing colon at the
  left, optional meta text or bare-label actions at the right, one shared
  rule below. The menu's breadcrumb row and the panels' title row already
  are this band; the notification center gains one.
- **Trailing colon on headers, ` / ` on meta pairs (§2 item 10, new).**
  Every section header on the live site ends in a colon, no exceptions
  found. Inline meta pairs take no colon and fuse with a spaced slash,
  which the shell already does (`PENDING / 2`, `appName / relTime`) and
  this revision names as law.
- **The ink button (§2 item 11, new).** A committing action's resting
  cell is a full-bleed `foreground` fill carrying `background` ink, the
  shape of mek's Submit. Hover and press keep the accent-pair inversion,
  so this is a resting affordance, not a revival of the retired
  photo-negative selection.
- **Ink-promotion hover for bare labels (§1.1, new amendment).** A
  label-only control promotes its ink one band on hover (`foregroundDim`
  to `foreground`) and leaves its ground alone, which is mek's nav
  behavior. Cells keep the fill-alpha and inversion model, and the
  bar-cell accent-inversion directive stands.
- **Faint placeholders (§1.4).** A field's placeholder ink is
  `foregroundFaint`, one band under the field's own label.

Study notes, recorded as reference with no rule and no palette role
added: mek's announcement modal is a warm dark card, ground #33241e, with
the paper #eee9dc as its content ink and #9c9587 as the meta ink on both
grounds, so the ramp already survives a dark ground with its meta step
intact. The site's own `prefers-color-scheme: dark` swaps nine tokens to
a terminal facet (#000 canvas, #161617 surface, #fff ink, #0f0 accent)
while the paper ramp tokens stay put: the shell's dark mode is that facet
of the same language, not a divergence from it. The PROJECTS dropdown
pixel-samples flat #d9d2c1 on every row, so there is no zebra striping to
adopt (what reads as alternation is glyph density); a summoned surface
sits one step below canvas with shared 1px rules, which is what §2 item 1
already requires. Empty column ends carry faint asterisk-family dings
(`✳ ❋`) from the MEK Dings faces; a faint glyph is permitted the same way
here, as an empty-state ornament in `foregroundFaint`, never as a
mandate.

Measured and deliberately not adopted: the modal's `box-shadow: 4px 4px 0
rgba(0,0,0,.25)` hard offset plate (the no-shadows hard rule stands),
mek's custom bitmap faces (the fontconfig `monospace` alias hard rule
stands), hidden scrollbars (a browser concern, not a QML one), and mek's
sub-AA header contrast (#9c9587 on canvas measures about 2.2:1, while
shell headers stay `foregroundDim` per the 2026-08-07 WCAG stance, a
deliberate divergence). No feature, IPC, provider, or state-machine
change, and no palette change: the twelve roles in §1.5 carry every rule
above.

## 1. The token system

Every value below is a **default**; nothing here freezes a magic number —
each is reachable through the base-size/scale roots so retheming rescales
the whole shell from two numbers. Task 2 implements this vocabulary in
`shell/Core/Theme.qml`; the matugen-driven palette roles (twelve since
the 2026-08-07 revision: `background`, `backgroundAlt`, `foreground`,
`foregroundDim`, `foregroundFaint`, `rule`, `accent`, `onAccent`,
`urgent`, `onUrgent`, `warning`, `onWarning` — `shell/Theme/palette.js`,
full table in §1.5) are the color tokens the state/border machinery
below resolves against. Matugen wiring and `theme.json` remain the
theming contract; §1.5 defines how the twelve roles are populated.

### 1.1 Four interactive states

Every control (bar cell, menu row, panel button, toggle, slider, text
field) is in exactly one of four states at any moment:

| state | meaning | default color token |
| --- | --- | --- |
| `normal` | idle chrome | `foreground` |
| `hover-cursor` | mouse hover **or** panel keyboard cursor row (unified — a panel's own arrow-key cursor reads identically to a real mouse hover) | `foreground` |
| `selected` | persistent chosen/current (the enabled toggle, the current workspace, the checked radio) | `foreground` |
| `focus` | real Qt `activeFocus`; defaults to mirroring `hover-cursor` so Tab-focus and mouse-hover read identically | inherits `hover-cursor` |

Each state carries a **fill alpha**, applied against the state's
resolved color (a palette role — `foreground` / `accent` / `urgent` /
`background` — or a raw hex from a theme override). Borders are simpler
since the 2026-08-07 revision: a control's border always draws the
`rule` token at alpha 1.0 (§1.4's ink hierarchy makes rules the
quietest ink on screen, so no alpha games are needed), and the old
per-state border alphas are retired:

| state | fill alpha | border width | border color |
| --- | --- | --- | --- |
| `normal` | 0.04 | 2 | `rule` |
| `hover-cursor` | 0.08 | 2 | `rule` |
| `selected` | 0.18 | 0 | (borderless) |
| `focus` | = hover-cursor | = hover-cursor | = hover-cursor |
| `pressed` (mouse-down only, not a persistent state) | 0.22 | — | — |

Border width defaults to **2** — the spec's non-negotiable brutalist
baseline (`docs/superpowers/specs/2026-07-27-formalshell-design.md`,
CLAUDE.md's hard rules) — not omarchy's own 1px default; the fill
alphas, the state vocabulary itself, and the per-side/gradient spec
shape carry over from omarchy as-is. A state's border width of `0`
drops that border entirely — `selected` is borderless by default (the
fill alone reads as chosen), while a text field or a bar cell that
wants a visible ring uses the 2px default. Exception to the
borders-are-`rule` doctrine: a border that *means* something (the lock
field's error state in `urgent`, an accent-carrying focus ring named
by a surface's own brief) may draw its semantic role instead; plain
structural chrome never does. Paint priority when more than one
applies: `pressed` > `focus` (only when the control is real-focusable) >
`hover-cursor` > `selected` > `normal`.

Where the ASCII-OS accent overrides this for a genuinely tabular surface
(menu cursor row, picker grid, notification-center row — see §2),
**inversion** replaces the fill-tint for the *selected*/cursor state
only, and since the 2026-08-07 revision the pair is always
accent-carried: `{ bg: accent, fg: onAccent }` (`{ bg: urgent,
fg: onUrgent }` for an urgent-carrying row). The old photo-negative
`{ bg: foreground, fg: background }` pair is retired shell-wide; it is
what made the shell read as a high-contrast terminal instead of an old
OS (mek.gallery's selection is always its blue, never a negative).
Inversion and the fill-alpha model are never both active on the same
cell.

**Amendment (bar-cell hover, owner directive over a tint/underline).** The
bar's own discrete widget cells (`Cell.qml`'s `standalone` contract, §3)
apply this same inversion to the `hover-cursor` state too, not just
tabular selection: hovering a bar cell swaps its fill to `accent` and
its content (text and glyphs alike) to `onAccent` (the accent pair per
the 2026-08-07 revision; the directive is "hover inverts", the pair is
accent's), replacing the fill-alpha tint + hover border every other
cell still uses. The fill still
fades in over `Theme.motion.fast` (the fade lives on the fill layer, not
the color swap), but the content color itself snaps instantly the moment
the state resolves, same as every other inversion in this document (§4.3).
Cells already carrying a full-bleed `accent`/`urgent`/`selected` fill (the
focused workspace, a critical battery) keep that fill instead — no double
treatment. Panels, menu, and every other non-`standalone` cell are
unaffected; the menu's cursor row already inverted on its own, so this
change unifies the idiom rather than introducing a second one.

**Amendment (bare labels hover by ink promotion, 2026-08-09).** A control
that is only a label, with no cell chrome of its own (a card title-bar
band's right-side actions per §2 item 9, a nav-style text action), neither
tints nor inverts on hover. It promotes its ink one band up §1.4's
hierarchy, `foregroundDim` to `foreground`, and its ground does not
change. This is mek.gallery's nav behavior: labels idle at the meta ink
and go to content ink under the pointer. It applies only where there is no
cell to fill; anything drawn as a cell keeps the fill-alpha model above,
including the bar-cell accent-inversion directive. Checkable: sample a
title-bar action's background hovered and idle, both equal the card's own
ground; sample its text, it moves from the `foregroundDim` hex to the
`foreground` hex.

**Amendment (the lit area is the hit area, 2026-08-14).** Whatever a state
fill covers is what the pointer has to be able to reach. A control whose
target is smaller than its own fill reads as clickable across a band that
answers nothing, and on the bar that band includes the row of pixels against
the screen edge, the easiest pixel on the display to hit. `Cell.qml` carries
a `hit` slot spanning the whole cell for exactly this reason; a pointer
target put in the default slot instead lands in the padded content box and
is short by the control padding (§1.3) on every side, which is a defect
rather than a density choice. Checkable: hover a bar cell one pixel below
the screen's top edge, inside its leading gutter, and both the fill and a
click have to land.

### 1.2 Border specs

A border is a small object, not a scalar width:

```
{ color: <token or hex>, widths: { top, right, bottom, left }, gradient: { colors: [...], angle, enabled } }
```

- **Per-side widths** let a cell drop its shared edge (e.g. a menu row only
  draws its *bottom* rule, relying on the next row's top edge being the
  same line, so adjacent rows never double a rule).
- **Gradient** is a solid color by default (`enabled: false`); a two-stop
  45°-style gradient is available for a surface that wants a directional
  border (e.g. an "active window border" token shared with the compositor's
  own border) but is off unless a theme opts in — FormalShell ships flat
  borders everywhere today.
- A renderer picks the cheap flat-`Rectangle`-with-border path when
  `gradient.enabled` is false and all four widths match; it falls back to a
  shape/overlay path only when a spec actually needs per-side or gradient
  rendering. This keeps the common case (a uniform hairline rule) cheap.

### 1.3 Scale roots

Two numbers set the whole shell's size:

- **`fontBaseSize`** (default **13**, matching the shell's current body
  size) is the rem root. `fontScale = fontBaseSize / 13`. Every font token
  is `fontBaseSize × multiplier`, rounded:

  | token | multiplier | px @ base 13 |
  | --- | --- | --- |
  | `caption` | 0.833 | 11 |
  | `bodySmall` | 0.917 | 12 |
  | `body` | 1.0 | 13 |
  | `subtitle` | 1.083 | 14 |
  | `title` | 1.167 | 15 |
  | `heading` | 1.333 | 17 |
  | `display` | 2.0 | 26 |
  | `displayLarge` | 2.333 | 30 |

  `family` is always the fontconfig `monospace` alias (never a hardcoded
  family — CLAUDE.md hard rule); `display` is the *same* family, at the
  larger multiplier — FormalShell does not bundle a second display face.

- **`spacingScale`** (default **1.0**, tracking `fontScale` by default so a
  larger base font gets roomier spacing automatically) multiplies a shared
  spacing set:

  | token | base px | semantic token | base px |
  | --- | --- | --- | --- |
  | `xxs` | 2 | `controlGap` | 8 |
  | `xs` | 3 | `controlPaddingX` | 8 |
  | `sm` | 4 | `controlPaddingY` | 4 |
  | `md` | 6 | `inputPaddingY` | 7 |
  | `lg` | 8 | `controlHeight` | 28 |
  | `xl` | 10 | `popupRowHeight` | 28 |
  | `xxl` | 12 | `rowGap` | 8 |
  | `xxxl` | 14 | `rowPaddingX` | 12 |
  | `huge` | 18 | `labelGap` | 4 |
  | | | `panelGap` (card-to-bar margin) | 14 |
  | | | `panelPadding` (card internal padding) | 18 |
  | | | `popupPadding` | 14 |
  | | | `popupWidthNarrow` | 280 |
  | | | `popupWidthDefault` | 320 |
  | | | `popupWidthWide` | 400 |
  | | | `popupWidthMenu` | 560 |
  | | | `popupWidthMenuSplit` | 840 |

  Both scales can be overridden as a whole (one number denser/roomier) or
  per-token (a theme pins `display` to something huge for the lock clock
  without moving `body`). `controlPaddingX`/`controlPaddingY` match
  `lg`/`sm` exactly (2026-08-07 spacing-consistency pass, Task 6) — Cell.qml,
  the one shared row primitive, resolves its own padding through these
  rather than the bare scale steps, so the two numbers can't drift apart
  independently again. `popupWidth{Narrow,Default,Wide,Menu,MenuSplit}` are
  the five steps every floating card's width snaps to (menu at 560 is its
  own step; everything from a small popout to the picker snaps to
  narrow/default/wide) instead of each surface picking its own literal.
  `MenuSplit` (840, 1.5x `Menu`) is the menu's own further step, for the
  clipboard/share-history route's 50/50 list-plus-preview split (§3 Menu).

  **A panel that does not name its width is a defect (2026-08-17).** Every
  `Panel` sets `panelWidth` explicitly from the four steps above; silence
  defaulting to `popupWidthDefault` is not a decision, it is the widest and
  the densest surface in the shell landing on the same width by accident.
  Checkable: `grep` `shell/Surfaces/Panels/` for `panelWidth` and every file
  declaring a `Panel` root has one.

  **Card-gutter split (2026-08-07, Task 6):** `popupPadding` (14) insets a
  *summoned list surface* — the menu, the notification center; `panelPadding`
  (18) insets a *bar-anchored panel* — every widget popout (audio, network,
  bluetooth, power, calendar, weather, media, github, usage) and the picker,
  which reuses the panel frame. Both apply on all four sides of the card's
  content, via the same technique: the frame draws an explicit border ring,
  content insets by `border width + the surface's own padding token`, and an
  eraser rectangle papers over the row content's own trailing hairline
  (Cell's shared-rule contract) so only the frame's outer rule shows —
  established by Panel.qml, mirrored by Menu.qml and (since this pass)
  Center.qml.

Spacing discipline (2026-08-07): every gap, padding, margin, and row
height in shell QML resolves through `Theme.space`/`Theme.fontSize`
tokens — a raw pixel literal for any of these is a defect, with the
only exceptions being genuinely structural sizes a surface's own brief
names (the lock field's 381×67, the notification image's 40×40 slot, the
media panel's 96×96 album-art slot, screen-relative anchors). Sibling
surfaces use the *same* token for the same structural element: one
`trackThickness` for every flat track, one `popupRowHeight` for every
ledger row, one `panelPadding` for every card. A gap between groups is at
least twice the gap within a group, or the grouping reads as noise.
Checkable: `grep` for numeric margin/padding/spacing literals, and diff
any two sibling surfaces' row/padding tokens.

### 1.4 Ink hierarchy

On any surface, loudness is strictly ordered, and every element belongs
to exactly one band:

| band | role | carries |
| --- | --- | --- |
| 1 (loudest) | `foreground` | content: values, titles, body text, glyphs |
| 2 | `foregroundDim` | meta: uppercase section headers, timestamps, captions (§2.3) |
| 3 | `foregroundFaint` | faint: disabled states, field placeholders, dither texture, the dog-ear fold mark (§2 item 7) |
| 4 (quietest) | `rule` | structure: hairline rules, control borders, card borders |

`accent`/`urgent`/`warning` sit outside the ramp: they are the loud
exceptions (§2.4), spent only where a state genuinely demands one, and
always as full-bleed fills or inversions carrying their `on*` ink —
never as tints. One exception: a bare label with no cell chrome of its
own (§1.1's ink-promotion controls) may rest at `accent` ink while its
own state is armed or current, or when it names a live destination the
way mek spends its blue on underlined link text far more often than on
selection (137 uses, mostly links). The notification center's DND toggle
is the shipped case: armed, its resting ink is `accent` with no fill
behind it. The ban stands on an accent-tinted fill, never on a bare
label's own resting ink. Checkable: sample any border or rule in a
screenshot, it equals the `rule` hex; sample any meta label, it equals
`foregroundDim`, or `accent` if it is one of these armed/current/link
labels, and never sits on a fill of its own; sample a text field's
placeholder, it equals `foregroundFaint` while the field's own label one
band above equals `foregroundDim`; nothing structural samples as a
foreground alpha blend.

### 1.5 Palette roles

The twelve color roles, how matugen populates them
(`shell/Theme/templates/theme.json.tmpl`), and the static Flexoki
fallback (`shell/Theme/palette.js`):

| role | meaning | matugen source | Flexoki dark | Flexoki light |
| --- | --- | --- | --- | --- |
| `background` | canvas | `surface` | `#100F0F` | `#FFFCF0` |
| `backgroundAlt` | card/panel surface step | `surface_container` | `#1C1B1A` | `#F2F0E5` |
| `foreground` | content ink | `on_surface` | `#CECDC3` | `#100F0F` |
| `foregroundDim` | meta ink | `on_surface_variant` | `#878580` | `#6F6E69` |
| `foregroundFaint` | faint/disabled/ornament | `outline` | `#575653` | `#9F9D96` |
| `rule` | rules + borders | `outline_variant` | `#403E3C` | `#CECDC3` |
| `accent` | the one loud color | `primary` | `#4385BE` | `#205EA6` |
| `onAccent` | ink on accent fills | `on_primary` | `#100F0F` | `#FFFCF0` |
| `urgent` | critical/error | `error` | `#D14D41` | `#AF3029` |
| `onUrgent` | ink on urgent fills | `on_error` | `#100F0F` | `#FFFCF0` |
| `warning` | degraded/low, second loud color | `tertiary` | `#DA702C` | `#BC5215` |
| `onWarning` | ink on warning fills | `on_tertiary` | `#100F0F` | `#FFFCF0` |

Fallback hexes are kepano/flexoki scale steps (dark faint = base 700,
light faint = base 400, warning = orange 400/600); dark `on*` inks are
ink-on-color (Material's own dark-scheme convention, and the higher
measured contrast — see the 2026-08-07 revision block). The previously
shipped mapping sent both `foregroundDim` and `rule` to matugen's
`outline`, which flattened the ramp on every wallpaper theme; the
re-spread above is what keeps §1.4 true under matugen. theme.json is
the whole contract: pywal or any other engine themes the shell by
rendering these same twelve keys (a documented pywal template ships in
`shell/Theme/templates/`), and `palette.js`'s per-key merge keeps any
pre-expansion theme.json valid by filling missing roles from Flexoki.

## 2. What "classic ASCII OS" means, concretely

Every rule below is checkable from a screenshot or a `grep` — not a mood
adjective:

1. **Box-drawing / ruled structure inside tabular content.** Any surface
   whose content is genuinely a list of like rows (menu items, a panel's
   device list, notification-center entries, the picker grid) draws its
   rows/cells sharing one border between neighbors — never a double rule,
   never a whitespace-only gap standing in for a divider. Checkable: sample
   two adjacent rows in a screenshot; the border between them is a single
   line, not two, not blank space.
2. **Selection = inversion, on tabular content only.** The cursor row in
   the menu, the current cell in the picker grid, and a highlighted
   notification-center row invert to the accent pair (`bg: accent`,
   `fg: onAccent`; the urgent pair on urgent-carrying rows) instead of
   using the fill-alpha `selected` state. Checkable: the selected row's
   fill samples as the `accent` hex and its text as `onAccent`, not a
   tinted fill and not a foreground/background photo negative.
3. **Uppercase, letter-spaced meta rows.** Any small caption-sized label
   that names *what a piece of content is* rather than being the content
   itself (a bar widget's tiny corner tag, a panel section header, a
   notification's app-name-plus-timestamp row, breadcrumbs) renders
   uppercase with added letter-spacing at `Theme.font.caption`, dimmed via
   `foregroundDim`. Checkable: `text.toUpperCase()` (or equivalent) appears
   in the component, and `font.letterSpacing` is nonzero on that `Text`.
4. **Accent as a full-bleed cell, not a tint.** Where a cell needs to read
   as "urgent" or "the active thing" at a glance (critical notification,
   focused workspace, an armed toggle) the *entire* cell fills with
   `accent`/`urgent`/`warning` and swaps to the matching `onAccent`/
   `onUrgent`/`onWarning` ink — never a colored border around an
   otherwise normal fill, never a soft accent-tinted wash. Checkable:
   sample the cell's fill color in a screenshot; it equals the
   accent/urgent/warning token, not a low-alpha blend of it.
5. **Terminal-grid feel in type.** Numeric displays that must not jitter
   (clock, countdown, battery percentage, life-progress percentage) use
   `font.family` monospace with tabular-width digits (true for any
   monospace font by construction) — never a proportional fallback.
6. **ASCII ornament stays confined to named accent surfaces.** Ledger-style
   headers and box-drawing interior structure are permitted on the menu,
   panel-internal lists, the picker grid, and the screensaver's banner —
   never invented as decoration on a card's *outer* chrome (that chrome is
   omarchy's plain bordered rectangle per §3), with item 7's dog-ear fold
   mark as the single sanctioned exception.
7. **Dog-ear fold mark on floating-card chrome (2026-08-09, replacing the
   corner squares of 2026-08-07).** Every floating card (menu, panels,
   notification toasts and center, OSD, picker) draws one small right
   triangle at its top-left border corner: legs `Theme.space.lg` long
   (8px at scale 1.0) running along the top and left border edges, filled
   `foregroundFaint`, sitting on the border ring. The other three corners
   are plain border. This is the live site's card idiom as of the
   2026-08-09 study; the four 6px corner squares the previous revision
   read off the shipped CSS no longer exist anywhere in mek.gallery's DOM,
   so they are retired here too. mek draws its fold in the hairline ink,
   ours sits one band louder in `foregroundFaint`, the band §1.4 reserves
   for ornament. One shared component draws it; no surface hand-places its
   own. Checkable: a card's top-left corner samples as `foregroundFaint`
   and its other three corners sample as `rule`, and exactly one QML
   component contains the triangle geometry.
8. **Ordered dither is the period texture (2026-08-07).** Where a fill
   needs to read as "partial" or "pending" (the unfilled remainder of a
   track, a pending/expired notification row's backdrop, a disabled
   toggle's field), a 2×2 ordered-dither checker of `foregroundFaint` on
   transparent replaces the low-alpha tint — the 1-bit Macintosh/Amiga
   texture, flat and still, radius 0, no blur. Scanline, CRT-curvature,
   and phosphor-glow effects stay banned everywhere; they are costume,
   not structure. Checkable: zoom any track remainder in a screenshot
   and individual dither pixels resolve; no surface samples as a smooth
   low-alpha gray wash where a dither is mandated.
9. **Card title-bar band (2026-08-09).** Every floating card opens with a
   one-row band above its content: an uppercase meta label with the
   trailing colon of item 10 at the left in `foregroundDim`, an optional
   right side carrying meta text or bare-label actions, and one shared
   rule under the whole band (the band draws its own bottom rule; the
   frame's content erasers of §1.3 are unchanged). Right-side actions rest
   in `foregroundDim` and promote to `foreground` on hover per §1.1's
   ink-promotion amendment, never a cell fill. mek's own modal is the
   reference: `ANNOUNCEMENT` at the left, `CLOSE X` at the right, one 1px
   rule under both. The menu's breadcrumb row and the panels' title row
   are this band. Checkable: a card's first row is the shared band
   component, its label ends in `:`, and there is exactly one rule between
   the band and the content below it.
10. **Trailing colon on headers, ` / ` on meta pairs (2026-08-09).** A
    label that introduces the content under it ends in a colon: the card
    title band (`NOTIFICATIONS:`), a panel section header (`OUTPUT:`,
    `PAIRED DEVICES:`), the menu breadcrumb. The live site does this
    without exception (`DROP A MESSAGE:`, `DEV WORKS & PROJECTS:`, and the
    nav's running page title `ABOUT MEK.TXT:`). A meta row that *is* the
    content takes no colon, and neither does an empty state:
    `PENDING / 2`, `APP NAME / 2M AGO`, `NO NOTIFICATIONS`. Fields inside
    one meta row fuse with a spaced slash, never a bullet, pipe, or dash,
    matching mek's `Jul 2026 / DEV` and `SANROK Studio / Exhibition &
    Media / OBJKT`. The colon is appended when the label renders and is
    never written into an externally sourced string. Checkable: `grep` a
    meta label that has rows under it and it sets the colon flag; `grep` a
    meta pair and its separator is `" / "`.
11. **The ink button (2026-08-09).** A cell whose action commits something
    (a notification's action row, an authentication dialog's confirm)
    rests as a full-bleed `foreground` fill carrying `background` ink:
    borderless, radius 0, no tint, sitting between `warning` and
    `selected` in §1.1's fill priority. Hover and press stay the
    accent-pair inversion every other cell uses, so the ink fill reads as
    "this is the committing control", never as "this row is chosen". It is
    not a revival of the photo-negative *selection* the 2026-08-07
    revision retired: that was a state a row entered, this is how one
    control looks at rest. `accent` still means selected/current and
    `urgent` still means critical. A loud color is never a button fill:
    mek spends its blue on links and selection only, and the shell spends
    `accent` on selection and current-state only. Checkable: sample a
    committing cell's resting fill, it equals the `foreground` hex and its
    text equals `background`; sample it hovered, it equals `accent` with
    `onAccent` text.
12. **Content imagery keeps a color dither; the tray is true color
    (2026-08-09, content color amended 2026-08-09, tray reverted
    2026-08-09, chunky palette 2026-08-09, image-derived palette
    2026-08-12).** Named content imagery, album covers and animated art and
    the wallpaper, renders through `DitherImage`'s ordered-Bayer Canvas pass
    instead of a plain `Image`, in `mode: "retro"`, and keeps its own
    colors. The pass runs on a `width/chunk x height/chunk` grid (`chunk` 2
    by default) rather than one pass per source pixel, and each grid cell
    paints as one `chunk`-sized hard-edged square: at a 96px slot, 1px
    dither cells read as texture, not as an era, so the named default is
    the coarser grid, not the finer one (owner, live shell, 2026-08-09:
    "the album cover is dithered like i asked, but the colors dont change,
    it doesnt become 90s image style"). Content imagery is deliberately
    exempt from matugen retheming, on purpose: a photo doesn't retheme
    either, and forcing an album cover into the two chrome ink roles would
    erase the reason for showing a color image at all.

    **The palette is derived from the image, not from a fixed grid of steps
    (2026-08-12).** Owner, live shell: "the dithering looks cool for the
    wallpaper, but its too intense and it adds dots to monotone wallpapers
    ... I want the dithering engine to make images look like 90s
    wallpapers/ascii pixelart", with a limited-palette pixel-art night scene
    as the reference. Both halves of that report follow from what the pass
    used to do — posterize each RGB channel onto `levels` evenly-spaced
    steps (3, so 0/128/255) and Bayer-bias a channel across a step
    boundary:

    - A flat region sitting anywhere near a step boundary dithered forever,
      up to a 50/50 checker, because the boundary belonged to the grid and
      not to the image. A monotone wallpaper is one such region the size of
      the screen.
    - The two colors being mixed were a full step apart, 128 per channel,
      so every dot was maximum contrast.

    So `shell/Components/dither.js` derives up to `paletteSize` colors (6 by
    default) from the image itself by **median cut**, and each cell takes its
    nearest entry, ordered-dithered against only its second nearest, in
    proportion to how far between the two it actually sits. A solid source's
    own color is its whole palette, so it paints perfectly flat; everything
    else mixes neighbors the image itself put next to each other, so dense
    regions read as shading rather than as noise. Hue survives more strongly
    than under per-channel posterizing, because every entry is an average of
    the source's own colors and nothing is forced onto an axis. `paletteSize`
    is also the intensity knob: more colors means less quantization error,
    so less of the image patterns at all. Runs of same-index cells paint as
    one `fillRect`, which is what keeps a full-screen pass affordable now
    that flat regions genuinely stay flat.

    The dither is display-side only. Nothing derived here is ever written to
    disk, and matugen reads the untouched wallpaper FILE
    (`ThemeEngine.qml`), so a dithered rendering cannot seed the color
    scheme — a blue wallpaper cannot become an orange scheme by way of its
    dots.

    **The wallpaper is one of the content surfaces (2026-08-12).** Owner:
    "it would be cool for the rendered wallpaper to also be dithered, as an
    optional but on by default thing ... similar to album covers." Same
    retro pass, on by default, off with `wallpaper.dither: false` in
    settings.json, palette size overridable with
    `wallpaper.ditherColors`, and it is content in exactly the sense above:
    exempt from matugen retheming, keeping the photograph's own hues while
    the chrome over it recolors from that same photograph.

    Its grid is sized in **screen** pixels, not source pixels: the cell is
    the screen's long edge over 480, floored at 2px, so the texture is a
    property of the display rather than of whichever file is loaded. Two
    wallpapers of wildly different pixel dimensions dither identically on
    the same screen, a 4K display gets larger cells rather than four times
    as many of them (a finer grid at a higher resolution would read as
    noise, and cost four times the paint), and the source is cover-cropped
    to the screen before the pass runs — nearest-neighbor, so the scale
    never hands the quantizer a color the file didn't contain — so cells
    stay square whatever the file's aspect ratio. Both crossfade layers
    dither, and the fade waits on the incoming layer's canvas rather than on
    its decode, so a wallpaper change never shows an undithered frame or a
    blank one.

    Checkable, and the two halves need two samples: `dev/smoke-niri.sh
    --wallpaper` screenshots a SOLID wallpaper before the crossfade and a
    64x64 patch of it must be that exact color end to end (a monotone source
    keeps no dots at all), then crossfades to a GRADIENT and a full-width
    strip of the result must carry at least three colors and no more than
    `wallpaper.ditherColors` of them (it quantized, and it dithered).

    Three named content surfaces before it: the media panel's album art, both
    the static cover and the Apple Music animated cover (sampled off its
    decoded video at ~8fps and re-dithered per frame, the resulting choppy
    cadence is the aesthetic, not a defect, and stops the moment
    `motion.enabled: false`, playback pauses, or the frame errors, falling
    back to the static dithered art); and the bar's now-playing cell's mini
    cover (M20 Task 4b/5b, §3 Bar), static only, no bar-scale animated
    decode. The mini cover keeps its colors even on a hovered (inverted)
    cell, content ruling winning over the cell's own hover inversion, the
    same precedent the menu's app icons already set. The bar visualizer's
    per-bar fill colors (§4 item 8) are chrome inks, not content: they
    read the level bands, and swap on hover like every other ink on that
    cell. A cover-derived palette shipped here briefly and the owner
    rejected it 2026-08-10 ("the album cover's colors are ugly"). Nothing
    else auto-dithers:
    notification images, menu thumbnails, launcher icons, and the
    wallpaper picker's grid all stay true-color — the picker in particular
    shows candidates as they are, since the point of that grid is choosing
    a photograph, not previewing the texture it will be shown through. The
    lock screen's blurred wallpaper backdrop stays undithered for the same
    reason a blur and a dither cancel each other out. Checkable: zoom the media
    panel's album art in a screenshot, individual chunk-sized dither cells
    resolve as flat squares, and every sampled cell's channels each land
    on one of the posterized steps of the source image's own color, never
    `Theme.color.background` or `Theme.color.foreground`.

    The tray icons are out of the dither list. M20 Task 5 shipped a
    `mode: "mask"` 1-bit silhouette treatment here, thresholding an icon's
    own alpha channel instead of luminance so a painted pixel became
    `Theme.color.foreground` (or the cell's inverted ink on a hovered
    cell) regardless of the vendor's own colors: the sanctioned answer at
    the time to third-party SNI icons that render as white or light
    symbolic marks meant for a dark bar and disappear against a light
    one. The owner ran it against real vendor icons in a live session and
    rejected it as "deep fried" (2026-08-09); tray icons render as a
    plain true-color `IconImage` again. The square slot sizing stays:
    every tray icon still pins into one slot sized by the shared
    body-text token, so the SNI protocol's arbitrary 16/22/24px pixmaps
    don't vary the cell's padding rhythm. Open problem: the light-mode
    invisibility the mask treatment was meant to fix is back, with no
    shipped answer, treatment TBD with the owner. Checkable: zoom a tray
    icon in a screenshot, pixels carry the vendor's own colors, never a
    flattened `Theme.color.foreground` silhouette.
13. **The panel hero (2026-08-17).** Every panel opens with one shared block
    (`Components/PanelHero.qml`): a leading glyph in a fixed-width slot so a
    wider Nerd Font codepoint never shifts the title next to it, the panel's
    noun in sentence case (content ink, not a meta label), an uppercase
    state line through `MetaLabel`, and — only when the panel's whole point
    is a number — that number promoted out of the type scale entirely, to
    `display` (26px) or `displayLarge` (30px) rather than `body`. A panel
    whose point is not a number (a device list, a picker) carries no
    oversized readout at all; inventing one where the content is a list, not
    a figure, is a defect. An optional full-width `rail` reads a 0..1
    progress as a flat `accent` fill over the `DitherFill` remainder, the
    same read-only track idiom every other slider in the shell already
    uses, no knob. The block draws only Cell's own shared-rule bottom/right
    border, never a second box of its own. Checkable: a panel whose brief
    names one number as its subject (battery charge, current temperature,
    today's date) renders that number at `display`/`displayLarge`, never
    `body`; every other row on the same card stays at `body` or `caption`.
    Dated exception (owner, 2026-08-18): the media panel does not open with
    this shared hero when art exists — the panel's whole point is the
    artwork, so its opening block is the art+identity row at the dedicated
    96x96 slot (§1.3's structural-size exception), the analogue of a number
    panel's oversized readout. The hero-slot cover (`leading` at
    `Theme.space.xxl * 2` = 24px) shipped 2026-08-17 and read as a downgrade
    from the dedicated slot; the panel falls back to the ordinary hero
    (note glyph, title, meta) only in the no-art case, so no player ever
    gets a 96px blank.
14. **Section rhythm is the fused rule, not a gap (2026-08-17).** A section
    header (an uppercase `MetaLabel` cell) transitions into its first row,
    and a section's last row into the next header, exactly like any two
    adjacent rows: `Panel.qml`'s `contentColumn` carries zero spacing of its
    own, and every row's breathing room comes from the one token `Cell`
    already resolves its padding through, `controlPaddingY` (§1.3) — a
    header cell and a content cell are the same primitive at the same
    padding, so no panel can drift its own rhythm by hand. No panel spaces a
    header away from its first row with an extra `Item`, a `Column`
    `spacing`, or a margin; the shared hairline between them (item 1) is the
    only divider. Checkable: `contentColumn`'s own `Column` carries no
    `spacing` property, and no panel file under `shell/Surfaces/Panels/`
    declares a bare spacer `Item` between two content `Cell`s.

**Where the two references conflict, omarchy's structural chrome wins**:
the outer shape of a floating surface (card with margin, single border,
internal padding, radius 0) is always omarchy's, never mek.gallery's fused
edge-to-edge grid. The ASCII-OS accent governs *what's drawn inside* a
surface once it's already a table of rows, never whether the surface itself
floats with a margin or fuses to the screen edge.

## 3. Concrete translations

- **Bar** — a single-row strip of **discrete widget cells**, each its own
  `normal`/`hover-cursor`/`selected` control (§1.1) — `hover-cursor`
  rendered as full accent inversion rather than a tint or border, per §1.1's
  bar-cell amendment above — separated by `Theme.spacing.sm`-ish gaps in
  the omarchy style — not forced edge-to-edge adjacency. The focused
  workspace cell is a full-bleed `accent` fill
  (§2.4); other workspace cells are `normal`. A widget with an open panel
  gets omarchy's small **accent dot** on its inner edge (the edge facing the
  desktop) rather than a border-color change, so "panel open" reads at a
  glance without relayouting the cell. Clock/battery/network cells carry an
  uppercase caption meta tag (`BAT`, `NET`) only where the value alone is
  ambiguous; the widget's primary value is normal-weight, not uppercase. A
  cell whose glyph already carries the value suppresses that label outright
  (M23): weather and audio ship label-off, since the condition glyph and the
  mute/level glyph say exactly what the label would repeat, and the
  suppressed value moves into the cell's own `tooltipText` rather than
  disappearing. Battery keeps its label, since a charge percentage is
  content the glyph only brackets to the nearest 10%.
  `bar.widgets.<name>.showLabel` flips any cell either way per install. The
  clock carries no meta tag at all under the same rule: `19:31` is never
  ambiguous, and as the one two-line cell it was setting the whole bar's
  height to say so. This bar's one Bartender affordance is a widget rather
  than a tray feature (M24): `chevron` is an ordinary `bar.layout` entry, and
  everything placed on its governed side of its own region collapses behind
  it. Its position is the entire configuration, so which cells hide is a
  question of where the boundary sits, not of a per-widget flag, and moving
  it one slot changes the answer. The governed side runs inward, away from the region's
  own anchored edge (M25): the right region is pinned to the screen edge, so
  its chevron collapses what *precedes* it and the group opens into empty
  bar, leaving the chevron and every cell outboard of it at the x they
  already had. The left region mirrors that; `center` is pinned to nothing
  and reflows from both ends whichever way it governs, so it keeps the left
  region's direction. The glyph follows the same rule, always pointing where
  the group moves on the next click. The reveal animates the governed cells'
  width over `Theme.motion.standard` (§4) rather than swapping them in one
  frame, so the group glides rather than snapping. Collapsed is the default,
  persisted per region to `state.json`. One chevron per region, and one with
  nothing on its governed side hides nothing and is dropped rather than
  drawn as a control that answers no click. The tray sits under that rule like any other widget, with no drawer,
  no visible limit and no per-icon buckets of its own: M23 shipped those and
  M24 replaced them, because two chevrons on one bar made the affordance
  ambiguous about what it governed.
  The now-playing cell's mini cover art (M20) is the fourth sanctioned
  image-icon site, after the menu's launcher rows, the bar's active-window
  cell, and notification card images: unlike those three, it renders
  through the retro color dither (§2 item 12) rather than a plain `Image`,
  so it stays inside the dither language while keeping the cover's own
  colors, unaffected by hover inversion or a theme retheme alike. Static
  art only, no bar-scale animated decode: the panel's Apple Music video
  only exists while the panel itself is open, so sharing it at the bar
  would mean a second, permanently-idle Video pipeline for a slot this
  small.
- **Menu** — a floating card (omarchy chrome: bordered rectangle, `panelGap`
  margin, radius 0) whose *content* is the ASCII-OS accent: a full-height
  column of rows sharing one border per pair, cursor row inverted (§2.2),
  search field as the top row, breadcrumb as an uppercase meta row (§2.3),
  and an action bar as the bottom row. Launcher app rows — and the bar's
  active-window cell (M14) — are the sanctioned image-icon exception: the
  desktop entry's icon-theme image renders at the glyph cell's size, radius
  0, no border — like the DMS/omarchy launchers — while every other icon in
  the shell stays a Nerd Font glyph.
  The **action bar** is Raycast's footer read through this language rather
  than copied from it: one ledger cell, the primary verb for the cursor row
  on the left behind a full-bleed accent key cap (§2.4 — the one loud thing
  in the row, because it is the one thing `Enter` will do), the
  always-applicable keys on the right as bordered caps carrying band-2 dim
  ink (§1.4). Key caps are literal characters checked against the pinned
  nerd-fonts cmap, never names: U+23CE ⏎ is present in it, the more obvious
  U+21B5 ↵ is not.
  One level draws as a **grid** instead of rows — the wallpaper/image picker
  (§Concrete translations' "grid of image cells sharing hairline rules") —
  keeping the same card, search field, cursor and action bar. It is a view
  swap over one level, not a second surface: the picker has no window of its
  own. The clipboard and share-history levels draw as a **50/50 split**
  instead, same precedent: a left-half history list beside a right-half
  preview pane holding the cursor row's complete text or image, behind one
  shared vertical rule, on the same card at its own wider `popupWidthMenuSplit`
  step.
- **Panels** (audio/network/bluetooth/power/calendar/weather/media) — each is one
  omarchy-style card anchored under its bar cell (`panelGap` margin,
  bordered, radius 0, `panelPadding` internal padding). Inside: an uppercase
  `PanelSectionHeader`-equivalent caption introduces each group ("OUTPUT
  DEVICE:", "PAIRED DEVICES:", "NOW PLAYING:", colon per §2 item 10), then
  rows share rules in the ASCII-OS table style; sliders (volume,
  brightness) are full-width tracks whose fill level is a flat `accent`
  block — no round thumb, no gradient fill.
- **Notifications** — each popup toast is its own small omarchy card
  (bordered, radius 0); stacked toasts keep omarchy's card-to-card gap, not
  fused adjacency. The notification **center** (the summoned history list)
  is the ASCII-OS table surface: rows share rules, app-name-plus-timestamp
  is an uppercase meta row, a selected/highlighted row inverts. Critical
  severity is a full-bleed `urgent` fill (§2.4) on either surface. Cards
  render the notification's own image, or else the sender's themed app
  icon, in a 40×40 slot, hidden entirely when neither resolves — the
  shell's third sanctioned image-icon exception (M15), after the menu's
  launcher rows and the bar's active-window cell.
- **OSD** — one small omarchy card, three-cell row inside it (icon | label |
  value fill track), fixed widths per the existing M-plan contract.
- **Lock/greeter** — one composed centered block (Task 6's brief), not three
  floating items: a genuinely large `display`/`displayLarge` clock with
  tabular digits sits directly above a **381×67-scaled** (at `fontBaseSize`
  13, scale proportionally) bordered input field with a 3px-equivalent
  outline (`Border` spec, not `Theme.borderWidth`), centered uppercase
  placeholder ("ENTER PASSWORD"), `●` U+25CF masking whose letter-spacing
  **shrinks to fit** so a long password never clips silently, "CHECKING…"
  during auth, an error state that swaps both the message (italic) and the
  border spec to the `urgent` token, and — when the platform exposes a
  fingerprint sensor — a fingerprint glyph pinned inside the field's right
  edge with symmetric horizontal reserve so centered dots stay centered.
  Wake on any click/move/key; Escape or Ctrl+U clears. The blurred wallpaper
  backdrop (`MultiEffect`, blur 1.0 / blurMax 128 / blurMultiplier 1.25 /
  contrast -0.08 — omarchy's exact parameters) remains the shell's one named
  blur exception (CLAUDE.md hard rule). The greeter is the same composed
  block, same component, identical language — no clock-less/field-only
  divergence from the lock screen.
- **Screensaver** — the shell's other named continuous-motion exception
  (§2, item 6): a full-screen block-drawing ASCII banner
  (`FormalShell`, `▄ █ ▀` family, the same weight as omarchy's `logo.txt`)
  is the subject, centered, animated by a selectable effect — any of
  ttfx's 37, or `random`, the default. No cells, no rules, no meta rows on
  this surface; its entire content *is* the motion, and it exits instantly
  (no fade) on real input.

  This is also the one surface whose colors are **not** the shell's
  palette. It runs ttfx (`omacom-io/ttfx`, the engine omarchy's own
  screensaver uses) and paints the truecolor frames ttfx emits, so each
  effect arrives in its own upstream gradient — decrypt amber, matrix
  green, rain blue, slide purple-red-orange. Omarchy passes no gradient
  overrides and neither do we (owner's call, 2026-08-11): a random effect
  per cycle is what makes the color change. Only the background and the
  fallback color for glyphs ttfx leaves uncolored come from the theme. On
  a host with no ttfx on PATH the surface falls back to effect.js's five
  builtin effects, which are accent-colored as before.
- **Picker** — the ASCII-OS table surface applied to a grid instead of a
  column: image cells share hairline rules, current cell inverts (§2.2),
  keyboard-navigable. Omarchy's skewed carousel remains an explicitly later
  flourish (spec §11), not adopted here.
- **Capture picker** — the only surface that is mostly *not* drawn: it
  renders a grim-captured freeze of each output at 1:1 and puts chrome on
  top of it, because that freeze is what the capture itself photographs.
  Chrome is a scrim over everything except the selection (four plain
  rectangles at 0.6 on `background`, never a mask or a shader — §2's no-blur
  rule holds here as everywhere but the lock screen), an `accent` selection
  border at `Theme.borderWidth`, and one standalone readout cell carrying
  `W×H` plus the dim uppercase name of what is selected. A bottom-centered
  standalone cell carries the key legend in the meta-label idiom. All chrome
  drops for one frame before the capture fires, so none of it is baked in.

  **The toolbar** sits along the bottom edge, under the legend: a bordered
  card (`background` fill, `rule` border at `Theme.borderWidth`, radius 0,
  `popupPadding` inset) holding one row of cells. They are the bar's
  `standalone` cells, not the fused ledger — six discrete buttons is exactly
  what that chrome is for, and it brings the bar's own hover inversion
  (§1.1/§3) with it. The current tool is `selected`, so it stays inverted
  under the pointer without a second treatment (§2.4). Two dim uppercase
  `MetaLabel` group headers (`SHOT`, `REC`) separate the two halves in the
  mek meta-row idiom, and the trailing commit button is the ink cell (§2
  item 11) — the one committing action on the surface.

  The record tools swap two things and nothing else: the selection border
  moves from `accent` to `urgent` (the same role the bar's recording
  indicator and the old slurp-driven record selection already carry), and the
  ink cell's glyph and label change. One palette role does the whole job of
  saying "this is about to record", with no second color and no motion.

  The one place a surface differs by backend. A window the compositor
  reports a box for is **highlighted** in place; a window it reports no box
  for is **named** instead, in a centered ledger card of title-over-dim-app-id
  rows with the cursor row inverted (§2.2), and captured by id server-side.
  Both are window selection, so no capability is lost either way. This is
  niri: it fills `tile_pos_in_workspace_view` only for floating windows
  (`src/layout/tile.rs:869` versus `floating.rs:336`), so tiled windows have
  no rectangle to draw. The split is on the rect being null, never on a
  compositor name, so a niri that gains tiled geometry becomes the
  highlight case with nothing here to change.

## 4. Motion

Written to the owner's M13 brief verbatim: "fast and subtle, it should just
look better." Motion is additive polish on top of the flat-and-still
baseline above — it never changes an end state, never causes a layout jump,
and every rule here is checkable:

1. **Two durations, one curve.** `Theme.motion.fast` (100ms) paces hover
   fills; `Theme.motion.standard` (130ms) paces surface enter/exit. Both
   sit inside a hard 90–140ms band — nothing in the shell animates slower
   or faster. The only easing curve is `Theme.motion.easing`
   (`Easing.OutCubic`), used for enter and exit alike.
2. **Opacity plus small translate only.** An entering surface fades from 0
   and slides `Theme.motion.slide` (6px, hard band 4–8px) into its resting
   place — a panel drops down from under the bar, the OSD rises from the
   bottom edge, right-anchored surfaces slide in from the right. Exit is
   the same pair reversed. No scale, no bounce, no blur, no zoom; radius
   stays 0.
3. **Full-bleed accent/selection swaps stay instant.** The ledger
   inversion (menu cursor row, picker cell, center row), the focused
   workspace's accent fill, an armed toggle, a critical cell's urgent fill
   — these are *states*, not transitions (§1.1/§2.2/§2.4), and they snap.
   Only the low-alpha hover fill fades; the moment a cell resolves to
   `selected`/`accent`/`urgent`, the swap is immediate.
4. **Every animation is interruptible.** Transitions are driven by
   `Behavior`s (or a single animated scalar), so reversing a state
   mid-flight reverses the animation from wherever it is — never a queued
   replay, never a blocked input.
5. **`motion.enabled: false`** (settings.json) zeroes both durations —
   every transition collapses to today's instant state swap, pixels
   untouched. This is the shell's reduced-motion switch; Wayland has no
   `prefers-reduced-motion` to inherit.
6. **Sanctioned-instant surfaces.** Lock/greeter enter and exit stay
   deliberately unanimated — a security surface snapping shut/open is
   intentional (CLAUDE.md). The screensaver left this carve-out on
   2026-08-12 (owner: "make the screensaver fade in/out too, currently
   it's instant"), superseding the earlier reading that dismissal had to
   read as regaining control instantly. It now fades **both ways**,
   opacity only (no slide — a full-screen surface has no edge to slide in
   from), at `Theme.motion.reveal` rather than `Theme.motion.standard`:
   the same 400ms band the wallpaper crossfade already uses, because a
   full-screen swap paced at 130ms reads as a flash rather than a fade.
   `motion.enabled: false` zeroes `reveal`, so a reduced-motion session
   keeps the old hard cut in both directions. Checkable: the surface stays
   mapped until its opacity reaches 0 (`Screensaver.qml`'s `visible:
   root.active || content.opacity > 0`, the same hold Panel.qml uses), and
   the animation freezes at the start of the exit fade instead of running
   on behind it.
7. **Marquee-on-overflow** (owner-requested, M16 Task 11) is the fourth
   continuous-motion carve-out, with a real gate — never a decoration
   running for its own sake. The bar's now-playing title scrolls
   (`Theme.motion.marqueePxPerSec`, ~30px/s, no easing, a
   `Theme.motion.marqueeHoldMs` ~2s hold at the loop start) only when the
   title genuinely overflows its cell's cap AND the bar window is actually
   on screen; a title that fits never moves. This sits outside rule 1's
   90–140ms band on purpose (a scrolling title reads better paced in
   seconds, not fractions of one). Unlike the pulse and the screensaver, it
   DOES respect `motion.enabled: false`: a disabled marquee falls back to
   today's plain elide.
8. **The bar's visualizer** (owner-requested: "next to the now playing it
   would be nice to have an ASCII style audio visualizer"; dithered-track
   rendering added 2026-08-09 for consistency with the other fill tracks)
   is the fifth continuous-motion carve-out. Its live frames come from a
   real `cava` child process (`VisualizerService.qml`), not a QML
   animation, so the gate kills the process outright rather than pausing a
   paint: it runs only while `MediaService.isPlaying` AND the bar window
   showing the widget is actually on screen AND `Theme.motionEnabled` —
   any one going false stops the process, zero CPU, same as the marquee
   gate above but enforced on a real OS process instead of a `Behavior`.
   Six per-column dithered tracks (§2 item 8's fill+dither
   idiom) render the live spectrum, a fill rising from each column's bottom
   to its own level. The fill's color is the column's own energy band
   (`Model.levelColorBand`): `dimForeground` below 0.4, `foreground`
   through the middle, `Theme.color.accent` only past a 0.85 peak, so the
   color carries loudness rather than decoration. M20 Task 5b replaced
   these bands with per-bar colors sampled from the playing track's cover
   and the owner rejected that on the live shell 2026-08-10 ("the album
   cover's colors are ugly just keep it like it was before") — the bands
   are the shipped default, and the extraction component is gone. Hover
   inversion wins here, unlike the now-playing cell's own mini cover: dim
   and content collapse to the inverted ink on their own, and a peak bar
   swaps to `onAccent` so it never fights the cell's accent hover fill.
   Like the marquee and rotation,
   this DOES respect `motion.enabled: false`: a disabled-motion session
   renders the same empty tracks (zero fill, pure dither) as the
   not-playing state, never a live spectrum.

The "breathing" opacity pulse stays reserved for genuinely in-progress
states (charging, an active call) at its own 900ms pacing, and the
screensaver plus the lock backdrop blur remain the two named, load-bearing
exceptions to "flat and still" — not a crack in the doctrine, a documented
carve-out each. The wallpaper crossfade (`Background.qml`) is the third:
`Theme.motion.reveal` (400ms, `Easing.InOutQuad`) sits outside rule 1's
90–140ms band on purpose — a full-screen image swap reads better slower
than a control hover — and, unlike the pulse, it does respect
`motion.enabled: false` (zeroed to a hard cut straight onto the new
wallpaper, same as `fast`/`standard`). The now-playing marquee is the
fourth (rule 7 above) — gated subtle by owner request, never running
unwatched or undisableable. The bar's visualizer (rule 8 above) is the
fifth, the only one of the five gated on a real child process rather than
a QML animation.

Do not restyle a surface outside a plan that schedules it (Tasks 2–7 of the
M8b plan schedule every surface named above in turn).
