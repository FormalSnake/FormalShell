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

## 1. The token system

Every value below is a **default**; nothing here freezes a magic number —
each is reachable through the base-size/scale roots so retheming rescales
the whole shell from two numbers. Task 2 implements this vocabulary in
`shell/Core/Theme.qml`; existing matugen-driven palette roles
(`background`, `backgroundAlt`, `foreground`, `foregroundDim`, `accent`,
`urgent`, `rule`, `onAccent` — `shell/Theme/palette.js`) are the color
tokens the state/border machinery below resolves against. Matugen wiring,
`theme.json`, and the Flexoki fallback are unchanged by this document —
only what a theme's colors get *rendered into* changes.

### 1.1 Four interactive states

Every control (bar cell, menu row, panel button, toggle, slider, text
field) is in exactly one of four states at any moment:

| state | meaning | default color token |
| --- | --- | --- |
| `normal` | idle chrome | `foreground` |
| `hover-cursor` | mouse hover **or** panel keyboard cursor row (unified — a panel's own arrow-key cursor reads identically to a real mouse hover) | `foreground` |
| `selected` | persistent chosen/current (the enabled toggle, the current workspace, the checked radio) | `foreground` |
| `focus` | real Qt `activeFocus`; defaults to mirroring `hover-cursor` so Tab-focus and mouse-hover read identically | inherits `hover-cursor` |

Each state carries a **fill alpha** and a **border alpha**, applied
independently against the state's resolved color (a palette role —
`foreground` / `accent` / `urgent` / `background` — or a raw hex from a
theme override):

| state | fill alpha | border width | border alpha |
| --- | --- | --- | --- |
| `normal` | 0.04 | 2 | 0.4 |
| `hover-cursor` | 0.08 | 2 | 0.25 |
| `selected` | 0.18 | 0 | 1.0 |
| `focus` | = hover-cursor | = hover-cursor | = hover-cursor |
| `pressed` (mouse-down only, not a persistent state) | 0.22 | — | — |

Border width defaults to **2** — the spec's non-negotiable brutalist
baseline (`docs/superpowers/specs/2026-07-27-formalshell-design.md`,
CLAUDE.md's hard rules) — not omarchy's own 1px default; every other number
in this table (alphas, the state vocabulary itself, the per-side/gradient
spec shape) carries over from omarchy as-is. A state's border width of `0`
drops that border entirely — `selected` is borderless by default (the fill
alone reads as chosen), while a text field or a bar cell that wants a
visible ring uses the 2px default. Paint priority when more than one
applies: `pressed` > `focus` (only when the control is real-focusable) >
`hover-cursor` > `selected` > `normal`.

Where the ASCII-OS accent overrides this for a genuinely tabular surface
(menu cursor row, picker grid, notification-center row — see §2), fg/bg
**inversion** replaces the fill-tint for the *selected*/cursor state only:
`{ bg: foreground, fg: background }` (or `{ bg: accent, fg: onAccent }` for
an urgent/accent-carrying row). Inversion and the fill-alpha model are
never both active on the same cell.

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
  | `xs` | 3 | `controlPaddingX` | 10 |
  | `sm` | 4 | `controlPaddingY` | 6 |
  | `md` | 6 | `inputPaddingY` | 7 |
  | `lg` | 8 | `controlHeight` | 28 |
  | `xl` | 10 | `popupRowHeight` | 28 |
  | `xxl` | 12 | `rowGap` | 8 |
  | `xxxl` | 14 | `rowPaddingX` | 12 |
  | `huge` | 18 | `labelGap` | 4 |
  | | | `panelGap` (card-to-bar margin) | 14 |
  | | | `panelPadding` (card internal padding) | 18 |
  | | | `popupPadding` | 14 |

  Both scales can be overridden as a whole (one number denser/roomier) or
  per-token (a theme pins `display` to something huge for the lock clock
  without moving `body`).

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
   notification-center row swap foreground/background instead of using the
   fill-alpha `selected` state. Checkable: the selected row's text color and
   fill color are swapped foreground/background hex values, not a tinted
   fill.
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
   `accent`/`urgent` and swaps to `onAccent` text — never a colored border
   around an otherwise normal fill, never a soft accent-tinted wash.
   Checkable: sample the cell's fill color in a screenshot; it equals the
   accent/urgent token, not a low-alpha blend of it.
5. **Terminal-grid feel in type.** Numeric displays that must not jitter
   (clock, countdown, battery percentage, life-progress percentage) use
   `font.family` monospace with tabular-width digits (true for any
   monospace font by construction) — never a proportional fallback.
6. **ASCII ornament stays confined to named accent surfaces.** Box-drawing
   corner marks or ledger-style headers are permitted on the menu,
   panel-internal lists, the picker grid, and the screensaver's banner —
   never invented as decoration on a card's *outer* chrome (that chrome is
   omarchy's plain bordered rectangle per §3).

**Where the two references conflict, omarchy's structural chrome wins**:
the outer shape of a floating surface (card with margin, single border,
internal padding, radius 0) is always omarchy's, never mek.gallery's fused
edge-to-edge grid. The ASCII-OS accent governs *what's drawn inside* a
surface once it's already a table of rows, never whether the surface itself
floats with a margin or fuses to the screen edge.

## 3. Concrete translations

- **Bar** — a single-row strip of **discrete widget cells**, each its own
  `normal`/`hover-cursor`/`selected` control (§1.1), separated by
  `Theme.spacing.sm`-ish gaps in the omarchy style — not forced edge-to-edge
  adjacency. The focused workspace cell is a full-bleed `accent` fill
  (§2.4); other workspace cells are `normal`. A widget with an open panel
  gets omarchy's small **accent dot** on its inner edge (the edge facing the
  desktop) rather than a border-color change, so "panel open" reads at a
  glance without relayouting the cell. Clock/battery/network cells carry an
  uppercase caption meta tag (`BAT`, `NET`) only where the value alone is
  ambiguous; the widget's primary value is normal-weight, not uppercase.
- **Menu** — a floating card (omarchy chrome: bordered rectangle, `panelGap`
  margin, radius 0) whose *content* is the ASCII-OS accent: a full-height
  column of rows sharing one border per pair, cursor row inverted (§2.2),
  search field as the top row, breadcrumb as an uppercase meta row (§2.3).
  Launcher app rows — and the bar's active-window cell (M14) — are the
  sanctioned image-icon exception: the desktop entry's icon-theme image
  renders at the glyph cell's size, radius 0, no border — like the
  DMS/omarchy launchers — while every other icon in the shell stays a Nerd
  Font glyph.
- **Panels** (audio/network/bluetooth/power/calendar/weather/media) — each is one
  omarchy-style card anchored under its bar cell (`panelGap` margin,
  bordered, radius 0, `panelPadding` internal padding). Inside: an uppercase
  `PanelSectionHeader`-equivalent caption introduces each group ("OUTPUT
  DEVICE", "PAIRED DEVICES", "NOW PLAYING"), then rows share rules in the
  ASCII-OS table style; sliders (volume, brightness) are full-width tracks
  whose fill level is a flat `accent` block — no round thumb, no gradient
  fill.
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
  is the subject, centered, animated by a selectable effect (`decrypt`,
  `rain`, `expand`, `slide`, `scatter`, or `random` — the default). No
  cells, no rules, no meta rows on this surface; its entire content *is*
  the motion, and it exits instantly (no fade) on real input.
- **Picker** — the ASCII-OS table surface applied to a grid instead of a
  column: image cells share hairline rules, current cell inverts (§2.2),
  keyboard-navigable. Omarchy's skewed carousel remains an explicitly later
  flourish (spec §11), not adopted here.

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
6. **Sanctioned-instant surfaces.** Lock/greeter enter and exit, and the
   screensaver's own exit, stay deliberately unanimated — a security
   surface snapping shut/open is intentional (CLAUDE.md), and dismissing
   the screensaver must read as regaining control immediately, not
   waiting out a fade. The screensaver's *entrance* is the one exception
   inside this carve-out that does fade, opacity only at
   `Theme.motion.standard` (no slide — a full-screen surface has no edge
   to slide in from).
7. **Marquee-on-overflow and status rotation** (owner-requested, M16 Task
   11) are the fourth and fifth continuous-motion carve-outs, each with a
   real gate — never a decoration running for its own sake. The bar's
   now-playing title scrolls (`Theme.motion.marqueePxPerSec`, ~30px/s, no
   easing, a `Theme.motion.marqueeHoldMs` ~2s hold at the loop start) only
   when the title genuinely overflows its cell's cap AND the bar window is
   actually on screen; a title that fits never moves. The power panel's
   charging/discharging status line cycles its real phrase set (state,
   time-to-full/empty, charge rate) every `Theme.motion.rotatePeriod`
   (~3s), fading at `Theme.motion.standard`, only while the panel is open
   and more than one phrase is real — a single-phrase set stays put. Both
   sit outside rule 1's 90–140ms band on purpose (a scrolling title or a
   phrase change reads better paced in seconds, not fractions of one) —
   only the rotation's own fade transition uses `Theme.motion.standard`.
   Unlike the pulse and the screensaver, both DO respect
   `motion.enabled: false`: a disabled marquee falls back to today's plain
   elide, and disabled rotation just stops advancing past the primary
   phrase.

The "breathing" opacity pulse stays reserved for genuinely in-progress
states (charging, an active call) at its own 900ms pacing, and the
screensaver plus the lock backdrop blur remain the two named, load-bearing
exceptions to "flat and still" — not a crack in the doctrine, a documented
carve-out each. The wallpaper crossfade (`Background.qml`) is the third:
`Theme.motion.reveal` (400ms, `Easing.InOutQuad`) sits outside rule 1's
90–140ms band on purpose — a full-screen image swap reads better slower
than a control hover — and, unlike the pulse, it does respect
`motion.enabled: false` (zeroed to a hard cut straight onto the new
wallpaper, same as `fast`/`standard`). The now-playing marquee and the
power panel's status rotation are the fourth and fifth (rule 7 above) —
gated subtle by owner request, never running unwatched or undisableable.

Do not restyle a surface outside a plan that schedules it (Tasks 2–7 of the
M8b plan schedule every surface named above in turn).
