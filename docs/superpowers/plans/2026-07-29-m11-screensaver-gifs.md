# FormalShell M11: Screensaver effect GIFs

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding.

**Origin — owner ask:** record a GIF of the screensaver showing all variants,
one per effect, and confirm the random-per-activation behaviour matches
omarchy's `--random-effect`.

**Already confirmed, do not re-derive:** random selection works. `screensaver.effect`
defaults to `"random"` (`Screensaver.qml:78`), a fresh `_activationSeed` per
activation feeds `Effect.resolveEffectName(requested, seed)` (`:81`, `:115`),
and an unknown name warns then falls back (`:119`). Five effects exist in
`shell/Screensaver/effect.js`: `decrypt`, `rain`, `expand`, `slide`, `scatter`.

**The problem to solve.** A naive recorder would burst-screenshot the live
screensaver, but the VM renders through llvmpipe, so wall-clock capture gives
uneven frame spacing and a choppy GIF. The effects are already a pure function
of a frame counter (`Effect.frameState(name, frame, banner)`), and each has a
known `Effect.convergenceFrame(name, banner)`. So drive capture by frame
number instead of by clock.

## Constraints

- `CLAUDE.md` hard rules bind. `docs/DESIGN.md` is the design authority.
- **No existing feature may change.** The screensaver's normal idle-driven
  behaviour, its media guard, its lock chain and its random selection must be
  untouched. The frame-step path is a verification affordance, exactly like
  `picker choose` and `panel open`, and must not become how the screensaver
  normally advances.
- Smoke script changes additive only.
- Regression gate: `just test` green, `just vm-smoke --screensaver` still
  passes, `just vm-smoke --wallpaper` still recolours.
- ⚠️ `branding/screensaver.txt` is raw block-drawing characters: targeted
  `Edit` only, never a wholesale rewrite.

---

### Task 1: Deterministic frame stepping + GIF recorder

**Files:** modify `shell/Ipc/ScreensaverIpc.qml`,
`shell/Surfaces/Screensaver/Screensaver.qml`, `dev/smoke-niri.sh`; create
`docs/media/` output.

**Produces:**
1. A `screensaver frame(n)` IPC verb that pins the surface to frame `n` of the
   currently-selected effect and renders it. It must only take effect while the
   screensaver is already showing, must not disturb the effect selection, and
   must be released when the screensaver stops so normal animation resumes.
   Report honestly if it is a no-op because the screensaver is not up.
   Also expose whatever is needed to read back the current effect name and its
   convergence frame, so the recorder knows how many frames to capture rather
   than guessing.
2. A `--screensaver-gif` smoke mode that, for each of the five effects in turn:
   pins `screensaver.effect` to that name via the settings fixture, starts the
   screensaver, steps `frame` from 0 to convergence plus a short hold, captures
   one screenshot per frame, and assembles `docs/media/screensaver-<effect>.gif`
   with imagemagick.

**Size discipline.** Five GIFs live in the repo forever. Scale to a sensible
width (around 640px), cap the palette, run `-layers optimize`, and keep each
file under about 1.5 MB. State the actual byte sizes in your evidence. If an
effect needs more frames than that budget allows, drop the frame rate rather
than truncating the animation before it converges.

**Steps:** implement → `just vm-smoke --screensaver-gif` → **Read every one of
the five GIFs' first, middle and last frame** (extract stills with imagemagick
and Read those; you cannot Read an animated GIF directly) and confirm each
actually animates from noise to the finished `FORMALSHELL` banner, and that the
five look genuinely different from each other → regression: `just test`,
`just vm-smoke --screensaver`, `just vm-smoke --wallpaper` → commit
`feat(screensaver): deterministic frame stepping and per-effect gif recorder`; push.

---

### Task 2: Publish the GIFs

**Files:** modify `README.md`, `docs/USAGE.md`, `CLAUDE.md`, `.gitignore` if needed.

1. Add the five GIFs to the README, near the screensaver entry in the
   screenshots table or as their own small row. Keep the README's new product
   shape: this is a 234-line file now, do not regrow it. A compact row of five
   labelled GIFs, not five full-width images with paragraphs.
2. `docs/USAGE.md`: document `screensaver.effect` accepting a specific name or
   `random` (the default, fresh per activation), name all five effects, and
   document `screensaver.asciiPath` for replacing the banner art.
3. `CLAUDE.md`: add the `--screensaver-gif` smoke mode to the verification loop.
4. Check every image path resolves before finishing.

**Steps:** verify paths → commit `docs(screensaver): publish the five effect gifs`; push.
