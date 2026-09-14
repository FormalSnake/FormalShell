# M55: synced lyrics, the spectrum in the media panel, room on the bar

**Date:** 2026-09-14
**Status:** in progress on `m55-lyrics` (worktree `../FormalShell-m55`).
**Spec:** `docs/superpowers/specs/2026-09-14-m55-lyrics-spectrum-room.md`
(wins on conflict), over the 2026-08-25 and 2026-07-27 specs.

## Owner's ask (2026-09-14)

"Caelestia has a cool feature in their now playing panel that shows the
visualizer (we have it in the bar but not panel), and where you can see
auto fetched lyrics. It would be a nice feature, supporting everything from
lyrics for a kinda karaoke like thing. If the lyrics aren't timed don't
show them. ../kopuz has cool lyric visuals too." Then: "also disable for me
the visualizer in the bar, only on open. It overlaps with other items and we
need behaviour for these overlap so that half the bar doesn't just
disappear basically."

The owner's own layout (`~/.config/nix`, `users/kyandesutter/mixins/
formalshell.nix`) dropped `visualizer` from `bar.layout.center` in
3a09ecf8; the shell side is below.

## What the references do (read 2026-09-14, mechanics only)

- caelestia (`plugin/src/Caelestia/Services/lyrics.cpp`,
  `modules/dashboard/media/LyricList.qml`): lrclib `/api/get` with
  track/artist/album/duration, `/api/search` for candidates, raw `.lrc`
  cached per id under `$XDG_CACHE_HOME`, `plainLyrics` never read; a
  regex over `[m:ss.xx]` with one line per timestamp on a multi-stamp
  line; the active index a binary search on position plus 100ms; a
  ListView keeping the current line centred with an animated highlight
  move; current line in primary with a glow, the rest in outline; a
  500ms timer re-emitting `positionChanged`. Its spectrum is libcava in
  process, 60 bars, drawn as a ring round the cover.
- kopuz (`crates/utils/src/lyrics/lrc.rs`, `crates/components/src/
  playback/lyrics.rs`): enhanced LRC (`<m:ss.xx>` word chunks), lines
  merged on equal timestamps, translations folded in; a wipe across sung
  words; distant lines blurred; a gap of five seconds or more becomes an
  interlude row whose fill follows the gap; the position extrapolated
  between updates.

## Locked decisions

D1 to D9 in the spec. Notes for the implementer that the spec leaves open:

- `Lyrics.parseLrc` yields `[{time, text, words: [{time, text}]}]` sorted by
  time; a line with several `[..]` stamps is one entry per stamp; lines
  with the same time merge (first text kept, the second folded on a new
  line, kopuz's translation rule); `[ar:..]`, `[ti:..]` and any stamp
  with letters are skipped; a line with no stamp and no words is skipped.
  `hasUsableTiming` is two or more lines with a strictly increasing pair
  somewhere, or one line.
- `indexForTime(lines, t)` is the last index with `time <= t + 0.1`, or -1
  before the first line; `wordIndexForTime` the same over a line's words.
- `displayLines(lines)` inserts an interlude entry (`interlude: true`,
  `time`, `end`) before the first line when it starts at 5s or later, and
  between two lines whose gap from the earlier line's estimated end (its
  last word's time plus 0.35s, else its time plus 7s, clamped to the next
  line's time) is 5s or more.
- `depthOpacity(distance)` is `[1, 0.7, 0.45, 0.25][min(3, |d|)]`.
- The lookup chain is `test -s <key>.lrc` (hit: `cat`), else `test` on
  `<key>.none` newer than 7 days (miss: `none`), else curl `/api/get`,
  else curl `/api/search`; a parse failure of a 200 body is `error`, a
  curl exit is `error`, a 404 or a body with no usable `syncedLyrics` is
  `none` and writes the marker. `_serial` guards every callback.
- The viewport's column is a `Column` of line items under a clipped
  `Item`; the column's `y` is the anchor minus the active item's `y` minus
  half its height, `Behavior on y { Anim {} }`; a line's `opacity` and
  `color` take `Anim { kind: "effects" }` and `CAnim`. Word items are
  `Text`s in a `Flow` with `spacing` the width of one space in the same
  font. Interlude dots are three `primitive-exempt` circles, `xxs` apart.
- The spectrum band's columns share the bar cell's trough, fill and colour
  rules (`Model.levelColorBand`); the band is one `Item` holding a `Row`
  of 24 `primitive-exempt` troughs, each `(width - 23 * xxs) / 24` wide.
- `Layout.fitExtent(extents, gap, room)` returns the sum of the longest
  prefix of `extents` that, with `gap` between neighbours, fits `room`;
  zero extents are skipped in the count and cost no gap. Bar.qml feeds it
  the along-axis extents of the region rail's visible children, in region
  order, and the end region's cap becomes that answer instead of the raw
  room. `bar room` reads the counts the same function yields.
- `NowPlaying.qml` takes `slackAlong` from Bar.qml exactly as `Tray.qml`
  does and assigns `_labelBudget` in a `_refit` on slack, strip, cover and
  natural-width changes; `maxWidth` becomes `min(220, 15% of the strip,
  _labelBudget)` and never a binding on its own width.

## Tasks

One subagent per task, sequential, each ending in its verification run
and one commit on `m55-lyrics`. The VM runs `dev/vm-lock.sh just vm-test`
and `dev/vm-lock.sh just vm-smoke <flags>`; read every PNG under
`artifacts/`.

### Task 1: the lyric model

- `shell/Lyrics/model.js` (`.pragma library`, no Quickshell access):
  `cacheKey`, `getUrl`, `searchUrl` (percent-encoded, `album_name` and
  `duration` only when present), `pickSynced(bodyText)` for the get and
  search shapes (a JSON parse guarded, first `syncedLyrics` with usable
  timing), `parseLrc`, `hasUsableTiming`, `indexForTime`,
  `wordIndexForTime`, `displayLines`, `depthOpacity`, `INTERLUDE_MIN_SECONDS`,
  `FUDGE_SECONDS`, `MISS_TTL_DAYS`.
- `tests/tst_lyrics_model.qml` covering every function above, including
  multi-stamp lines, `<..>` words, metadata lines, a translation line
  merged, a search body with a plain-only first hit and a synced second,
  an empty body, a body that is not JSON.
- Verify: `dev/vm-lock.sh just vm-test` green, output read.

### Task 2: LyricsService and `media lyrics`

- `shell/Services/LyricsService.qml` (singleton, in `Services/qmldir`):
  `enabled` off `media.lyrics`, `panelWants` set by MediaPanel, `state`,
  `source`, `lines`, `hasWords`, the cache dir off `XDG_CACHE_HOME`, a
  `mkdir -p` once, the chain in the plan notes with AppleMusicArtService's
  `_procComponent`/`_run`/`_curl` idiom and its `_serial`; the User-Agent
  `FormalShell (https://github.com/FormalSnake/FormalShell)`; the write
  through `sh -c 'printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"'`.
- `shell/Ipc/MediaIpc.qml`: `lyrics()` returning the D9 JSON, `index`
  read off `Lyrics.indexForTime(lines, MediaService.position)`.
- `shell/Core/Config.qml`'s key comment: `media.lyrics`, `media.visualizer`.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-lint`.

### Task 3: the lyrics block in the media panel

- `shell/Surfaces/Panels/MediaPanel.qml`: the `LYRICS` section before the
  player chips per D5, the `FrameAnimation` clock, the cursor section
  (Up/Down, Enter seeks, follow pauses while the cursor is in it), the
  click-to-seek, `panelWants` bound to `isOpen`. The header comment
  updated. `sectionCount` and `cursorCount` follow the sections present.
- `docs/DESIGN.md` §3 "Panel": one sentence on the media panel's lyrics
  block (the anchor, the depth ramp, the word wipe, no glow).
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-lint`;
  `dev/vm-lock.sh just vm-smoke --media` still passes, PNGs read.

### Task 4: the spectrum band

- `shell/Visualizer/model.js`: `BAR_COUNT` 24, `CELL_BAR_COUNT` 6,
  `downsample(levels, count)` (peak per group), tests in
  `tests/tst_visualizer_model.qml`.
- `shell/Services/VisualizerService.qml`: `framerate = 60`, `panelWants`,
  the gate `available && isPlaying && motion && (visibleBars > 0 ||
  panelWants)`; the header comment updated (it no longer says the
  singleton is unreferenced without the cell).
- `shell/Surfaces/Bar/widgets/Visualizer.qml`: draws
  `Model.downsample(VisualizerService.levels, Model.CELL_BAR_COUNT)`.
- `MediaPanel.qml`: the band under the now-playing block per D6, absent
  when `VisualizerService.state !== "available"` or `media.visualizer` is
  false; `VisualizerService.panelWants` bound to `isOpen && enabled`.
- `docs/DESIGN.md` §3 "Panel": the band, one sentence.
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --visualizer` still passes (the cell at six tracks), PNGs read.

### Task 5: room on the bar

- `shell/Bar/layout.js`: `fitExtent(extents, gap, room)` returning
  `{extent, count}`; tests in `tests/tst_bar_layout.qml`.
- `shell/Surfaces/Bar/Bar.qml`: the two end regions' caps through
  `fitExtent` over their rail's visible children; `slackAlong` handed to
  the now-playing cell; a `roomState()` function per bar returning the D7
  JSON; the region comment at `:785-793` rewritten for the new rule.
- `shell/Surfaces/Bar/widgets/NowPlaying.qml`: `slackAlong` and `_refit`
  per the plan notes.
- `shell/Ipc/BarIpc.qml`: `room()` over `PanelRegistry.bars`.
- `docs/DESIGN.md` §3 "Bar": the room paragraph (now-playing yields, then
  whole cells from the end region's inner edge, nothing cut mid-cell, the
  chevron untouched).
- Verify: `dev/vm-lock.sh just vm-test`; `dev/vm-lock.sh just vm-smoke
  --bar-layout --chevron`, then `--media`, PNGs read, `bar room` called by
  hand over `dev/vm.sh run` inside a smoke session is not possible, so the
  leg in Task 6 is the proof; here the existing legs must not regress.

### Task 6: the smoke legs

- `dev/smoke.d/lyrics.sh` `--lyrics`: needs `--media`'s fixture (source its
  helpers the way `visualizer.sh` does); seeds a word-timed LRC under
  `$iso_home/.cache/formalshell/lyrics/` keyed with `cacheKey` for the
  fixture's tags and duration (the leg computes the key in shell the same
  way; a mismatch is the assert failing, which is the point) and a `.none`
  marker for the second player's track; `panel open media`; `media
  lyrics` twice 3s apart (`synced`, `source: cache`, index advanced); the
  frame; `media select` to the second player; `media lyrics` `none`;
  `panel state` shorter than before. Prints `SMOKE_LYRICS_*` paths.
- `dev/smoke.d/spectrum.sh` `--spectrum`: the tone fixture, no visualizer
  cell in the layout; `pgrep -f 'cava -p'` empty before `panel open
  media`, one after, empty after `panel close`; the open frame.
- `dev/smoke.d/bar_room.sh` `--bar-room`: a `bar.modules` fixture of
  twelve `CommandModule`s with 40-character labels in the right region
  and the long-title track playing; `bar room` reports `right.hidden >=
  1` and `nowPlaying.budget < 220`; the frame, read for a whole cell at
  the right region's inner edge.
- `docs/USAGE.md`: `media.lyrics`, `media.visualizer`, `media lyrics`,
  `bar room`, the visualizer paragraph rewritten (the panel band, the cell
  opt-in); `CLAUDE.md`'s leg list gains the three legs.
- Verify: `dev/vm-lock.sh just vm-smoke --lyrics`, `--spectrum`,
  `--bar-room`, each read; then `--visualizer --media` together.

### Task 7: the record

- This plan's status line, the commit list, deviations.
