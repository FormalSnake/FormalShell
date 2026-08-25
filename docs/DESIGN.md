# FormalShell design language

The shell is Omarchy quattro's set of surfaces and habits, drawn as shadcn/ui
in its dark and light themes, with the wallpaper filling the palette through
matugen. The full token tables and the reasoning are in
`docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`; that spec
wins if this file disagrees with it. This file is the working rulebook: what
to reach for when building or restyling a surface.

## 1. Tokens

Every value below is a `Theme` property. A surface never writes a literal
colour, radius, size or duration.

**Color** (`Theme.color.*`): `background`, `foreground`, `card`,
`cardForeground`, `popover`, `popoverForeground`, `primary`,
`primaryForeground`, `secondary`, `secondaryForeground`, `muted`,
`mutedForeground`, `accent`, `accentForeground`, `destructive`,
`destructiveForeground`, `warning`, `warningForeground`, `border`, `input`,
`ring`, `chart1`..`chart5`. matugen fills them from the wallpaper; the
fallback is shadcn's zinc palette. The wallpaper colour is `primary`.
`accent` is a neutral hover fill, never the wallpaper colour.

**Radius** (`Theme.radius*`): `Sm` 6, `Md` 8, `Lg` 10, `Xl` 14, `Full`.
`theme.radius` in `settings.json` moves the base (default 10); the others
follow. Nested corners are outer minus padding, floored at `Sm`.

**Border**: 1px `border`. `input` on text fields. No other width exists.

**Ring**: focus is `border` swapped to `ring` plus a 3px outer halo of `ring`
at 0.5 alpha. Same drawing on every surface.

**Translucency and blur**: the bar strip, panels and the launcher card paint
`Theme.surface(Theme.color.card)`, the card colour at
`theme.surfaceOpacity` (0.85). Hyprland blurs what is behind them
(`layerrule = blur` + `ignorealpha` on `formalshell:bar`, `formalshell:panel`,
`formalshell:menu`, in the example config); the shell itself never blurs.
Toasts, OSD, lock and the modal scrim stay opaque.

**Type** (`Theme.fontFamilySans`, `Theme.fontFamilyMono`,
`Theme.fontSize.*`, `Theme.weight.*`): sans for words (titles, labels,
buttons, section labels, descriptions, hints), mono for values (numbers,
units, times, identifiers, chords, clipboard and terminal content). Both are
fontconfig aliases, Geist Sans and Geist Mono by intent. Sizes `caption` 11,
`bodySmall` 12, `body` 13, `subtitle` 14, `title` 15, `heading` 17,
`display` 26, `displayLarge` 30. Weights `normal` 400, `medium` 500,
`semibold` 600. Values that change are mono, so they stay tabular.

**Space** (`Theme.space.*`): `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24,
`xxl` 32; `controlHeight` 32, `barCellHeight` 28, `barMargin` 6,
`controlPaddingX` 12, `controlPaddingY` 6, `rowGap` 4, `panelPadding` 12,
`sectionGap` 16, `trackThickness` 6; `popupWidthNarrow` 320, `Default` 380,
`Wide` 480, `Menu` 560, `MenuSplit` 840, `MenuApp` 900.

**Motion** (`Theme.motion.*`): `fast` 100 for hover fills, `standard` 130
for enter/exit, `reveal` 400 for the wallpaper crossfade, `slide` 4px.
`motion.enabled=false` zeroes the durations. Enter is opacity plus a 4px
slide toward the anchor; exit is opacity only. List cursors jump.

**Icons**: `Icon { name: "wifi" }`, resolved through the set `theme.icons`
selects (`lucide` default, `nerd`) in `shell/Theme/icons.js`. Size equals
the neighbouring text's font size. No raw codepoints in surface files.

## 2. Primitives

`shell/Components/` holds one component per shadcn part the shell uses.
Build with these; add a primitive only when two surfaces need the same new
thing.

| primitive | is | states |
| --- | --- | --- |
| `Cell` | a bordered `radiusMd` item: bar cell, list row, chip | rest (`card`, `border`), `ghost` rest (nothing, for the bar's own cells), hover (`accent`), cursor (ring), selected (`accent` fill), active (`primary` fill, `primaryForeground` ink), destructive (`destructive` border and ink) |
| `Button` | shadcn button, `variant`: `default` (`primary` fill), `outline` (`border`, transparent), `ghost` (no border, hover `accent`), `destructive` | hover, cursor, pressed (`accent` at 0.8), disabled (opacity 0.5) |
| `IconButton` | a `ghost` Button that is `controlHeight` square, one `Icon` | as Button |
| `Card` | `card` fill, 1px `border`, `radiusXl`, `panelPadding` | none |
| `SectionLabel` | `caption`, `medium`, `mutedForeground`, uppercase, `letterSpacing.meta`; optional trailing count `(3)` | none |
| `Input` | `input` border, `radiusMd`, `controlHeight`, placeholder `mutedForeground` | focus (ring), error (`destructive` border, caption below) |
| `Switch` | 32x18 track, `muted` off, `primary` on, `background` knob | cursor (ring) |
| `Segmented` | `muted` group, `radiusMd`, active segment `background` with a 1px `border` | cursor (ring) |
| `Track` | a `trackThickness` progress or slider: `muted` track, `primary` fill, `radiusSm` | none |
| `Tooltip` | `popover`, `radiusSm`, `caption`, 6px off the anchor | none |
| `KeyCatcher` | key dispatcher for keyboard-driven surfaces (Escape, Tab, arrows and hjkl, Enter, Space, x, printable) | `blocked` while an inline editor has focus |
| `Panel` | the popout window: `Card` under a bar cell, header row (icon, title, `IconButton`s), `KeyCatcher` around the content, cursor bookkeeping | open, closed |

## 3. Surface rules

**Bar.** One continuous strip across the top of the output: `card` fill at
`surfaceOpacity`, a 1px `border` along its bottom edge and no other edge,
`barCellHeight + 2 * barMargin` tall, no side or top margin. Regions inset
`md` from both screen edges; cells sit `barMargin` down from the top and are
`barCellHeight` tall, `sm` apart, grouped where Omarchy groups (workspaces,
indicators). Cells are ghost `Cell`s: no fill and no border at rest, since
the strip already carries both. Hover, cursor, active, selected,
destructive and warning draw as they do anywhere else. A cell whose panel is
open draws a 2px `primary` line along its bottom edge. Workspace dots are
`mutedForeground`, the active one a `primary` pill.

**Panel.** Header, then sections. A section is a `SectionLabel` and a column
of `Cell` rows `rowGap` apart. A hero (the connected AP, the active sink) is
an inner `Card` with `radiusMd`. Footer: `outline` Button left, `display`
number right. Width `Default`; `Wide` for media, monitor, calendar. Nothing
in a panel scrolls except a row list longer than the screen.

**Launcher.** shadcn Command: `Card` `Menu` wide at 30% from the top; input
with a bottom rule only; breadcrumb chips; rows with the cursor row in
`accent`; hint footer in `caption` `mutedForeground`. Modal over a 0.5 black
scrim.

**Toasts.** The sonner stack as built. `Card` chrome; critical is a
`destructive` border and icon, not a fill.

**Notification centre.** Full-height `Card` with a left border only; DND is
a `Switch`; unread rows carry a 6px `primary` dot.

**OSD.** `Card` pill bottom-centre: `Icon`, `Track`, tabular percentage.

**Lock, greeter.** Wallpaper, 0.5 scrim, `displayLarge` x3 clock, date as a
`SectionLabel`, one `Input`. Wrong password: `Input` error state.

**Picker.** Thumbnail `Cell`s with `radiusMd`; cursor is the ring;
`Dark | Light` is a `Segmented`.

**Tooltip, tray menu, polkit, console, capture, hot corners.** Same tokens,
no exceptions.

## 4. Keyboard

Anything a pointer can do on a shell surface has a key, and the target is
visible. Panels take keys through `KeyCatcher` and show the cursor as the
ring; the launcher shows it as the `accent` row. A panel opened by pointer
hides the cursor until the first key. `panel toggle <name>`, `panel toggleAt
<n>` and `menu summon <route>` are the keybind entry points; the shipped
Hyprland bindings are in `docs/examples/hyprland/formalshell.conf`.

## 5. Never

- A literal colour, radius, duration or pixel size in a surface file.
- A hardcoded font family, a Nerd Font glyph, an SVG icon asset.
- Words in mono or values in sans.
- A shadow, a gradient, or a blur drawn by the shell (blur is the
  compositor's, behind a translucent card). Dither only behind
  `wallpaper.dither` or `lock.dither`, both off by default.
- Foreground/background inversion for selection.
- A trailing colon on a label. `NETWORKS (1)`, not `NETWORK:`.
- A full-bleed `primary` or `destructive` row. Colour goes on the border, the
  icon or the dot; fills are for buttons and the active toggle.
- A hover fill that moves, or a cursor that slides between rows.
- Uppercase anywhere but `SectionLabel` and the breadcrumb.

## 6. Verify

`just vm-smoke <flag>` on nested Hyprland, then read the PNG. A change to a
token or primitive re-runs base, `--menu`, `--notify` and `--panel network`
at minimum; a change to one surface re-runs that surface's leg. Contrast:
`mutedForeground` on `card` stays at or above 4.5:1 in both fallback modes.
