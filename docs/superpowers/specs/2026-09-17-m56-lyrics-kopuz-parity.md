# M56: the lyrics pane at parity with kopuz

**Date:** 2026-09-17
**Over:** the M55 spec (`2026-09-14-m55-lyrics-spectrum-room.md`). M55's D3
(when a lookup runs), D4 (only synced lyrics show), A1/A2 (the two-column
panel) and the keyboard section stand. D1, D2, D5, D9, A3 and A3b are
replaced by what follows.

## The brief

Owner, 2026-09-17: "Is the lyrics view like in kopuz, where there's proper
support for apple music style lyric fade, blur DoF, and syllable swipe? In
kopuz the system is very robust. I want it ported to the shell. Blur can be
optional but on by default." Then: "the chunk wipe doesn't appear to work, I
never saw it. In kopuz you can always see it even if the lyrics file doesn't
properly provide it." Then: "I want full parity with kopuz basically."

Why the wipe never showed: the shell asks lrclib alone, and lrclib almost
never carries `<mm:ss.xx>` word stamps, so `_hasChunks` was false for nearly
every track. kopuz's wipe is always there because its first provider is
paxsenix's Apple Music endpoint, which returns syllable timing, line end
times, background vocals and duet turns for most of a mainstream catalogue.

The reference is `../kopuz` at b2a8a601: `crates/utils/src/lyrics.rs`,
`crates/utils/src/lyrics/{model,lrc,paxsenix}.rs` and
`crates/components/src/playback/lyrics.rs`. kopuz is the owner's own project;
port its mechanics and constants directly.

## Decisions

**P1 The line model.** One normalised shape for every provider, kopuz's
`LyricLine` in the shell's own field names:
`{time, end, text, words: [{time, text, joinsNext}], parent, background,
oppositeTurn, estimated}`. `end` is a number or `null`; `parent` an index or
`null`; `estimated` is true when `words` were synthesised (P4). `parseLrc`
keeps its M55 behaviour and fills the new fields with their empty values.
A translation line merged on an equal stamp is wrapped in parentheses unless
it already is (kopuz's `append_translation`).

**P2 Providers.** Four, kopuz's order and its rule that word timing beats
line timing:

1. A sibling `.lrc` beside the track when MPRIS gives a `file://`
   `xesam:url` (same basename, `.lrc`). A hit with usable timing ends the
   chain.
2. paxsenix Apple Music: iTunes search (`https://itunes.apple.com/search`,
   `term` = "title artist", `entity=song`, `limit=8`, `country=US`), the
   best song by kopuz's `lyrics_match_score` (token overlap, 55 floor,
   `(feat.`/`(ft.`/`(featuring` stripped) plus `12 - |delta seconds|`, a
   candidate more than 12s off the MPRIS length dropped; then
   `https://lyrics.paxsenix.org/apple-music/lyrics?id=<trackId>`. `content`
   rows become lines exactly as `paxsenix_apple_to_lines` does it: `text`
   parts into `words` with `part: true` meaning the next part joins with no
   space, `should_insert_apple_space`'s punctuation rule, `backgroundText`
   as its own `background: true` line after its parent with `parent` set
   and its start the first part's stamp, a row with `background: true` and
   no `backgroundText` a background line itself, `oppositeTurn` carried,
   milliseconds to seconds. The response's `lrc` is the fallback when
   `content` has no usable timing. `plain` is never read (D4).
3. paxsenix YouTube: `/youtube/search?q=`, `best_youtube_result`'s scoring
   (same floor, same 12s window, `m:ss` durations), then
   `/youtube/lyrics?id=` as LRC text.
4. lrclib, as M55 has it.

2, 3 and 4 start together. Quality is kopuz's `lyrics_quality`: 2 when any
line has more than one word chunk, 1 for line timing, 0 for nothing. The
first quality-2 answer wins outright. Otherwise the chain waits for every
provider to settle and takes the highest quality, ties going to the lower
number in the list above (Apple's line timing carries end times, lrclib's
does not). Timeouts: 10s on the Apple lyrics call, 5s on the searches and
lrclib, 3s on the YouTube lyrics call. Musixmatch (off by default in kopuz,
an unofficial token dance), embedded tag lyrics and the Jellyfin/Subsonic
server APIs are out of scope.

**P3 Cache.** `$XDG_CACHE_HOME/formalshell/lyrics/<key>.json` holds
`{source, lines}` in P1's shape, kept forever; `<key>.miss` is the empty
seven-day marker. A result is written to disk only when every started
provider answered definitively (a hit or an honest miss); a run where any
provider failed on the network is kept for the session only, so a track
that got lrclib's line timing during a paxsenix outage asks again next
session. M55's `.lrc` and `.none` files are neither read nor written; the
service removes them once at startup.

**P4 The wipe is always there.** A line with provider chunks wipes by them.
A line without (`words` empty) gets synthesised ones: one chunk per
whitespace-separated word, the line's span (`time` to `end`, or to the
smaller of the next main line's start and `time + 7s`) shared between them
in proportion to their character counts, `estimated: true` on the line.
`media lyrics` reports it, so a leg can tell a real syllable track from an
estimated one. Interlude rows and merged translation text never get chunks.

**P5 Which lines are lit.** kopuz's functions, ported whole with their
tests: `main_line_indices`, `next_main_line_start`, `line_active_at` (a line
with an end goes dark at it unless the next main line starts within 3s, the
seamless gap), `active_main_line_index`, `background_line_bound`,
`active_secondary_lines` (a background line is judged on its own timing and
can stay lit into the next main line), `line_end_estimate` and
`build_display_lines` (interludes from the end of the whole run including a
background line that outlasts its parent, `parent` remapped). Between lines
with no seamless gap nothing is lit and the depth ramp holds its last
anchor. The position every one of them reads is `MediaService.position`
minus `media.lyricsOffsetMs / 1000`.

**P6 The wipe, soft.** Every lit line (the main one and each secondary)
draws its chunks; every other line is plain text. A chunk is the
`mutedForeground` word under a `foreground` copy masked by a horizontal
gradient whose soft band (kopuz's 46% to 54% of a 220% wide gradient, so
about a fifth of the chunk's width) slides across with the chunk's progress;
unsung text reads at kopuz's 0.45 of the sung alpha. The span is capped at
1.2s. The chunk being sung carries a glow (white at 0.3 alpha, 4px growing
to 10px) that decays over 0.6s once the chunk ends. Both are `MultiEffect`
(`QtQuick.Effects`, in qtdeclarative, no new dependency): `maskSource` for
the band, `shadowEnabled` with a zero offset for the glow. Background lines
draw at 0.7 alpha, their unsung part at 0.7 x 0.45.

**P7 Depth of field.** Every line that is not lit blurs by its distance in
display rows from the anchor: `min(distance x 1.1px, 6px)` (kopuz's rightbar
ramp, the pane's type being that size), scaled by
`media.lyricsBlurStrength / 100`, quantised to 0.5px, animated on the
`effects` clock. The anchor is the active main line, else the highest lit
secondary, else the last anchor. A hovered line or the keyboard cursor's
line is lifted to 0 so it can be read before it is chosen. The effect
exists only on rows inside the viewport with a blur above 0; rows outside
it carry no layer. `media.lyricsBlur` false removes every blur and leaves
M55's opacity ramp doing the depth alone; with blur on the ramp stays, so a
far line is both dim and soft. `media.lyricsBlur` does not gate the glow or
the soft band.

**P8 Lines, laid out.** Main lines left-aligned at `title` size. When any
line in the track has `oppositeTurn`, those lines are right-aligned, italic,
scaled from `Item.Right`, and every line is capped at 90% of the pane's
width so the two voices read as sides. Background lines draw at `body`
size, indented one `controlPaddingX` on their voice's side. Activation is
still the transform (0.85 to 1) and never a relayout; a background line
activates to 0.9. A line arriving at lit fades from 0.68 to 1 over 260ms
(kopuz's `fadeLineIn`).

**P9 Scroll.** The lit main line rests 42% down the viewport (kopuz's
comfort offset), not at its centre, travelling on `spatial`. A wheel over
the pane takes the scroll over: the column follows the wheel, clamped to its
own ends, the song no longer moves it, and a resync button (an `Icon` named
`refresh-cw`, a `radiusMd` ghost control at the pane's bottom right, in the
cursor section's tab order after the lines) appears. The button, a new
track, or the keyboard cursor entering the section re-arms follow. Hover
never scrolls (M55's amendment stands).

**P10 Configuration.** `media.lyricsBlur` (bool, default true),
`media.lyricsBlurStrength` (int 0 to 200, default 100),
`media.lyricsOffsetMs` (int, -5000 to 5000, default 0, positive holds the
lyrics back). `media.lyrics` stands. All read through `Config.get`,
documented in `Config.qml`'s header and `docs/` where M55's key is.

**P11 IPC.** `media lyrics` adds `end`, `background`, `oppositeTurn` and
`estimated` per line, and at the top level `active` (the main index into
the display lines, -1 for none), `secondary` (array of lit secondary
indices), `blur` (bool), `follow` (bool, false after a wheel takeover) and
`quality` (0, 1 or 2). `source` is one of `local`, `apple`, `youtube`,
`lrclib`, `cache`.

**P12 The rulebook.** `docs/DESIGN.md` and the repo `CLAUDE.md` say nothing
in the shell blurs or shadows anything. The lyrics pane's depth of field and
the sung-chunk glow are the exception, the owner's call of 2026-09-17, and
both files say so where the rule is stated. Nothing else gains a blur.

**P13 The pane on the right** (owner, 2026-09-17: "move lyrics to the right
side of the panel, this way it feels less jarring when the lyrics suddenly
load"). M55's A1 is reversed: the now-playing column leads and the lyrics
pane trails it, same gutter, same equal split. The column keeps its place
when lyrics arrive and the panel grows away from it, so nothing the pointer
or the eye was on moves. Where the panel's own anchoring would shift the
column as the width morphs (a panel hung off a right-region cell grows to
the left), the morph holds the column's leading edge still and the pane
opens out of its trailing side. Cursor sections keep their order.

## Verification

- `tests/tst_lyrics_model.qml`: kopuz's own test cases for P5 ported by name
  (the `The Chain` overlap, the untimed background line, the assumed tail,
  the intro and gap interludes, the background line outlasting its parent),
  plus the paxsenix row conversion, the match scoring, P4's synthesis and
  the provider ranking, all against fixtures written for the test (no
  copyrighted lyric text in the repo).
- `--lyrics` seeds a P3 cache file with a syllable line, a background line
  that overlaps the next main line, and a duet turn; asserts `active`,
  `secondary`, `quality: 2` and `estimated: false` off `media lyrics`, a
  second track with line timing only reporting `estimated: true` with its
  wipe visibly partway in a frame, and the `.miss` track as before.
- `--lyrics-blur`: one session, a frame with `media.lyricsBlur` true and one
  after the settings symlink is retargeted to false (`config_reload.sh`'s
  method), a crop over a far line compared by edge energy: lower with blur
  on. IPC `blur` agrees with each frame.
- The provider chain is proven against the real services once, by hand, in
  the VM (`dev/vm.sh run` with a real track over an mpv MPRIS fixture), and
  the evidence recorded in the plan; legs never touch the network.
- Both Linux hosts rebuilt onto the merged HEAD at the end.
