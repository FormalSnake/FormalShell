# CLAUDE-decisions.md

Architecture decisions and rationale for FormalShell. Not committed (repo
rule) — local reference only.

## M18: the mek ramp (2026-08-07)

- **Why the palette grew 8→12 roles, not a hardcoded ramp.** The owner
  wants matugen AND pywal support kept. A wallpaper-derived ramp needs
  every ink/rule/ornament band to be a themeable role, not a literal —
  otherwise the "quiet structure" look (mek.gallery reference) only exists
  under the default Flexoki fallback and breaks the instant a wallpaper
  recolors. `foregroundFaint`/`warning`/`onWarning`/`onUrgent` were added
  because §1.4's four-band ink hierarchy and the warning state both needed
  a themeable role that didn't exist; `theme.json` stays the single
  contract so any engine (matugen, pywal, hand-written) themes identically.
- **Why dark `onAccent`/`onUrgent`/`onWarning` flip to ink (#100F0F), not
  paper.** Measured WCAG contrast: paper-on-accent in dark mode was
  3.83:1 (fails AA body text); ink-on-accent is 4.86:1. Material's own
  dark color schemes already use dark `on_primary` — this aligns with that
  convention rather than inventing one. Light mode keeps paper on accent
  (6.36:1, no problem there).
- **Why `control()` was deleted instead of reconciled with the state
  table.** Confirmed zero callers anywhere in `shell/`, and its alpha
  values (hover border 0.35, selected border 0.9 @ 2px) already
  contradicted the canonical `STATE_APPEARANCE` table (0.25/1.0 @ 0px) —
  keeping it as a second, disagreeing definition of hover/selected was a
  standing trap for the next person who read it instead of the real table.
  Repo rule: no compat shims for genuinely dead code.
- **Why selection inversion defaults to `"accent"` role, not a boolean.**
  A boolean `useAccent` only has two states and both existed
  (accent/photo-negative); the actual need was N semantic pairs (accent,
  urgent, later maybe warning) sharing one `{bg, fg}` shape. A role string
  scales to that without another signature change.
- **Why `DitherFill` is a `Canvas`, not a `Repeater` of cells.** A 2px
  checker over a track/backdrop is many more cells than a single paint
  call; `Canvas` repaints once per resize/color change (not per frame),
  staying inside "no new animations, static texture" while avoiding a
  heavy per-pixel Item tree. No prior Canvas usage existed in this repo —
  the API surface (`reset()`, `fillStyle`, default `Canvas.Image` render
  target) was grounded against Qt 6.8 docs via Context7 before writing it.
- **Why "disabled toggle field" (§2.8's third dither site) was left
  unbuilt.** No such control exists in the codebase — every toggle-shaped
  UI here (Wi-Fi power, adapter power, DND) is a `Cell`-rendered text
  button, not a separate switch/field with its own background to dither.
  Repo doctrine is no invented/synthetic states; the component was built
  to spec and left unapplied there rather than manufacturing a call site.
- **Why `warning` only landed on Battery, not network/tailscale/timers.**
  The plan's rule: spend `warning` only where the service layer already
  carries a genuine ok/degraded/critical tri-state. Audited each named
  candidate against its model file — `Network/model.js` (boolean
  `connected` only), `Tailscale/model.js` (a process-identity state
  machine, not a severity ramp), `Usage/usage.js`, Bluetooth's model — none
  had a tri-state. Only `Power/model.js`'s `warnEvent()` (ok/warn/critical)
  qualified. Not inventing a threshold elsewhere keeps `warning` meaning
  the same thing everywhere it appears.
- **Why popup widths snap to 4 steps (280/320/400/560) instead of keeping
  each surface's own literal.** The audit found an 8-value spread
  (260-560) with no scale behind it — pure accretion, one surface at a
  time, never reconciled. 4 steps covers the same range; each surface
  moved to its nearest step rather than the token being invented to match
  every existing literal exactly, so a few widths shifted by design (noted
  as an intended, not accidental, visual diff in Task 6/8 evidence).

## M19: the mek grammar (2026-08-09)

- **Why the study was re-done in a live browser.** The 2026-08-07 capture
  described 6px corner *squares*; the live DOM has none — mek ships
  dog-ear fold triangles on ledger-cell corners. Also caught: the first
  browser capture was silently recolored by the Dark Reader extension
  (warm paper read as dark olive); `<meta name="darkreader-lock">`
  injection is the reliable opt-out.
- **Why no new palette roles.** mek's warm dark card (#33241e) and its
  terminal-facet dark scheme were measured but not adopted as roles:
  matugen compat is an owner hard requirement, and no Material role maps
  to "warm dark in both schemes" (inverse_surface flips light in dark
  mode). All M19 chrome draws the existing 12 roles, so every matugen/
  pywal theme recolors it for free.
- **Why the ink button is not the retired photo-negative.** The retired
  pair was *selection* rendered as fg/bg swap; the ink button is a
  resting affordance of a committing action (mek's Submit), with
  hover/press still the accent pair. DESIGN §2 item 11 words the
  carve-out.
- **Why section headers stay `foregroundDim`.** mek's own headers sample
  ≈2.2:1 (sub-AA); the shell keeps the 2026-08-07 WCAG stance and the
  divergence is recorded in DESIGN.md as deliberate.
- **Why the dog-ear is `foregroundFaint`, not `rule`.** mek draws its
  fold hairline-colored, but §1.4 puts ornament in the faint band and
  rules in the quietest; keeping the mark one band louder than the 2px
  border keeps it legible and keeps §1.4's bands intact.
- **Why no polkit/lock confirm button got ink.** Neither flow renders a
  button at all (Enter-to-submit `TextInput`s only, confirmed in code
  and in the --polkit smoke PNG); inventing one to spend the idiom would
  have been a feature change inside a styling plan.
