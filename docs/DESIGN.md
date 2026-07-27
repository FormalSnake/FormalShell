# FormalShell design language

Reference: **https://www.mek.gallery/** (MEK.txt) — the owner's canonical "this is
how the desktop should look" example, recolored by matugen instead of MEK's
paper-white. Screenshot studied 2026-07-27. These rules bind every surface built
from M4 onward and the M9 polish pass retrofits M1–M3 surfaces to them.

## The one idea: a ruled ledger grid

Every FormalShell surface is a **table of cells separated by shared hairline
rules** — not floating cards, not pill buttons, not padded islands.

1. **Cells, not cards.** A surface (bar, menu, panel) is a rectangular grid of
   compartments. Adjacent cells SHARE one border (no double rules, no gaps
   between cells). The outermost edge gets the same rule. Radius 0 everywhere.
2. **Hairline rules.** Dividers are `Theme.borderWidth` (2px logical, may read
   as 1px hairline at scale) in a dedicated `rule` color = foreground at low
   alpha (matugen `outline` role). Rules are the ONLY separation mechanism —
   never whitespace gaps, never background-shade changes alone.
3. **Cell anatomy.** A cell optionally carries a **meta row**: tiny uppercase
   dimmed label in the top-left/top-right corner (`Jul 2026 / DEV` style —
   for us: widget names, dates, states like `BAT / 87%`, `WS / 3`). Content
   sits below/beside at normal size. Meta = `Theme.font.caption`, uppercase,
   `foregroundDim`.
4. **Selection = inversion.** The selected/active cell swaps foreground and
   background (or fills with `accent` and uses the matugen on-accent color).
   Hover = rule brightens + subtle fill (existing `Theme.control("hover")`).
   No glows, no scale animations.
5. **Accent is a block, not a tint.** Like MEK's full-bleed orange/blue panels:
   accent color appears as ENTIRE cells (focused workspace cell, active toggle
   cell, urgent notification cell), rarely as text color, never as soft washes.
6. **Type.** Monospace (fontconfig `monospace` alias) for all content. Labels,
   nav, and meta rows are UPPERCASE with slight letterspacing. An optional
   display face for oversized headers (clock on lock screen, menu title) may
   come later as a theme option (`font.display`), defaulting to the mono —
   MEK uses custom pixel/blackletter faces (GROUT, DINASTI); we do NOT bundle
   those, the slot exists so a user can point one in.
7. **Density.** MEK is information-dense: small paddings (`Theme.spacing.sm`
   inside cells, `md` max), no hero whitespace. A bar cell is exactly
   content + sm padding + rule.
8. **Flat forever.** No shadows, no blur (lock-screen backdrop stays the only
   exception), no gradients in fills (border gradients from the token system
   remain allowed but default off in this language — rules are solid).
9. **Motion.** State changes are instant or near-instant color transitions
   (existing 120–200ms); the only "alive" idiom is the breathing opacity pulse
   for in-progress states. Nothing slides, bounces, or zooms.

## Concrete translations

- **Bar**: a single-row ledger — each widget is a bordered cell butted against
  its neighbor (workspaces = N cells sharing rules, focused one inverted/accent;
  clock cell with `TIME` meta label; battery cell `BAT / 87%`). The bar's
  bottom edge is one rule against the desktop.
- **Menu**: a full-height column of rows, each row a cell (icon cell + label
  cell sharing a rule, MEK nav-tab style); search field is the top cell;
  breadcrumb/title as a meta row. Cursor row inverted.
- **Panels** (audio/network/bt/power/weather): a small table — header meta row,
  then rows per device/network with rules between; sliders are full-width
  cells whose fill level is a flat accent block (no round thumbs).
- **Notifications**: stacked cells sharing rules; app name + timestamp as the
  meta row; critical = accent-filled cell.
- **OSD**: one three-cell row (icon | label | value), fixed widths per M-plan.
- **Lock/greeter**: oversized clock (display slot), single bordered input cell.

## Token additions this implies (for the next theme-touching plan)

- `Theme.color.rule` (matugen `outline` at defined alpha) — dividers.
- `Theme.color.onAccent` (matugen `on_primary`) — text on accent-filled cells.
- `Theme.font.display` (defaults to mono family) + `Theme.label(text)` helper
  convention: uppercase + letterspacing for meta rows.
- Inversion pair helper: `Theme.inverted()` → `{ bg: foreground, fg: background }`.

Do not restyle existing M1–M3 surfaces outside a plan that schedules it.
