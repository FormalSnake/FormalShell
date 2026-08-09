# FormalShell M21: first live-session feedback on the M19/M20 line

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-09, running the deployed shell on e1504g):**
"system tray apps look deep fried, revert that. App icons are gone next
to their title [resolved itself — icon-theme warm-up on a fresh session,
dropped from scope], workspaces and system tray apps still have
different hover heights than the other items. Also, the album cover is
dithered like i asked, but the colors dont change. It doesnt become 90s
image style."

**Context.** The tray mask-mode silhouettes (M20 Task 5) read as "deep
fried" on real vendor icons — revert to true-color icons; the M20 slot
normalization (one square slot per icon) stays, it fixed the margin
jitter and is unrelated to the color treatment. Reverting reopens the
original light-mode-invisible-icon problem — record it as an open
problem in DESIGN.md rather than shipping a treatment the owner
rejected. The retro dither kept hues too faithful: 4 levels/channel is
64 colors (imperceptible on most covers) and 1px dither cells at a 96px
slot read as texture, not era. The preview the owner approved was
4x-magnified 64-color output — the chunk, not just the palette, is the
look.

## Constraints

- All CLAUDE.md hard rules stand. Matugen compat untouched (these
  changes are content imagery + chrome geometry only).
- macOS verification loop: `just vm-build` / `vm-test` / `vm-lint` /
  `just vm-smoke <flags>`; PNGs Read from ./artifacts/.
- Commits conventional single-line, no body, no Co-Authored-By; never
  CLAUDE-*.md.

### Task 1: Revert tray icons to true color

- `Tray.qml`: drop the `DitherImage mode:"mask"` pipeline (and its
  grabToImage feed — also silences the "Ignoring sourceSize request for
  image url that came from grabToImage" session-log warning); icons
  render as plain `IconImage` again, in the M20 fixed square slot
  (keep), `smooth: false` (keep). Delete the now-unconsumed mask-mode
  branch ONLY if nothing else consumes it — `rg 'mode: *"mask"' shell/`
  — if the mode has no consumer left, delete the branch and its tests
  (delete-what-you-replace); DitherImage's duotone/retro modes are
  consumed (media) and stay.
- DESIGN.md §2 item 12: tray icons come OUT of the 1-bit surface list;
  add one open-problem sentence — symbolic vendor icons can be
  near-invisible on the light ramp, treatment TBD with the owner
  (mask silhouettes shipped and were rejected 2026-08-09).
- Verify: `git add -A`; `just vm-build && just vm-test && just
  vm-lint`; `just vm-smoke --tray` — Read both shots: vendor-colored
  icons in uniform slots, collapsed and expanded.

### Task 2: One hover-fill height for every bar cell

- Symptom: workspace pills and tray item cells draw a shorter/taller
  hover fill than directly-hosted widgets. Diagnose first: compare how
  a direct widget Cell gets its height (bar region layout) vs the
  nested `Row`-hosted Cells in `Workspaces.qml` and `Tray.qml`
  (content-derived `implicitHeight` + `controlPaddingY` vs the region's
  stretched height). Fix by binding every standalone bar cell to one
  shared height source (the bar's content height token / region height)
  rather than per-cell content padding — whatever mechanism the direct
  widgets already use, extend it to the nested Rows; no new magic
  numbers, no per-widget special cases.
- Verify: `git add -A`; gates green; `just vm-smoke --tray` (tray +
  workspaces + neighbors in one frame) — Read the PNG and compare cell
  bounds pixel-exactly: workspace pill, tray cell, and clock cell all
  span the same vertical extent. Rest-state bounds prove the fill
  geometry (hover fill uses the same rect as the cell).

### Task 3: The 90s look — chunky cells, snapped palette

- `DitherImage.qml` retro mode: add `property int chunk: 2` — the
  Bayer/posterize pass computes at `width/chunk × height/chunk` and
  renders each computed pixel as a `chunk`-sized square (fillRect
  already draws rects; scale the geometry — no smooth scaling anywhere,
  the upscale must stay hard-edged). Default `levels` drops 4 → 3
  (27 colors: hues visibly snap to steps, the "colors change" the owner
  asked for). Both surfaces (MediaPanel slot, NowPlaying mini-cover)
  inherit the defaults; the mini-cover may pin `chunk: 1` ONLY if the
  chunked result is illegible at bar size — judge from the smoke shot
  and say which you shipped. `AnimatedAlbumArt.qml` inherits panel
  defaults.
- Update the DitherImage unit tests for chunk geometry (a computed
  cell renders as a uniform chunk-sized square) and the 3-level
  quantization steps (0/128/255).
- DESIGN.md §2 item 12: record levels=3 and the chunk-cell rendering as
  the named default.
- Verify: `git add -A`; gates green; `just vm-smoke --media` — Read the
  PNG: cover shows chunky (≥2px) dither cells and visibly snapped hues
  (sample: pixel values sit on 0/128/255-step combinations of the
  source hues, and adjacent original gradients collapse to stepped
  bands). Compare against the M20 media shot and state the visible
  difference plainly.

### Task 4: Sweep-lite, screenshots, redeploy

- Legs, PNGs Read: plain, `--tray`, `--media`, `--visualizer` (palette
  extraction unchanged but its source pipeline was touched — prove bars
  still color from the cover).
- Regenerate `tray-niri.png`, `media-niri.png` (+ `bar-niri.png` only
  if Task 2 visibly moved rest-state bounds). Final gates green.
- Deploy: push, `nix flake update formalshell` + commit/push on
  e1504g's config (pull the lock commit back to the mac — both repos
  stay level), `sudo -n nixos-rebuild switch --flake .#e1504g` (the
  plain sudo path — the transient-unit path fails libgit2 ownership),
  confirm the new generation, and tell the owner to reload the session.
