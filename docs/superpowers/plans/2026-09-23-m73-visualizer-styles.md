# M73: visualizer leveling and styles

Owner ask (2026-09-23): the media panel's spectrum pegs on a loud track or a
high volume, every column at full height. Fix that, and add Winamp-style
effects drawn in the same box as the current twelve columns, picked in
config, switchable at runtime for exploration, every one listed in the
README. Reference: cliamp (github.com/bjarneo/cliamp, `ui/vis_*.go`), read
for ideas, not ported.

Branch `feat/visualizer-effects`, worktree `../FormalShell-visualizer`.

## Why it pegs

`VisualizerService` runs cava with `autosens = 0`, `sensitivity = 800` and
`ascii_max_range = 100`, then `model.js` lifts every value through `sqrt`.
A fixed gain tuned on pink noise at amplitude 0.8 means anything louder (a
mastered track, a raised app or sink volume) clips at cava's 100 and sqrt
pushes the rest near the top: 0.64 raw already draws at 0.8.

## Task 1: leveling (model.js + VisualizerService)

- cava: `ascii_max_range = 1000` (headroom and resolution, clipping at 100
  is half the problem), `sensitivity` lowered so a loud track does not hit
  the ceiling; `autosens` stays 0 because cava's own autosens drives every
  passage to full scale, which is the same complaint.
- model.js, pure and tested: an automatic gain stage of our own.
  - `agcStep(ref, framePeak, dt)`: a peak follower on the frame's loudest
    raw band. Attack ~0.12s when the peak rises past `ref`, release ~4s
    back down, floored at `AGC_FLOOR` so silence and a noise floor are never
    amplified into motion.
  - `normalize(fraction, ref)`: `fraction / ref * AGC_TARGET` (target
    ~0.78) through a soft knee above ~0.6 that approaches 1 asymptotically,
    so only a transient over the running peak reaches the top and a steady
    loud passage sits in the upper third, not on the ceiling.
  - Response curve: replace sqrt with a milder power (~0.7) so the gaps
    between bands survive; tune by the unit tests' numbers, not by eye.
- `VisualizerService` holds `_agcRef`, advances it per cava frame, and
  resets it with the levels when cava stops. `levels` stays 0..1 per band,
  so the bar cell and the panel both benefit with no change on their side.
- The level-colour bands (`LEVEL_ACCENT_FROM`) were chosen against sqrt;
  re-check them against the new curve so accent stays a peak signal.
- Tests in `tests/tst_visualizer_model.qml`: a constant loud frame at
  several input gains converges to the same drawn height below 0.9; a
  quiet passage after a loud one recovers within the release time; silence
  under the floor stays 0; a transient over the running peak draws taller
  than the steady level; relative band order is preserved.

## Task 2: styles (renderer, config, IPC, click)

- `shell/Visualizer/styles.js` (`.pragma library`): `STYLES`, the ordered
  list of `{ id, label, description }`, and one `draw(ctx, w, h, levels,
  state, ink, dt, t)` per style. `ink` carries resolved colours
  (`groove`, `dim`, `content`, `accent`) and the mono family; `state` is a
  per-renderer object for peak caps and particles, reset on style change.
  Every style fits the current box (12 columns' width,
  `Theme.space.controlHeight` tall) and draws from `VisualizerService.levels`
  alone: no invented waveform. A style that needs time-domain shape
  synthesises it from the band levels and says so in its description.
- Styles, in cycle order: `bars` (today's look, the default), `peaks`
  (thin columns with falling Winamp caps), `led` (segmented Winamp 2 LED
  matrix with caps), `mirror` (bars about the horizontal centre),
  `butterfly` (bass in the middle, mirrored left and right), `outline`
  (bar tops only), `wave` (a filled curve through the bands), `dots`
  (stippled dot grid lit to level), `ascii` (shade glyphs `░▒▓█` in the
  mono font), `matrix` (falling mono glyphs lit by their column), `rain`
  (droplets falling inside the bar shapes), `flame` (flickering tips
  rising off the bars), `bubbles` (rings rising at a rate set by energy),
  `scope` (an oscilloscope trace summed from the bands), `pulse` (a disc
  breathing on the bass, a ring on the mids), `heartbeat` (an ECG trace
  that beats on bass onsets), `terrain` (a scrolling ridge of recent
  loudness).
- `shell/Surfaces/Panels/VisualizerCanvas.qml`: one `Canvas` replacing the
  Repeater of `Rectangle`s in `MediaPanel.qml`, same width and height, a
  `FrameAnimation` repainting only while `VisualizerService` is running
  (and once more to settle on the baseline). Colours from `Theme.color`
  only: `muted` groove, `mutedForeground` dim, `foreground` content,
  `primary` accent, the same bands `bars` uses today.
- Config: `media.visualizerStyle` (string, default `"bars"`); an unknown id
  falls back to `bars` and `visualizer status` says so. Document it in
  `shell/Core/Config.qml`'s key list beside `media.visualizer`.
- Runtime: `VisualizerService.styleOverride` (in memory, `""` follows
  config; the shell never writes settings.json). `style` is the resolved
  id. New IPC target `visualizer` (`shell/Ipc/VisualizerIpc.qml`, wired in
  `shell.qml`): `style(name)` (an id, `next`, `prev`, or `config` to drop
  the override; unknown id answers an error listing the ids), `styles()`
  (ids, one per line), `status()` (JSON: style, override, configured,
  running, state).
- The spectrum box takes a click to cycle forward and a wheel notch to
  cycle either way, `PointingHandCursor`, and a `Tooltip` naming the style
  if the panel's other controls carry tooltips.
- Tests: `tests/tst_visualizer_styles.qml` draws every style against a
  recording mock context for silence, a flat loud frame and a ramp, over a
  few steps of `dt`, asserting no throw, no NaN coordinates, nothing
  outside `0..w` x `0..h`, and that `STYLES` ids are unique and include
  `bars` first.

## Task 3: rig and docs

- `dev/smoke.d/visualizer_styles.sh`, `--visualizer-styles`: visualizer.sh
  / spectrum.sh's real tone fixture (use a richer signal than one sine, a
  chord or pink noise, so the bands differ), panel open, every id from
  `visualizer styles` set over IPC in turn, one crop of the spectrum box
  per style saved as `visualizer-style-<id>.png`, asserting each crop is
  non-empty and that no two consecutive styles' crops are identical. Then
  one run of the tone at a raised volume asserting `visualizer status`
  levels are not all above 0.9 after the AGC settles (expose `levels` in
  `status` for this). Add the leg to CLAUDE.md's leg list.
- A contact sheet `docs/media/visualizer-styles.png` built from the crops
  (`convert` montage, id under each), committed.
- README: a short paragraph under "A tour" and a table of every style id
  with its one-line description, the contact sheet above it. USAGE.md:
  `media.visualizerStyle`, the `visualizer` IPC verbs, click and wheel,
  and the leveling change in the Visualizer section (the 800%/sqrt text
  there is stale after Task 1).
