# FormalShell M18: the mek ramp — warm ink hierarchy, accent inversion, ornament, spacing consistency

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding — especially
> DESIGN.md's "Revision 2026-08-07: warm ink hierarchy (the mek ramp)"
> block and the new §1.4/§1.5, which this plan implements. The spec wins
> over this plan on conflict.

**Origin, owner ask (2026-08-07):** "How can we style the shell better to
fit the mek.gallery aesthetic? His aesthetic is old computers and
videogames. The shell currently just looks high contrasty." Follow-up
(same day, approving the proposed direction): "I want to keep
matugen/pywal support, so the palette must probably be expanded. Also
make sure all spacings and layouts stay consistent. Currently there are
inconsistencies and stuff."

**Research already done (2026-08-07), do not re-derive.**

*mek.gallery measured (from its shipped Framer CSS, not eyeballed):*
canvas `#eee9dc`, panel `#d9d2c1`, input fills `rgba(99,96,89,0.08)`,
hairlines `#b6b1a3` at 1px (≈1.5:1 vs canvas — the quietest element on
screen), meta inks `#9c9587` / `#636059`, content ink `#2e2e2e`, one
loud blue `#09f` (secondary loud `#ff4001`), 6px corner marks absolutely
positioned on card corners, pixel icons built from 2px squares, dithered
imagery composited with `mix-blend-mode: multiply`. Diagnosis: the
reference is a six-step ramp with quiet structure, not high contrast.
FormalShell's read as "high contrasty" comes from borders/rules drawn as
`foreground` alphas (as loud as content) and photo-negative selection.

*FormalShell root causes, file:line:*

- `shell/Core/Theme.qml:155-162` — legacy `control()` draws hover/focus
  borders as `foreground` @ 0.35 and selected borders as `accent` @ 0.9;
  `rule` is never consulted.
- `shell/Core/Theme.qml:188-195` (`stateStyle()`) +
  `shell/Theme/tokens.js:114-120` (`STATE_APPEARANCE`) — the §1.1 model
  resolves border color to the state's own color with alphas
  0.4/0.25/1.0; `rule` again never consulted.
- `shell/Theme/tokens.js:175-179` (`invertedPair`) — default inversion
  is the photo-negative `{bg: foreground, fg: background}`; the accent
  pair exists but is opt-in.
- `shell/Theme/templates/theme.json.tmpl` — `foregroundDim` AND `rule`
  both map to `colors.outline`, so every matugen wallpaper theme ships
  the flattened ramp; the ramp cannot survive theming without the §1.5
  re-spread.
- `shell/Theme/palette.js:41-45` — Flexoki dark `onAccent` is paper
  `#FFFCF0`: 3.83:1 on accent `#4385BE` (fails AA body); ink `#100F0F`
  measures 4.86:1. Material's own dark schemes use dark `on_primary`.

*Contrast verified (WCAG 2, python, both modes) — reproduce with any
checker before changing values:* dark ramp fg 11.98 / dim 5.19 / faint
(`#575653`) 2.61 / rule 1.80; light ramp 12+ / 4.97 / faint (`#9F9D96`)
2.64 / rule 1.55. Warning `#DA702C` on dark bg 5.77, `#BC5215` on paper
4.69. Dark ink-on-accent 4.86 (paper 3.83), ink-on-urgent 4.42 (best
available over Flexoki red 400; large-text AA only, noted in DESIGN.md).
`foregroundFaint` is ornament/disabled-only by law (§1.4).

*Spacing/consistency audit:* see "Audit findings (2026-08-07)" section
below — Task 6's work list is drawn verbatim from it.

## Constraints

- All CLAUDE.md hard rules stand: nested-session testing only, D-Bus
  isolation, radius 0, border 2, fontconfig `monospace` alias, Nerd Font
  glyphs (targeted Edits only on glyph-bearing files), honest
  unavailable states, no Node, opaque compositor ids, conventional
  commits, verification evidence before every commit.
- DESIGN.md's motion rules are untouched by this plan. No new
  animations; the dither and corner marks are static texture.
- No feature, IPC, provider, or layout-structure changes. Drawn output
  and token plumbing only, except where Task 7 spends the `warning`
  role on an already-existing state.
- theme.json backward compatibility is load-bearing: `palette.js`'s
  per-key merge must keep any pre-expansion theme.json valid (missing
  new keys fall back to Flexoki per-key, never whole-object).
- `just build` needs `git add` first (flake sees only tracked files).
  Visual claims need `just vm-smoke` legs with the PNG actually Read.

### Task 1: Palette expansion — 12 roles, matugen re-spread, pywal template

- `shell/Theme/palette.js`: extend `COLOR_KEYS` with `foregroundFaint`,
  `onUrgent`, `warning`, `onWarning`; extend both Flexoki fallbacks with
  §1.5's exact hexes (dark: faint `#575653`, onUrgent `#100F0F`, warning
  `#DA702C`, onWarning `#100F0F`, and flip `onAccent` to `#100F0F`;
  light: faint `#9F9D96`, onUrgent `#FFFCF0`, warning `#BC5215`,
  onWarning `#FFFCF0`). Light `onAccent` stays paper.
- `shell/Theme/templates/theme.json.tmpl`: re-spread per §1.5 —
  `foregroundDim` ← `on_surface_variant`, `foregroundFaint` ←
  `outline`, `rule` ← `outline_variant`, `onUrgent` ← `on_error`,
  `warning` ← `tertiary`, `onWarning` ← `on_tertiary`.
- New `shell/Theme/templates/pywal-theme.json.tmpl`: a documented pywal
  user template (pywal renders `{color0}`…`{color15}`/`{background}`/
  `{foreground}` substitutions) mapping pywal's 16-color scheme onto
  the twelve keys, with a header comment telling the user to drop it in
  `~/.config/wal/templates/` targeting
  `$XDG_STATE_HOME/formalshell/theme.json`. This file is documentation
  shipped as a template — ThemeEngine does not run pywal; theme.json is
  the contract and the shell's FileView watch (`Theme.qml:120-131`)
  picks up any writer.
- Tests: extend the existing palette/tokens QML tests for the new keys,
  the per-key fallback of a pre-expansion theme.json, and the dark
  `onAccent` flip. `gtk-colors.css.tmpl`/`qtct-colors.conf.tmpl`/
  `niri-border.kdl.tmpl` consume matugen roles directly and are
  untouched — assert nothing about them.
- Verify: `just build && just test && just lint`; `just vm-smoke
  --wallpaper` and confirm the printed `theme status` JSON carries all
  twelve keys with matugen-derived (non-Flexoki) values.

### Task 2: State machinery — borders draw `rule`, inversion is accent

- `shell/Theme/tokens.js`: `STATE_APPEARANCE` per §1.1's updated table —
  drop `borderAlpha`, add the resolved-border-is-`rule` behavior.
  `stateAppearance()` consumers get `{fillAlpha, borderWidth}`;
  `Theme.stateStyle()` returns `border: color.rule, borderAlpha: 1.0`
  for bordered states (semantic-border exception per §1.1: an explicit
  `borderToken` argument may name `urgent`/`accent` where a surface's
  brief demands a meaning-carrying border).
- `shell/Core/Theme.qml` `control()` (legacy path): **delete it.** The
  audit confirmed zero callers anywhere in `shell/` and its alphas
  (hover border 0.35, selected border 0.9 @ width 2) already disagree
  with the canonical table — dead code shipping a second definition of
  hover/selected. Delete, don't reconcile (CLAUDE.md: no compat shims).
- `shell/Theme/tokens.js` `invertedPair()`: default pair becomes
  `{bg: accent, fg: onAccent}`; signature moves from `useAccent` to a
  role argument (`"accent"` default, `"urgent"` for urgent rows); the
  photo-negative pair is deleted, not kept as an option. Update
  `Theme.inverted()` and every call site in the same task (search for
  `inverted(` and `invertedPair(` — half-applied inversion is worse
  than none).
- Update the tokens/state QML tests to the new table and pair.
- Verify: `just test`; `just vm-smoke --menu` and Read the PNG — cursor
  row must sample accent/onAccent, not white-on-black; bar-cell hover
  is covered by Task 4's screenshots.

### Task 3: Ink hierarchy sweep — rules quiet, meta dim, nothing borrowed

- Sweep every surface for structural borders/rules drawn as
  `foreground`-derived alphas or non-`rule` tokens and move them to
  `rule` @ 1.0 (the audit findings below carry the concrete file:line
  list — ledger row rules, card borders, separator lines).
- Meta rows: confirm every §2.3 uppercase caption inks `foregroundDim`
  (the shared `MetaLabel.qml` is the mechanism; converting the
  hand-rolled uppercase strays onto it is Task 6's item, not this
  one's — here only the *color* of existing meta text is in scope).
- Introduce `foregroundFaint` where the audit found disabled/inert
  states hand-dimming with two different ad hoc opacities on the same
  semantic (muted stream rows `opacity: 0.5` at
  `Surfaces/Panels/AudioPanel.qml:255`, disabled transport buttons
  `opacity: 0.35` at `Surfaces/Panels/MediaPanel.qml:162,212`): inert
  ink renders `foregroundFaint` at opacity 1.0, one treatment
  everywhere, per §1.4.
- Verify: `just vm-smoke --panel audio --notify` and Read both PNGs:
  card borders and row rules sample as `rule`'s hex exactly; section
  headers sample as `foregroundDim`.

### Task 4: Accent inversion rollout — bar hover, menu, picker, center

- `shell/Components/Cell.qml` (`standalone` bar-cell hover inversion)
  and every tabular cursor/selection site (menu rows, picker grid cell,
  notification-center row) render Task 2's accent pair. Cells already
  carrying full-bleed `accent`/`urgent`/`selected` fills keep them (no
  double treatment, §1.1).
- Confirm the fill fade stays on the fill layer at `Theme.motion.fast`
  with the ink swap instant (§4.3 unchanged).
- Verify: `just vm-smoke --menu --picker` (two runs or combined legs as
  the rig allows) and Read the PNGs: menu cursor row and picker current
  cell sample accent/onAccent; `--tray` collapsed shot for a bar-cell
  hover is not driveable headlessly — assert bar hover by code review
  plus the existing qml tests on `Cell.qml`'s state resolution.

### Task 5: Ornament — corner marks and Bayer dither, one component each

- New `shell/Components/CornerMarks.qml`: four `xs`-sized
  (`Theme.space.xs`) squares in `foregroundFaint`, anchored on the
  border corners of a parent card, per §2.7. Applied to the floating
  cards: menu, panels (via the shared `Panel.qml` frame), toasts,
  notification center, OSD, picker. One component, no per-surface
  geometry.
- New `shell/Components/DitherFill.qml`: 2×2 ordered-dither checker of
  `foregroundFaint` on transparent per §2.8 — implement with a tiny
  `Canvas`/`ShaderEffect`-free approach if possible (a `Repeater` of
  cells is too heavy; a `Canvas` painted once per resize/color change
  is acceptable and stays within pure QML/JS). Applied to: track
  remainders (the flat slider/OSD track idiom sites), pending
  notification-row backdrops, disabled toggle fields — the §2.8 list,
  nothing else.
- Verify: `just vm-smoke --osd --center` legs; zoom the PNGs (Read
  them) — dither pixels resolve on the OSD track remainder, corner
  marks sample `foregroundFaint` on card corners. `just test && just
  lint` for the new components.

### Task 6: Spacing and layout consistency

Work list from the audit findings section below, in priority order:

- **Card gutter unification (audit #1).** `Surfaces/Notifications/
  Center.qml:148-151` gains the popup gutter every sibling already has
  (rows currently sit ~2px from the card edge). Decide the split once
  and write it into DESIGN.md §1.3 in the same commit: `popupPadding`
  (14) for summoned list surfaces (menu, notification center),
  `panelPadding` (18) for bar-anchored panels — then make all three
  surface families actually match that sentence.
- **Wire the dead semantic tokens (audit #2).** `controlHeight`,
  `popupRowHeight`, `rowGap`, `rowPaddingX`, `controlGap`,
  `controlPaddingX/Y`, `labelGap` have zero consumers; row geometry is
  a repeated ad hoc formula (`Theme.space.sm/lg + Theme.borderWidth`,
  e.g. `Components/Cell.qml:80-81`, `Surfaces/Menu/MenuRow.qml:38`).
  Route the shared primitives (`Cell.qml`, `MenuRow.qml`, panel row
  components) through the semantic tokens, adjusting token base values
  to match today's rendered geometry where they differ — geometry must
  not jump; the point is that parity stops being coincidence.
- **One uppercase action-label treatment (audit #3, #6-§6).** Every
  hand-rolled uppercase clickable label (`Center.qml:174-199` DND /
  CLEAR ALL, `PowerPanel.qml:416`, `BluetoothPanel.qml:618`,
  `WeatherPanel.qml:168`, `Menu.qml:392-394`, `Battery.qml:83`,
  `Visualizer.qml:76-78`'s conditional third variant) renders through
  `MetaLabel.qml` or one shared action-label variant of it:
  `Font.AllUppercase` + `Theme.letterSpacing.meta`, never bare JS
  `.toUpperCase()` with zero tracking.
- **Shared `PanelOpenDot.qml` (audit #6).** The 4px panel-open dot is
  duplicated verbatim in 11 bar widgets; extract one component sized
  `Theme.space.sm`, and `CalendarPanel.qml:389-390`'s event dot uses
  the same token.
- **Auth-field border parity (audit #4).** The spec's lock brief (§3)
  names a 3px-equivalent outline; `Components/AuthPrompt.qml:143` ships
  2px while `Surfaces/Polkit/PolkitDialog.qml:272` hand-rolls
  `3 * fontScale`. Both password fields share one border spec at the
  spec's 3px-equivalent, defined once.
- **Popup width scale (audit #10).** Add `popupWidth{Narrow,Default,
  Wide,Menu}`-style tokens to `tokens.js` (values chosen to cover
  today's 260/280/300/320/360/380/420/560 spread with at most four
  steps, snapping each surface to its nearest step) and move every
  `panelWidth`/`implicitWidth` literal onto them. Small visible width
  shifts are intended here; anything beyond width is not.
- **Token hygiene strays (audit #9, §1, §3).** `AuthPrompt.qml:115`
  letter-spacing borrows `Theme.space.md` → `Theme.letterSpacing`
  token; `AudioPanel.qml:296` 1px divider → `Theme.borderWidth` or a
  documented rationale; `MediaPanel.qml`'s thrice-repeated 96px art
  slot becomes one named property (and DESIGN.md's sanctioned
  image-slot list gains it, since only 40×40 and 381×67 are named
  today).
- Out of scope, deliberately: the hero-type multipliers
  (`AuthPrompt.qml:114` ×4, `Screensaver.qml:265` ×2.4) — M16's audit
  already ruled "token-derived, rescale correctly, leave them"; do not
  relitigate. The legacy `Theme.font` object dies in Task 2's file
  touch or here, whichever lands second — every consumer reads only
  `.family`, so replace it with a `fontFamily` string property and
  delete the stale size math (`Core/Theme.qml:51-58`).

- Verify: `just build && just test && just lint`; `just vm-smoke` plain
  leg plus `--panel calendar` and `--center`, Read the PNGs against the
  previous screenshots: intended diffs are the named ones (center
  gutter, width snapping, label tracking); any other geometry jump
  blocks.

### Task 7: Spend the `warning` role

- Battery: the low-but-not-critical band renders the bar battery cell
  as a full-bleed `warning` cell with `onWarning` ink (the critical
  band stays `urgent`); thresholds are whatever `PowerPanel`/battery
  service already define — no new thresholds invented.
- Audit other existing degraded states (network limited-connectivity,
  tailscale connecting, timer/pending states) and apply `warning` ONLY
  where a tri-state (ok/degraded/critical) already exists in the
  service layer. Two-state features stay two-state.
- Verify: `just vm-smoke` (the VM has no battery — the cell stays
  honestly absent; assert via qml tests on the cell's state mapping)
  plus `just test`.

### Task 8: Docs, screenshots, memory bank, final sweep

- Regenerate every `docs/screenshots/*.png` via the corresponding
  `just vm-smoke` legs; Read each PNG before accepting it.
- README/docs surfaces that describe theming gain the twelve-role table
  reference and the pywal template pointer; DESIGN.md needs no further
  edits (already amended 2026-08-07).
- Sync CLAUDE-patterns/CLAUDE-decisions memory-bank files with the new
  token doctrine per the memory-bank skill.
- Final `just build && just test && just lint` plus a combined
  `just vm-smoke --wallpaper --menu` leg; Read the PNG and the `theme
  status` JSON as the closing evidence.

## Review checkpoints

- After Task 2: the state-machinery diff is the highest-risk change
  (every control renders through it) — run the full smoke matrix before
  proceeding, not after.
- After Task 6: diff every regenerated screenshot against its
  predecessor; any geometry change the audit didn't predict blocks.
- Close: DESIGN.md §1.4's checkable claims (sample borders = `rule`
  hex, meta = `foregroundDim`, selection = accent pair) verified
  against final screenshots, stated with pixel samples in the task
  evidence.

## Audit findings (2026-08-07)

Full-tree sweep of `shell/` against the token system, run this session.
Do not start Task 3 or Task 6 without reading this section.

### Hardcoded pixels bypassing `Theme.space`

- Panel-open dot `width/height: 4` duplicated verbatim, no shared
  component, in 11 bar widgets: `Surfaces/Bar/widgets/
  BluetoothWidget.qml:61-62`, `AudioWidget.qml:49-50`,
  `WeatherWidget.qml:61-62`, `NowPlaying.qml:81-82`,
  `UsageWidget.qml:67-68`, `TailscaleWidget.qml:70-71`,
  `BellWidget.qml:61-62`, `NetworkWidget.qml:73-74`,
  `Battery.qml:107-108`, `Clock.qml:49-50`, `GithubWidget.qml:73-74`;
  plus `CalendarPanel.qml:389-390`'s event dot.
- The nine semantic control tokens (`controlGap` … `labelGap`) have
  zero consumers; the only reference is a comment at
  `Surfaces/Gallery/Gallery.qml:299-305`. Row geometry everywhere is
  the repeated `Theme.space.sm/lg + Theme.borderWidth` formula
  (`Cell.qml:80-81`, `MenuRow.qml:38`) — parity by coincidence.
- Card gutters, three treatments: `Menu.qml:422-423,1056,1058,1149`
  `popupPadding` (14); `Components/Panel.qml:75,78,243-259` and
  `PolkitDialog.qml:194,222` `panelPadding` (18);
  `Center.qml:148-151` neither — rows inset only by `borderWidth`.
- Bespoke `panelWidth` literals: `ImagePicker.qml:42` (420),
  `UsagePanel.qml:66` (300), `CalendarPanel.qml:58` (280),
  `GithubPanel.qml:31` (380), `WeatherPanel.qml:45` (260), default 320
  at `Components/Panel.qml:26`; `Menu.qml:978` (560),
  `Center.qml:99` (420), `NotificationCard.qml:32` (360),
  `PolkitDialog.qml:51` (`360 * fontScale`), `Bar.qml:120` (420 cap).
- `MediaPanel.qml:44-45,51-52,81-82` — 96px album-art slot repeated
  three times in one file; undocumented image-slot size.
- `AudioPanel.qml:296` — `width: 1` divider vs the 2/0 border
  convention.

### Fonts

Clean: every `font.pixelSize` resolves through `Theme.fontSize.*`. The
two token-derived hero multipliers (`AuthPrompt.qml:114` ×4,
`Screensaver.qml:265` ×2.4) stay per M16's ruling.

### Colors and alphas

- No raw `#hex` outside `palette.js`; the one `Qt.rgba`
  (`Cell.qml:170`) is token-driven. Clean baseline for Task 3.
- `Core/Theme.qml:155-162` `control()`: dead (zero callers) and its
  alphas (hover border 0.35, selected border 0.9 @ 2px) contradict
  `tokens.js`'s canonical 0.25 / 1.0 @ 0px. Task 2 deletes it.
- Disabled/inert opacity split: 0.5 (`AudioPanel.qml:255`) vs 0.35
  (`MediaPanel.qml:162,212`) — Task 3 replaces both with
  `foregroundFaint` ink.
- `AuthPrompt.qml:115` uses `Theme.space.md` as letter-spacing, three
  lines above a correct `Theme.letterSpacing.wide` use at `:123`.

### Border widths

Only five explicit `border.width` sites; four are `Theme.borderWidth`.
The violation: `PolkitDialog.qml:272` `Math.round(3 * Theme.fontScale)`
vs the lock field's 2px (`AuthPrompt.qml:143`) — two password boxes,
two weights, while the spec's lock brief names a 3px-equivalent
outline. Task 6 unifies on one shared spec.

### Uppercase/meta treatment

`Components/MetaLabel.qml` (`Font.AllUppercase` +
`Theme.letterSpacing.meta`, 27 consumers) is the solid convention. The
strays render uppercase by hand: `Center.qml:174-176,197-199` (tracked,
body-sized), `PowerPanel.qml:416`, `BluetoothPanel.qml:618`,
`WeatherPanel.qml:168`, `Menu.qml:392,394`, `Battery.qml:83` (bare
`.toUpperCase()`, zero tracking), and `Visualizer.qml:76-78` switching
convention by state within one element.

### Ranked, most screenshot-visible first

1. Notification-center rows flush at ~2px vs menu 14 / panels 18.
2. Dead semantic row tokens; row parity is coincidence.
3. Action-label tracking split (Center vs PowerPanel siblings).
4. Password-field border 2px vs 3px.
5. Disabled opacity 0.5 vs 0.35.
6. Panel-open dot ×11 copies of a bare `4`.
7. `control()`'s contradictory alpha table (dead, but a trap).
8. Hero multipliers ×4 vs ×2.4 (out of scope per M16).
9. `space.md` as letter-spacing in AuthPrompt.
10. Popup width spread 260-560 with no scale behind it.
