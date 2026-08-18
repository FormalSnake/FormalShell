# FormalShell M35: animated mini cover on the bar's now-playing cell

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. Runs after M34;
> do not start implementation while another workflow holds the tree or
> the VM.

**Origin, owner ask (2026-08-18):** the bar's now-playing mini cover
"doesnt appear to be animated ... like the image in the bar, the panel
is fine." This reverses M20's recorded decision (DESIGN.md §2.12: the
mini cover is "static only, no bar-scale animated decode") — the owner
wants the Apple Music animated cover on the bar cell too.

**State today (verified, do not re-derive):** the media panel's 96x96
art (restored M31) layers `AnimatedAlbumArt.qml` over the static
`DitherImage` — it samples the decoded video at ~8fps and re-dithers
each frame (the choppy cadence is the aesthetic), active only while
`isOpen && MediaService.isPlaying && AppleMusicArtService.animatedArtUrl
!== ""`, falling back to static art on every failure path. The bar's
now-playing cell renders a static `DitherImage` mini cover that keeps
its own colors even on hover inversion (content ruling, §2.12).

## Constraints

- **Gates mirror the visualizer's (§4.8), enforced on the decode**: the
  bar-side animation runs only while `MediaService.isPlaying` AND
  `AppleMusicArtService.animatedArtUrl` is non-empty AND the bar window
  showing the cell is actually on screen AND `Theme.motionEnabled`. Any
  gate going false stops the decode outright (zero CPU), never just
  pauses a paint. Static dithered art is the fallback for every failure
  and gated-off path, exactly the panel's contract.
- **One decode, N renderings.** The panel open while the bar animates
  must not spawn a second video pipeline. Read `AnimatedAlbumArt.qml`
  and `AppleMusicArtService` first; lift the frame sampling into one
  shared source (service-level frame provider or equivalent) that both
  surfaces' dither passes consume. If the existing structure already
  guarantees a single decode, name where and leave it.
- The mini cover's content ruling stands: its own colors on a hovered
  (inverted) cell, animated or not.
- Same ~8fps sampled, re-dithered cadence as the panel; the mini slot's
  existing size and chunk behavior unchanged.
- DESIGN.md §2.12's mini-cover sentence is rewritten as the dated owner
  reversal, and the animated set's membership list updated; §4 gains no
  new carve-out (this rides the existing animated-cover one, gated like
  the visualizer).

### Task 1: shared frame source, bar-side animation, docs, smoke

**Files:** modify `shell/Surfaces/Panels/AnimatedAlbumArt.qml` and/or
`shell/Services/AppleMusicArtService.qml` (per the one-decode
constraint), the now-playing bar widget (locate it in
`shell/Surfaces/Bar/widgets/`), `docs/DESIGN.md`, `docs/USAGE.md` if it
describes the static mini cover.

**Produces:**
1. The bar mini cover animating under the four gates, single shared
   decode, static fallback intact.
2. Docs updated per the constraints.
3. Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --media`
   (the rig has no Apple Music animated art, so the leg's screenshots
   prove the static path is byte-identical — Read them against the
   prior run's); the animated path itself is verified by review of the
   gating plus the owner's live session after rollout, and the commit
   says so honestly rather than claiming rig proof that cannot exist.
   Commit (`feat(bar): animate the now-playing mini cover`).

## Review checkpoint

After Task 1: gate audit (kill each of the four gates in source and
confirm the decode dies, not just the paint), double-decode hunt (panel
open + bar visible = one pipeline), hover-inversion content ruling
intact, `motion.enabled: false` leaves a static cover and zero media
processes, static-path smoke screenshots unchanged, DESIGN.md reversal
recorded at §2.12, commits pushed.
