# FormalShell M26: quattro panel grammar, readability, interaction depth

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-17):** "Fetch the latest release of omarchy
quattro (now its public). I like their general panel layouts a lot, and also
how a lot of the info is displayed like date/time, their battery widget, a
lot of their features we don't have, etc. Investigate and implement with
subagents. Make sure to keep our ASCII style just improve the layouts and
such to make the shell more usable and readable"

Upstream read at `origin/quattro` HEAD `262d6f06` (2026-08-17), 23 commits
past the public `v4.0.0` tag (2026-08-14). MIT, DHH. Read-reference: nothing
in this plan copies upstream QML. Where a file below is substantially ported
it carries the attribution header CLAUDE.md requires, and no task in this
plan is expected to need one.

## What the investigation actually found

Four parallel read-only agents mapped omarchy's bar, its panel grammar, a
feature diff, and FormalShell's own internals. The headline is that **the
feature gap is close to empty**. The first-pass diff claimed emoji picker,
Wi-Fi QR share and a network speed test as missing; all three already ship
here (`shell/Menu/emoji.json`, `shell/Network/wifiqr.js`,
`shell/Network/speedtest.js`), and FormalShell is ahead upstream on
notification grouping, wallpaper theming, capture, hot corners and reminders.
Everything in this plan is therefore **layout, hierarchy and interaction**,
which is what the owner asked for anyway.

Three structural differences explain why omarchy reads better at a glance:

1. **Every panel opens with a hero block.** One glyph, one bold noun, one
   uppercase state line, one optional control, and, when the panel's whole
   point is a number, that number rendered far outside the type scale (28pt
   battery percent, 56pt temperature, 52pt date). FormalShell has `display`
   (26px) and `displayLarge` (30px) tokens defined at `DESIGN.md:322-323`
   and uses them in exactly one file in the entire shell,
   `Components/AuthPrompt.qml`. Every panel here opens straight into
   undifferentiated body-size rows.
2. **Panel width is a per-panel decision.** Upstream declares a desired
   width per panel and clamps it to the screen (network 985, audio 657,
   clock 560, weather 480, power 299). FormalShell has four sanctioned
   width steps (`DESIGN.md:347-350`, `popupWidth{Narrow,Default,Wide,Menu}`
   = 280/320/400/560) and `NetworkPanel.qml` never sets one, so the densest
   surface in the shell renders at the same 320 default as the simplest,
   squeezing signal bar, lock glyph, SSID, hover-revealed FORGET, status
   subline, inline password fields, QR matrix and speed test into roughly
   284px of content width.
3. **One cursor, shared by mouse and keyboard.** Upstream's
   `Ui/CursorSurface.qml` forbids a row from reading `containsMouse` for
   paint: hover writes panel cursor state at the root, and every row derives
   its fill from that state. This is what guarantees exactly one highlight
   on screen and is the precondition for keyboard navigation working at all.
   FormalShell panels paint from per-cell `hovered` and have no keyboard
   navigation: `rg` finds key handling in exactly two files under
   `shell/Surfaces/Panels/`, and one of them is an inline password field.

Two smaller findings carry disproportionate weight:

- **Bar cells still jitter.** M16 Task 2 put `Behavior on implicitWidth` on
  `ActiveWindow.qml:65-67` and `NowPlaying.qml:61-63`, and stopped there.
  `Battery.qml`, `AudioWidget.qml`, `WeatherWidget.qml`, `GithubWidget.qml`,
  `UsageWidget.qml` and `SystemUpdateWidget.qml` all render changing numeric
  text with no glide, so every tick snaps their width and shoves every cell
  to their right in the same region. `Osd.qml:14-16` states a "plan-wide
  no-jitter contract" that the bar does not honour.
- **Interaction depth is thin.** Upstream documents a left/right/middle/
  scroll action for nearly every bar widget (`manual/05-the-top-bar.md:17-33`)
  and treats the secondary buttons as where the good stuff lives. Of
  FormalShell's 23 bar widgets, exactly three (`BellWidget`, `Tray`,
  `AudioWidget`) handle anything but a left click.

## Deliberate scope cuts

- **Bar position and drag-to-rearrange.** `bar.position` is still marked
  reserved at `Core/Config.qml:10`, and upstream's left/right/bottom bars
  with vertical compact widget forms, drag-a-widget-to-reorder, and
  drag-the-bar-to-another-edge are a structural feature, not a readability
  one. Out of scope, worth its own milestone.
- **`centerAnchor`.** Upstream pins one center widget to true screen center
  so flanking widgets cannot push it. Genuinely good, but it only matters
  once the center region carries widgets that come and go, and Task 7's
  jitter fix removes most of the motivation. Deferred.
- **Dictation indicator**, which needs the external Voxtype daemon, and the
  **Dropbox panel**. Neither is installed on any host here.
- **Upstream's `memento mori` life-progress bar.** The year-progress rail in
  Task 4 is kept; the birth-year/life-expectancy half is not.

## Global constraints, binding on every task

- ASCII/ledger grammar wins over upstream's visual choices on every
  conflict. Radius stays 0, borders stay 2px, no blur, no shadows, no pill
  toggles, no knobbed sliders, no arc gauges, no chevrons. Where upstream
  uses `Qt.darker(fg, n)` to dim, use the `foregroundDim`/`foregroundFaint`
  ink bands from `DESIGN.md:§1.4`. Where upstream uses a 1px 12%-alpha
  `PanelSeparator`, use the shared-rule contract `Cell.qml` already draws.
- Every gap, padding and font size resolves through `Theme.space` /
  `Theme.fontSize`. A raw pixel literal is a defect (`DESIGN.md:375-379`).
- Panel widths come only from the four `popupWidth*` steps. Inventing a
  fifth literal is a defect.
- The shell never writes `settings.json`. Anything a click mutates at
  runtime goes to `$XDG_STATE_HOME/formalshell/state.json` via `Core/State`.
  Any file touching that singleton while importing QtQuick must
  `import qs.Core as Core` and say `Core.State`, per the M24 chevron trap
  documented in `CLAUDE.md`.
- Verification per task: `just test`, then `git add -A && just lint`, then
  the named `just vm-smoke` flag. **Read the returned PNG.** A task that
  changes a surface and reports green without reading its screenshot is not
  done.
- Commit per task, conventional lowercase subject, no Co-Authored-By, no
  body. Exclude `CLAUDE*.md` from commits.

---

## Task 1: `PanelHero.qml`, the shared panel opening block

Add `shell/Components/PanelHero.qml` and register it in
`Components/qmldir`. It is the block every panel opens with, and it is the
single place the `display`/`displayLarge` tokens become reachable outside
the lock screen.

API, all optional except `title`:

- `glyph` (string): leading Nerd Font codepoint, rendered in a fixed slot
  `Theme.space.xxl * 2` wide so a wider glyph cannot shift the title.
- `title` (string): the panel's noun, `fontSize.subtitle`, `foreground`.
  Sentence case, not uppercase: it is content, not a meta label.
- `meta` (string): the state line under the title. Renders through the
  existing `MetaLabel` so uppercase and `letterSpacing.meta` come from the
  one component that owns that contract, never hand-rolled.
- `readout` (string) and `readoutSize` (enum `display` | `displayLarge`):
  the oversized number, right-aligned, monospace tabular by construction
  (`DESIGN.md:485-488`). Absent by default.
- `trailing` (Component): a control slot, right-aligned, used when the hero
  itself owns a toggle.
- `rail` (real, 0..1, default -1 meaning absent): a full-width progress rail
  under the block, drawn as `DitherFill` for the unfilled remainder plus a
  flat `accent` fill, matching the existing slider idiom in
  `AudioPanel.qml:361-386`. No knob.

Height is content-derived, never fixed. The block draws its own bottom rule
via `Cell`'s shared-rule contract and nothing else: no box around the hero,
no second border inside the card's own frame.

Then adopt it in exactly two panels to prove the API before it spreads:
`PowerPanel.qml` and `WeatherPanel.qml`. Weather is the clearest case for
`readout` (the temperature) and Power for `readout` + `rail`.

Add a DESIGN.md §2 addendum documenting the hero as the standard panel
opening block, with the "panels whose point is a number promote that number
to `display`/`displayLarge`" rule stated as a checkable.

Verify: `just test`, `just lint`, `just vm-smoke --panel power` and
`--panel weather`. Read both PNGs, confirm the hero renders and that the
oversized readout has not broken the card's width or the dog-ear.

Commit: `feat(panels): open every panel with a hero block`

## Task 2: panel width discipline

Audit all 14 files in `shell/Surfaces/Panels/` plus the picker. Every one
declares `panelWidth` explicitly from the four sanctioned steps. Today most
inherit `popupWidthDefault` (320) by silence, including the two extremes.

Required outcomes:

- `NetworkPanel.qml` moves to `popupWidthWide` (400). It is the densest
  surface in the shell (`NetworkPanel.qml:1040-1119` squeezes a top line
  into ~284px) and 400 is the widest step that is not the menu's own.
- `BluetoothPanel.qml` and `AudioPanel.qml` take `popupWidthWide` if their
  content genuinely needs it after Task 1's hero lands, `popupWidthDefault`
  if it does not. Decide by reading the smoke PNG, not by guessing.
- Panels that are genuinely narrow (`CalendarPanel`, `WeatherPanel` at 280
  today) keep `popupWidthNarrow` but state it explicitly.
- Add the rule to DESIGN.md next to the width table at `:347-350`: a panel
  that does not name its width is a defect, silence is not a default.

Verify: `just test`, `just lint`, `just vm-smoke --panel network`,
`--panel bluetooth`, `--panel audio`. Read all three PNGs and confirm no
row now over-runs or leaves a dead gutter.

Commit: `fix(panels): give every panel an explicit width step`

## Task 3: battery and power

The owner named the battery widget specifically. Upstream's version is
richer in three ways worth having, all in
`shell/plugins/panels/power/Model.js` and `Panel.qml` upstream.

**Charge-threshold detection.** A laptop holding at a configured charge
limit currently reads here as plain "charging" forever. Upstream
distinguishes it three ways (`Model.js:52-64`): UPower state
`PendingCharge`; `FullyCharged` reported below 99%; or `Charging` with a
near-zero rate or a time-to-full of 8 hours or more. In that state the icon
uses the discharging ramp rather than the charging one and the label reads
a distinct "THRESHOLD" state. Implement the same three-way detection in
`shell/Surfaces/Bar/widgets/Battery.qml` and surface it in both the bar
cell's tooltip and the power panel's hero meta line. Verify the UPower
property semantics against quickshell's own C++ source before writing them,
per CLAUDE.md's standing warning that `percentage` is 0..1 and has already
caused two shipped bugs.

**Hero readout.** `PowerPanel.qml` opens with the Task 1 hero: battery
glyph, "Battery", uppercase state meta (`ON BATTERY` / `CHARGING` /
`THRESHOLD` / `FULLY CHARGED`), the percentage as `displayLarge`, and the
charge level as the hero `rail`. Upstream rotates flavour text through the
meta line every 2.8s; do not port that, it is noise on a brutalist surface
and it fights `DESIGN.md`'s motion band.

**Stats ledger.** Under the hero, a ruled two-column ledger of the numbers
UPower already exposes and this panel currently drops: design capacity,
charge cycles, time remaining (or time to full), and discharge rate (or
"HOLDING" in the threshold state). Labels in `foregroundDim` via
`MetaLabel`, values in `foreground`. This is exactly the mek ruled-row
idiom `DESIGN.md` sanctions for tabular content. Rows stay mounted once
first populated so an AC plug/unplug does not collapse and re-expand the
panel.

Verify: `just test`, `just lint`, `just vm-smoke --panel power`. Read the
PNG. The VM has no real battery, so the honest-unavailable-state rule
applies in full: the hero must render an honest absent state rather than a
fabricated percentage, and that is what the screenshot needs to show.

Commit: `feat(power): read battery state as a hero and a stats ledger`

## Task 4: clock and calendar

The owner named date/time display specifically. Today the bar clock is
`Qt.formatTime(_now, "hh:mm")` with nothing else (`Clock.qml:22`), and the
calendar panel hand-builds a `_monthNames` array
(`CalendarPanel.qml:67-70`).

**Bar clock format ring.** Right-click cycles a format ring and persists
the choice. Upstream's ring (`clock/Model.js:21-30`) pairs every 24h preset
with its 12h twin so one click swaps notation. Adopt that shape with
FormalShell's own presets: `hh:mm`, `h:mm AP`, `ddd hh:mm`, `ddd d MMM hh:mm`,
`yyyy-MM-dd hh:mm`, and an ISO-week preset `d MMM 'W'ww`. Qt has no ISO-week
specifier, so `ww` is substituted by hand before `Qt.formatDateTime` runs,
the same way upstream does at `Model.js:135-141`. **The choice persists to
`state.json`, never `settings.json`** (hard rule). The cell must carry the
Task 7 width behaviour, since these formats differ wildly in width.

**Calendar grid.** Three changes, all readability:

- Always render 6 week rows regardless of month, so stepping months never
  resizes the card. Upstream does this at `clock/Model.js:223-263` and it
  is the single biggest reason its calendar feels stable.
- An ISO week-number column down the left, each row numbered by the ISO
  week owning that row's Thursday. Rendered in `foregroundFaint`, the band
  `DESIGN.md:§1.4` reserves for the quietest ink, so it never competes with
  the dates.
- Out-of-month days drop to `foregroundFaint`, today keeps the accent-pair
  inversion it already has.

**Calendar hero.** The panel opens with the Task 1 hero: today's date as
the `display` readout, weekday as the title, and a year-progress `rail`
(day-of-year over days-in-year) with the percentage as the meta line.
Replace the hand-built `_monthNames` array with `Qt.locale()` month names
while touching this file.

Verify: `just test`, `just lint`, `just vm-smoke --panel calendar` (that
flag already stages a real one-event `.ics` fixture dated today). Read the
PNG and confirm the week column, the 6-row grid, and that the fixture event
still renders in the events ledger.

Commit: `feat(calendar): add a date hero, ISO weeks and a stable grid`

## Task 5: ink hierarchy and section rhythm

`DESIGN.md:§1.4` mandates a content/meta ink split that several panels do
not honour, so their rows all read at one loudness with nothing to scan by.

- `WeatherPanel.qml:224-252`: the forecast row draws glyph, weekday and
  high/low all at `foreground`/`body`. Weekday becomes the dimmed anchor,
  the temperature stays `foreground`.
- `AudioPanel.qml:340-346`: the output-percent row has label and value at
  equal weight. Label to `foregroundDim`.
- `NetworkPanel.qml:1121-1128`: the CONNECTING/FAILED status subline is a
  raw `Text` at `fontSize.caption` with no `letterSpacing`, bypassing the
  uppercase-plus-tracking contract `DESIGN.md:§2 item 3` states as a
  checkable. Route it through `MetaLabel`.
- Sweep the remaining panels for the same two defects (raw caption `Text`
  where `MetaLabel` belongs, and rows with no dimmed anchor) and fix what
  the sweep finds. Report the count.

Establish one section rhythm across panels while here: section header to
first row, and last row to next section header, each resolve through a
single named token rather than per-panel choices. Upstream's equivalent
invariant is 14 above a rule, 14 below, 10 header-to-row; pick FormalShell's
own from the existing `Theme.space` ladder and apply it uniformly.

Verify: `just test`, `just lint`, `just vm-smoke --panel weather`,
`--panel audio`, `--panel network`. Read all three PNGs.

Commit: `fix(panels): restore the content and meta ink split`

## Task 6: one idiom for inline toggles

`DESIGN.md:§1.1`'s 2026-08-09 amendment says a bare-label control gets no
cell fill, only ink promotion. `Center.qml:244-270` follows it. Three
panels still wrap the same class of control in a full bordered `Cell`,
adding rule lines inside already-tight rows and leaving two visual idioms
for one UI role:

- `AudioPanel.qml:254-264,348-357` (mute)
- `NetworkPanel.qml:1241-1254` (WI-FI POWER), `:1299-1312` (QR),
  `:1415-1428` (PASSWORD SHOW/HIDE)

Convert all five to ink promotion. Sweep for others and report the count.

Verify: `just test`, `just lint`, `just vm-smoke --panel audio` and
`--panel network`. Read both PNGs and confirm the rows lost a rule line
each without losing their hit area.

Commit: `fix(panels): promote ink instead of boxing inline toggles`

## Task 7: the bar's no-jitter contract

`Osd.qml:14-16` states a plan-wide no-jitter contract the bar does not
honour. M16 Task 2 glided `ActiveWindow` and `NowPlaying` and stopped.

- Extend `Behavior on implicitWidth` (`Theme.motion.standard`, `OutCubic`,
  matching the two existing sites exactly) to `Battery.qml`,
  `AudioWidget.qml`, `WeatherWidget.qml`, `GithubWidget.qml`,
  `UsageWidget.qml` and `SystemUpdateWidget.qml`.
- Give glyph-only cells a fixed glyph slot so a variable-width Nerd Font
  codepoint cannot shift its neighbours. Upstream pins every bar icon to a
  27px slot for exactly this reason (`Ui/BarIconButton.qml:20-21`); derive
  FormalShell's from `Theme.space`, do not copy the literal.
- Do not port upstream's `OpticalGlyph` ink-bounds re-centering. It is a
  real improvement but it is a second mechanism, and the fixed slot solves
  the jitter this task is about. Note it in the plan's follow-ups instead.

Verify: `just test`, `just lint`, `just vm-smoke`. Read the PNG. The
static screenshot cannot show a glide, so additionally state in the commit
evidence which six files gained the behaviour and confirm by diff that the
duration and easing match the two pre-existing sites token for token.

Commit: `fix(bar): glide every numeric cell's width`

## Task 8: panel keyboard navigation

The precondition is the single-cursor rule. Today panels paint from
per-cell `hovered`, so mouse and keyboard cannot share a highlight.

- Add cursor state to `Components/Panel.qml`: an active-cursor flag and a
  selected row index. Rows derive their paint from that state. A row must
  not read `containsMouse` for paint; a mouse enter writes the panel's
  cursor state and the paint follows from it. This is upstream's
  `CursorSurface` contract (`Ui/CursorSurface.qml:14-40`) restated in
  FormalShell's `Cell` terms, and it is what guarantees exactly one
  highlight on screen.
- Key handling on the panel root, with `Keys.priority: Keys.BeforeItem` so
  arrows beat an inner Flickable's scroll: arrows and `hjkl` move, Return
  and Space activate, Escape closes. The **first** arrow press only makes
  the cursor visible without moving it, so the highlight appears where the
  user can see it before anything happens (upstream does this deliberately).
- A live inline text field (`NetworkPanel`'s password entry) blocks the
  whole set while focused.
- Selection uses the accent-pair inversion `Theme.inverted()` already
  provides. No new selection idiom.

Do **not** port upstream's Tab-to-neighbouring-panel behaviour in this
task; it needs the panel registry to carry an ordering and is a separate
change.

Verify: `just test`, `just lint`. Driving real keys needs a virtual-keyboard
client, and `dev/smoke-niri.sh --lock` already proves `wtype` works in the
rig: add a `--panel-keys` leg (or extend `--panel`) that opens the audio
panel, `wtype`s Down Down Return, and screenshots the result. Read the PNG
and confirm the cursor moved and exactly one row is highlighted. If `wtype`
cannot reach an `OnDemand`-focus panel surface, say so explicitly with the
failure output rather than claiming the path works.

Commit: `feat(panels): navigate rows by keyboard on a shared cursor`

## Task 9: the bar widget action contract

Upstream treats right and middle click as where the good stuff hides and
documents the whole table at `manual/05-the-top-bar.md:17-33`. Three of
FormalShell's 23 widgets handle anything but a left click.

Add secondary actions only where one is genuinely obvious. Proposed set,
adjust with reasons if a widget makes a better case:

| Widget | Right | Middle / scroll |
| --- | --- | --- |
| Clock | cycle the format ring (Task 4) | open the calendar panel |
| Weather | refresh | open the forecast panel |
| Audio | mute | scroll: volume (exists, keep) |
| Battery | toggle the percentage label | open the power panel |
| Network | toggle Wi-Fi radio | open the network panel |
| Bluetooth | toggle the radio | open the bluetooth panel |
| NowPlaying | next track | scroll: previous/next |
| Microphone | mute | open the audio panel |

Every action must already exist as a service call; this task wires buttons
to existing behaviour and adds no new backend. Each secondary action states
itself in the cell's tooltip, otherwise it is undiscoverable, which is the
one real criticism of upstream's design here.

Document the full table in `docs/USAGE.md` alongside the existing IPC
target list.

Verify: `just test`, `just lint`, `just vm-smoke`. Read the PNG to confirm
nothing shifted. The rig has no synthetic pointer, so right and middle
clicks cannot be driven headlessly: state that limit plainly in the commit
evidence rather than implying the actions were exercised.

Commit: `feat(bar): give every widget its secondary actions`

---

## Review checkpoints

- **After Task 4** (tasks 1-4): the hero component, width discipline,
  battery and calendar. Hunt for invented width literals, `display` tokens
  applied where the panel's point is not a number, `settings.json` writes
  from the clock's format ring, a `Core.State` import trap per M24, UPower
  percentage treated as 0..100, and screenshots claimed but not read.
- **After Task 9** (tasks 5-9): hunt for design drift (a pill, a knob, a
  chevron, a non-zero radius, a raw pixel literal), rows still painting
  from `containsMouse` after Task 8, secondary actions wired to backends
  that do not exist, unpushed commits, and any task reporting green whose
  named smoke flag was never actually run.

## Follow-ups this plan deliberately leaves open

- Bar position (left/right/bottom) and drag-to-rearrange.
- `centerAnchor` for the center region.
- `OpticalGlyph` ink-bounds re-centering for Nerd Font glyphs.
- Tab to the neighbouring panel, which needs panel ordering in the registry.
- Panel summon hotkeys. The `panel` IPC target already supports this; it
  needs compositor keybinds in `shell/Compositor/keybinds.js`, which
  currently has none for panels.
