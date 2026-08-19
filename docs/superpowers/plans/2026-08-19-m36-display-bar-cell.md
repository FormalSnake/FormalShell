# FormalShell M36: display bar cell

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Origin, owner ask (2026-08-19):** after M33 moved brightness into the
display panel, "add it to the bar on both machines" — the display panel
has no bar cell, so it was reachable only over IPC/keybinds while
omarchy's own monitor panel opens from its bar.

## Constraints

- Clone the established opt-in widget shape (M29's `AirpodsWidget` /
  `BluetoothWidget` are the templates): a `Cell.standalone` bar cell,
  cmap-verified Nerd Font display/monitor glyph, no value text (the
  panel is consult, not glance — the cell carries no number), click →
  `panel.toggleFrom(root)`, `PanelOpenDot` inverted-aware,
  `bar.widgets.display.showLabel` respected, ⚠️ `import qs.Core as
  Core` for any `State` access.
- Wiring per the four-edit checklist: widget `Component` +
  `_builtinComponents.display` in `Bar.qml`, `displayPanel` property
  threaded from `shell.qml`, `BUILTIN_WIDGETS` gains `display` as
  opt-in, NOT in `DEFAULT_LAYOUT` (default bar stays byte-identical).
  The panel instance and its `display` registry entry already exist.
- Always visible when placed (the cell has no absent state to hide on:
  a session always has at least one output).

### Task 1: widget, wiring, smoke, docs

**Files:** create `shell/Surfaces/Bar/widgets/DisplayWidget.qml`;
modify `shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`,
`shell/Bar/layout.js`, `tests/tst_bar_layout.qml` (the opt-in
assertion, mirroring airpods'), `docs/USAGE.md`.

**Produces:** the cell per the constraints; the `--panel display` smoke
leg's settings fixture leads its bar layout with `display` so the same
run screenshots the cell (open-dot lit while the panel is open); USAGE
documents the widget. Verify: `just vm-test`, `just vm-lint`,
`just vm-smoke --panel display` — Read the PNG (cell present, dot lit,
panel anchored under it if anchorX applies). Commit
(`feat(bar): display cell`).

## Review checkpoint

Orchestrator-reviewed (single small task): diff read in full, glyph
verified against the cmap, no DEFAULT_LAYOUT change, smoke PNG read.
