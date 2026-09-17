# M56: the lyrics pane at parity with kopuz

**Date:** 2026-09-17
**Status:** in progress on `m56-lyrics-parity` (worktree `../FormalShell-m56`).
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

### Task 3: the pane (spec P5 to P9, P11's panel fields)

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
