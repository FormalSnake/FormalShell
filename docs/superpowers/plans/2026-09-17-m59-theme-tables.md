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
