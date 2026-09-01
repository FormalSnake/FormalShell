# Screensaver: omarchy's rendering vs ours

Read off omarchy `quattro` @ f32ebbdb (`bin/omarchy-screensaver`,
`bin/omarchy-launch-screensaver`, `default/{alacritty,foot,ghostty}/screensaver*`,
`default/hypr/apps/system.lua:35`, `shell/plugins/services/idle/Service.qml`)
against `shell/Surfaces/Screensaver/Screensaver.qml` and
`shell/Screensaver/ttfx.js`. Same engine (ttfx 0.3.0), different host.

## Adopted 2026-09-01

- ttfx at `--frame-rate 120`, their number, was 60.
- Black canvas, white default foreground, both constants rather than theme
  colors: every upstream ttfx gradient is authored against black, and a
  wallpaper palette behind one washes it out.
- 18pt banner (24px at 96dpi) on every screen instead of a font scaled to
  span the output. The old fit-to-width survives as a ceiling, so a screen
  too narrow for the banner shrinks the font rather than clipping it the way
  a terminal does.
- Every output animates, one ttfx run each, sharing the effect, seed and
  cycle counter. `display.outputPriority` no longer picks an animating head,
  and `screensaver status` no longer reports `mainOutput`.
- Cycle hold cut from 6s to 4s. They loop with no hold at all.

Kept ours: block codepoints painted as rectangles on the cell grid rather
than as glyphs (`Screensaver.qml:661`, `blocks.js`). Terminals fill their own
cell; a font need not, and Geist Mono's U+2588 does not, which is the stripe
`dev/smoke.d/screensaver.sh` asserts is absent. Their renderer is the one
thing of theirs that would put gaps back in.

## What still differs

| | omarchy | us |
| --- | --- | --- |
| Host | a real terminal (`alacritty`/`ghostty`/`foot`/`kitty`), class `org.omarchy.screensaver`, floating + fullscreen by window rule | layer-shell overlay, `formalshell:screensaver` |
| Glyphs | the terminal's rasterizer | our `Canvas`, blocks as rectangles |
| Banner too wide | clipped at the terminal's cell count | font shrinks until it fits |
| Entry/exit | Hyprland window animation, `animation = "slide"` | 400ms opacity fade both ways |
| Loop | `while true`, ttfx restarted the moment it converges | 4s hold on the converged banner, then reroll |
| Effect pick | `--random-effect`, ttfx's own, can repeat | ours, excluding the effect just shown (`ttfx.js:60`) |
| Dismissal | one byte read off the tty, or the window losing focus | key, click or pointer move on the surface |
| Cursor | `cursor:invisible` compositor-wide, restored on exit | `Qt.BlankCursor` on the surface |
| No ttfx | notify and exit; same for a terminal that is not one of the four | fall back to `effect.js`'s five builtin effects |
| Idle chain | idle service launches the screensaver, a second timer locks, closing the window counts as activity | one surface, optional `screensaver.lockAfterSeconds`, default off |
| Branding | `~/.config/omarchy/branding/screensaver.txt`, with a PNG/SVG to ASCII transcode | bundled `branding/screensaver.txt`, overridden by `screensaver.asciiPath`, watched live |

## argv

Omarchy: `-i <banner> --frame-rate 120 --canvas-width 0 --canvas-height 0
--reuse-canvas --anchor-canvas c --anchor-text c --random-effect --no-eol
--no-restore-cursor`.

Ours (`ttfx.js:101`) matches it except where a pipe forces otherwise:
`--canvas-width`/`--canvas-height` carry our measured cell counts and
`--ignore-terminal-dimensions` says to trust them (no tty behind the pipe, or
ttfx silently uses 80x24), `--terminal-background-color` is the black above,
`--seed` makes a pinned recorder run replayable, and the effect is named
rather than left to `--random-effect`. `--no-restore-cursor` is unusable
here: the restore-cursor sequence is our frame delimiter (`ttfx.js:80`).
