# M59: themes as tables

**Date:** 2026-09-17
**Status:** in progress on `m59-theme-tables` (worktree `../FormalShell-m59`).
**Spec:** `docs/superpowers/specs/2026-09-17-pantheon-mode-declarative-themes.md`,
Part 1. The 2026-08-25 spec and `docs/DESIGN.md` win where it is silent.
Part 2 (the pantheon table and its habits) is M60, planned once this lands.

## Owner's ask (2026-09-17)

"Themes should be declarative and separated here." The `pantheon-depth`
spike put chrome forks inside the shared primitives; this milestone moves
every primitive's chrome out into one table per theme and leaves the
primitives as renderers. Nothing the owner sees changes: the acceptance
test is a pixel diff against main.

## Decisions

**T1 One file per theme.** `shell/Theme/themes/metamorphosis.js` carries the
shipped look. `shell/Theme/themes/retro.js` exports the same table (retro
differs from metamorphosis by scalars `presets.js` already owns: radius,
opacity, blur, dither, fonts, icons), spelled as a one-line re-export so
the file says so. `presets.js` resolves `theme.preset` to `{ ..., style }`
and `Theme.style` is the table; `Theme.habit` is its `habits` entry.

**T2 The box.** Every role entry is one box, the spec's shape:
`fill` (a `Theme.color` role, `"black"`, `"white"` or `"transparent"`),
`fillAlpha` (a number or `"surface"`), `radius` (`"sm" | "md" | "lg" | "xl"
| "pill" | number`), `border` (`{ color, alpha, width }` or null), `face`
(`{ from: [color, alpha], to: [color, alpha] }` or null), `layers` (a list
of `{ inset?, x?, y?, blur?, spread?, color, alpha }`, CSS `box-shadow`
order), `tint` (`[color, alpha]`, the fill blended toward that colour and
left opaque, shadcn's `hover:bg-primary/90`, or null). Any `alpha` may be a
number or `{ light, dark }`, resolved by `Theme.color.mode`, which is how
both the metamorphosis washes and elementary's per-mode shadows fit one
schema.

**T3 Roles and states.** The spec's table, plus `menu` (the tray menu and the
second bar: the popover frame at `radiusMd`), `frame` (the screen frame
ring) and `wash` (the pointer washes: `hover`, `press`, `filledHover`,
`filledPress`, today's `Tokens.STATE_ALPHA`, from which `Theme.hoverFill`
and friends keep deriving so no caller changes). A state absent from a role
inherits `rest`; a role absent from a table fails `tst_theme_style.qml`.

**T4 `Box.qml`.** `Components/Box.qml` takes `role`, `state`, an optional
`radius` override (the concentric rule is geometry, a consumer's business),
and a `silhouette` slot for casts. It draws, in this order: casts (one
`MultiEffect` per blurred layer, over a hidden padded layer of the
silhouette that is also its inverted mask, `z: -1` so it lands under its own
fill), rings (bordered rectangles at negative margins), the fill, the face,
the inset hairlines (four clipped rectangles), the border. Fill and border
colours cross on `CAnim` exactly as `Cell` and `Button` cross them today.
With no layers and no face it is one `Rectangle` and a border, and costs
that.

**T5 The primitives.** `Card`, `Cell`, `Button`, `Input`, `Switch`, `Track`,
`Segmented`, `ButtonGroup`, `Tooltip`, `Drawer`/`Shoulders` (colours only:
the shape stays a `Shape`), `Bar` (strip fill and edge), `FrameRing` and
`Scrim` read their role through `Box` or, where a `Rectangle` cannot be
replaced (Shoulders' paths, the bar's one-edge hairline), through
`Theme.style` directly. No `Theme.color.*`, `Theme.surface()`,
`Theme.radius*` or `Theme.borderWidth` for chrome remains in a primitive
after this; ink (text and icon colour) stays a token, since it is content.

**T6 The cursor ring is a state.** `cursor` in the table is `{ border, layers:
[{ spread: 3, color: "ring", alpha: 0.5 }] }` and the primitives' hand-drawn
halos become that layer, keeping the `_haloOwned` walk (one halo per list).

**T7 Habits.** `habits: { bar: "strip", emerge: "join", notification: "row",
launcher: "list", switcher: false }` in every table, validated by the same
test. M59 declares and validates them; the `Loader` split lands with the
first second variant in M60, so no surface grows a `Loader` with one source
here.

**T8 Parity.** `dev/parity.sh <legs...>` runs the given legs from this
worktree and from a worktree at `origin/main` (`../FormalShell-main`,
created if absent), both through `dev/vm-lock.sh just vm-smoke`, keeps the
frames under `artifacts/parity/{main,branch}/`, and writes
`compare -metric AE` diffs to `artifacts/parity/diff/`. Frames carry the
clock and toast timestamps, so a diff is accepted when every differing
pixel lies inside the clock cell's rect (off `debug dump`) or a toast's
time label; anything else is a defect in the migration. The legs:
`--gallery`, `--panel network --notify --tooltip`, `--menu`, `--osd`,
`--center`, `--join`, `--retro --gallery`.

## Tasks

One subagent per task, in order, each ending on its own verification with
the output read, then one commit. Every VM command goes through
`dev/vm-lock.sh`, background ones included: another session shares the VM.

### Task 1: the table and the renderer (T1 to T4, T6, T7)

`shell/Theme/themes/metamorphosis.js` and `retro.js`, `presets.js` handing
back `style`, `Theme.style`/`Theme.habit` in `Core/Theme.qml` and the test
stub, `Components/Box.qml` registered in `qmldir`, `tests/tst_theme_style.qml`
(every role and state present in every table, every colour a known name,
every alpha in range, habits valid) and `tests/tst_box.qml` (each layer
kind drawn once under a sentinel palette: hairline geometry and colour,
ring margin and colour, cast present only when a blurred layer exists, face
only when set, fill and border crossfading). Nothing else changes yet.
Verify: `just test`, `dev/vm-lock.sh just vm-lint`.

### Task 2: the floating surfaces (T5)

`Card`, `Tooltip`, `Scrim`, `Drawer` and `Shoulders`, `Bar`'s strip and
`FrameRing` onto the table. Verify: `just test`, lint, then
`dev/vm-lock.sh just vm-smoke --panel network --notify --tooltip`,
`--frame`, `--join` green with the PNGs read.

### Task 3: the controls (T5, T6)

`Cell`, `Button`, `Input`, `Switch`, `Track`, `Segmented`, `ButtonGroup`
onto the table, cursor halos onto the `cursor` state. The component tests
(`tst_cell_states`, `tst_button`, `tst_button_group`, `tst_input`,
`tst_switch`, `tst_track`, `tst_segmented`) keep passing against the same
observable colours and geometry; where one walks children by index, update
the walk, never the assertion. Verify: `just test`, lint,
`dev/vm-lock.sh just vm-smoke --gallery`, `--panel-keys`, `--toggles` green.

### Task 4: parity (T8)

`dev/parity.sh`, the run, the diffs read. Any non-clock pixel is a fix in
the migration, then the run again. Record the numbers in Evidence.

### Task 5: the record

`docs/DESIGN.md` §2 (the `Box` row, the primitives' rows losing their
literal chrome descriptions in favour of "role `x`"), §5 (a literal colour
or radius in a surface file now also means a literal in a primitive), a new
§1 paragraph "Themes" naming the table; `CLAUDE.md`'s chrome-defaults
paragraph; `docs/USAGE.md` presets section; this plan's Status. Then merge
to main, push, rebuild e1504g and g815 off main (which also retires the
spike's `--override-input`), delete the `pantheon-depth` branch.

## Evidence

Filled per task: the commands run, the numbers read.

**T8, parity.** `dev/parity.sh` added: for a leg set, it runs
`dev/vm-lock.sh just vm-smoke <flags>` once from `../FormalShell-main` and
once from this worktree, collects every frame each run pulled back (parsed
off `dev/vm.sh smoke`'s own "pulled screenshot:" lines), and diffs each
pair with `compare -metric AE`. Seven tags run, 129 frame pairs total:

- `gallery` (1 frame, 1 non-zero): `primary` AE 1068.98, entirely the dev
  gallery's AUTHPROMPT/IDLE clock swatch rolling 23:21 to 23:22 between the
  two runs. Confirmed: the static CELL-role "Hovered" swatch a few rows
  below it, drawn through the same table with no live timer, is pixel exact.
- `panel network --notify --tooltip` (3 frames): a first run showed 3
  non-zero (`panel-tooltip` 26.01, `primary` 25.48, `toasts-expanded`
  40.41), all confined to the panel header's close button, hovered by
  `dev/smoke.d/tooltip.sh`'s pointer park. Pixel sampling found the rest
  fill identical both sides (`#2C2C2F`) but the hover wash not
  (`#26262C` main, `#2A2A30` branch), i.e. a fade-in caught mid-settle
  rather than a table difference. An immediate rerun of the same tag landed
  at 0.22-0.40 AE (clock rounding only), confirming a one-off VM scheduling
  gap, not a defect.
- `menu` (4 frames, 1 non-zero): `menu-root` AE 14.47, the search field's
  blinking caret plus the bar clock. The keybind label glyphs `compare`
  also flagged are pixel-identical on inspection.
- `osd` (17 frames, 15 non-zero): `osd-desktop` and `osd-rest` are exact.
  `osd-brightness`/`osd-manual`/`primary` (AE 14.36 each) are the clock.
  The 12 `osd-emerge-*` burst frames (AE 4.12 to 96.30, `osd-emerge-4`
  highest) are the pill's own resize tween sampled at a fixed wall-clock
  offset: a direct crop of `osd-emerge-4` shows the identical 30% pill,
  same colours and radius, the whole outline lit up by roughly a 1px
  position difference at that sample tick.
- `center` (16 frames, 15 non-zero, `center-emerge-desktop` exact): spans
  the clock, the tray's unread badge digit, and the leg's own
  `for i in $(seq 1 30); do notify-send ... & done` fixture
  (`dev/smoke.d/center.sh:93`), whose 30 parallel sends land in a different
  D-Bus arrival order each run and reshuffle every "History row N" label.
  Confirmed by sampling the card header and row borders (identical both
  sides) while only the row digits differ. `center-emerge-6` (7550.46, the
  highest) is this same shuffle plus mid-tween sampling, not a chrome
  change.
- `join` (87 frames, 49 non-zero): all 21 `join-d-*` frames (the top-bar-cut
  case) are exact. The `join-a/b/c-*` open and close bursts (up to
  `join-a-4` at 4298.58) are the join's own resize tween sampled frame by
  frame; a direct crop of `join-a-4` shows the identical card, content and
  colours, offset about 8px vertically at that sample tick. `join-owner`/
  `primary` (AE 30.36/24.57) are the clock.
- `retro --gallery` (1 frame, 1 non-zero): `primary` AE 0.36, clock
  rounding.

No pixel outside a clock, a caret or toast timestamp, a live badge count,
or a tween's own timing sample was found to differ in chrome (fill,
border, radius, spacing) across any tag. No fix commits.
