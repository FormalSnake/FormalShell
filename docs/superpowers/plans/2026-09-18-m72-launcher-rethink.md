# M72: the launcher, rethought

Owner, 2026-09-18: the launcher is not consistent with the rest of the
shell (not even its separators and buttons) and feels buggy while typing
and navigating. One layout and one behaviour for every theme; a theme
changes styling (table roles), bar position and motion, nothing else. The
app grid is the default everywhere. DESIGN.md is stale and is not the
yardstick: consistency means drawing through `shell/Components/` and the
`Theme.box()` roles, the way `Components/Panel.qml` does, so the launcher
is right under metamorphosis, retro and pantheon alike.

Evidence the plan is built on (read-only investigations, 2026-09-18):

- Root cause of the input bugs: the cursor is an index into
  `_displayRows` shared by five views, each fed differently (a keyed
  ListModel synced a tick late through `Qt.callLater`, fresh JS arrays for
  the three grids and the app grid's tail rows), each following the cursor
  its own way, and nothing re-asserts a view's `currentIndex` after a sync
  or re-derives the cursor when rows change for any reason but typing.
- Chrome: 27 hand-rolled sites. Two raw-Rectangle rules
  (`Menu.qml:2493`, `MenuRow.qml:146`), three cursor fills in three
  shapes, two raw hover fills, a hand-made search field with no
  `input.selection`, clickable text instead of `Button`, five radius
  overrides beating the table, `SectionLabel` used for values.
  `dev/check-primitives.py` does not scan `shell/Surfaces/Menu` at all.

## T1: one cursor, one row pipeline (the typing and navigation bugs)

- The cursor is a row id, not an index. It is re-derived whenever the
  row list changes for any reason (typing, a `when` condition resolving,
  clipboard or window churn, keybinds refresh): keep the same row if it
  survives, else clamp, else row 0 on a new query.
- One sync step, synchronous, run for the view that is on screen only.
  After it, every view's `currentIndex` is set from the cursor in the same
  step. No `Qt.callLater` deferral between what is drawn and what Enter
  acts on.
- Grid and tail models are keyed like the row list, never a fresh array
  per keystroke, so a cell survives a re-rank and the grid keeps its
  scroll. The emoji grid likewise (3,944 rows must not be re-appended on
  every key).
- The view kind is stable within a level: typing never flips the root
  between the grid and the row list, and `levelEnter` fades only when the
  LEVEL changes. A query with no app hits shows the grid's own empty
  section over the tail rows. `:e` followed by a letter does not swap the
  view twice.
- Keys. Up/Down/Left/Right navigate the results (grid cells, then the
  tail rows). Ctrl+Left/Right move the text caret by word and
  Ctrl+Backspace deletes a word, so a typo is fixable while the grid owns
  the arrows. Grid wraps keep the column (`Menu.qml:1821`). PageUp/Down
  move a page, Home/End go to the first/last result. Tab never leaves the
  field. Backspace on an empty query pops one level per physical press,
  never on auto-repeat. Escape clears a non-empty query first, then pops,
  then closes.
- Pointer. The hover wash is gated by the same `PointerMoveGate` as the
  cursor, so a row sliding under a parked pointer is not lit. A keyboard
  scroll cancels a running wheel glide (`WheelScroll.qml:48`).
- Open. The previous session's rows do not animate in; the root arrives
  settled with the cursor on row 0 and focus in the field.
- `menu status` reports the cursor id and each live view's
  `currentIndex`, so the rig can assert they agree.

Verify: `just vm-test`; `dev/vm-lock.sh just vm-smoke --menu --app-grid
--emoji --picker --wheel`, reading every PNG; new tests for the cursor
re-derivation, the wrap arithmetic and the key policy.

## T2: the grid is everyone's default

Delete the `launcher` habit (`style.js` HABITS, every table, `Theme.habit`,
`appgrid.js`'s `defaultFor`): `menu.appGrid` defaults true for every theme
and stays a user key. Tests and the `--app-grid` leg's text follow.

Verify: `just vm-test`; `vm-smoke --app-grid` and `--retro --app-grid`.

## T3: split Menu.qml by responsibility

`Menu.qml` is 3,248 lines. Move the data providers out (emoji data, nix
search, keybinds, wallpaper picker scan and select token, selection-file
IPC, paste-after-close, launch watch) into their own files under
`shell/Surfaces/Menu/` or `shell/Services/`, and the inline views (row
list, picker grid, emoji grid, split preview) into `views/` beside
`AppGridView.qml`. No behaviour change; T1's tests and legs are the proof.

## T4: the chrome, through the primitives and the table

- One launcher row on `Cell` (ghost at rest, the table's `selected` for
  the cursor, `destructive` for an armed confirm), shared by `MenuRow`,
  the grid's tail rows and the monitor's process table. One cursor
  treatment across every view: the `cell` role's `selected` state,
  travelling, radius from the table.
- The layout is Raycast's, kept plain (owner, 2026-09-18: "I like
  raycast on macos but I also appreciate simplicity"). Three bands, each
  full-bleed and split by a `Separator`:
  1. Header: inside a level, a back chip carrying the level's icon and
     name (click or Backspace on an empty query pops it); then the
     search field itself as the header, borderless, one type step above
     body, placeholder in muted ink; then the close `IconButton`. The
     field reads the `input` roles (`input.selection` at least); if a
     borderless field needs a role, it is added to all three tables.
  2. Body: sections, each a `SectionLabel` heading (sentence case, muted,
     no rule) over its rows or cells. At root the app grid is the first
     section, "Applications", and the command rows follow under their own
     headings. A row is icon, title, a muted subtitle after it, and a
     right-aligned muted accessory naming what the row is ("Application",
     "Command", a route's shortcut prefix) or its value.
  3. Footer: the current level's icon and name on the left; on the
     right the primary verb as a `Button` with its key as a keycap, then
     the secondary verbs' key legend. No other chrome.
- The card is a fixed size per level kind (the grid root, a row list, a
  split with preview), never resized by typing: results scroll inside it.
  Its size morphs only on a level change, on the theme's own clock.
- Nothing else: no hint strips, no breadcrumbs beyond the back chip, no
  per-view headers (the monitor's own header row folds into its
  sections).
- Every rule is `Separator`. A section heading is a `SectionLabel` alone,
  never a rule plus a label. Values are never `SectionLabel`s.
- The footer's primary verb is a `Button`; the key legend stays text.
- Picker, emoji and app cells are one tile component on `Cell`; no radius
  override anywhere, the table decides. Column counts and height caps
  become named tokens.
- Provider empty states are sentence case and not cursor targets.
- `shell/Surfaces/Menu` joins `dev/check-primitives.py`'s `SCANNED`, and
  every hit is fixed rather than exempted.

Verify: `just vm-test`, `just vm-lint`, and the T1 legs under each theme
(`--pantheon`, `--retro`, default), every PNG read.

## T5: the monitor view on the same row and controls

MonitorView's process rows take T4's row, its cursor and hover go through
the table, the sort control becomes a `Segmented`, column headers stop
being recoloured `SectionLabel`s, the kernel chip stops being one.

Verify: `just vm-test`; `vm-smoke --monitor --processes` under all three
themes.
