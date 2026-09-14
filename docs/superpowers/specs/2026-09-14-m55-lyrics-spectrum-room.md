# M55: synced lyrics and the spectrum in the media panel, room on the bar

**Date:** 2026-09-14
**Status:** approved as an addendum to
`2026-08-25-shadcn-omarchy-redesign.md` (owner brief, 2026-09-14). That spec
and `2026-07-27-formalshell-design.md` stand; this one adds to their media
panel, their bar and their configuration and wins over any plan on conflict.

## The brief

The owner's words, condensed: caelestia's now-playing panel shows the
visualizer (ours is only a bar cell) and auto-fetched lyrics, karaoke-like.
Support everything, but lyrics that are not timed are not shown. kopuz's
lyric visuals are the other reference. Then: take the visualizer off my bar,
show it only when the panel is open, because it overlaps other cells, and the
bar needs a behaviour for that overlap so half the bar does not just
disappear.

What was read, for mechanics and values only, no ported code:
caelestia-dots/shell (`plugin/src/Caelestia/Services/lyrics.cpp`,
`modules/dashboard/media/LyricList.qml`, `CoverVisualiser.qml`) and kopuz
(`crates/utils/src/lyrics/*.rs`, `crates/components/src/playback/lyrics.rs`).

## Decisions

**D1 Source.** lrclib.net alone. `GET /api/get` with `track_name`,
`artist_name`, `album_name` when the player publishes one and `duration`
(seconds, rounded) when finite; on a miss `GET /api/search` with
`track_name` and `artist_name`, taking the first result whose
`syncedLyrics` carries usable timing. `plainLyrics` is never read. The
User-Agent names the shell and its repo, as lrclib asks. Transport is
`curl` in a `Process` (AppleMusicArtService's idiom: `--fail`, an 8s
`--max-time`, stdout captured), never QML's XMLHttpRequest. No NetEase, no
musixmatch, no proxy services, no local `.lrc` lookup: lrclib is the open
provider both references share, and the rest are either a third party's
private API or out of this panel's reach.

**D2 Cache.** `$XDG_CACHE_HOME/formalshell/lyrics/<key>.lrc` holds the raw
synced LRC of a hit and is kept forever; `<key>.none` is an empty marker for
a track lrclib had nothing timed for, asked again once it is seven days old.
`key` is `Lyrics.cacheKey(artist, title, album, duration)`: the four joined,
lowercased, every run of non-alphanumerics a `-`, the duration in whole
seconds on the end (`applemusic.js`'s shape). Written to a temp name and
`mv`ed, never through `FileView.setText`.

**D3 When.** A lookup runs only while the media panel is open, `media.lyrics`
is true and the active player publishes a title and an artist (the
hidden-work rule: a closed panel costs nothing, and a cache hit is one
`cat`). A track change while open runs again. A lookup in flight when the
panel closes finishes into the cache and is served on the next open; a
result for a track the user has since left never lands (the serial guard).

**D4 What shows.** Only synced lyrics, ever. The lyrics block is absent
while there is nothing timed to show: lookup off, no track, loading, a
known miss, a failed lookup. No spinner, no `NO LYRICS` row: the owner's
rule is that untimed lyrics are not shown, and a placeholder that flashes on
every open of a track with no lyrics is worse than the panel it already
was. `media lyrics` over IPC says which of those it is.

**D5 The block.** The last section before the player chips: a `LYRICS`
`SectionLabel` over a clipped viewport `controlHeight * 5` tall. The active
line sits at the viewport's vertical centre, in `title` size, `medium`
weight, `foreground`; every other line is `body`, `mutedForeground`, and its
opacity falls with its distance from the active line (1, then 0.7, 0.45,
0.25 and no lower), which is the depth kopuz draws with blur and caelestia
with a mask, done here with the one dimension the rulebook allows. The
column travels so the arriving line lands on the anchor, on `spatial`;
colour and opacity change on their own clocks. A line with word timing
(enhanced LRC, `<mm:ss.xx>` inside the line) is drawn a word at a time: sung
words `foreground`, unsung `mutedForeground`, each crossing on `CAnim`, so a
word-timed line reads as a wipe and a line-timed one lights whole. A silence
of five seconds or more before the first line or between two lines is an
interlude row: three dots, `mutedForeground`, each turning `foreground` as its
third of the gap elapses. No glow, no blur, no shadow, no font-size
animation: the position clock is a `FrameAnimation` re-emitting the player's
`positionChanged` (Quickshell's own documented idiom) only while the panel is
open, the player is playing and lyrics are synced; the active index is the
last line whose time is at or under the position plus 100ms.

Pointer: a click on a line seeks there when the player can seek. Keyboard:
the lyrics are a cursor section between the tracks and the player chips.
Up and Down walk lines, Enter seeks, and while the cursor is in the section
the column follows the cursor rather than the song; Tab out and it follows
the song again.

**D6 The spectrum.** A band under the now-playing block, the content
column wide and `controlHeight` tall: 24 columns of the same `muted`
trough and bottom-up fill the bar cell draws, spaced `xxs`, coloured by the
same three energy bands. One cava process still: `Model.BAR_COUNT` becomes
24 and the bar cell draws `Model.downsample(levels, 6)`, the peak of each
group of four, so the six-track cell reads as it did. cava's framerate rises
to 60 for the band's sake, which costs nothing while nothing shows it. The
service's gate gains a second consumer: it runs while a track plays, motion
is on and (a bar cell is on screen or the media panel is open with
`media.visualizer` true). The band is absent when cava is not on PATH, when
`media.visualizer` is false, and it stays with empty troughs while the
panel is open and the track paused (the process is dead, the levels are the
baseline, which is the bar cell's own honesty). The cell stays the opt-in
`bar.layout` entry it was; the owner's own layout drops it.

**D7 Room on the bar.** Today an end region clips against the live centre
pixel by pixel (`Bar.qml`'s width caps), so a crowded strip cuts a cell in
half. Two rules replace that, in this order:

1. The now-playing cell gives ground first. Its label budget is worked out
   from the strip's slack the way the tray's is (`Tray.qml`'s `_refit`:
   assigned, not bound, from its own extent plus the slack, which the answer
   cannot move): `min(220, 15% of the strip, what is left)`, down to the
   cover or icon alone, with the title in the tooltip it already has.
2. What still does not fit hides whole cells. An end region's extent snaps to
   a cell boundary (`Layout.fitExtent`: the longest run of cells from the
   region's anchored end whose extents and gaps fit the room), never a pixel
   inside a cell. The centre keeps its floor-and-ceiling clamp, so the end
   region loses cells before the start region, and every cell comes back the
   moment room does.

`bar room` over IPC reports the slack, each region's cell and hidden counts
and the now-playing budget, per screen. The chevron stays config-only; a
hidden cell is not moved to it, it is simply off the strip until there is
room.

**D8 Configuration.** New: `media.lyrics` (bool, default true),
`media.visualizer` (bool, default true, the panel's band). No `visualizer.*`
keys; the cell is still governed by `bar.layout` alone.

**D9 IPC.** `media lyrics` returns JSON: `state` one of `off`, `idle`,
`loading`, `synced`, `none`, `error`; `source` `cache` or `lrclib`; `lines`,
`words` (bool), `index`, `position`. `bar room` as in D7.

## Verification

- `just test`: `tst_lyrics_model.qml` (cache key, LRC parse with multiple
  timestamps per line and enhanced words, metadata lines skipped, usable
  timing, index for time, interludes, depth opacity, lrclib URL and response
  picking), `tst_visualizer_model.qml` (downsample), `tst_bar_layout.qml`
  (`fitExtent`).
- `just vm-smoke --lyrics`: a word-timed LRC seeded into the isolated cache
  for `--media`'s fixture track; the panel open; `media lyrics` `synced` with
  the index advancing between two reads; the PNG read; the second player's
  track with a `.none` marker reads `none` and the panel is shorter.
- `just vm-smoke --spectrum`: no visualizer cell in the layout, the tone
  playing; no cava child before `panel open media`, one after, none after
  close; the PNG read.
- `just vm-smoke --bar-room`: a strip crowded past its length; `bar room`
  reports hidden cells and a now-playing budget under 220; the PNG shows a
  whole cell at each end region's inner edge.
- `--visualizer`, `--media`, `--chevron`, `--bar-layout` still pass.
