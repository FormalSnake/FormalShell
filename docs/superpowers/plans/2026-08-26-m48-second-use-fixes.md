# M48: fixes from the second live session

**Date:** 2026-08-26
**Status:** approved, pre-implementation
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict). `docs/DESIGN.md` is the rulebook.

## Owner's list (2026-08-26)

1. Panels need Omarchy's buttons: icon buttons and horizontally stacked
   button rows (the power panel's profile row is the example).
2. Focus rings get clipped by their containers. Never.
3. Some panels (the notification centre) are taller than the screen; cap
   every surface at the screen height minus its padding.
4. Every panel's position respects a padding around the screen.
5. Notification icons do not show.
6. The emoji route is a grid.
7. The launcher reads more like shadcn's cmdk and Omarchy's menu.

## Locked decisions

- D1 `ButtonGroup`: a new primitive, a horizontal row of `Button`s sharing
  one `muted` trough at `radiusMd` (segmented look, one `selected` at a
  time when `exclusive`, plain buttons otherwise), each button an optional
  `Icon` plus a sans label, `controlHeight` tall, Left/Right through the
  owner's `KeyCatcher`, Enter presses the cursor button, ring on the
  cursor button. Omarchy quattro's `shell/Ui/ButtonGroup.qml` and
  `PanelActionButton.qml` and its power panel are the read-only reference
  for which controls become groups: power profiles, audio output/input
  pick, bluetooth power/scan, network wifi power, display enable/mirror,
  media transport where a row of icon buttons already exists. Rows that
  are lists stay lists.
- D2 rings never clip: the ring halo (`ringWidth` outside the border) is
  drawn inside the item's own bounds by insetting the item's visible frame
  by `ringWidth` when it sits in a clipping container, or the container
  reserves `ringWidth` of padding on every side; whichever is chosen, it is
  done once in the primitive or the list container (`Cell`, `Button`,
  `WheelScroll`'s flickables, `Panel`'s content column, `Menu.qml`'s lists,
  `Center.qml`'s list) and never per surface. A test instantiates a ring
  cell at the edge of a clipping parent and asserts the halo's pixels are
  inside the parent.
- D3 screen padding: one token, `Theme.space.screenPadding` (12), is the
  distance from every screen edge for every floating surface: panels sit
  `barMargin` under the bar and `screenPadding` from the side edge; the
  notification centre sits `screenPadding` from the top (under the bar),
  right and bottom edges and is no longer full height; toasts and the OSD
  keep `screenPadding` from their edges; tooltips and the tray menu clamp
  to it. Every surface's max height is the screen height minus the bar and
  the paddings, and its content scrolls (`WheelScroll`) when taller.
- D4 notification icons: the card resolves, in order, the notification's
  `image-path`/`image-data` hint, its `app_icon` (a path or a themed icon
  name through Quickshell's icon lookup), the desktop entry of `desktop-entry`
  or the sender name, then the `bell` `Icon`. The rig proves it with
  `notify-send -i` on a fixture PNG and on a themed name that exists in the
  VM, read off the toast frame.
- D5 emoji grid: the emoji route renders as the picker-style grid (8 or so
  columns of `radiusSm` cells, the glyph at `heading` size, the name in a
  tooltip or under the cursor cell), search narrows it, arrows move in two
  dimensions, Enter copies and pastes as today, the frecency/recent row
  stays as a first section.
- D6 cmdk: the launcher's list is inset by `Theme.space.xs` inside the card
  and its rows are `radiusSm` items (shadcn's `cmdk` item: `rounded-sm`,
  `px-2 py-1.5`), the cursor row `accent`, groups get a `SectionLabel`
  heading (`Suggestions`, `Apps`, `Recent`, the route names) with a 1px
  `border` separator between groups, each row has its icon at 16px, label
  in sans, and a right-aligned hint in mono (`⌘K`-style chords for routes
  that have a keybind, counts for routes that list things), the input
  placeholder reads `Type a command or search...` at root and the route's
  own prompt inside it, the footer keeps its hints. Omarchy's menu tree
  and breadcrumb behaviour stay as they are.

## Tasks (parallel worktrees)

- Task A, launcher: D5, D6 (`Menu.qml`, `MenuRow.qml`, `views/`, emoji
  provider glue, `menu` rig legs, USAGE). Commit
  `feat(menu): cmdk rows and an emoji grid`.
- Task B, panels: D1, D2, D3 for panels and shared primitives
  (`ButtonGroup.qml`, `Cell`/`Button`/`WheelScroll`/`Panel` ring insets,
  `screenPadding` token, panel max height, the panels that take a
  `ButtonGroup`, DESIGN.md §2 row). Commit
  `feat(panels): button groups, unclipped rings, screen padding`.
- Task C, notifications: D3 for the centre, toasts and OSD, D4 (`Center`,
  `Toasts`, `NotificationCard`, `Osd`, `Tooltip` clamp, rig legs, USAGE).
  Commit `fix(notifications): icons, screen padding, capped centre`.

## Done when

All three commits are in, the rig legs for each surface are green with the
PNGs read, no ring is clipped in any of them, no surface exceeds the screen
minus padding, both boxes rebuilt.
