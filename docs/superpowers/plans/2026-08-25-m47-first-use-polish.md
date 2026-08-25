# M47: polish from the first live session

**Date:** 2026-08-25
**Status:** implemented 2026-08-25 (rebuild of both boxes pending their return)
**Spec:** `docs/superpowers/specs/2026-08-25-shadcn-omarchy-redesign.md`
(spec wins on conflict; this plan amends its "Bar" paragraph, see D1).

## Why

The owner ran the redesign on both Linux boxes for the first time on
2026-08-25 and reported four things: nothing blurs, it is only
transparent; the wheel does not scroll the wallpaper grid, only the arrow
keys move; paddings are uneven between surfaces; the bar should be one
continuous shadcn strip, semi-transparent with blur, not floating pills.

## Locked decisions

- D1: the bar is one continuous strip: full width, `Theme.surface(card)`
  fill, a 1px `border` along its bottom edge, `barCellHeight + 2 *
  barMargin` tall with no side or top margins. Cells inside are ghost items:
  no fill and no border at rest, `accent` on hover, the `primary`
  open-panel underline, the workspace dots as they are. Groups keep their
  `sm` gap. The spec's "Bar" paragraph is amended to this; the pills are
  gone, not optional.
- D2: blur is the compositor's, and the owner's Hyprland config is the Lua
  API, so the layer rules go into `~/.config/nix`'s
  `users/kyandesutter/mixins/hyprland.nix` in that API's own form, looked
  up in the Hyprland wiki (Context7 or the wiki page for the Lua config),
  never guessed: blur plus `ignore_alpha` for `formalshell:bar`,
  `formalshell:panel`, `formalshell:menu`, `formalshell:notifications-center`,
  `formalshell:tooltip`. The example hyprlang config in this repo already
  carries the hyprlang form and stays the reference for non-Lua users. The
  shell side needs no change beyond D1's translucent strip.
- D3: the wheel scrolls every scrollable launcher view (rows, grid, split
  list, app view tables) and every panel list longer than its viewport;
  wheel over a slider row keeps adjusting the slider. The cursor does not
  follow the wheel.
- D4: one padding rule, applied everywhere and written into DESIGN.md §1:
  cards (`panelPadding` 12) inset their content; rows are `controlHeight`
  32 tall with `controlPaddingX` 12 and vertically centred content; a
  `SectionLabel` sits `sectionGap` 16 below the previous block and `rowGap`
  4 above its rows; icon and label are `iconGap` 8 apart; header rows are
  `controlHeight` tall with the same horizontal padding as the rows under
  them; the launcher's input row and footer use the same `controlPaddingX`
  as its rows; toasts, the OSD pill, the centre and the tooltip use the
  same numbers. Every literal or ad hoc margin that deviates is replaced
  with the token; measured on the rig's PNGs, not assumed.

## Tasks

### Task 1: blur wiring in the owner's nix config

D2. Files: `~/.config/nix/users/kyandesutter/mixins/hyprland.nix` only (a
separate repo; the owner's six uncommitted files there are not yours: stage
only that file). Verify the Lua form against the wiki and, if the VM can run
a Lua config, against `Hyprland --verify-config` there; otherwise say the
verification waits for the owner's box. Commit in that repo:
`hyprland: blur behind the formalshell surfaces`. Do not push, do not
rebuild.

### Task 2: wheel scrolling

D3. Files: `shell/Surfaces/Menu/Menu.qml` (rows, grid, split, app views),
`shell/Components/Panel.qml` or the panels' list containers, `Cell.qml`'s
`wheeled` path for slider rows, tests where a pure helper exists. Verify
on the rig with `wlrctl pointer scroll` (the rig's virtual pointer, see
`dev/smoke.d/tooltip.sh`) in a new `--wheel` leg: summon the wallpaper
grid, scroll, assert `picker status` or the grid's `contentY` moved and the
cursor index did not; screenshot before and after.
Commit: `fix(menu): scroll every list with the wheel`.

### Task 3: continuous bar

D1. Files: `Bar.qml`, `Cell.qml` (a `ghost` bool the bar sets, or the bar
cells' own chrome), the widgets that set cell chrome, `docs/DESIGN.md` §3
"Bar", the spec's "Bar" paragraph, `tests/tst_bar_layout.qml`,
`tst_cell_states.qml`. Verify base, `--wallpaper` (the strip is translucent
over the gradient), `--panel network` (the underline), `--chevron`
(collapse still works inside the strip), PNGs read.
Commit: `feat(bar): one continuous translucent strip`.

### Task 4: paddings

D4, after Task 3 merges. Audit every surface's PNG from the rig against the
rule (bar, every panel, launcher root/grid/split/app view, toasts, centre,
OSD, tooltip, lock, picker, polkit), list each deviation with the file and
line, fix them, re-shoot. `docs/DESIGN.md` §1 gains the padding rule as
written in D4. Commit: `fix(ui): one padding rule on every surface`.

### Task 5: screenshots and bump

Re-run the screenshot set from M46 Task 8 for the surfaces Tasks 3 and 4
changed (bar and anything with a padding fix), then push `main`, bump the
flake input in `~/.config/nix` (stage `flake.lock` only, plus Task 1's
file), and rebuild both boxes when they are on.
Commit: `docs: screenshots after the first-use polish`.

## Done when

Blur shows behind the bar, panels and launcher on the owner's boxes; the
wheel scrolls the wallpaper grid; the bar is one strip; every surface
measures to D4 on the rig's PNGs; both boxes rebuilt.
