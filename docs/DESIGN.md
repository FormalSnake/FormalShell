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
fallback is shadcn's zinc palette, and a wallpaper with `flexoki` in its
path pins Flexoki instead. The wallpaper colour is `primary`.
`accent` fills a selected row and a list's own cursor, never the wallpaper
colour.

**Hover and press** (`Theme.hoverFill`, `Theme.pressFill`): a wash of the
ink, not a fill. Every surface the pointer reaches is drawn at
`surfaceOpacity`, so an opaque chip on top of one lands at a delta the
wallpaper decides: a bright wallpaper lifts the surface past `accent` and
the hover reads as a dark patch, one close to `card` leaves no delta at
all. The wash stacks on whatever resolved there instead and keeps its size
and its direction over every wallpaper. A control already carrying a
colour takes `Theme.hoverFilled(c)`/`Theme.pressFilled(c)`, the fill
blended toward `background` and left opaque (shadcn's `hover:bg-primary/90`);
dropping its opacity instead makes it see-through on a translucent panel.

**Radius** (`Theme.radius*`): `Sm` 6, `Md` 8, `Lg` 10, `Xl` 14, `Full`.
`theme.radius` in `settings.json` moves the base (default 10); the others
follow. Nested corners are outer minus padding, floored at `Sm`.

**Border**: 1px `border`. `input` on text fields. No other width exists.

**Ring**: focus is `border` swapped to `ring` plus a 3px outer halo of `ring`
at 0.5 alpha (`Theme.ringWidth`). Same drawing on every surface. The halo
falls outside the item's own bounds, so a clipping container reserves room
for it: it grows its clip rect by `ringWidth` on every side and insets its
content by the same, which leaves every row at the x, width and top it had
without a ring. The rule lives in the container (`Panel`'s content
flickable, the launcher's and the centre's lists), never in the surface, and
a row never insets itself.

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

**Space** (`Theme.space.*`): the raw steps are `xxs` 2, `xs` 3, `sm` 4,
`md` 6, `lg` 8, `xl` 10, `xxl` 12, `huge` 18; the semantic keys are
`controlHeight` 32, `barCellHeight` 28, `barMargin` 6, `controlPaddingX` 12,
`controlPaddingY` 6, `rowGap` 4, `iconGap` 8, `panelPadding` 12,
`sectionGap` 16, `trackThickness` 6; `screenPadding` 12,
`popupWidthNarrow` 320, `Default` 380,
`Wide` 480, `Menu` 560, `MenuSplit` 840, `MenuApp` 900. `panelPadding` is
the gap inside a card, `screenPadding` the gap outside a floating surface;
they share a value and describe different things.

**Padding**: one rule, on every surface. A card insets its content by
`panelPadding`. A row is `controlHeight` tall with `controlPaddingX` either
side and its content vertically centred; it is taller only when its own
content needs the room, and a badge that sits inside a row rather than
being one (`Cell { chip: true }`) hugs its label. A `SectionLabel` sits
`sectionGap` below the block
above it and `rowGap` above its rows, and the rows inside a section are
`rowGap` apart. An icon and the label beside it are `iconGap` apart. A
header row is `controlHeight` tall and takes the same horizontal padding as
the rows under it: none of its own where those rows draw their own border
(a panel), `controlPaddingX` where they do not, which is why the launcher's
input row and footer line up with its row labels rather than with the card
edge. A floating surface sits `screenPadding` off the screen edge it hangs
from and `barMargin` off the bar or the item it is anchored to, and is no
taller than the screen minus the bar and those two paddings: past that its
content scrolls (`WheelScroll`) rather than the surface running off the
display. Toasts, the OSD pill, the notification centre and the tooltip take
those same numbers. A surface never writes its own margin.

**Motion** (`Theme.motion.*`): `fast` 100 for hover fills, `standard` 130
for enter/exit, `emphasized` 250 on `emphasizedEasing` for the bar's
workspace indicator, `reveal` 400 for the wallpaper crossfade, `slide` 4px.
`motion.enabled=false` zeroes the durations. Enter is opacity plus a 4px
slide toward the anchor; exit is opacity only. List cursors jump. The
workspace pill is the one carve-out inside the chrome: it travels the width
of the dot row, which `standard` reads as a jump, so it takes `emphasized`
and its two edges take different durations, which is what makes the pill
stretch across the gap and close up behind itself.

**Icons**: `Icon { name: "wifi" }`, resolved through the set `theme.icons`
selects (`lucide` default, `nerd`) in `shell/Theme/icons.js`. Size equals
the neighbouring text's font size. No raw codepoints in surface files.

**Presets** (`theme.preset`): a table of defaults for the chrome knobs,
never a mode a surface can read. `shadcn` (the default) is everything
above. `retro` is the shell's earlier language as a setting of this one:
`theme.radius` 0, `theme.icons` `nerd`, `theme.fonts` `mono` (words take
the mono face too), `theme.surfaceOpacity` 1, `theme.blur` false,
`theme.dither` true. An explicit key wins over the preset. `radius` 0
means 0 on every step and every pill (`Theme.pillRadius`), whichever
preset set it. `theme.dither` on renders content imagery (launcher and
active-window icons, notification images, album art) through `Picture`'s
retro pass, paints a `Track` groove as `DitherFill`, and is the default
for `wallpaper.dither` and `lock.dither`; tray icons, the picker grid and
clipboard thumbnails stay true colour. Hyprland follows through
`formalshell-chrome.conf` (`$rounding`, `$blur`), published beside the
colours. A surface reads `Theme.radius*`, `Theme.fontFamilySans`,
`Theme.iconSet`, `Theme.dither` and `Theme.pillRadius`, and never
`Theme.preset`.

## 2. Primitives

`shell/Components/` holds one component per shadcn part the shell uses.
Build with these; add a primitive only when two surfaces need the same new
thing.

| primitive | is | states |
| --- | --- | --- |
| `Cell` | a bordered `radiusMd` item: bar cell, list row, chip | rest (`card`, `border`), `ghost` rest (nothing, for the bar's own cells), hover (`hoverFill`), cursor (ring), selected (`accent` fill), active (`primary` fill, `primaryForeground` ink), destructive (`destructive` border and ink) |
| `Button` | shadcn button, `variant`: `default` (`primary` fill), `outline` (`border`, transparent), `ghost` (no border), `selected` (`background` fill behind a border), `destructive` | hover and pressed (a fill blends toward `background`, everything else takes the wash), cursor, disabled (opacity 0.5) |
| `IconButton` | a `ghost` Button that is `controlHeight` square, one `Icon` | as Button |
| `Card` | `card` fill, 1px `border`, `radiusXl`, `panelPadding` | none |
| `SectionLabel` | `caption`, `medium`, `mutedForeground`, uppercase, `letterSpacing.meta`; optional trailing count `(3)` | none |
| `Input` | `input` border, `radiusMd`, `controlHeight`, placeholder `mutedForeground` | focus (ring), error (`destructive` border, caption below) |
| `Switch` | 32x18 track, `muted` off, `primary` on, `background` knob | cursor (ring) |
| `ButtonGroup` | a `muted` trough at `radiusMd` holding one ghost `Button` per option, `xs` inside: a choice among several (power profiles, the audio device pick) when `exclusive`, a set of actions (the media transport) when not | selected (`background` with a 1px `border`), active option (`primary` fill), cursor (ring on one button) |
| `Segmented` | `muted` group, `radiusMd`, active segment `background` with a 1px `border` | hover on an unchosen segment (the wash, ink lifted off `mutedForeground`), cursor (ring) |
| `Track` | a `trackThickness` progress or slider: `muted` track, `primary` fill, `radiusSm` | cursor (ring), for a surface that addresses the track as a row |
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
`mutedForeground` in fixed slots that never reflow, with one `primary` pill
layered over them on the focused slot; a switch moves the pill, a hovered
dot grows a step, and an urgent dot is `destructive` and pulses once.

**Which primitive.** An on/off state is a `Switch`, never a button whose
label is its own state and never an icon that flips between an on and an off
name. A choice among several, or a row of actions belonging to one thing, is
a `ButtonGroup`. A level is a `Track`. Text entry is an `Input`. A badge
inside a row is `Cell { chip: true }`. A heading is a `SectionLabel`. A
surface that draws its own bordered or rounded `Rectangle` is drawing chrome
a primitive owns; `dev/check-primitives.py` fails the build unless that
Rectangle carries a `// primitive-exempt:` comment saying what no primitive
covers (an indicator dot, a colour swatch, a QR module).

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
`destructive` border and icon, not a fill. The card's icon slot resolves the
notification's image, its app icon, the sender's desktop entry, then a
`bell`; a picture takes a `radiusSm` frame. The surface under the stack is
the whole output and holds that size for as long as it is mapped, so a
compositor's own layer animation has no geometry change to fight; the cards
move, and everything outside them is click-through.

**Notification centre.** A floating `Card` off the right edge, content-tall
and capped at the output; DND is a `Switch`; unread rows carry a 6px
`primary` dot.

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
