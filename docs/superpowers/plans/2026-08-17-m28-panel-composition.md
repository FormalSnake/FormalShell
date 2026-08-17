# FormalShell M28: finish the panel composition M26 started

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-17):** "most panels are a tad cleaner now but
there's room for improvement", then, against the ranked audit below, "fix
1--5 please".

M26 introduced `PanelHero`, explicit panel widths and the content/meta ink
split, but only converted the panels its own tasks named. A read-only audit
of all 13 panels (sources plus the rendered smoke screenshots in
`artifacts/`) ranked what is still wrong. This plan is items 1 through 5 of
that ranking, and nothing else.

**Line numbers in this plan came from the audit and predate M27's commits.
Verify each one before editing; the surrounding code is the authority.**

## The five

1. **`PanelHero` is used by 4 of 13 panels.** Weather, Calendar, Power and
   (as of `ddc6e7d`) Usage. Audio, Media, Network, Bluetooth, Display,
   Tailscale, SystemUpdate, Github and AppMenu still open cold on a
   `MetaLabel` header cell. DESIGN §2 item 13 says every panel opens with the
   one shared block.
2. **Audio's subject number is a cramped `body` row.** `AudioPanel.qml`
   renders `30%` at `fontSize.body` beside a bare MUTE label over a 6px
   track, three stacked things inside one padded row. The panel is about that
   number and never promotes it.
3. **MediaPanel is the worst-composed surface in the shell.** Roughly 96px of
   blank to the left of the title (an album-art slot reserved but never
   painted), the title elided at half width beside that blank, a row
   containing nothing but a 6px track, and three 13px transport glyphs
   floating in ~93px cells.
4. **NetworkPanel inverts its own ink hierarchy six times.** `WI-FI`,
   `SHARE`, `PASSWORD`, `SPEED TEST`, `DOWNLOAD` and `UPLOAD` are hardcoded
   all-caps `Text` at `body`/`foreground` with no tracking: band-1 loudness
   spent on the label, band-2 on the value. Breaks DESIGN §2 item 3
   (uppercase implies `MetaLabel` plus letter-spacing) and §1.4.
5. **Two toggle idioms inside one panel.** `DisplayPanel.qml` draws ON/OFF as
   a nested bordered `Cell` with `selected` inversion in one place and as a
   bare ink-promoted `MetaLabel` about 150 lines later. Same word, same job,
   two answers. M26's inline-toggle unification reached one and not the other.

## Global constraints, binding on every task

- ASCII/ledger grammar wins over upstream on every conflict. Radius 0,
  borders 2px, no blur, no shadows, no knobs, no pills, no gauges.
- Every gap, padding and font size resolves through `Theme.space` /
  `Theme.fontSize`. A raw pixel literal is a defect (`DESIGN.md:375-379`).
- **Do not repeat the duplication trap.** A hero must not restate a fact the
  section below it already owns in the same form. Two panels shipped that bug
  this week (the calendar's doubled year progress, `77b72ef`; the usage
  hero's near-miss with its own CLAUDE header). The hero carries the panel's
  subject; the sections carry the detail. If the hero would say exactly what
  the first row says, change what the hero says.
- **The hero title carries the instance, not the panel's own noun** (audit
  item 11). The card's title band already says `MEDIA:` / `NETWORK:`, so a
  hero titled "Media" is the same word twice. Use the track title, the
  connected SSID, the device name.
- `PanelHero` already has a `trailing` slot and zero callers. Where a panel's
  primary toggle currently occupies its own row, move it into the hero rather
  than inventing another row.
- Honest unavailable states, never faked data. A panel with nothing to show
  renders its own dim cell.
- Verification per task: `just vm-test`, `git add -A && just vm-lint`, then
  the named `just vm-smoke --panel <name>`. **Read the returned PNG** and
  compare it against the pre-change screenshot in `artifacts/`. A task that
  restyles a surface and reports green without reading its screenshot is not
  done.
- **Another session may be editing this repo.** Before committing, check
  `git status` and stage ONLY the files your own task touched. Never
  `git add -A` into a commit.
- Commit per task, conventional lowercase subject, no body, no
  Co-Authored-By, no em dashes. Exclude `CLAUDE*.md`.

---

## Task 1: Audio, promote the number the panel is about

Item 2, and item 1 for this panel.

- Open `AudioPanel.qml` with a `PanelHero`: speaker glyph, title = the active
  sink's own name (the instance, not the word "Audio"), `meta` = the sink
  state, `readout` = the volume percentage at `display`, `rail` = the volume
  fraction.
- Delete the now-redundant `OUTPUT:` header row and the cramped
  label/percent/track row it introduced. The hero replaces both.
- Mute is the panel's primary toggle: move it into the hero's `trailing`
  slot, the first caller that slot has had.
- Adopt upstream's header-line pairing for the REMAINING sections (audit's
  own recommendation): a section header cell carries its noun left and its
  numeric readout right on the same line, with any track underneath. That is
  one row saved per section and puts the label in band 2 where §1.4 wants it.
  Apply it to the per-app mixer rows too, so the panel has one rhythm.
- Keep the flat accent fill over a dither remainder. No knob, no radius.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel audio`. Read
the PNG against the previous audio screenshot in `artifacts/`.

Commit: `fix(audio): open on the volume instead of burying it`

## Task 2: Media, recompose it

Item 3, and item 1 for this panel. This is the largest task here; the surface
is currently mostly empty space.

- The album-art slot reserves roughly 96px and paints nothing when there is
  no art. Either paint it or collapse it: an unpainted reservation is dead
  space, and DESIGN's honest-state rule wants a real cell or no cell. Feed
  the art into the hero's glyph slot when present, and fall back to a glyph
  when absent, so the left edge lines up with every other panel either way.
- Hero title = the track title (the instance). `meta` = artist, or the player
  name when there is no artist. Never "Now playing" as the title: the card
  band already says `NOW PLAYING:`.
- The title currently elides at half width beside the blank. Once the blank
  is resolved it gets the full remaining width.
- The lone row containing nothing but a 6px track becomes a real row: elapsed
  and total on the header line (the same pairing Task 1 establishes), track
  underneath.
- The three transport glyphs render at 13px inside ~93px cells. Size them at
  `fontSize.heading` and let the cells size to their content, so the controls
  read as controls.
- Play/pause is the panel's primary toggle and belongs in the hero's
  `trailing` slot if it fits the transport row's logic better than a separate
  row; use judgement and say which you chose and why.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --media` (that flag
plays a real MPRIS fixture track, so the hero has genuine metadata to render;
`--panel media` alone would show only the honest empty state). Read the PNG
against `artifacts/media-final.png`.

Commit: `fix(media): fill the panel with the track instead of blank space`

## Task 3: Network, put the ink back the right way round

Item 4.

Six labels are hardcoded all-caps `Text` at `body`/`foreground` with no
letter-spacing: `WI-FI`, `SHARE`, `PASSWORD`, `SPEED TEST`, `DOWNLOAD`,
`UPLOAD`. Each names what its row contains, which is the exact definition of
a meta label.

- Route all six through `MetaLabel`, which owns uppercase and
  `letterSpacing.meta` in one place. The value or action beside each keeps
  content ink.
- Sweep the rest of the file for the same defect and fix what the sweep
  finds. Report the count.
- While here, item 15's network detail: field placeholders sit at
  `foregroundDim` and belong at `foregroundFaint` per §1.4.
- Do NOT restructure the panel or add a hero in this task. Task 5 does that.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel network`. Read
the PNG.

Commit: `fix(network): give every label its meta ink`

## Task 4: Display, one answer for ON/OFF

Item 5.

`DisplayPanel.qml` draws the same ON/OFF control two ways: a nested bordered
`Cell` with `selected` inversion, and a bare ink-promoted `MetaLabel` about
150 lines later. DESIGN §1.1's 2026-08-09 amendment settles it: a bare-label
control gets no cell fill, only ink promotion.

- Convert the bordered one to ink promotion, matching its sibling.
- Sweep the file for any third idiom and report what you find.
- Confirm the hit area survives the conversion. M27's review caught exactly
  that regression class once already.

Verify: `just vm-test`, `just vm-lint`, `just vm-smoke --panel display`. Read
the PNG and confirm the row lost its inner box without losing its target.

Commit: `fix(display): one idiom for on and off`

## Task 5: heroes for the remaining panels

Item 1, everything Tasks 1 and 2 did not already cover: `NetworkPanel`,
`BluetoothPanel`, `DisplayPanel`, `TailscalePanel`, `SystemUpdatePanel`,
`GithubPanel`, `AppMenuPanel`.

Each gets a `PanelHero` whose title is that panel's **instance**, not its
noun:

- Network: the connected SSID, `meta` = the connection state, `trailing` =
  the Wi-Fi radio toggle.
- Bluetooth: the adapter or the connected device, `trailing` = the radio
  toggle.
- Display: the focused output's name, `meta` = its resolution.
- Tailscale: this machine's tailnet name, `meta` = the backend state,
  `trailing` = the connect toggle.
- SystemUpdate: `readout` = the pending update count, `meta` = what they are.
- Github: `readout` = the open PR or issue count.
- AppMenu: the focused window's app name.

Rules:

- A panel whose backend has nothing to report renders an honest hero, not a
  fabricated one. No invented SSID, no fake device.
- Where the panel already has a header row saying the same thing the hero
  now says, delete the header row. Do not leave both.
- Do not give a panel a `readout` unless the panel is genuinely about a
  single number. A `display`-size string that is not the subject is noise.

This is seven panels; work through them one at a time and screenshot each.

Verify: `just vm-test`, `just vm-lint`, then `just vm-smoke --panel <name>`
for network, bluetooth, display, tailscale and github. Read every PNG.
SystemUpdate and AppMenu have no smoke flag: say so plainly in the evidence
rather than implying they were screenshotted.

Commit: `feat(panels): open every panel on its own subject`

---

## Review checkpoints

- **After Task 2**: hunt for a hero restating what the first row below it
  says (the duplication trap this plan names explicitly), a hero titled with
  the panel's own noun rather than its instance, dead space merely moved
  rather than removed, a raw pixel literal, and screenshots claimed but not
  read.
- **After Task 5**: hunt for panels given a `readout` that is not the
  panel's subject, fabricated hero content where the backend reports
  nothing, header rows left in place beside the hero that replaced them, hit
  areas lost in Task 4's conversion, `MetaLabel` hand-reimplemented instead
  of used, unpushed commits, and any smoke flag reported green whose artifact
  does not exist.

## Explicitly out of scope

Audit items 6 through 15, including the shared `PanelTrack` extraction (12
hand-rolled `DitherFill` tracks), PowerPanel's hero disappearing on AC,
section grounds, and the Tailscale online/offline ink collision. They are
real and they stay on the list; this plan is items 1 to 5 as asked.
