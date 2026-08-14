# FormalShell M24: a positional bar chevron, replacing the tray's own buckets

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-14), immediately after M23 shipped:** "the
chevron is not what i expected. I want the chevron to show/hide bar items
that shouldn't always show, and the chevron in of itself is an item so it can
be changed position."

Two follow-up decisions, both the owner's, both binding here:

1. **Hide rule: by position.** The chevron is a boundary, not a toggle over a
   named set. Everything after it in its own region collapses. Moving it in
   `bar.layout` is the only control. No per-widget config key.
2. **The tray's per-icon buckets are replaced, not kept.** M23's
   pinned/drawer/hidden manager comes out. The tray becomes an ordinary bar
   widget that can sit behind the chevron like any other.

This supersedes M23's Task 3 entirely. M23's Tasks 1 and 2 (icon-only
widgets, single-line clock) stand and must not be touched.

## Context

M23 (commit `a9be440`, already pushed to main and live on g815 and e1504g)
built Bartender at the wrong altitude: inside the tray, over SNI item ids.
The owner wants it at the bar level, over widgets. The tray's own `+N`
overflow chevron is the second chevron that made the concept ambiguous, so it
goes too.

Removing the tray's grouped drawer is a deliberate **spec deviation**. Spec
§Surfaces-1 says "SNI tray (grouped drawer)", and `Tray.qml`'s header argues
for the 4-item limit as protection against "an unbounded strip of icons".
Under M24 that protection is generalized rather than deleted: a user with a
large tray places the chevron before it and the whole tray collapses. Record
this in the plan and in `Tray.qml`'s header. It is an owner decision, the same
class as the `panel` IPC addendum.

## Constraints

- All CLAUDE.md hard rules stand: radius 0, no blur, no shadows, border
  width 2, fontconfig `monospace` alias, Nerd Font glyphs, pure QML/JS.
- ⚠️ `Tray.qml` and every bar widget carry raw multi-byte Nerd Font
  codepoints. Targeted `Edit` only, never a whole-file `Write`.
- Compositor and SNI ids stay opaque strings.
- The shell never writes `settings.json`. Collapse state goes to
  `state.json`.
- Do not touch `Bar.qml`'s `PanelWindow`, anchors, or exclusion zone. The
  whole-bar hide toggle remains explicitly out of scope by owner instruction.
- Honest unavailable states: a chevron with nothing after it is a dead
  control and must not render (see Task 2's warning path).

## Task 1 — Remove M23's tray buckets

Delete outright:

- `shell/Tray/model.js`
- `tests/tst_tray_model.qml`
- `shell/Surfaces/Bar/widgets/TrayManagePanel.qml`

Revert to a plain strip:

- `shell/Surfaces/Bar/widgets/Tray.qml` — drop the bucket resolution, the
  `_visibleLimit`/overflow arithmetic, the `+N`/`−N` chevron cell, the
  right-click manage binding, the `TrayCollapseGate`, and the auto-collapse
  `Timer`. What remains is the `Repeater` over `SystemTray.items` rendering
  one `Cell` per item, with the existing left/middle/right click handling and
  `QsMenuAnchor` context menu kept exactly as they are. Keep the live
  `ObjectModel` binding and its header comment: the reason it must not become
  a `.values` snapshot is unchanged by any of this.
- `shell/Services/TrayService.qml` — the singleton's whole reason for
  existing was shared drawer state. With no drawer, delete the file and its
  `qmldir` entry, and remove every import of it.
- `shell/Ipc/TrayIpc.qml` — remove `pin`, `unpin`, `hide`, `show`, `manage`,
  `expand`, `collapse`. Keep `status` (now just the item list) and
  `activate`. `status`'s shape becomes
  `{"items":[{"id","title","hasMenu"}]}`.
- `shell/Core/State.qml` — remove `trayPinned`/`trayHidden` and
  `setTrayBuckets`.
- `shell/Core/Config.qml` — remove the `bar.tray.pinned`/`bar.tray.hidden`
  block.
- `shell/Components/TrayCollapseGate.qml` — check for remaining callers
  first with `rg`. Delete only if this was its sole consumer.

`shell/Components/PanelOpenDot.qml`'s negative-margin fix from M23 stays. It
is about bar height, not the tray.

## Task 2 — The chevron widget

**`shell/Bar/layout.js`** (pure, already the tested resolver):

- Add `"chevron"` to `BUILTIN_WIDGETS`. It is NOT in `DEFAULT_LAYOUT`: the
  no-config bar must stay byte-identical, same rule the seven opt-in
  builtins already follow.
- Annotate every resolved entry with `region` (the region it resolved in)
  and `collapsible` (true when a chevron appears earlier in that same
  region's resolved array).
- One chevron per region. A second in the same region is dropped with a
  warning: `bar.layout.<region>: only one chevron per region`.
- A chevron that is last in its region collapses nothing, so it is dropped
  with a warning: `bar.layout.<region>: chevron has nothing after it`. A dead
  control that renders a cursor and hides nothing is exactly the failure M23
  already hit with its empty drawer.
- These rules are pure functions over the resolved arrays. Extend
  `tests/tst_bar_layout.qml` (find its real filename with `rg --files
  tests/`) to cover: no chevron leaves every entry `collapsible: false`; a
  mid-region chevron marks only the entries after it; a trailing chevron is
  dropped with its warning; a second chevron is dropped with its warning; a
  chevron in one region does not mark entries in another.

**`shell/Core/State.qml`**: `barCollapsed`, an object keyed by region,
defaulting `{"left": true, "center": true, "right": true}`. Collapsed is the
default, matching Hidden Bar and Bartender, so adding a chevron to the layout
visibly does something on first run. One `setBarCollapsed(region, collapsed)`
writer following the existing single-write shape.

**`shell/Surfaces/Bar/widgets/ChevronWidget.qml`** (new): a `standalone` Cell
like every other widget, one Nerd Font chevron glyph, click toggles its own
region's collapse state through `State`. Region-aware glyph direction: the
glyph points toward the collapsed group, so in a right region it is
right-pointing while collapsed and left-pointing while expanded, mirrored in
a left region. Use `nf-md-chevron_left` (U+F0141) and `nf-md-chevron_right`
(U+F0142); confirm both are in the pinned nerd-fonts-jetbrains-mono cmap
before shipping, the same check M23 ran. `tooltipText` names the action and
the count, e.g. `BAR / SHOW 4` and `BAR / HIDE 4`.

**`shell/Surfaces/Bar/Bar.qml`**: register the component in
`_builtinComponents`, and gate the region delegate. The delegate currently
reads (`Bar.qml:314-316`):

```qml
visible: entryLoader.item
    ? (entryLoader.item.shown !== undefined ? entryLoader.item.shown : true)
    : false
```

⚠️ Read the delegate's header comment at `Bar.qml:288-306` before touching
this. It documents, from a reproduced bug, that binding to a Loader-hosted
item's built-in `visible` permanently detaches that item's own `visible`
binding, which is why `shown` exists as a second channel. Add the collapse
gate as an additional term on `entryLoader.visible` itself. Do not route it
through `item.shown`, and do not read `item.visible`.

**`shell/Ipc/BarIpc.qml`** (new target, a spec addendum in the same class as
`panel`): `chevron toggle|expand|collapse [region]` and `chevron status`.
Region optional: with exactly one chevron in the layout it is inferred; with
more than one and no argument, return an error naming the regions rather than
guessing. `status` returns each region's chevron presence, collapsed state,
and the names it is hiding. Without these routes the feature cannot be
verified headlessly at all, since the rig has no synthetic pointer. Register
the target wherever the other `*Ipc.qml` singletons are registered.

**`shell/Core/Config.qml`**: document `chevron` as a `bar.layout` entry name,
including that its position is the whole configuration and that collapse
state lives in `state.json`.

## Task 3 — Verification, screenshots, docs

**`dev/smoke-niri.sh`:**

- Rework the existing `--tray` leg: drop the pin/hide/manage legs and their
  assertions and the `tray-manage.png` capture, and drop the `tray expand`
  call. With six stubs and no drawer, assert `tray status` reports all six
  items and screenshot the full strip. Restore `screenshot_delay` for
  `tray_mode` to a budget that matches the shortened drive script; M23 raised
  it to 24 for legs that no longer exist. Getting this wrong is a false
  failure, not a slow test: the kill script takes the stubs down before niri
  quits, so a drive step landing after the delay reads an empty item list.
- Add `--chevron`: write a `settings.json` fixture placing `chevron` mid
  right-region, screenshot collapsed (`chevron-collapsed.png`), call
  `bar chevron expand` over IPC, screenshot expanded
  (`chevron-expanded.png`), and dump `bar chevron status` both times. Assert
  on the JSON, not just capture it: the collapsed dump must list the hidden
  names and the expanded dump must show the same names no longer hidden.
  Both PNGs need a `SMOKE_CHEVRON_*` marker line or `dev/vm.sh` will not pull
  them back to the mac, which M23 got wrong once already.

**Docs:** rewrite the tray/chevron sentences in `docs/DESIGN.md` §3's Bar
bullet that M23 added, update `CLAUDE.md`'s `--tray` bullet and add a
`--chevron` one, and record the grouped-drawer spec deviation in
`Tray.qml`'s header.

**Screenshots:** refresh `docs/screenshots/tray-niri.png`, delete
`docs/screenshots/tray-manage-niri.png` (its surface no longer exists), and
add `chevron-collapsed-niri.png` / `chevron-expanded-niri.png`.

## Acceptance

- `just vm-build`, `vm-test`, `vm-lint` green, output read.
- `vm-smoke --tray` and `vm-smoke --chevron` green, every PNG read.
- A `settings.json` with no `bar` key renders exactly today's arrangement,
  with no chevron anywhere.
- `rg -n 'TrayService|TrayManagePanel|Tray/model' shell/` returns nothing.
