# Pantheon mode, and themes as tables

Status: draft for the owner, 2026-09-17. Supersedes the `pantheon-depth`
spike (branch of the same name, deployed on both hosts through
`--override-input`, never merged): that branch put a `Relief` and a
`Shadow` inside the shared primitives behind a `theme.depth` knob, which
overrode the metamorphosis look from inside its own components. The owner's
verdict: "themes should be declarative and separated", and the pantheon
look itself was "a lazy border everywhere", not Pantheon.

## The brief

Owner, 2026-09-17: "a mode for the shell to be like pantheon, but made for
my keyboard based setup and tiling WMs. What you did now is override our
metamorphosis theme. Themes should be declarative and separated here."

Two deliverables, in this order:

1. **Themes as tables.** The chrome every primitive draws comes out of one
   declarative table per theme, in one file per theme. A primitive renders
   what its role's entry says and never names a theme; a theme never
   reaches into a primitive. The shipped look (shadcn chrome, Omarchy
   habits, the metamorphosis motion: `2026-08-25` spec) becomes the
   `metamorphosis` table and renders pixel for pixel as it does today.
2. **A `pantheon` theme** on that mechanism: elementary OS 8's material,
   read off its stylesheet and shell sources (numbers below, with the file
   each came from), and its habits where they survive a keyboard-first
   tiling desktop: wingpanel's bar, Gala's switcher, elementary's
   notification bubble, Slingshot's grid, the popover that drops rather
   than buds. The dock and the multitasking view stay out: both need a
   pointer and floating windows.

## Non-goals

- Porting elementary code. Everything here is numbers read off GPL sources
  and reimplemented in QML; nothing is copied.
- A user-facing theme editor, or deep overrides of the table from
  `settings.json`. `theme.preset` picks a table; the scalar `theme.*` keys
  that exist today keep overriding scalars. Nothing new is overridable.
- A second compositor. Hyprland stays the only one; the Pantheon window
  chrome is a Hyprland config the shell publishes, as `formalshell-chrome`
  already is.
- Fonts. elementary sets Inter at 9pt and the owner runs Geist. The table
  carries no font family, so the fontconfig aliases stay.

## Part 1: a theme is a table

### The shape

`shell/Theme/themes/<name>.js`, one per theme, `.pragma library`, exporting
`STYLE`. `presets.js` keeps resolving `theme.preset` and the scalar knobs it
already owns (radius, icons, fonts, surfaceOpacity, blur, dither) and hands
back `style: STYLE` beside them; `Theme.style` is what primitives read.

Every entry describes one **box** in CSS terms, so elementary's stylesheet
transcribes into it line for line and shadcn's does too:

```js
card: {
    fill: "card",            // a Theme.color role, or "black" / "white"
    fillAlpha: "surface",    // a number, or "surface" for theme.surfaceOpacity
    radius: "xl",            // a Theme.radius* step, or a number
    border: { color: "border", alpha: 1, width: 1 },
    face: null,              // or { from: ["white", 0.2], to: ["white", 0] }, top to bottom
    layers: [                // CSS box-shadow, in order, outermost last
        { inset: true, y: 1, color: "white", alpha: 0.3 },
        { inset: true, y: -1, color: "white", alpha: 0.2 },
        { inset: true, x: 1, color: "white", alpha: 0.07 },
        { inset: true, x: -1, color: "white", alpha: 0.07 },
        { spread: 1, color: "black", alpha: 0.1 },
        { y: 3, blur: 4, color: "black", alpha: 0.15 },
        { y: 3, blur: 3, spread: -3, color: "black", alpha: 0.35 }
    ]
}
```

Colours are role names resolved at draw time, so matugen keeps driving the
palette under every theme; alphas are literals in the table, which is how
elementary's own stylesheet is written. A layer with no `blur` and no
`spread` and `inset` is a hairline; with `spread` and no `blur` a ring; with
`blur` a cast. `face` is the one gradient the material has, elementary's
`%outset-background`.

The table is keyed by **role**, and a role by **state** where the state
changes chrome:

| role | states |
| --- | --- |
| `bar` | rest; plus `adaptive` (Part 2) |
| `card` | rest |
| `popover` | rest (tooltip, tray menu, the second bar) |
| `button.default`, `.outline`, `.ghost`, `.selected`, `.destructive` | rest, hover, press, disabled |
| `cell` | rest, ghost, hover, active, selected, destructive, warning |
| `input` | rest, focus, error |
| `switch.track` | off, on |
| `switch.knob` | rest |
| `track.groove`, `track.fill` | rest |
| `trough` | rest (ButtonGroup, Segmented) |
| `segmented.chip` | rest |
| `cursor` | the ring: colour, width, alpha |
| `scrim` | colour, alpha |

A role missing from a table fails validation (a unit test walks every table
against the role list), so a theme cannot silently fall back to another
theme's chrome.

### The renderer

One primitive, `Components/Box.qml`, draws a box description and nothing
else: the fill, the face gradient, the border, inset hairlines (four
clipped rectangles), rings (bordered rectangles at negative margins) and
casts (one `MultiEffect` per blurred layer over a hidden silhouette, masked
inverted at the silhouette so a translucent card keeps the blurred desktop
it shows). The silhouette is a slot, so a `Shoulders` shape casts the same
way a rounded rectangle does. A box with no layers costs what a `Rectangle`
costs today.

`Card`, `Cell`, `Button`, `Input`, `Switch`, `Track`, `Segmented`,
`ButtonGroup`, `Tooltip` and `Drawer` compose a `Box` with `role:` and
`state:` and lose every literal about chrome they carry now; what stays in
them is behaviour (pointer, cursor, measurement, morphs). The Relief and
Shadow primitives of the spike are deleted.

### Habits are table entries too

Pantheon differs from Omarchy in more than chrome, and those differences
are declared the same way, as values a surface reads and never as a theme
name a surface tests:

| key | metamorphosis | pantheon |
| --- | --- | --- |
| `bar.kind` | `strip` (card fill, hairline, ghost cells) | `wingpanel` (Part 2) |
| `emerge` | `join` (the metamorphosis, `Shoulders`) | `popover` (a card dropping from its cell, no join) |
| `notification.layout` | `row` (today's card) | `bubble` (Part 2) |
| `launcher.default` | `list` | `grid` |
| `switcher` | off | on (Part 2) |

Each value is its own QML file behind a `Loader`
(`Surfaces/Bar/BarStrip.qml` beside `Surfaces/Bar/BarWingpanel.qml`), so the
rule holds: no `if (Theme.preset === ...)` anywhere under `shell/`. `retro`
keeps every metamorphosis habit and changes chrome alone.

### Parity

The `metamorphosis` table is done when the smoke frames it produces are
the frames main produces: `--gallery`, `--panel network --notify --tooltip`,
`--menu`, `--osd`, `--center` and `--join`, diffed pixel for pixel against
the same legs run on main in the same VM. That diff is the acceptance test
for Part 1, and it runs before a single pantheon line lands.

## Part 2: the pantheon theme

### The material, off `elementary/stylesheet` (gtk-4.0, `main`)

Base: `rem()` is 9pt, so `rem(3px)` = 3px at the default size. Colours:

| token | light | dark | source |
| --- | --- | --- | --- |
| `highlight` | white | white at 0.2 | `_exported.scss` |
| `borders` (toplevel) | black 0.2 | black 0.75 | `_index.scss` |
| `border` (controls) | black 0.2 | black 0.3 | `_index.scss` |
| `bg 0` inputs | SILVER_100 `#fafafa` | mix(BLACK_300, BLACK_500, 50%) | `bg-color()` |
| `bg 1` views | white | mix(BLACK_300, BLACK_500, 25%) `#3a3a3a` | |
| `bg 2` background | `#fafafa` | BLACK_500 `#333` | |
| `fg` | `#333` | white | |

GTK's `alpha(c, f)` multiplies, so a dark-mode highlight line written as
`alpha(@highlight_color, 0.3)` lands at white 0.06, not 0.3: the dark
material is quiet. Under matugen the five `bg` levels map onto the surface
container roles the way `recolor.py` in the owner's nix config already maps
them, and `accent` is `primary`.

The mixins, as table layers (`_index.scss`):

| mixin | layers |
| --- | --- |
| `outset-highlight("full")` | inset top white 0.3, inset bottom white 0.2, inset left and right white 0.07 (all times the highlight base) |
| `inset-shadow()` | 0 1px white 0.3 outside (a lit lower lip), inset 0 1px 1px black 0.05, inset 0 0 1px 1px black 0.05 |
| `outset-shadow(1)` | 0 1px 1px black 0.05 |
| `outset-shadow(2)` | 0 1px 1px black 0.07, 0 1px 2px black 0.08 |
| `outset-shadow(3)` | 0 1px 3px black 0.12, 0 1px 2px black 0.24 |
| `shadow(1)` | 0 1px 3px black 0.12, 0 1px 2px black 0.24 (dark 0.42, 0.44) |
| `shadow(2)` | 0 3px 4px black 0.15, 0 3px 3px -3px black 0.35 (dark 0.25, 0.45) |
| `shadow(3)` | 0 3px 8px 2px black 0.1, 0 5px 5px -3px black 0.4, 0 8px 5px 1px black 0.1 (dark 0.2, 0.5, 0.2) |
| `shadow(4)` | 0 2px 4px 2px black 0.1, 0 15px 12px -10px black 0.4, 0 8px 14px 4px black 0.15 (dark 0.2, 0.5, 0.25) |
| `%outset-background` | face gradient white 0.2 to white 0, top to bottom |

The roles (`widgets/*.scss`):

| role | recipe |
| --- | --- |
| `button.default` rest | fill `bg 0`, face, border 1px `border`, highlight full, outset-shadow(2), radius 3, padding 4x7 |
| `button` press/checked | fill black 0.05 (dark 0.15), inset-shadow |
| `button` disabled | fill black 0.03, highlight full, outset-shadow(1), ink dimmed |
| `button.ghost` | nothing; checked fill fg 0.15 |
| `button.selected` (suggested) | fill `accent`, border black-mixed accent 0.5, ink `selected fg` |
| `button.destructive` | fill STRAWBERRY_500, white ink with a 1px text shadow of the fill |
| `switch.track` off | fill black 0.05 (dark 0.1), border 1px `border`, inset-shadow, radius 16 |
| `switch.track` on | fill `accent`, face, border shade(accent, 0.85) |
| `switch.knob` | fill `bg 0`, face, highlight full, ring 1px `border`, outset-shadow(3), 24px, radius 99 |
| `track.groove` | fill black 0.05, border 1px `border`, inset 0 0 0 1px black 0.03, 0 1px white 0.3 below, radius 12 |
| `track.fill` | fill `accent`, border 1px black 0.3, inset 0 0 0 2px black 0.03 |
| `input` rest | fill `bg 1`, border 1px `border`, inset-shadow, radius 3 |
| `input` focus | border `accent`, 0 0 0 2px accent 0.3 outside, inset-shadow |
| `check` | fill `bg 0`, face, border 1px `border`, highlight, outset-shadow(1), 12px, radius 3; checked fill `accent` |
| `card` | fill `bg 1`, highlight full, ring 1px black 0.1, shadow(2); collapsed shadow(1) |
| `popover` | fill `bg 2`, border 1px `borders`, highlight full, shadow(2), radius 6; a submenu shadow(3); rows 6x12, hover fill fg 0.15 |
| `tooltip` | fill BLACK_700 0.9, shadow(1), radius 3, padding 6, white ink with 0 1px 2px black 0.6 text shadow |
| list row selected or focused | fill fg 0.15 |
| `window` focused | ring 1px `borders`, shadow(4), radius 6; backdrop shadow(2); maximized none |
| `dialog` | highlight full, ring 1px `borders`, shadow(3) |

Motion (`_animate.scss`): open 250, close 200, expand 300, collapse 250,
in-place 100, all on `cubic-bezier(0.4, 0, 0.2, 1)`. Gala
(`lib/Constants.vala`): open 350, close 195, hide 200, menu map 150, snap
250, workspace switch 300 to 400. These become the pantheon entries of the
motion table; the two clock families stay, the numbers change.

### The shell surfaces, off `wingpanel`, `notifications`, `gala`, `dock`, `applications-menu`

**Bar (`bar.kind: wingpanel`).** No strip card, no hairline, no ghost
cells with borders. The panel is a band whose paint is decided by what is
under it (`wingpanel-interface/BackgroundManager.vala`): the wallpaper band
under the panel is sampled for mean luminance, its standard deviation and
acutance. Busy (std over 45, or acutance over 8, or mean under 180 with
mean + 1.645 std over 180) gives a translucent panel, black 0.3 with a
`0 1px 3px black 0.15, 0 1px 1px black 0.3` cast under it, or white 0.5
with white 0.15 and 0.03 inset lines when the user prefers light. Calm and
bright (mean over 180) gives dark ink on nothing; calm and dark gives light
ink on nothing. Any maximized or fullscreen window on the output makes it
solid `#000`. Ink is white bold with `0 0 2px black 0.3, 0 1px 2px black
0.6` on a dark band, black 0.65 with white shadows on a light one.
Indicators are `0.25rem` margin, `0 0.5rem` padding, radius 3, and an open
one fills `highlight` 0.6 (white 0.3 on the maximized panel). Layout stays
the three regions: launcher left, clock centre, indicators right, which is
wingpanel's own order. The sampling runs in `ThemeEngine` off the wallpaper
it already holds plus Hyprland's fullscreen state the `--fullscreen` leg
already reads, and publishes `bar.paint` as one of `light`, `dark`,
`translucentLight`, `translucentDark`, `maximized`. `bar adaptive` in the
`debug` dump reports the numbers.

**Popovers (`emerge: popover`).** A panel is a `popover` box, radius 9
(wingpanel's indicator popovers are `0.75rem`), at least `20rem` wide,
`0.5rem` off the bar, dropping straight down from its cell: fade plus a
short travel on Gala's 150ms menu map, with no shoulders and no gap
opened in the line. The keyboard model and the `panel` IPC are what they
are under metamorphosis.

**Notifications (`notification.layout: bubble`).** The elementary bubble
(`notifications/data/application.css`, `src/AbstractBubble.vala`): 332
wide, radius 9, fill `bg 1` at 0.8, `0 0 0 1px borders, 0 1px 3px black
0.2, 0 3px 9px black 0.3` plus the highlight lines, 16px in from the
output's corner, icon left with a 6px column gap, bold title, body at 33
characters, a round close button that appears on hover, 4s timeout and
never for urgent, a flip-in over 400ms (opacity and an x rotation from 90
degrees, dipping to -10 at 60%), and restacking on an ease-out-back 200ms
with a 150/n stagger. Optional `notifications.sound` through canberra
(`dialog-information`, `dialog-warning` for urgent, the category map for
the rest), off by default.

**Launcher (`launcher.default: grid`).** Slingshot: 5 by 3 pages of 64px
icons with 16-character labels, arrows moving the cursor across pages,
search on top. `menu.appGrid` already draws this; the theme only makes it
the default route.

**Window switcher (`switcher: on`).** Gala's Alt+Tab
(`lib/Widgets/AbstractSwitcher.vala`, `WindowSwitcherIcon.vala`): a card
of `bg 2` at 0.6 over compositor blur, 1px `borders`, radius 9, an inner
highlight stroke inset 1.5 at radius 8 and 0.3, 12px padding, 64px icons on
a 3px-radius cell, the selected one on an `accent` fill, the caption under
the row, at least 64px off the output's edges. A new surface,
`Surfaces/Switcher/`, summoned by `switcher next|prev|commit` over IPC so
the compositor bind drives it, drawn from Hyprland's client list, released
on the modifier's release the way `hotcorner_relock` already reads keys.

**OSD.** Pantheon has none: volume keys open the indicator's popover with
a 175px scale. Ours stays, as an `.osd` box (black_500 0.9, radius 6,
shadow(1)), since a tiling desktop wants the readout without a pointer.

**Scrim.** Gala's modal group dims at 125/255. Ours is 0.5. Unchanged.

**Dark schedule.** `prefer-dark-schedule: sunset-to-sunrise` with a
20:00 to 06:00 fallback when there is no location. `theme.mode: "auto"`
flips the mode on sunrise and sunset off the Weather module's location,
with that fallback; the crossfade already exists.

**Windows.** Published into `formalshell-chrome.conf` beside `$rounding`
and `$blur`, read by the dotfiles' Hyprland config: rounding 6, a 1px
`borders` frame, and `shadow(4)` as Hyprland can draw it (`range` 24,
`render_power` 3, `offset` 0 6, colour black 0.35; backdrop windows
`shadow(2)`, range 8, offset 0 3, black 0.25). Under `metamorphosis` the
shadow stays off, so the file grows keys and no host changes look until it
switches preset.

### What Pantheon has that this mode drops, and why

The dock (pointer-driven, tiling has no floating windows to park), the
multitasking view (hyprexpo), pointer hot corners as the way in (ours stay
as they are), the headerbar-tinted windows (CSD is the app's business),
the accent picked from the wallpaper by nearest of eleven named hues
(matugen's `primary` already answers it; `theme.accent: "named"` snapping
to elementary's eleven is a later option).

## Configuration

```jsonc
{ "theme": { "preset": "pantheon" } }
```

Scalar keys keep their meaning under every preset. New keys, all read
through the table or `Theme`, none by a surface: `theme.mode: "auto"`,
`notifications.sound`. `theme.depth` from the spike is removed.

## Nix side (`users/kyandesutter/mixins/elementary/default.nix`)

- `programs.formalshell.settings.theme.preset = "pantheon"` (landed).
- The Hyprland decoration block reads the new `$shadow*` keys from
  `formalshell-chrome.conf` instead of hardcoding `rounding = fsRadius`.
- `sound-theme-freedesktop` on the path when `notifications.sound` is on.
- The GTK recolour and the icon theme are untouched; they are already the
  Pantheon half of the desktop.

## Verification

- Part 1: the parity diff above, plus unit tests for the table walker,
  for every layer kind `Box` draws, and for each primitive resolving its
  role and state.
- Part 2: `--pantheon` rider (exists) over `--gallery`, `--panel`,
  `--notify`, `--menu`; new legs `--bar-adaptive` (four wallpapers, four
  paints read off the dump and the frame), `--switcher` (three fixture
  windows, next and prev over IPC, the accent cell moving), and
  `--notify` under the bubble layout reading the flip-in's frames.
- Both hosts rebuilt onto main once the plan lands; the spike branch and
  its `--override-input` go away with it.

## Build order

1. `Box` and the metamorphosis table, primitives migrated, parity diff
   green.
2. The pantheon table: chrome only, `--pantheon --gallery` read by eye
   against elementary's own widgets on e1504g.
3. Habits, one per task: popover emerge, wingpanel bar with the adaptive
   paint, bubble notifications, grid default, the switcher, the dark
   schedule, the window chrome keys.
4. Nix: the decoration block, the sound theme; rebuild e1504g, then g815.

## Risks

- `MultiEffect` per cast layer: a `shadow(4)` is three casts. Cheap on the
  hosts' GPUs, slow under the VM's llvmpipe, so smoke legs read layer
  counts and frames, never timing.
- The wallpaper sampling is a read of the wallpaper's own pixels, which
  `ThemeEngine` has, not a screen capture (`LockSurface.qml`'s header:
  never `ScreencopyView`). Windows under the bar are not sampled; that is
  wingpanel's own compromise too, which is why it goes solid on maximize.
- The switcher is the one new input surface: it takes the keyboard only
  while open, through the same `KeyCatcher`, and never grabs the modifier.
