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
fallback is shadcn's zinc palette, and a wallpaper with a pinned palette's
name in its path (`flexoki`, `zenbones`) pins that palette instead, for the
shell and for every app template alike (`shell/Theme/flexoki.js` and
`shell/Theme/zenbones.js` each carry all three views of one table). The
wallpaper colour is `primary`.
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

**Translucency and blur**: the bar strip, panels, the launcher card and the
polkit consent card paint `Theme.surface(Theme.color.card)`, the card colour
at `theme.surfaceOpacity` (0.85). Hyprland blurs what is behind them
(`layerrule = blur` + `ignore_alpha` on `formalshell:bar`, `formalshell:panel`,
`formalshell:menu`, `formalshell:polkit`, and the rest, in the example
config); the shell itself never blurs. A translucent card with nothing
blurred behind it reads as a rendering fault rather than as depth, so the
two travel together: a surface is either on that list or opaque. Toasts, OSD
and lock are the opaque ones. The polkit layer covers the whole output and
its scrim is well above `ignore_alpha`, so the desktop blurs behind the
scrim too, which is the modal's depth cue; the scrim itself is still plain
black at 0.5.

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
`controlHeight` 32, `barCellHeight` 28, `barCellWidth` 44, `barMargin` 6,
`controlPaddingX` 12, `controlPaddingY` 6, `rowGap` 4, `iconGap` 8, `panelPadding` 12,
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

   A surface here is a thing that floats with nothing behind it, not a
   window. The capture overlay and the plugin overlay are transparent and
   full-screen, so the blocks inside them (the region readout, the toolbar,
   the unnamed-window list, the plugin error) each sit on the raw desktop and
   each is its own frame. Two cards in one of those files is two surfaces,
   not a surface spending twice.

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
from and `barMargin` off the bar or the item it is anchored to, centred on
that item along the bar's own axis and clamped to the padding at either end,
and is no
taller than the screen minus the bar and those two paddings: past that its
content scrolls (`WheelScroll`) rather than the surface running off the
display. Toasts, the OSD pill, the notification centre and the tooltip take
those same numbers. A surface never writes its own margin.

**Motion** (`Theme.motion.*`): two families of clock, and the property picks
the family, never the surface. `spatialFast` 350, `spatial` 500 and
`spatialSlow` 650 pace anything with a position or a size: x, y, width,
height, margins, scale, radius, rotation, an emerge, a morph, a cursor's
travel. `effectsFast` 150, `effects` 200 and `effectsSlow` 300 pace anything
with neither: opacity, colour, a progress that only drives alpha. Two names
sit outside both families, `emphasized` 400 for the workspace pill and
`emphasizedDecel` for a toast arriving from off screen, which is a curve on
`spatial`'s clock with no duration of its own. `reveal` 400 is the
full-screen fades: the wallpaper and palette crossfades, the lock's blank and
wake, the screensaver's own enter and exit, on `effectsSlow`'s curve.

The curves are Material 3 Expressive's, the set caelestia runs on (amended
2026-09-09, owner: caelestia's morphs, not curves alone). Each is a cubic
bezier through `easing.bezierCurve` rather than a Qt enum, since the enum
curves cannot do what the spatial ones do: every spatial curve carries a y
control point above 1, so what travels passes its rest by a few pixels and
settles back on it. The effects curves never overshoot. A spatial kind put on
an opacity is clamped by Qt instead, which reads as the fade stalling just
short of the end. `motion.enabled=false` zeroes every duration and pins
`Deform` to identity, so every surface lands at once, at rest and
undeformed; the curves themselves are left alone, a zero-duration animation
ending in the same place whatever it carries.

A surface names a clock exactly one way. `Behavior on x { Anim {} }`,
`Behavior on opacity { Anim { kind: "effects" } }`,
`Behavior on color { CAnim {} }`. `Anim`'s `kind` is one of the eight names
above and defaults to `spatial`; `CAnim` is the colour half, always
`effectsSlow`, since a colour has no position to overshoot and a crossfade
shorter than that reads as a flicker rather than as a change. The positioner
transitions are the same primitive: `MoveTransition` on `spatial`,
`AddTransition` on `effects`, `RemoveTransition` on `effectsFast`.

An edge-anchored card and the bar are one silhouette (amended 2026-09-09).
The bar draws a single 1px `border` along its inner edge, and a card hanging
off that edge opens a gap in the line: the card's own rect plus a `radiusXl`
at either end, both gap edges travelling on `spatial`. `Shoulders` draws the
card with that edge left open and a concave quarter fillet outside each of
its two corners, running out to where the line resumes, so the card grows out
of the bar rather than parking against it. The open surface publishes the
rect as `PanelRegistry.join` (the bar's edge, the card's x and width along
it, the screen) off its frame's live position, so a size morph and a handoff
carry the gap with them frame by frame; that rect is the only thing the two
windows share. `theme.radius` 0 draws square corners and no fillets, which is
a plain card against a whole line. The panels take `Shoulders`, and the
chevron's and the tray's second bars with them. Everything that meets no line
keeps `Card`: the notification centre and the OSD each sit a `screenPadding`
clear of the output's own edge, and the launcher, the tooltip and the modals
float with nothing for a fillet to run out to.

A card that arrives squashes into the edge it came from (`Deform`, amended
2026-09-09). Its scene position and size are sampled every frame, the
velocity taken from the delta, and a matrix stretches the card along the
direction of travel and compresses it across, so the area holds. Each
component of that matrix rides an underdamped spring, so the card keeps
deforming for a beat after the travel has stopped and unwinds through its
rest instead of snapping to it. The stretch is capped at 35% however fast the
card goes, and `amount` sets how much of it a surface takes: 0.25 on the OSD,
0.15 on a popout, 0.1 on the launcher. The matrix is centred on the anchored
edge's midpoint rather than on the card's own centre, so a drawer squashes
into the bar and keeps its top edge on the line it hangs from. At rest it is
identity and the frame loop is stopped, so a still shell costs nothing.

An anchored surface opens as a drawer (amended 2026-09-09, owner: the fade,
0.97 zoom and 8px slide it replaces read as the surface not animating at
all). A panel, the notification centre and the OSD each hang off one edge:
the card starts behind that edge, displaced toward it by its own extent on
that axis, and travels to rest on `spatial` both ways, clipped at the line it
rests on so it comes out from under the bar rather than across it. No fade
and no zoom, since the clip is what hides it; its contents come up on
`effects` behind the travel, so the card lands before its text. The launcher
unfolds instead: the card is drawn at its search row's height on
`effectsFast`, at full opacity, and its height carries the level under the
rule on `spatial` while the card clips, so the rows are revealed rather than
pushed into place. That level takes no fade of its own, the growing edge
being the reveal; a level change while the launcher is already open plays one
`effects` fade in with no out half, since the route is resolved by the
keystroke that asked for it and the body has already changed by the time an
out half could run. Polkit and the plugin overlay keep the modal recipe,
opacity on `effects` and scale from 0.97 on `spatialFast` from centre, and
the tooltip and the bar's own reveal take the same. Every one of them waits
for its window to be on screen before it starts: a compositor can spend most
of an enter putting the surface up, and an animation that ran behind it would
land already at rest.

Opening a panel while another is open is a handoff, and it runs on one clock
(amended 2026-09-09). The new card is drawn on the old card's rect, the old
window is cut on the tick the travel starts, and the one card left travels
and resizes to its own place on `spatial` while its contents crossfade on
`effects` over the first part of that same movement. One eased parameter
carries the rect rather than four animations over x, y, width and height:
the destination stays live, so content that settles its height a frame late
moves where the card is going instead of stranding the travel short of it,
and the four components ride one curve either way. The shoulders travel with
the frame and the bar's gap follows them.

Geometry never jumps (M53). Anything whose x, y, width or height changes
while it is on screen animates the change: a positioner carries
`move: MoveTransition {}`, a list adds and removes rows through
`AddTransition` and `RemoveTransition`, an item carries a Behavior, and a
container whose size follows animated children rides their clock. Sizes
follow content live on `spatial`, a panel whose section count changes and the
launcher's list under a query alike, and a closing surface freezes its size
first. Bar cells enter and leave through their own presence while the strip's
rails carry the neighbours. The launcher's rows keep their identity across a
query, so a re-rank moves rows instead of rebuilding them; only a level
change or a diff touching more than 64 rows resets the list.

Content never snaps. What one slot draws crossfades on `effects` when it
changes: an icon glyph, a label under a width morph, the launcher's empty
state, the clipboard preview, a calendar month. A fill or border that
switches which colour token it binds crossfades through `CAnim`. A palette
change (mode toggle, matugen recolour, preset swap) crossfades every
`Theme.color.*` over `reveal`.

The cursor travels (amended 2026-09-09, owner: a keyboard user wants what a
keystroke moves to be seen moving). It is one item per list, the launcher's
`accent` row and a panel's ring, moving on `spatialFast`; a one-step move
travels, while a wrap, a filter reset and a level change snap, since nothing
connects the two positions. A selection fill (`Segmented`, the picker's mode
tabs) travels the same way on `spatial`. Everything a key drives is a
retargeting Behavior, never a restarting animation, so key repeat glides. A
toast is the carve-out on the way in: it is a surface arriving from off
screen rather than chrome appearing in place, so it travels its own width
plus `screenPadding` from the anchored edge on `emphasizedDecel`, which
decelerates into rest without carrying it back past the edge it came from,
and it leaves on `spatial`. The workspace pill keeps its own: both its edges
take `emphasized` and the trailing one runs at twice that clock, so the
leading edge reaches the new slot while the trailing edge is still leaving
the old one, which is what makes the pill stretch across the gap and close up
behind itself.

Tooltips are one card per output. It appears 400ms after the pointer parks on
a cell and, within 500ms of leaving, follows the pointer to the next cell
instead of paying the delay again: the card travels and morphs its width on
`spatial`, its text crossfading on `effects`.

**Startup** (M52): nothing paints before the shell knows what it looks
like. The boot surfaces (bar, background, frame) hold their windows
unmapped until `Config.loaded`, `Theme.paletteReady` and
`PluginService.loaded` have all flipped, each of which flips on its failure
branch too, with a 400ms backstop so a wedged read can never keep the
screen bare; then each maps once at final geometry, one exclusive-zone
publish, one tiling shift. The bar's content enters on `Presence` from its
own edge, and only after that reveal settles do the cells' size Behaviors
arm, so a service answering late is laid out rather than animated in. The
first real wallpaper hard-cuts (`reveal` is for changes, not boot), and a
theme republish that changes nothing writes no file and reloads nothing.

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
| `Cell` | a bordered `radiusMd` item: bar cell, list row, chip; fill, border and ink crossfade on `effects`, and a cell under a list that owns the cursor or the selection fill draws neither itself | rest (`card`, `border`), `ghost` rest (nothing, for the bar's own cells), hover (`hoverFill`), cursor (ring), selected (`accent` fill), active (`primary` fill, `primaryForeground` ink), destructive (`destructive` border and ink) |
| `Button` | shadcn button, `variant`: `default` (`primary` fill), `outline` (`border`, transparent), `ghost` (no border), `selected` (`background` fill behind a border), `destructive` | hover and pressed (a fill blends toward `background`, everything else takes the wash), cursor, disabled (opacity 0.5) |
| `IconButton` | a `ghost` Button that is `controlHeight` square, one `Icon` | as Button |
| `Card` | `card` fill, 1px `border`, `radiusXl`, `panelPadding`; the surface's own frame, never nested | none |
| `Shoulders` | the same frame with the anchored edge left open and a concave fillet outside each of its two corners, running out to the bar's line (§1 Motion): what every surface hanging off the bar draws instead of `Card` | none |
| `Picture` | content imagery, bare: the retro pass under `theme.dither`, no frame and no rounding | none |
| `Cover` | a `Picture` in a `muted` well with a 1px `border`, clipped to `Theme.coverRadius`: album art, a notification's app icon | none |
| `SectionLabel` | `caption`, `medium`, `mutedForeground`, uppercase, `letterSpacing.meta`; optional trailing count `(3)` | none |
| `Input` | `input` border, `radiusMd`, `controlHeight`, placeholder `mutedForeground` | focus (ring), error (`destructive` border, caption below) |
| `Switch` | 32x18 track, `muted` off, `primary` on, `background` knob | cursor (ring) |
| `ButtonGroup` | a `muted` trough at `radiusMd` holding one ghost `Button` per option, `xs` inside: a choice among several (power profiles, the audio device pick) when `exclusive`, a set of actions (the media transport) when not | selected (`background` with a 1px `border`), active option (`primary` fill), cursor (ring on one button) |
| `Segmented` | `muted` group, `radiusMd`, one `background` fill with a 1px `border` that travels to the active segment on `spatial` | hover on an unchosen segment (the wash, ink lifted off `mutedForeground`), cursor (ring) |
| `Track` | a `trackThickness` progress or slider: `muted` track, `primary` fill, `radiusSm` | cursor (ring), for a surface that addresses the track as a row |
| `Tooltip` | `popover`, `radiusSm`, `caption`, 6px off the anchor; one surface per output, driven through `TooltipRegistry` | delayed (400ms), travelling (within 500ms of the last hide) |
| `KeyCatcher` | key dispatcher for keyboard-driven surfaces (Escape, Tab, arrows and hjkl, Enter, Space, x, printable) | `blocked` while an inline editor has focus |
| `Anim` | the one `NumberAnimation` in the shell: `kind` resolves a duration and a bezier out of `Theme.motion` (§1 Motion), `spatial` by default | none |
| `CAnim` | the colour half of it, always `effectsSlow`: every `Behavior on color` and `border.color` | none |
| `Deform` | the velocity squash (§1 Motion): samples `target` each frame and exposes the `matrix4x4` its consumer hands to a `Matrix4x4` transform, `amount` per surface | running, at rest (identity, frame loop stopped) |
| `Presence` | the enter/exit motion controller (§1 Motion) a summonable surface binds `opacity`, `scale` and its edge travel to, gating the window's `visible` on `shown` | open, exiting, settled, `bypass` (the pose lands at once, for a handoff) |
| `Panel` | the popout window: `Shoulders` under a bar cell, header row (icon, title, `IconButton`s), `KeyCatcher` around the content, one travelling cursor ring and the scroll that follows it, the frame's size and position morphs | open, closed, handing over |

## 3. Surface rules

**Bar.** One continuous strip along one edge of the output (`bar.position`,
top by default): `card` fill at `surfaceOpacity`, a 1px `border` along its
inner edge and no other edge, `barCellHeight + 2 * barMargin` thick on a
top or bottom bar and `barCellWidth + 2 * barMargin` on a left or right
one, no margin on the edge it sits on. Regions inset `md` from both ends of
the strip; cells sit `barMargin` in from the outer edge and are the strip's
own cell thickness, `sm` apart, grouped where Omarchy groups (workspaces,
indicators).
On a left or right bar the same three regions run top to bottom (`left` at
the top) and nothing turns: each cell stacks its icon over its label
upright, which is why the strip is wider than a horizontal one is tall. A
label too wide for the strip wraps into it and stands down only when a
single word still does not fit, leaving the icon and the tooltip to carry
the cell. The two exceptions turn because they cannot do either: a window
title and a now-playing track are free text of no fixed length, so those
alone rotate, reading bottom to top on the left and top to bottom on the
right. The open-panel mark and the tooltip go to the side facing the
desktop, and a panel hangs `barMargin` off that side at the cell that
opened it. Cells are ghost `Cell`s: no fill and no border at rest, since
the strip already carries both. Hover, cursor, active, selected,
destructive and warning draw as they do anywhere else. A cell whose panel is
open draws a 2px `primary` line along its bottom edge. Workspace dots are
`mutedForeground` in fixed slots that never reflow, with one `primary` pill
layered over them on the focused slot; a switch moves the pill, a hovered
dot grows a step, and an urgent dot is `destructive` and pulses once.

The tray's place on the bar is a dots toggle, and the icons themselves live
in a second bar hanging off it. The strip can carry them instead
(`tray.maxVisible`: -1 for as many as fit, N for up to N), but never some here
and the rest there: the tray moves whole, so it never reads across two
surfaces and the cut never moves under the user when something else on the bar
resizes. Room has the last word over any ceiling, since the tray is the one
region cell with no fixed number of items and so the one that gives ground
when the strip runs out of edge. That second bar is a card of the same ghost
cells at `panelPadding`, one item deep, sitting where any panel would; it is
the tray's own overflow, and the chevron has one of its own: everything on a
chevron's governed side lives in the same kind of second bar, always, and the
chevron cell opens and closes it. Not a state a crowded bar falls into, the
same call the tray's dots take: the group is somewhere else rather than
sometimes here and sometimes there, so nothing on the strip moves when a
track starts playing.

**Frame.** Off by default (`frame.thickness` 0). On, the bar's `card` fill
continues round the other three edges as a band `frame.thickness` wide, and
a rounded rectangle (`frame.radius`, 20; 0 with a base radius of 0) is cut
out of the whole for the desktop, so the bar reads as the thick side of one
frame and the two corners beside it curve into the strip. The bar's window
grows to the output and paints the whole ring, strip included, then its
cells over it, so the three are one surface under the compositor's blur and
above windows; it draws the single 1px `border` along the cut-out and takes
input on the strip alone. Windows tile
inside it (the band is an exclusive zone on each of its edges), and every
floating surface clears it the way it clears the bar.

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
- A duration or a curve outside `Anim` and `CAnim`. The workspace pill's
  trailing edge, which doubles the `emphasized` token on the primitive, is
  the one carve-out: the relation between its two edges is the effect, and a
  second token would be a name with one caller.
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
