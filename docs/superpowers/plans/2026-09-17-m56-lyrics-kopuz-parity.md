# M56: the lyrics pane at parity with kopuz

**Date:** 2026-09-17
**Status:** implemented 2026-09-17 on `m56-lyrics-parity` (worktree
`../FormalShell-m56`), oldest first: 66114ef (this plan and the spec),
a42dce5 (docs, the pane moved to the panel's trailing side), 9196c11 (the
line model at kopuz's shape, paxsenix rows, the lit set, estimated
chunks), 7f0c9fd (apple music and youtube through paxsenix beside
lrclib, ranked by timing, the json cache), 76908ad (the pane itself: soft
wipe and glow, depth of field, several lines lit, the trailing side),
7a881f8 (docs, lyrics load on the track change rather than on open),
7b1d175 (lyrics load on the track change itself, not on open), b0b1cdb
(the legs for the lit set, the estimated wipe, the blur key and the held
column). Task 5 is the docs commit carrying this line.

Where the shipped code deviates from the task text, on purpose:

- Task 2: the by-hand provider run only exercised Apple Music, since its
  quality-2 answer wins the race outright and nothing waits for YouTube or
  lrclib to finish behind it. `follow` lives on `LyricsService` rather than
  the pane so IPC can read it, and a panel reopen re-arms it too, not only
  a wheel takeover's own listed triggers.
- Task 3: `MultiEffect`'s mask thresholds alpha rather than multiplying it,
  so the unsung line's 0.45 lives in the `mutedForeground` copy under the
  mask and the mask itself carries only the soft band. The arrival fade
  runs on `effectsSlow` (300ms) rather than a value the surface picks,
  since `docs/DESIGN.md` forbids a surface writing its own duration. The
  leading-edge hold gives way to the screen's far padding, so an
  anchorless `panel open media` near the screen edge still slides; the leg
  uses `panel toggle media` instead. The pane is its own file,
  `shell/Surfaces/Panels/LyricsPane.qml`, rather than nested under a
  `Media/` directory.
- Task 4: fixed an out-of-range read in the model's lit-set functions,
  found when the panel's two bindings disagreed for one evaluation. P13's
  hold check lives inside `lyrics.sh` rather than a leg of its own. The
  blur leg's margin is `off > on * 1.10` against a measured 1.15 to 1.24.
**Spec:** `docs/superpowers/specs/2026-09-17-m56-lyrics-kopuz-parity.md`
(wins on conflict), over the M55 spec.

## Owner's ask (2026-09-17)

Full parity with kopuz's lyrics view: the Apple Music style fade, the depth
of field blur (optional, on by default), the syllable wipe, and the wipe
showing on every track rather than only on the rare enhanced LRC. Merge to
main at the end and rebuild both Linux hosts.

## Where M55 stands against kopuz (read 2026-09-17, kopuz b2a8a601)

Has: lrclib, enhanced LRC chunks, a hard-edged clip wipe on the one active
line, the opacity ramp, the interlude note, click and keyboard seek.
Missing: the paxsenix Apple Music and YouTube providers with quality
ranking (the reason no wipe ever showed), line end times and the seamless
gap, background and duet lines, several lines lit at once, the soft wipe
band, the glow, the blur ramp with hover lift, the 42% comfort offset, the
wheel takeover with a resync button, the lyrics offset.

## Tasks

One subagent per task, in order, each ending on its own verification with
the output read, then one commit. Every VM command goes through
`dev/vm-lock.sh`. `git add` new files before any nix build.

### Task 1: the model (spec P1, P4, P5, and P2's pure half)

`shell/Lyrics/model.js`, `tests/tst_lyrics_model.qml`. The normalised line
shape; `parseLrc` filling it, translations parenthesised; `fromPaxsenixApple
(bodyText)` and its space rule; `matchScore`, `bestItunesSong`,
`bestYoutubeResult`, `parseColonDuration`; `quality`, `pickBest(results)`
with P2's tie order; the URL builders for iTunes and both paxsenix routes;
`synthesiseWords(lines)`; P5's functions under camelCase names, replacing
`indexForTime` as the panel's source of truth (`activeMainIndex`,
`activeSecondary`, `displayLines` with `parent` remapped); `blurFor
(distance, strength)` with P7's ramp and quantum; `comfortY`. Delete what
the new functions replace. Tests: kopuz's cases by name plus the rest of
the spec's list. Verify: `just test`.

### Task 2: LyricsService (spec P2, P3, P10's offset, P11)

`shell/Services/LyricsService.qml`, `shell/Ipc/MediaIpc.qml`,
`shell/Core/Config.qml`, `MediaService` if `xesam:url` is not exposed yet.
The local `.lrc` step, the three remote providers started together with
their own timeouts, the ranking, the definitive-answer rule for disk
writes, the `.json`/`.miss` cache, the one-time removal of M55's `.lrc` and
`.none` files, `lines` published in P1's shape with P4 applied. `media
lyrics` per P11 (the fields the panel owns, `active`, `secondary`, `follow`,
`blur`, arrive in task 3; add the service's now). Verify: `just test`,
`just lint` in the VM, and the by-hand provider run the spec asks for, its
output pasted under "Evidence" below.

### Task 3: the pane (spec P5 to P9, P13, P11's panel fields)

P13 first: the pane moves to the trailing side of the row, and a frame
burst through a lyrics arrival shows the now-playing column's leading edge
at one x throughout.

`shell/Surfaces/Panels/MediaPanel.qml`, split into
`shell/Surfaces/Panels/Media/LyricsPane.qml` and `LyricLine.qml` if the
file's own conventions allow a panel to own a directory (mirror a sibling
that already does; otherwise keep it in the one file). Lit set from the
model, the masked wipe and glow, the blur ramp with hover and cursor lift
and the in-viewport gate, duet and background layout, the arrival fade, the
42% anchor, the wheel takeover and the resync button in the cursor order.
Load the `animate` and `better-ui` skills first; motion goes through
`Anim`/`CAnim` and `docs/DESIGN.md` §1. Verify: `just test`, `just lint`,
`dev/vm-lock.sh just vm-smoke --lyrics` with the PNG read.

### Task 4: the legs (spec Verification)

`dev/smoke.d/lyrics.sh` reworked for the P3 cache and the new assertions,
`dev/smoke.d/lyrics_blur.sh` new, `dev/smoke.d/README.md` and the flag
table wherever `--lyrics` is registered. Verify: both legs green in the VM,
every PNG read, then the whole media group (`--media`, `--spectrum`,
`--lyrics`, `--lyrics-blur`) once more for regressions.

### Task 5: the record

`docs/DESIGN.md` and `CLAUDE.md` per P12, the two new legs in `CLAUDE.md`'s
list, `Config` docs for P10's keys, this plan's Status line with the commit
hashes and any deviation. Run `humanizer` over the prose. Then merge to
main, push, and rebuild g815 and e1504g per `CLAUDE.md`.

## Evidence

Task 2, by hand, in the VM (2026-09-17): a real mpv MPRIS player tagged
"Blinding Lights" / "The Weeknd" / "After Hours", 200s of generated silence
(iTunes lists the real track at 200.046s), no cache seeded, no `.lrc` beside
the fixture file. `panel open media` then `media lyrics` polled until the
provider race left `loading`:

```
{
  "state": "synced",
  "source": "apple",
  "quality": 2,
  "words": true,
  "blur": true,
  "lineCount": 41,
  "firstLineWordCount": 4,
  "hasBackground": true
}
```

Task 3, P13, in the VM (2026-09-17), measured by hand with a temporary probe
leg: two mpv players, a `<key>.json` seeded for one and a `<key>.miss` for
the other, `panel toggle media` opened under the bar's own `nowPlaying` cell
on the untimed track, then `media select` onto the cached one, with six
frames armed 0.1s to 1.6s into the arrival. The card's left edge and the
now-playing title's own leading edge in each frame, in output pixels:

```
p13-narrow  left=766 text=767 right=1220
p13-frame0  left=766 text=767 right=1220
p13-frame1  left=766 text=767 right=1220
p13-frame2  left=766 text=767 right=1220
p13-frame3  left=766 text=767 right=1403
p13-frame4  left=766 text=767 right=1570
p13-frame5  left=766 text=767 right=1568
p13-wide    left=766 text=767 right=1568
```

The panel grew out of its trailing side over frames 3 to 5 and neither the
card's leading edge nor the column's title moved a pixel. The probe leg and
its artifacts were deleted after the run; the permanent leg is Task 4's.
A panel whose cell sits close enough to the screen's trailing edge cannot
hold that edge at all (the `--lyrics` leg's own anchorless open is one: 840
wide against a 1920 output, its left edge lands at 1068 against the narrow
panel's 1428), and `frameAlong`'s far clamp is what wins there.

paxsenix Apple Music won the race outright on its own quality-2 hit
(word-level timing throughout, a background line at index 28 with
`parent`/`background` set, interludes spliced into the display set,
`active: 0` on the opening one). YouTube and lrclib were never inspected
past that point (the early-decided path spec P2 asks for), so this run
doesn't independently prove their own parsing; Task 1's fixture-based tests
cover `bestYoutubeResult`/`fromPaxsenixApple`/lrclib's chain directly. The
probe leg (`dev/smoke.d/probe.sh`, temporary) and its artifacts were deleted
after the run; nothing from it is committed.
