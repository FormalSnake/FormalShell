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

**Separation**: one ladder, five rungs, and a boundary takes exactly one of
them. Reaching for a rung is a claim that the one below it was tried and was
not enough, so the question is never "does this need a box" but "how far up
does this boundary have to go".

1. **Nothing.** Rows inside one group. A row is `controlHeight` tall with
   `controlPaddingX` either side, and that padding is the gap. Rows in a
   uniformly interactive list abut at `spacing: 0`; the hover wash and the
   cursor ring are what a pointer needs, and neither is a resting mark.
2. **Space.** `sectionGap` between sections against `rowGap` inside one, a
   4x ratio, so the grouping reads before anything is drawn at all. This is
   the rung most boundaries stop at, and a boundary that still reads wrong
   with `sectionGap` under it usually wants a name, not a line.
3. **A name.** A `SectionLabel` over the group, inset to the row text under
   it. A heading both separates and says what the group is, which no amount
   of space or ink can do, so a group worth separating is usually a group
   worth naming.
4. **A rule.** `Separator`, a 1px `border` line, full-bleed across the
   surface or `inset` to the row text. For a seam space cannot carry: two
   halves of one surface that differ in kind (the monitor ledger above its
   process table), a header or footer against the content it frames, a
   divider a data source itself declares (a D-Bus menu's own separator
   entries), or a list whose rows are taller than one line. Never directly
   under a `SectionLabel`, which is rung 3 doing the same work twice.

   That last case is where rung 1 runs out. Rung 1 holds while every row is
   one line tall and the gap between rows is the largest gap in sight. A row
   carrying its own stack (the notification centre's sender line, summary,
   body and actions) has internal gaps as big as the gap to the next row, so
   space stops reading as separation and the list runs together into one
   block of text. Those rows take a rule between them. The test is the row's
   height, not the list's length: uniform `controlHeight` rows still abut at
   `spacing: 0` and still take nothing.
5. **A card.** `Card`. Every floating surface is one, drawn at its outer
   edge: the panel's frame, the launcher's, a toast's, the OSD pill, the
   notification centre's. Inside that frame a surface may spend one more, on
   the single block the rest of it points at, and it never spends that twice.
   Nothing goes a level deeper: a card inside that card does not exist, and a
   block that needs marking off inside one takes rung 4 or lower however much
   it outranks its neighbours (owner, 2026-08-26: "no nested cards anywhere,
   just a panel, and max one card", "one card for the preview so it didn't
   count as nested").

   Where each surface spends the allowance, or doesn't. The launcher's split
   route spends it on the preview pane: flat `MenuRow`s down one side and the
   card down the other, so the pane reads as the thing the list is pointing
   at. A panel spends it on nothing: the header's rule and `sectionGap`
   already rank the hero over the sections under it, and the border the hero
   used to draw was the "too big usage of cards everywhere" the owner called
   out. The notification centre spends it on nothing either: its rows are the
   list, not a block the list points at.

   What a resting box actually marks decides whether it is one. A fill and a
   border at rest say *the pointer or the keyboard acts on this*: a
   `Button`, an `Input`, a `Switch`, a `ButtonGroup` trough, a
   `Cell { chip: true }`, a lone clickable row that is not part of a uniform
   list. That is chrome on a control, and it never counts against the one
   card above. A block that only groups its children, or only reports a
   value, earns no box at any depth.

   An outline around imagery is not a card either. Album art and a
   notification's app icon keep a 1px frame, because a picture bleeding into
   the surface behind it has no edge of its own. `Cover` draws exactly that
   frame and nothing else, and rounds the picture to the same corner:
   `Theme.coverRadius(extent)`, a quarter of the slot's shorter side capped
   at `radiusSm`, so the bar's 17px art is a rounded square rather than a
   lozenge (owner, 2026-08-26) and a 96px panel cover lands on the ladder.
   Everything that wants no edge stays a plain `Picture`.

**Padding**: one rule, on every surface. A card insets its content by
`panelPadding`. A row is `controlHeight` tall with `controlPaddingX` either
side and its content vertically centred; it is taller only when its own
content needs the room, and a badge that sits inside a row rather than
being one (`Cell { chip: true }`) hugs its label. A `SectionLabel` sits
`sectionGap` below the block
above it and `rowGap` above its rows, and the rows inside a section are
`rowGap` apart. An icon and the label beside it are `iconGap` apart. A
header row is `controlHeight` tall and takes the same horizontal padding as
the rows under it: none of its own where those rows draw their own border,
`controlPaddingX` where they do not, which is why the launcher's input row
and footer line up with its row labels rather than with the card edge. A
`SectionLabel` follows the same rule against the rows it heads, so a section
of flat rows takes `controlPaddingX` and a section of bordered rows takes
none. A floating surface sits `screenPadding` off the screen edge it hangs
from and `barMargin` off the bar or the item it is anchored to, and is no
taller than the screen minus the bar and those two paddings: past that its
content scrolls (`WheelScroll`) rather than the surface running off the
display. Toasts, the OSD pill, the notification centre and the tooltip take
those same numbers. A surface never writes its own margin.

**Motion** (`Theme.motion.*`): `fast` 100 for hover fills, `standard` 130
for enter/exit, `emphasized` 250 on `emphasizedEasing` for the bar's
workspace indicator, `reveal` 400 for the wallpaper crossfade, `slide` 4px.
`motion.enabled=false` zeroes the durations. Enter is opacity plus a 4px
slide toward the anchor, and exit reverses it. A toast is the one carve-out:
it is a surface arriving from off screen rather than chrome appearing in
place, so it travels its own width plus `screenPadding` from the anchored
edge on `emphasized`, and leaves the same way (amended 2026-08-26, owner: the
4px nudge read as not animating at all). List cursors jump. The
workspace pill is the one carve-out inside the chrome: it travels the width
of the dot row, which `standard` reads as a jump, so it takes `emphasized`
and its two edges take different durations, which is what makes the pill
stretch across the gap and close up behind itself.

**Imagery**: content pictures go through `Picture`, which is a bare `Image`
plus the retro pass `theme.dither` turns on. A picture that needs an edge of
its own is a `Cover`. Neither is ever a raw `Image` in a surface file, and
neither is chrome: an app icon and an album cover keep their own colours on a
filled row, unlike every other ink on it.

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
| `Card` | `card` fill, 1px `border`, `radiusXl`, `panelPadding`; the surface's own frame, never nested | none |
| `Picture` | content imagery, bare: the retro pass under `theme.dither`, no frame and no rounding | none |
| `Cover` | a `Picture` in a `muted` well with a 1px `border`, clipped to `Theme.coverRadius`: album art, a notification's app icon | none |
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
inside a row is `Cell { chip: true }`. A heading is a `SectionLabel`. A seam is a
`Separator`. A
surface that draws its own bordered or rounded `Rectangle` is drawing chrome
a primitive owns; `dev/check-primitives.py` fails the build unless that
Rectangle carries a `// primitive-exempt:` comment saying what no primitive
covers (an indicator dot, a colour swatch, a QR module).

**Panel.** Header, then sections. A panel is ONE card. A section is a
`SectionLabel` and a column of `Cell` rows `rowGap` apart, and almost nothing in
one draws a box at rest (owner, 2026-08-26, "there's a too big usage of
cards everywhere"). A repeating list row in a section where every row is
interactive is `Cell { ghost: true }` at `spacing: 0`, the shape the tray
menu and the notification centre already had: uniform rows need no border to
read as controls, the hover wash and the cursor ring say it. A block that
only reports a number, and an empty state that only says `NO DEVICES`, is a
ghost or no `Cell` at all. What keeps its `radiusMd` fill and border is what
a reader could otherwise mistake: a lone control that is not part of a list,
and every row of a section that mixes clickable rows with static ones. Every
state still draws on a ghost, so nothing is lost but the resting box. The header takes a full-bleed `Separator`
under it, on every panel, so the card reads as a titled sheet rather than as
a title floating over a list. A hero (`PanelHero`: the connected AP, the
active sink, the playing track) is flat and leads the content column, its
own type doing the ranking the border used to do: a `subtitle` title over a
`bodySmall` caption, an optional `display` readout beside them, an optional
`Track` under them. Footer: `outline` Button left, `display`
number right. Width `Default`; `Wide` for media, monitor, calendar. Nothing
in a panel scrolls except a row list longer than the screen.

**Launcher.** shadcn Command: `Card` `Menu` wide at 30% from the top; input
with a bottom rule only; a shadcn Breadcrumb under it (ancestors in
`mutedForeground`, the level in `foreground`, a `chevron-right` between,
no fill and no frame); rows with the cursor row in
`accent`; hint footer in `caption` `mutedForeground`. Modal over a 0.5 black
scrim. The split route's preview pane is the one card this surface spends
inside its own frame (§1's ladder, rung 5): `radiusMd`, an `sm` gutter off
the list, flat rows beside it. Nothing inside the pane draws a frame of its
own, the preview picture included.

**Toasts.** The sonner stack as built. `Card` chrome; critical is a
`destructive` border and icon, not a fill. The card's icon slot resolves the
notification's image, its app icon, the sender's desktop entry, then a
`bell`; a picture takes a `radiusSm` frame. The surface under the stack is
the whole output and holds that size for as long as it is mapped, so a
compositor's own layer animation has no geometry change to fight; the cards
move, and everything outside them is click-through.

**Notification centre.** A floating `Card` off the right edge, content-tall
and capped at the output; DND is a `Switch` in a ruled header; unread rows
carry a 6px `primary` dot. Its rows are multi-line, so a `Separator` runs
between them (§1's ladder, rung 4) and the two tiers stay `SectionLabel`
sections `sectionGap` apart.

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
  `wallpaper.dither` or `lock.dither`, both off by default. The bar's own
  mini cover stops animating behind `media.animatedBarCover: false`; the
  media panel's own cover animates unconditionally.
- A card inside a card, and a resting fill-and-border around any block that
  only groups its children or only reports a value.
- Foreground/background inversion for selection.
- A trailing colon on a label. `NETWORKS (1)`, not `NETWORK:`.
- A full-bleed `primary` or `destructive` row. Colour goes on the border, the
  icon or the dot; fills are for buttons and the active toggle.
- A hover fill that moves, or a cursor that slides between rows.
- Uppercase anywhere but `SectionLabel`. The breadcrumb lost its carve-out
  with its chips (2026-08-26): shadcn's breadcrumb is a path in natural case.

## 6. Verify

`just vm-smoke <flag>` on nested Hyprland, then read the PNG. A change to a
token or primitive re-runs base, `--menu`, `--notify` and `--panel network`
at minimum; a change to one surface re-runs that surface's leg. Contrast:
`mutedForeground` on `card` stays at or above 4.5:1 in both fallback modes.
