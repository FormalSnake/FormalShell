# FormalShell M23: bar density and Bartender-style tray buckets

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. The spec wins over
> this plan on conflict.

**Origin, owner ask (2026-08-14):** "Omarchy Quattro, which just released,
looks much cleaner than this shell... there is a lot of info in the bar and
its very dense, and the bar is pretty tall too... it also only shows icons i
think for example the weather widget", then, on the hidden-bar half: "by
hidden bar i meant like on macos bartender or the hidden bar app, where tray
items can be in a chevron", then: "Do all that. Battery should be visible by
default. I dont want the hidden bar runtime, just the bartender part."

**Explicitly out of scope by owner instruction:** the whole-bar hide toggle
(omarchy's `bar-off` state flag, `Bar.qml:989-1024` upstream). Nothing in
this plan touches `Bar.qml`'s `PanelWindow` or its exclusion zone.

## Context: where the density actually comes from

Upstream comparison, both repos read at today's HEAD (omarchy `8b70f01`).

Omarchy's bar is 26px tall (`shell/Commons/Style.qml:341`, `sizeHorizontal`)
and carries 14 default entries. FormalShell's is content-derived
(`Bar.qml:88-90`, `implicitHeight: bar._cellHeight`) at roughly 32px and
carries 12. Omarchy fits more in less, and the reason is structural rather
than stylistic: every rich widget upstream renders through
`shell/Ui/BarIconButton.qml:14`, which hardcodes `labelVisible: false` and a
fixed 27px slot. Numbers and state live in that widget's own `Panel.qml`
popout. Only 3 of its 14 defaults draw text at all. FormalShell has no such
component: each of its 22 widget files writes its own `Row` of glyph plus
`MetaLabel`, so 8 of 12 defaults draw text and the decision was never made
once anywhere.

Two facts make this cheap to fix without importing omarchy's component:

1. The height is set by exactly one cell. `Bar._cellHeight` is the max over
   all cells, and `Clock.qml:21-53` is the only two-line one (a `TIME`
   `MetaLabel` over `hh:mm` over a dot-reserving `Item`). Every other cell is
   a single `Row`. Collapsing the clock to one line collapses the bar.
2. `DESIGN.md:688-709` already forbids what the clock does: caption meta tags
   belong on cells "only where the value alone is ambiguous". `19:31` is not
   ambiguous. The `TIME` label is the rule's own counterexample, so removing
   it is compliance, not a new direction.

On the tray, omarchy's `shell/plugins/bar/widgets/Tray.qml:155-160` sorts
every SNI item into `pinned` / `drawer` / `hidden`, with `drawer` as the
default bucket, reveals the drawer on chevron hover (`:262-264`), manages the
buckets from a right-click popup on the chevron (`:274`, `:403`, `:483-508`),
and persists both arrays inline on the widget's config entry (`:183-187`).
FormalShell's `Tray.qml:40-43` has a hardcoded `_visibleLimit: 4` and a purely
positional overflow, with no per-item control and nothing persisted.

**Deliberate divergence from upstream on the default bucket.** Omarchy
defaults every unlisted item to `drawer`. FormalShell keeps its current
"first N are visible" ordering as the fallback, so a user who never opens the
manage popup sees exactly today's arrangement. `pinned` and `hidden` become
overrides on top of that ordering rather than a replacement for it. This is a
strict superset of today's behavior and cannot regress an unconfigured
install.

## Constraints

- All CLAUDE.md hard rules stand: radius 0, no blur, no shadows, border
  width 2, fontconfig `monospace` alias, Nerd Font glyphs, pure QML/JS.
- ⚠️ Every file touched here except `layout.js`, `State.qml` and the new pure
  modules contains raw multi-byte Nerd Font codepoints. Use targeted `Edit`
  operations only. Never rewrite `Battery.qml`, `AudioWidget.qml`,
  `WeatherWidget.qml` or `Tray.qml` wholesale.
- The shell never writes `settings.json`. Runtime pin/hide state goes to
  `state.json` via `Core/State.qml`.
- Settings overrides state, never the reverse. Reuse the exact convention
  `shell/Calendar/progress.js:44-51` documents (`resolveOverride`).
- Compositor and SNI ids are opaque strings. Never parse or compare them
  numerically.
- Honest unavailable states: a hidden label must not delete information, it
  must move it to the cell's existing `tooltipText`.
- All runtime verification happens inside the nested session `dev/smoke-niri.sh`
  boots. Never against the host session.

## Task 1 — Per-widget label suppression, weather and audio icon-only

**Files:** `shell/Surfaces/Bar/widgets/{WeatherWidget,AudioWidget,Battery,BellWidget,GithubWidget,UsageWidget,KeyboardLayoutWidget,SystemUpdateWidget}.qml`, `shell/Core/Config.qml`.

Add one config-backed property to every bar widget that pairs a glyph with a
`MetaLabel`, and bind that label's `visible` to it:

```qml
readonly property bool _showLabel: Config.get("bar.widgets.weather.showLabel", false)
```

```qml
MetaLabel {
    visible: root._showLabel
    ...
}
```

`Row` skips invisible children and collapses its own spacing for them, so a
suppressed label leaves no gap and needs no second binding.

**Per-widget defaults.** Only two flip; the rest keep today's value and gain
the override only so the knob is uniform:

| Widget | Default | Reason |
| --- | --- | --- |
| `weather` | `false` | Owner named it directly. Glyph carries condition; temperature moves to the tooltip. |
| `audio` | `false` | Glyph already carries muted/level state. Matches omarchy, which is icon-only here always. |
| `battery` | `true` | Owner's explicit instruction: "Battery should be visible by default." |
| `bell` | `true` | The pending count is the widget's only content, not a label on something else. |
| `github`, `usage`, `keyboardLayout`, `systemUpdate` | `true` | All opt-in builtins absent from `DEFAULT_LAYOUT`. A user who added one asked for its reading. |

**Tooltip is load-bearing now.** Before hiding a label, confirm the cell's
`tooltipText` already carries the suppressed value, and add it if not.
`Battery.qml:84-96` is the model to follow. Weather's tooltip must state the
temperature; audio's must state the volume percentage and mute state. A
suppressed label that is nowhere else on the surface is a bug, not a density
win.

**Config schema.** Extend `Config.qml`'s existing `bar.*` doc comment
(currently `Config.qml:67-75`) with `bar.widgets.<name>.showLabel` (bool,
per-widget default as tabled above). Do not touch `shell/Bar/layout.js`:
layout entries stay bare strings, and this keys off the widget name
separately, so no entry-object parsing is introduced.

**Verification:** `just lint`, then `just vm-smoke` and Read the PNG. Weather
and audio must render as bare glyphs; battery must still read `BAT / NN%`.

## Task 2 — Single-line clock, shorter bar

**Files:** `shell/Surfaces/Bar/widgets/Clock.qml`, `shell/Core/Theme.qml`.

Delete the `TIME` `MetaLabel` (`Clock.qml:25-28`) and the dot-reserving
wrapper `Item` (`Clock.qml:43-53`). Replace the `Column` with the same
single-`Row`-plus-anchored-dot shape every other widget uses; `Battery.qml:98-122`
is the exact idiom to mirror, including `PanelOpenDot`'s
`anchors.bottom: parent.bottom` / `anchors.horizontalCenter`.

The wrapper `Item` exists only because the clock was the tall cell
(`Clock.qml:37-42` says so outright). Once it is a one-line cell that reason
is gone, and keeping it would re-inflate the height this task exists to
remove.

Update `Theme.qml:50-55`'s `barHeight` pre-binding placeholder and its comment
to the new approximate value. It is only the value used before the first
`Bar` instance binds the real one, but a stale 32 there is misleading.

**Verification:** `just vm-smoke` and Read the PNG. The bar must be visibly
shorter, the clock must read `hh:mm` alone, and the panel-open dot must still
appear under the clock when the calendar panel is open (drive it with
`dev/smoke-niri.sh --panel calendar`).

## Task 3 — Bartender tray: pinned / drawer / hidden buckets

**New file:** `shell/Tray/model.js` (pure, `.pragma library`, no Quickshell
access, testable head-on like `shell/Bar/layout.js`).

```
classify(id, pinned, hidden) -> "hidden" | "pinned" | "drawer"
buckets(ids, pinned, hidden, visibleLimit) -> { visible, drawer, hidden }
resolveOverride(settingsValue, stateValue)   // same contract as Calendar/progress.js:49
```

`buckets` rules, in order:

1. Ids in `hidden` drop out entirely and appear in neither `visible` nor
   `drawer`.
2. Ids in `pinned` are always in `visible`, regardless of `visibleLimit`.
3. Remaining ids fill `visible` in their incoming order until
   `visible.length` reaches `visibleLimit`; the rest go to `drawer`.
4. Reserve one slot for the chevron exactly as `Tray.qml:42` does today
   (`_visibleLimit - 1` when anything would overflow), so the row width is
   unchanged for an unconfigured tray.

Rule 3 preserves today's behavior byte for byte when `pinned` and `hidden`
are both empty. That equivalence is the acceptance test for this module.

**`shell/Core/State.qml`:** add `trayPinned` / `trayHidden` `var` adapter
properties (default `[]`) plus aliases, and one
`setTrayBuckets(pinned, hidden)` writer following the existing
`setCalendarLifeProgress` two-key single-write shape (`State.qml:44-48`).

**`shell/Services/TrayService.qml`:** resolve the live arrays through
`Model.resolveOverride(Config.get("bar.tray.pinned", undefined), State.trayPinned)`
and the same for `hidden`, so `settings.json` declaratively wins when
present. Add `togglePin(id)` / `toggleHide(id)` that move an id between
buckets and persist through `State.setTrayBuckets`. Pinning an id clears it
from `hidden` and vice versa: the buckets are mutually exclusive, matching
omarchy's `Tray.qml:189-211`.

Expose `readonly property bool bucketsLocked` — true when either settings key
is present — so the manage popup can say so rather than silently ignoring
clicks.

**`shell/Surfaces/Bar/widgets/Tray.qml`:**

- Replace the `_pinnedCount` / `_overflowCount` arithmetic (`:40-43`) with
  `Model.buckets(...)`, keeping the existing live-`ObjectModel` `Repeater`
  binding intact. The header comment at `:143-155` explains why the model
  must not become a `.values` snapshot; that constraint still holds.
- Render the chevron cell whenever there is at least one item, not only when
  overflowing. It is the only affordance the manage popup hangs off, and
  `better-layout`'s progressive-disclosure rule needs it visible. Keep the
  `+N` / `−N` count text, and show a bare chevron glyph when the drawer is
  empty but items exist.
- Right-click on the chevron cell opens the manage popup. Left-click keeps
  today's `TrayService.toggleDrawer()`.
- Leave `TrayCollapseGate` and the auto-collapse `Timer` (`:135-141`)
  untouched.

**Manage popup.** Build it from the existing ledger-row grammar (`DESIGN.md`
§2's ruled rows, uppercase meta labels, fg/bg inversion for the cursor row) —
the notification center's own rows are the closest existing reference. Do not
introduce a second popup mechanism: reuse `Components/Panel.qml` if it fits
the anchoring, otherwise follow `QsMenuAnchor`'s placement idiom already in
this file (`:59-63`).

Copy, per `better-writing` and this repo's uppercase-meta convention:

- Header meta row: `TRAY / MANAGE`.
- One explanatory line, sentence-cased body text:
  `Pinned icons stay on the bar. Hidden icons never show.`
- Per-row actions, verb-first: `PIN` / `UNPIN` and `HIDE` / `SHOW`.
- When `bucketsLocked`, replace the actions with a dim `SET IN SETTINGS` cell
  rather than rendering dead buttons.

Escape must close the popup, and the popup must not trap the pointer when
closed. Bar cells are not keyboard-focusable today (the bar surface takes no
keyboard interactivity), and this task does not change that; the IPC routes
below are the non-pointer path.

**`shell/Ipc/TrayIpc.qml`:** add `pin <id>`, `unpin <id>`, `hide <id>`,
`show <id>`, and extend `status` to report all three buckets plus
`bucketsLocked`. The smoke rig has no synthetic pointer — this is the same
reason `tray expand` already exists (`TrayService.qml:8-12`) — so without
these routes the feature cannot be verified headlessly at all. Unknown ids
return an error string, never a silent no-op.

**Verification:** `just lint`, `just test`, then the extended smoke leg in
Task 4.

## Task 4 — Smoke coverage, screenshots, docs

**`dev/smoke-niri.sh --tray`:** extend the existing leg, which already runs
six `dev/sni-stub.py` producers and drives `tray expand`. After the current
collapsed and expanded dumps, add:

1. `tray pin <id>` on an item that today lands in the drawer, then
   `tray status` — the id must move to `visible`, and the dump is written to
   `artifacts/` as `tray-status-pinned.json`.
2. `tray hide <id>` on a different item, then `tray status` — the id must
   appear in neither `visible` nor `drawer`, and the visible count must drop
   by one (`tray-status-hidden.json`).
3. A screenshot of the manage popup, summoned over IPC, as
   `tray-manage.png`.

Assert on the JSON rather than only capturing it, matching how the
`--picker` leg asserts `hasVariants` and the per-mode image sets.

**Screenshots:** refresh `docs/screenshots/bar-niri.png` and the tray shots
through the normal `just vm-smoke` path, since both the bar height and the
weather/audio cells change in every screenshot the repo ships.

**Docs:** update `CLAUDE.md`'s `--tray` bullet to describe the new legs, and
`Config.qml`'s schema comment for `bar.tray.pinned` / `bar.tray.hidden`. Add
the bar-density rule to `docs/DESIGN.md` §3's Bar section: a glyph-plus-meta
cell suppresses its label by default unless the value is the widget's only
content, with the suppressed value required in the tooltip.

## Acceptance

- `just build`, `just test`, `just lint` all green, output read.
- `just vm-smoke --tray` green, with the two status JSONs asserting the
  bucket moves and `tray-manage.png` read.
- `just vm-smoke --panel calendar` read, confirming the clock's panel-open
  dot survives the single-line change.
- An unconfigured install renders the same tray arrangement as before this
  change: same visible items, same overflow count.
- Battery still shows `BAT / NN%` with no configuration.
