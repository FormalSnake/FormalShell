# M44: toasts, notification centre, OSD, tooltip anchor

**Date:** 2026-08-25
**Status:** implemented 2026-08-25
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
("Toasts", "Notification centre", "OSD", "Tooltip", "Keyboard model");
`docs/DESIGN.md` §3. Spec wins on conflict.
**Builds on:** M41 primitives, M42's `Panel` cursor model.

## Why

The sonner stack is the one surface the owner asked to keep as built; its
cards, the notification centre, the OSD and the tooltip still wear the
ledger chrome. The centre is also the last `CardTitleBar` consumer, and the
notification IPC still lacks `dismissOne`.

## Scope

In: `Surfaces/Notifications/{Toasts,NotificationCard,Center}.qml`,
`Surfaces/Osd/Osd.qml`, `Components/Tooltip.qml` anchoring,
`Components/Switch.qml` (new primitive, DESIGN.md §2), `Components/CardTitleBar.qml`
deletion, `Ipc/NotificationsIpc.qml` `dismissOne`, rig legs `--notify`,
`--center`, `--osd` on `dev/smoke.sh`, docs. Out: notification data flow,
`model.js` positions, the OSD trigger graph.

## Locked decisions

- D1: M42 D1's exit checks on every file touched.
- D2: the stack's behaviour (depth stack, integer `Theme.space` step
  narrowing, critical wins the front, expand on hover and over IPC) does
  not change. `NotificationCard` is a `Card` `radiusXl` with app icon or
  `bell` `Icon`, app name as a `SectionLabel` with the time in mono after
  it, summary sans `medium`, body sans `mutedForeground` two lines max,
  actions as `outline` `Button`s in a row, close as an `IconButton`.
  Critical: `destructive` 1px border and a `triangle-alert` icon in
  `destructive`; no fill. Normal and low differ by nothing but the icon.
- D3: `Center.qml` is a right-anchored full-height `Card` with only its
  left `border`, `popupWidthWide`; header row: title sans `semibold`, DND
  as a `Switch`, `Clear all` ghost `Button`; `PENDING (n)` / `SEEN (n)`
  sections; rows as D2 cards at `radiusMd`; unread rows carry a 6px
  `primary` dot before the summary. Keyboard through a `KeyCatcher`:
  Up/Down cursor, Enter invokes the default action, `x` dismisses,
  `d` toggles DND, Escape closes. `CardTitleBar.qml` and its `qmldir`
  entry are deleted here.
- D4: `Switch.qml`: 32x18 `radiusFull` track, `muted` off / `primary` on,
  `background` knob with `Theme.motion.fast` slide, `cursor` ring,
  `checked`, `toggled(bool)`.
- D5: `Osd.qml` is a bottom-centre `Card` `radiusXl` pill: `Icon`
  (`volume-2`/`volume-x`/`sun`/`mic`), a `Track` `popupWidthNarrow` minus
  padding wide, the percent in mono `bodySmall`; same show/hide timing.
- D6: `Tooltip.qml` anchors to the cell that owns it in any window (panel
  headers included), `Theme.space.md` below or above when there is no room,
  and no longer suppresses itself while a panel is open. M41 Task 3's
  report names the constraint; fix it here.
- D7: `notifications dismissOne` drops the front popup; documented next to
  `dismissAll`.

## Tasks

### Task 1: toasts

`Toasts.qml`, `NotificationCard.qml`, tests (`tst_toasts*`,
`tst_notification*`). D2. Verify `just vm-smoke --notify` (port the leg to
`dev/smoke.sh` if missing; it exists there since M41), both PNGs read.
Commit: `feat(notifications): shadcn toast cards on the sonner stack`.

### Task 2: centre, switch, dismissOne

`Center.qml`, `Switch.qml` + `qmldir`, `CardTitleBar.qml` deletion,
`NotificationsIpc.qml`, tests (`tst_switch.qml` new). D3, D4, D7. Verify
`just vm-smoke --center` (port the leg), PNG read.
Commit: `feat(notifications): centre on the shadcn primitives, dismissOne`.

### Task 3: OSD, tooltip, docs

`Osd.qml`, `Tooltip.qml`, tests, `docs/USAGE.md` (notification keys,
`dismissOne`), `docs/ARCHITECTURE.md` notification and OSD sections where
names changed. D5, D6. Verify `just vm-smoke --osd` (port the leg), three
PNGs read, plus `--panel network` re-shot with the pointer parked on a
header button if the rig can park it; if not, say so.
Commit: `feat(osd): shadcn pill, tooltip anchoring`.

## Done when

Three commits in, files pass D1, `--notify`/`--center`/`--osd` green with
PNGs read, `CardTitleBar` gone, `just test` and `just vm-lint` pass.

## Landed

1. `c8738e1` feat(notifications): centre on the shadcn primitives, dismissOne
2. `18d5689` feat(osd): shadcn pill, tooltip anchoring
3. `f470e22` fix(dev): keep the osd and tooltip flags ahead of the usage case
4. `10c72f3` fix(dev): terminate the centre drive script heredoc
5. `882249f` feat(notifications): shadcn toast cards on the sonner stack
