# FormalShell M31: restore the media panel's large album art

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M29
> (`2026-08-18-m29-device-panels.md`) and M30 landed immediately before
> this plan.

**Origin, owner ask (2026-08-18):** "The now playing panel got a
downgrade. I liked the big album cover, it looked aesthetic." The
regression is M28's `2a6af5b` ("fill the panel with the track instead of
blank space"): it moved the media panel onto the shared `PanelHero` and
with that the album art shrank from its dedicated 96x96 slot
(`2a6af5b^:shell/Surfaces/Panels/MediaPanel.qml:22-80`, `_artSlotSize:
96`, art + identity merged in one row cell) to the hero's leading slot at
`Theme.space.xxl * 2` = 24px — the Apple Music animated cover with it.
DESIGN.md never sanctioned the shrink: §1.3's structural-size exceptions
still name "the media panel's 96x96 album-art slot", so this is drift
back toward the documented design, not a design change.

## Constraints

- Keep everything else M28 gave the panel: the track/progress fill, the
  transport cluster including `dba6395`'s rule fix, the seek row. Only
  the opening block changes.
- §2.13 (every panel opens with the shared hero) is resolved by
  exception, not violated silently: the media panel's *point* is the
  artwork and track, so its opening block is the art+identity row at the
  96x96 slot — the analogue of a number panel's oversized readout. The
  DESIGN.md edit below records exactly that.
- The 96x96 slot still collapses when no art exists (`_hasArt` gate,
  browsers publish no artUrl) — in that case the panel keeps the plain
  `PanelHero` with the note glyph, so no player ever gets a 96px blank.
- Content imagery rules unchanged (§2 item 12): `DitherImage`
  `mode: "retro"`, animated cover layered per its existing loader with
  the static art as the fallback for every failure path.

### Task 1: art+identity opening block, DESIGN.md record, media smoke

**Files:** modify `shell/Surfaces/Panels/MediaPanel.qml`,
`docs/DESIGN.md`; read `2a6af5b^:shell/Surfaces/Panels/MediaPanel.qml`
for the exact prior block.

**Produces:**
1. `MediaPanel.qml`: when `_hasArt`, the panel opens with the restored
   art+identity row cell — `_artSlotSize: 96` (a sanctioned structural
   literal per §1.3), `DitherImage` retro pass at 96x96, the
   `AnimatedAlbumArt` loader over it, title/artist column beside it,
   exactly the `2a6af5b^` composition modulo anything later commits
   fixed. When `!_hasArt`, today's `PanelHero` (note glyph, title,
   meta) stays. No other row changes.
2. `docs/DESIGN.md` §2.13 gains the dated exception: the media panel's
   opening block is the art+identity row at the 96x96 slot when art
   exists (owner, 2026-08-18: the hero-slot cover was a downgrade,
   restore the big cover), hero only in the no-art case. §1.3's 96x96
   mention stands as-is.
3. Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --media` —
   Read the PNG: the 96px dithered cover is back next to the title, the
   `NOW PLAYING / mpv` meta row and transports unchanged. Commit
   (`fix(media): restore the 96px album art block`).

## Review checkpoint

One checkpoint after Task 1: confirm the no-art path renders the hero
(not a blank slot), the animated-cover loader still gates on
`isOpen && isPlaying`, nothing else in the panel moved (diff against
`b7727a0`), DESIGN.md records the exception where §2.13 lives, smoke
evidence real, commit pushed.
