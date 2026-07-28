# FormalShell M6: Clipboard history + panels — Implementation Plan

> **For agentic workers:** Workflow-driven per `docs/superpowers/workflow-template.md`
> — one subagent per task, sequential, verification evidence required, push
> after every task commit (classifier-denied pushes: note and continue). Read
> `CLAUDE.md` and `docs/DESIGN.md` first — both binding. The spec
> (`docs/superpowers/specs/2026-07-27-formalshell-design.md` §Surfaces 1/2/4,
> §IPC) wins over this plan on any conflict.

**Goal:** The bar becomes a real three-region ledger with per-widget popout
panels, and the shell gains clipboard history. After M6: audio, network,
bluetooth, power/battery, clock+calendar and weather each have a working
panel reachable from its own bar cell; the calendar carries the year-progress
bar with the life-progress easter egg; clipboard history is a menu provider.

**Architecture:** One shared `Components/Panel.qml` — a ledger table popout
(header MetaLabel row, rows sharing hairline rules, radius 0, keyboard
`OnDemand`) anchored under its owning bar cell — instantiated once per panel
kind. A `panel` IPC target opens/closes/toggles by name so panels are
keybindable *and* headlessly verifiable. Each panel binds a first-party
quickshell service; all six confirmed present in the pinned quickshell 0.3.0:
`Quickshell.Services.Pipewire`, `Quickshell.Networking`,
`Quickshell.Bluetooth`, `Quickshell.Services.UPower`, plus the existing
`AudioService`/`BrightnessService`. Clipboard is a capture service writing a
capped JSON history into the state dir, surfaced through the menu's existing
provider mechanism.

## Spec addendum recorded by this plan

The spec's §IPC target list does not include `panel`. This plan **adds** it
(`panel.open(name)`, `close()`, `toggle(name)`, `state()`) rather than
conflicting with anything: per-widget popouts otherwise have no summon path
for compositor keybinds, and — decisively — no way to be verified headlessly
in the smoke rig. Task 9 documents it in the same places the other targets
are documented.

## Plan-wide constraints

- **DESIGN.md is binding for every surface.** Panels are ledger tables: a
  header meta row (uppercase, dimmed — `AUDIO / OUTPUT`, `WI-FI / 4`), rows
  per device/network/day sharing one hairline rule with their neighbours (no
  gaps, no double rules, no cards), radius 0, selection by inversion, sliders
  and progress bars as flat accent fills with **no round thumbs**, no
  shadows, no blur, no slide/bounce. Uppercase MetaLabel for all meta text.
- **Honest unavailable states, never faked data.** The test VM has no
  battery, no bluetooth adapter, no Wi-Fi radio and no geoclue fix. Every
  panel must render a single dim cell (`NO DEVICES`, `UNAVAILABLE`, …) when
  its backend reports nothing, and the smoke verification asserts the
  **surface structure** renders correctly in that state. Do not stub fake
  devices into the shell to make a screenshot look fuller; do not add fake
  `/sys` entries. Enabling a real service in `nix/testvm.nix` (NetworkManager
  on the virtio NIC, bluez, power-profiles-daemon, upower) so the panel has a
  genuine backend to talk to **is** sanctioned and preferred.
- Compositor window/workspace ids stay opaque strings. The shell only reads
  `settings.json`; runtime-mutable values (calendar birth year, life
  expectancy, clipboard history) go to `$XDG_STATE_HOME/formalshell/`.
- Nerd Font glyphs are raw multi-byte codepoints: use targeted `Edit`
  operations on files containing them, never a wholesale rewrite. Take icon
  codepoints from the font's own cmap or from `default-menu.jsonc`'s existing
  convention — never guess a codepoint.
- Smoke script changes are additive only; `dev/smoke-niri.sh` must stay
  byte-compatible with Linux-host use so the g815 can run it unchanged when
  it returns.
- Every task ends with its verification commands actually run, its
  screenshots pulled to `./artifacts/` and **Read**, and a commit pushed.

---

### Task 1: Bar three-region refactor + shared Panel + `panel` IPC + audio panel

**Files:** create `shell/Components/Panel.qml`, `shell/Surfaces/Panels/AudioPanel.qml`,
`shell/Surfaces/Bar/widgets/AudioWidget.qml`, `shell/Ipc/PanelIpc.qml`;
modify `shell/Surfaces/Bar/Bar.qml`, `shell/Components/qmldir`, `shell/shell.qml`.

**Produces:**
- `Bar.qml` split into the spec's three regions (left / center / right) —
  workspaces and active window stay left, the right region takes the new
  indicator/widget cells. Region boundaries share rules like every other
  cell; the bar's bottom edge stays one rule against the desktop.
- `Components/Panel.qml`: the reusable popout. Properties for a title (meta
  row text), the owning bar cell (for horizontal anchoring), and a default
  content slot. Ledger frame + outer rule + zero-spacing column, mirroring
  the pattern `Center.qml`/`Osd.qml` already established (read them first —
  do not invent a third structure). `WlrLayershell` top layer, keyboard
  `OnDemand`, closes on Escape and on click-outside.
- `PanelIpc.qml` target `panel`: `open(name: string)`, `close()`,
  `toggle(name: string)`, `state()` → the open panel's name or `""`. Unknown
  name returns an error string, never a silent no-op.
- `AudioPanel.qml`: per-node Pipewire sliders (output nodes first, then
  inputs), each row a full-width cell whose fill level is a flat accent
  block; mute toggles as inverted cells. Bind `Quickshell.Services.Pipewire`
  via `PwObjectTracker` — verify the exact API against the quickshell source
  before writing, as `AudioService.qml` already does.
- `AudioWidget.qml`: a bar cell showing the volume glyph + percentage, with
  the **panel-open accent dot** (Omarchy detail) while its panel is open.

**Steps:** implement → `just vm-smoke --panel audio` (add that smoke mode:
opens the named panel over IPC, screenshots) → Read the PNG: three-region
bar, audio cell with accent dot, panel as a ledger table with a flat accent
fill slider → `just test` + `just vm-lint` regression → commit
`feat(panels): three-region bar, shared panel popout, panel ipc, audio panel`; push.

---

### Task 2: Clipboard history service + menu provider

**Files:** create `shell/Services/ClipboardService.qml`, `shell/Clipboard/history.js`,
`tests/tst_clipboard_history.qml`; modify `shell/Services/qmldir`,
`shell/Menu/providers.js`, `shell/Menu/default-menu.jsonc`, `shell/Ipc/` (a
`clipboard` target per the spec's IPC list).

**Produces:**
- `history.js` (`.pragma library`, pure, TDD'd first): `add(state, entry, now)`
  with de-duplication (re-copying an existing entry moves it to the front,
  never duplicates), a 300-entry cap dropping the oldest, `remove(state, id)`,
  `clear(state)`, and a `sanitize` that drops empty/whitespace-only captures.
  Tests first (red): dedup-to-front, cap overflow, clear, purity.
- `ClipboardService.qml`: capture via `wl-paste --watch` under `Process`
  (verify the invocation against the wl-clipboard man page in the store, not
  memory), writing the capped history JSON to
  `$XDG_STATE_HOME/formalshell/clipboard.json`. Never captures while a
  password-manager style mime hint is present if one is cheaply detectable;
  otherwise document that it does not filter.
- `clipboard` IPC target: `list()`, `copy(id)`, `remove(id)`, `clear()`.
- A `clipboard` menu provider node so `formalshell menu summon clipboard`
  lists history entries and copying one is a menu action — sharing the
  menu's existing theme tokens and row idiom.

**Steps:** red → implement → green (`just test`) → in-VM proof: `wl-copy`
three strings in-session, then `qs ipc call clipboard list` shows all three
newest-first and a re-copy of the first does not duplicate → `just vm-smoke --menu`
style run summoning the clipboard route, Read the PNG → commit
`feat(clipboard): capped history service, clipboard ipc, menu provider`; push.

---

### Task 3: Clock bar widget + calendar panel (month grid + year progress)

**Files:** create `shell/Surfaces/Panels/CalendarPanel.qml`,
`shell/Surfaces/Bar/widgets/Clock.qml`, `shell/Calendar/progress.js`,
`tests/tst_calendar_progress.qml`; modify `shell/Surfaces/Bar/Bar.qml`,
`shell/shell.qml`.

**Produces:**
- `Clock.qml`: a bar cell with a `TIME` meta label and the time, per
  DESIGN.md's own bar translation. Opens the calendar panel.
- `progress.js` (pure, TDD'd): `yearFraction(now)` and
  `lifeFraction(now, birthYear, lifeExpectancy)` → 0..1 plus a formatted
  label; leap years correct; guards for a missing/absurd birth year
  (returns null rather than a wrong bar). Tests first.
- `CalendarPanel.qml`: month grid as a ledger table — weekday header meta
  row, one cell per day sharing rules, today inverted, days outside the month
  dimmed; below it the **year-progress bar** as a full-width flat accent fill
  cell with its percentage as mono text. Modeled on Omarchy quattro's
  calendar widget (read it in the reference clone; do not copy code — the
  repo is read-reference only per CLAUDE.md).

**Steps:** red → implement → green → `just vm-smoke --panel calendar` → Read
the PNG: month grid with today inverted, weekday meta row, year-progress
accent fill → commit `feat(panels): clock cell and calendar panel with year progress`; push.

---

### Task 4: Life-progress easter egg

**Files:** modify `shell/Surfaces/Panels/CalendarPanel.qml`, `shell/Core/State.qml`,
`shell/Core/Config.qml`, `shell/Calendar/progress.js` (if needed),
`tests/tst_calendar_progress.qml`.

**Produces:** double-clicking the year-progress bar prompts — **through the
menu's existing `input` mode**, not a new dialog — first for birth year then
for expected lifespan; both persist to `state.json` via the existing
`State` alias + writeAdapter pattern (read how `wallpaper`/`mode`/`dnd` do it
and mirror exactly). `settings.json` keys `calendar.birthYear` /
`calendar.lifeExpectancy` declaratively override the state values when
present (Config wins over State, matching the shell's read-only-settings
rule). Once set, the progress bar shows **% of life lived** and its meta
label changes accordingly; a toggle returns it to year progress.

**Steps:** extend tests for the override precedence (settings beats state,
state beats unset) → implement → in-VM proof: drive the double-click path
via the menu `input` IPC route, confirm `state.json` on disk gained the two
keys, relaunch the shell in the same state dir and confirm the life bar
persists → Read the PNG showing the life-progress bar and its meta label →
commit `feat(calendar): life-progress easter egg with state persistence`; push.

---

### Task 5: EDS/GOA calendar events feasibility spike

**Files:** create `docs/spikes/2026-07-28-eds-calendar-events.md`; modify
`shell/Surfaces/Panels/CalendarPanel.qml` and add whichever service the
outcome justifies.

**Produces:** an honest, evidence-backed answer to "can we read GNOME Online
Accounts calendar events from pure QML?", spiked in this order:
1. `gdbus`/`busctl` introspection of Evolution Data Server's calendar
   interfaces under `Process` — does the factory + view API work without a
   compiled helper, and can events be read as plain D-Bus without ECal's C
   client library doing the heavy lifting?
2. If EDS proves impractical without a compiled companion (which
   `CLAUDE.md` forbids), fall back to reading local ICS files from a
   configured directory (khal-compatible), implemented for real.
The spike doc records what was tried, the exact command output, and the
decision. Whichever path wins, event dots/rows render in the month grid as
ledger cells, and the calendar keeps working with **zero** events configured.

**Note:** EDS is almost certainly absent in the test VM. Installing
`evolution-data-server` into `nix/testvm.nix` for the spike is sanctioned;
if the spike concludes "not feasible in pure QML", say so plainly, record it
as a post-v1 item, and remove the dependency again rather than leaving a
service that cannot work.

**Steps:** spike → decide → implement the winning path → in-VM proof with at
least one real event visible in the grid (an ICS fixture is fine and is the
expected outcome) → commit `feat(calendar): events via <chosen path>, eds feasibility recorded`; push.

---

### Task 6: Network + Bluetooth panels

**Files:** create `shell/Surfaces/Panels/NetworkPanel.qml`,
`shell/Surfaces/Panels/BluetoothPanel.qml`,
`shell/Surfaces/Bar/widgets/NetworkWidget.qml`,
`shell/Surfaces/Bar/widgets/BluetoothWidget.qml`; modify `Bar.qml`,
`shell/shell.qml`, `nix/testvm.nix`.

**Produces:** the network panel on `Quickshell.Networking` (connection list,
signal strength as a mono bar, connect/disconnect as row actions, the active
connection inverted) and the bluetooth panel on `Quickshell.Bluetooth`
(adapter state cell, paired devices, connect/disconnect). Bar glyph cells for
each, with the panel-open accent dot. **Verify both module APIs against the
quickshell source/qmltypes before writing** — these are the two least-used
quickshell modules in this project so far.

`nix/testvm.nix` gains NetworkManager (the virtio NIC gives a genuine wired
connection to enumerate) and bluez (no adapter exists, so the panel must show
its honest `NO ADAPTER` state — that is the expected screenshot, and it is a
pass).

**Steps:** implement → `just vm-smoke --panel network` and `--panel bluetooth`
→ Read both PNGs and describe exactly what each shows, including which one is
in an unavailable state and why → commit
`feat(panels): network and bluetooth panels`; push.

---

### Task 7: Power/battery panel + battery bar cell

**Files:** create `shell/Surfaces/Panels/PowerPanel.qml`,
`shell/Surfaces/Bar/widgets/Battery.qml`; modify `Bar.qml`, `shell/shell.qml`,
`nix/testvm.nix`.

**Produces:** battery bar cell with the DESIGN.md `BAT / 87%` meta idiom
(hidden entirely when no battery exists rather than showing a lie), and a
power panel on `Quickshell.Services.UPower`: battery/AC state rows plus a
keyboard-navigable power-profile picker (power-profiles-daemon), selection by
inversion. The charging pulse is the breathing-opacity idiom DESIGN.md
allows for in-progress states — **only** while actually charging.

`nix/testvm.nix` gains power-profiles-daemon and upower. QEMU has no battery,
so the honest state is AC-only with the battery cell absent; the profile
picker is the part that must really work.

**Steps:** implement → `just vm-smoke --panel power` → Read the PNG: profile
picker rows with one inverted, honest AC/no-battery state → confirm the
battery bar cell is absent (not showing 0%) → commit
`feat(panels): power panel with profile picker and battery cell`; push.

---

### Task 8: Weather panel + Location service

**Files:** create `shell/Services/LocationService.qml`,
`shell/Surfaces/Panels/WeatherPanel.qml`, `shell/Weather/openmeteo.js`,
`tests/tst_openmeteo.qml`; modify `shell/Core/Config.qml`, `Bar.qml`,
`shell/shell.qml`, `nix/testvm.nix`.

**Produces:**
- `LocationService.qml`: geoclue by default via QtPositioning's
  `PositionSource`, **streaming** updates so an early inaccurate seed never
  becomes permanent (the spec cites PR #2914's lesson explicitly). Manual
  `location.latitude`/`location.longitude` in `settings.json` override it
  entirely and are the fallback when geoclue stalls.
- `openmeteo.js` (pure, TDD'd): request URL construction and response→model
  parsing, including the failure shapes (HTTP error, malformed JSON, missing
  fields) → tests first.
- `WeatherPanel.qml`: current conditions as a header meta row plus a forecast
  ledger table (one row per period, temperature as mono text, no icons beyond
  Nerd Font glyphs). Modeled on Omarchy's weather panel.

**In the VM:** geoclue cannot get a fix (no Wi-Fi radio), so the manual
lat/lon override is the verification path — which is also the more important
path to prove, since it is the documented fallback. The VM has working DNS
(`8.8.8.8`, configured for the macOS SLiRP quirk), so the open-meteo fetch is
real. If open-meteo is unreachable at test time, the panel must show an
honest error cell and the smoke must still pass on structure — say which
happened.

**Steps:** red → implement → green → `just vm-smoke --panel weather` → Read
the PNG → commit `feat(panels): weather panel and geoclue-backed location service`; push.

---

### Task 9: Docs + screenshots

**Files:** modify `README.md`, `docs/ARCHITECTURE.md`, `CLAUDE.md`; add
`docs/screenshots/panels-niri.png`, `docs/screenshots/calendar-niri.png`,
`docs/screenshots/clipboard-niri.png`.

**Steps:**
- Screenshots pulled from the VM and **Read before publishing** (a screenshot
  nobody looked at does not ship).
- README: Panels section (each panel, its backing service, its bar cell, the
  `panel` IPC verbs, keybind examples), Clipboard section (capture mechanism,
  cap, menu route, `clipboard` IPC verbs), Calendar section (year progress,
  the easter egg and where its two values live, the events outcome from the
  Task 5 spike stated honestly).
- ARCHITECTURE: bar three-region layout, the panel host + `panel` IPC
  contract, clipboard data flow, and the Location→Weather chain.
- CLAUDE.md: the new smoke modes in the verification loop; the `panel` IPC
  addendum; the honest-unavailable-state rule as a standing expectation for
  VM verification.
- Verify every documented command by running it. Commit
  `docs(panels): panels, clipboard, calendar, and the panel ipc contract`; push.

---

## Then

**M7** — now playing + Apple Music animated art, lock screen, screensaver
(Idle service), image/wallpaper picker. **M8** — greeter +
`nixosModules.formalshell-greeter`. **M9** — polish pass and the ledger
retrofit of the M1–M3 surfaces, then the e1504g daily-drive trial and the
g815 switchover gate. Note that M9's last two items need a Linux host back
and cannot be closed from the macbook.
