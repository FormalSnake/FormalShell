# FormalShell M33: brightness moves from the power panel to the display panel

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. Runs after M32
> (shell tray menus); do not start implementation while another workflow
> holds the tree or the VM.

**Origin, owner ask (2026-08-18):** "i also like omarchy's display
widget. Move the display things from battery to display, it makes no
sense they were merged anyway." This overrules the recorded M16-era
decision in `DisplayPanel.qml:12-15` ("its BRIGHTNESS slider is
deliberately NOT here"): the backlight section leaves the power panel
and joins the display panel.

**State today (verified 2026-08-18, do not re-derive):**

- `PowerPanel.qml` carries a `DISPLAY:` section (`:374-` area): one
  brightness row per `BrightnessService.devices` entry (DitherFill track,
  wheel steps at `:237-242`, `_brightnessHoverId` hover machinery at
  `:387-405`, h/l keyboard steps, `NO BACKLIGHT` honest cell at
  `:381-384`).
- `DisplayPanel.qml` is the omarchy-monitor-panel reimplementation:
  hero, `OUTPUTS:` per-output rows, `MIRROR:` section, its own keyboard
  cursor (`:121` notes it mirrors PowerPanel's h/l idiom already).
  Everything routes through CompositorService's backend contract; the
  SAFETY header (no unprompted output reconfiguration) is load-bearing
  and must survive untouched.
- `BrightnessService` is a singleton with no polling loop; the OSD and
  IPC paths (`osd brightness`) bind it independently of any panel and
  must keep working unchanged.

## Constraints

- This is a MOVE, not a rewrite: the brightness rows keep their exact
  row shape, tokens, wheel/keyboard behavior, and honest `NO BACKLIGHT`
  state. Only their home and section header change.
- The section lands in `DisplayPanel` under its own `BRIGHTNESS:` header
  (the old header said `DISPLAY:` only because it lived on a foreign
  panel), placed after `OUTPUTS:` and before `MIRROR:` (backlight is
  per-panel-ish state, mirror is topology; keep the glance-then-act
  order).
- The two panels' keyboard-cursor systems must not double-drive the
  moved rows: integrate with DisplayPanel's existing cursor/h-l
  machinery, delete PowerPanel's now-orphaned `_brightnessHoverId`
  plumbing entirely (no dead code left behind).
- `PowerPanel` header comment and `DisplayPanel` header comment both get
  rewritten where they describe the old split; the DisplayPanel header's
  "deliberately NOT here" paragraph is replaced with the dated owner
  reversal. Comment-rule hygiene per CLAUDE.md (no narration, no
  epitaphs).
- No service, model, IPC, or OSD change. `just vm-smoke --osd` must stay
  byte-identical in behavior.

### Task 1: the move, both headers, docs, smoke

**Files:** modify `shell/Surfaces/Panels/PowerPanel.qml`,
`shell/Surfaces/Panels/DisplayPanel.qml`, `docs/USAGE.md`,
`docs/ARCHITECTURE.md` (the panel-section lines describing where
brightness renders).

**Produces:**
1. The brightness section (rows, hover, wheel, h/l steps, `NO
   BACKLIGHT`) living in `DisplayPanel` under `BRIGHTNESS:`, gone from
   `PowerPanel` (which now ends at `AC POWER:`), both headers honest,
   no orphaned properties or handlers in either file.
2. Docs updated where they place brightness in the power panel.
3. Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel
   display` (Read the PNG: OUTPUTS rows, then the `BRIGHTNESS:` header
   with the VM's honest `NO BACKLIGHT` cell, then MIRROR), `just
   vm-smoke --panel power` (Read the PNG: panel ends at AC POWER, no
   display section), `just vm-smoke --osd` (brightness OSD leg
   unchanged). Commit (`refactor(panels): move brightness to the
   display panel`).

## Review checkpoint

After Task 1: diff both panels against the pre-move commit and confirm
the row shape moved verbatim (tokens, wheel deltas, step size), no
`_brightnessHoverId` remnants in PowerPanel, DisplayPanel's SAFETY
header intact and still true (brightness writes are backlight-only,
never output reconfiguration), the DisplayPanel cursor drives the moved
rows exactly once, docs consistent, smoke evidence real (re-run the
display and power legs, Read the PNGs), commits pushed.
