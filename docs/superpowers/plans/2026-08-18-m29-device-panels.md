# FormalShell M29: device panels (AirPods + DualSense)

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M28
> (`2026-08-17-m28-panel-composition.md`) landed immediately before this
> plan.

**Origin, owner ask (2026-08-18):** improve AirPods support to match the
omarchy-pods panel (battery per bud and case, listening modes, Conversation
Awareness, One-Bud ANC, ear detection) "but in our style. Still keep headers
and stuff"; then "there is airpods groundwork, but its hidden under
bluetooth and its not fun. I want a separate item. Maybe use this framework
to also improve the dualsense support"; then "in my nix config also add the
airpods panel to my always visible" (the owner-side layout change is the
orchestrator's job after the milestone, not a repo task).

**Research already done (2026-08-18), do not re-derive:**

- The referenced panel is NOT omarchy core. It is the third-party plugin
  `github.com/thisisgm/omarchy-pods` (widget MIT, `daemon/` GPL-3.0): a
  vendored, extended librepods daemon plus a Quickshell widget. FormalShell
  integrates with the **daemon's IPC contract only** — no code is ported
  from the daemon (GPL) and none needs to be from the widget (we
  reimplement in our own design language, so no attribution header
  applies).
- **Status contract** (verified from the plugin's
  `knowledge/librepods-status-schema.md` and `daemon/main.cpp`, cloned
  read-reference): the daemon writes its whole state as ONE line of
  compact JSON, keys sorted alphabetically, to
  `$XDG_STATE_HOME/librepods/status.json` via `QSaveFile` (never
  half-written), write-on-change only, and **removes the file on quit** —
  an absent file IS the "daemon down" signal. Keys:
  `schema_version` (int, currently 1), `connected` (bool — the L2CAP
  audio link, NOT daemon health), `device_name`, `model_name` (empty
  until identified), `is_pro_series` (gates CA/One-Bud/Adaptive),
  `supports_noise_off` (Pro 3 dropped Off), `noise_mode` (0 Off, 1 ANC,
  2 Transparency, 3 Adaptive, -1 unknown), `left`/`right`
  (`{available, level, charging, in_ear}`), `case`
  (`{available, level, charging}`, no `in_ear`), `conversational_awareness`
  (bool), `adaptive_noise_level` (0-100, meaningful only while mode 3),
  `one_bud_anc_mode` (bool), `ear_detection_behavior` (0 pause when one
  out, 1 when both out, 2 never), `lid_state` (0 open, 1 closed,
  2 unknown). Plus `*_total` telemetry counters, `model_int`,
  `model_number` — not panel data, ignore them.
- **Two shapes that bite:** `left`/`right`/`case` are ABSENT entirely
  until a battery packet arrives (never present with `available:false`),
  so the parser returns a complete default shape on every path. And
  `connected:false` does not mean nothing is known — battery keeps
  arriving over BLE adverts while the buds sit in the case, so the
  battery section gates on any known level, the control sections on
  `connected`.
- **Control contract** (verified from `daemon/librepods-ctl.cpp` +
  `daemon/ipcpath.hpp`): a `QLocalServer` at
  `$XDG_RUNTIME_DIR/librepods.sock` (absolute path; empty
  `XDG_RUNTIME_DIR` = no socket, no fallback). A client connects and
  writes the raw verb string, no framing, no reply expected (only
  `status`/`reopen` reply). Verbs: `noise:off|anc|transparency|adaptive`,
  `adaptive:N` (0-100), `ca:on|off`, `onebud:on|off`, `ear:one|both|off`.
  (`connect`/`disconnect`/`forget` exist but shell out to bluetoothctl —
  the Bluetooth panel owns that job, do not use them.) The shell writes
  the socket directly via `Quickshell.Io.Socket` — no CLI dependency,
  same one-shot self-destroying-Socket pattern (and rationale comment)
  as today's `LibrePodsService.qml:20-28`.
- **Ear detection is host-side policy**, not a device write: the daemon
  pauses/resumes media off ear notifications; `ear:*` just sets the
  persisted policy. Render it as a value row, not a device toggle.
- **DualSense backend is sysfs**, no daemon: hid-playstation publishes
  battery as `/sys/class/power_supply/ps-controller-battery-<MAC>/`
  (`capacity` 0-100 in 10% buckets, `status` Charging/Discharging/Full),
  the lightbar as `/sys/class/leds/input*:rgb:indicator`
  (`multi_intensity` = "R G B", readable), player LEDs as
  `<base>:white:player-1..5` (`brightness` 0/1). Node names key off the
  input index which changes per reconnect — glob, first match wins.
  The owner's host units (`dualsense-sync` in their nix config) OWN the
  lightbar/LED writes; the shell READS ONLY. Today's bar presence is a
  `custom:dualsense` command module polling a `dualsense-bar` script at
  30s — the builtin widget replaces it at the same cadence.
- The existing M17 integration (`LibrePodsService.qml` → stock librepods
  Qt app's write-only `/tmp/app_server` socket, the `AIRPODS NOISE`
  set-only group at `BluetoothPanel.qml:725-791`) is RETIRED by this
  milestone: the new daemon supersedes the stock app on the owner's
  hosts, and the owner explicitly wants AirPods out of the bluetooth
  panel. Delete, don't shim.

## Constraints

- Same as M17/M28: CLAUDE.md binds (host-session safety, D-Bus isolation,
  honest unavailable states, opaque ids, 0..1-fraction verification,
  targeted Edits on glyph-bearing files), DESIGN.md is the authority
  (hero per §2.13, fused section rhythm per §2.14, named `panelWidth`,
  colon headers, bare-label toggles, `DitherFill` tracks, no raw pixel
  literals), verification ONLY on the VM rig, one conventional commit per
  task, pushed, tree clean.
- Battery units: librepods `level` is 0-100 (schema doc); sysfs
  `capacity` is 0-100. Neither is fraction-shaped, but each task that
  renders one states the unit at the boundary in a comment-free way
  (divide nowhere; `%` appended at render).
- Nerd Font glyphs (earbuds for AirPods, gamepad for DualSense) are
  verified against the pinned font's cmap via `fonttools ttx` before
  use, never guessed — M17's established loop.
- No new poll loops beyond the DualSense widget's own 30s presence tick
  (equivalent to the command module it replaces, and only while the
  widget is actually in the layout / the panel open). AirPods costs zero
  idle processes: `FileView watchChanges` + per-action socket writes.
- The `airpods` IPC target is a spec addendum in the same sense as
  `panel` (CLAUDE.md hard-rules precedent): compositor keybinds and the
  smoke rig both need a headless drive path. Unknown verbs return an
  error string, never a silent no-op.
- New settings keys: none required. Bar cells are opt-in `bar.layout`
  names (`airpods`, `dualsense`), absent from `DEFAULT_LAYOUT`.
  `bar.widgets.<name>.showLabel` applies to them like any cell.
- GPL hygiene: nothing from `omarchy-pods/daemon` or its widget is
  copied into this repo. The fixture status.json in the smoke leg is
  authored from the schema table above, not pasted from the plugin.

---

### Task 1: AirPods status model + service

**Files:** create `shell/Airpods/model.js`,
`shell/Services/AirpodsService.qml`, `tests/tst_airpods_model.qml`;
modify `shell/Services/qmldir`.

**Produces:**
1. `shell/Airpods/model.js` — pure, testable:
   - `parseStatus(text)` → complete default shape on EVERY path (bad
     JSON, wrong `schema_version`, absent pod objects): `{ok, connected,
     deviceName, modelName, isPro, supportsOff, noiseMode, left, right,
     caseBattery, conversationalAwareness, adaptiveNoiseLevel,
     oneBudAnc, earDetection, lidState}` with pods normalized to
     `{available:false, level:-1, charging:false, inEar:false}` when
     absent.
   - `batteryRows(status)` → the rows the panel draws (label, level,
     hint text like `IN EAR`, `CHARGING`, both fused ` / ` per §2.10),
     empty when no component has a known level.
   - `modesFor(status)` → only the modes the device has: Off gated on
     `supportsOff`, Adaptive on `isPro`; each `{key, label, verb,
     active}`.
   - `earDetectionLabel(n)`, `lidLabel(n)`, `noiseModeLabel(n)`,
     `stateLine(status)` (the hero meta: e.g. `NOISE CANCELLATION /
     LID OPEN`, or `NOT CONNECTED` when the link is down but battery is
     known).
2. `AirpodsService.qml` (Singleton): `FileView` on
   `$XDG_STATE_HOME/librepods/status.json` (resolve exactly the way
   `State.qml` resolves `XDG_STATE_HOME`, fallback `~/.local/state`),
   `watchChanges: true`, bounded rewatch retry mirroring
   `Config.qml:211-220` since the directory may not exist yet;
   `available` = file present AND `parseStatus().ok`; `status` = the
   parsed object; `send(verb)` = one-shot self-destroying Socket to
   `$XDG_RUNTIME_DIR/librepods.sock` carrying the raw verb — port the
   wedged-QLocalSocket rationale comment from `LibrePodsService.qml`
   before that file dies in Task 2. A verb allow-list mirrors the
   contract; anything else is refused locally.
3. Tests: fixture lines (sorted-key, one-line, as the daemon writes)
   covering: full Pro 3 status, non-Pro (modes filtered), absent pods
   (fresh daemon), `connected:false` with battery (in-case state),
   wrong `schema_version`, malformed JSON. Assert `modesFor` never
   yields Adaptive for non-Pro nor Off for Pro 3.

**Verify:** `just vm-test`, `just vm-lint`. Commit
(`feat(airpods): status model and daemon bridge`).

### Task 2: the AirPods panel, its IPC target, and the bluetooth retirement

**Files:** create `shell/Surfaces/Panels/AirpodsPanel.qml`,
`shell/Ipc/AirpodsIpc.qml`; modify `shell/shell.qml`,
`shell/Surfaces/Panels/BluetoothPanel.qml`, `shell/Bluetooth/model.js`,
`tests/tst_bluetooth_model.qml`; delete
`shell/Services/LibrePodsService.qml` (+ its `qmldir` line).

**Produces:**
1. `AirpodsPanel.qml` — one omarchy-style card, `panelTitle: "AIRPODS"`,
   `panelWidth` named explicitly (`popupWidthDefault`), wired per the
   four-edit checklist (`docs/ARCHITECTURE.md:719-755`): instance beside
   the others in `shell.qml:110-123`, registry entry `airpods` at
   `shell.qml:179`. Structure, top to bottom, every row a `Cell` in the
   fused §2.14 rhythm:
   - **Honest states first**: no `AirpodsService.available` → one dim
     `NO DAEMON` cell (the daemon deleted its file or never ran);
     available but no battery known and not connected → `NO AIRPODS`.
   - **PanelHero** (§2.13): earbuds glyph (cmap-verified), title =
     `deviceName` (sentence case, content ink), meta =
     `Airpods.stateLine(...)`. No oversized readout: three batteries are
     a list, not one number, and inventing a readout is a §2.13 defect.
     No rail.
   - **`BATTERY:` section** (shown when any level known, per the
     in-case shape above): one row per `batteryRows` entry — label at
     body ink, full-width `DitherFill` track at
     `Theme.space.trackThickness` with the flat `accent` fill sized by
     `level/100`, trailing `NN%` in tabular monospace plus the
     `IN EAR` / `CHARGING` hint as `MetaLabel`. Exactly the
     PowerPanel/AudioPanel track idiom, read-only.
   - **`LISTENING MODE:` section** (gated on `connected`): one row per
     `modesFor` — mode label, `selected: active` (the §1.1 fill state —
     read-back exists now, so M17's `SET ONLY` tag dies with its group),
     activation sends the verb. While `noiseMode` is Adaptive, an
     `ADAPTIVE NOISE` row follows with the interactive track
     (press/drag/wheel → `adaptive:N`, the AudioPanel slider shape).
   - **Toggle rows** (Pro only, gated on `connected`):
     `Conversation awareness` and `One-bud ANC`, each a Cell with the
     title at body ink, a dim caption second line (our-voice copy:
     `LOWERS VOLUME WHEN YOU TALK`, `KEEPS ANC WITH ONE POD IN`), and
     the house bare-label toggle at the right — `ON`/`OFF`, accent when
     armed, ink-promotion hover, per §1.1's amendment. No invented
     switch control.
   - **`EAR DETECTION:` row**: a value cell showing
     `earDetectionLabel` (`PAUSE WHEN ONE IS OUT` / `WHEN BOTH ARE
     OUT` / `NEVER`); activating cycles to the next behavior via
     `ear:*`. Lid state, when known, joins the hero meta line rather
     than earning a row.
   - Keyboard cursor over all actionable rows, reveal-only first
     keypress, mirroring `BluetoothPanel.qml:195-228`.
2. `AirpodsIpc.qml` — `target: "airpods"`: `status()` (the parsed-state
   JSON, or an honest `{available:false}`), `noise(mode)`, `ca(state)`,
   `onebud(state)`, `ear(mode)`, `adaptive(level)`. Validates against
   the same allow-list; unknown input → error string. Registered in
   `shell.qml` beside the other Ipc items.
3. The retirement: `BluetoothPanel.qml` loses the `AIRPODS NOISE`
   group (`:70-80`, `:111-117`, `:125-128`, `:155-157`, `:275-278`,
   `:725-791`), `Bluetooth/model.js` loses `hasConnectedAirpods` (its
   only consumer dies here; update `tst_bluetooth_model.qml`),
   `LibrePodsService.qml` is deleted. `grep -ri librepods shell/` comes
   back empty except AirpodsService's socket-path comment.

**Verify:** `just vm-test`, `just vm-lint`, `just vm-smoke --panel
bluetooth` (Read the PNG: the panel ends at its device buckets, no
AIRPODS group), `just vm-smoke --panel airpods` once Task 5's leg
exists is the full proof — here a plain `panel open airpods` against
the VM's daemonless HOME must render the `NO DAEMON` cell; screenshot
and Read it. Commit (`feat(airpods): dedicated panel and ipc target`).

### Task 3: the AirPods bar cell

**Files:** create `shell/Surfaces/Bar/widgets/AirpodsWidget.qml`;
modify `shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`,
`shell/Bar/layout.js`, `tests/tst_bar_layout.qml` (if the widget list
is asserted there — read it first).

**Produces:**
1. `AirpodsWidget.qml` — a `Cell.standalone` bar cell: earbuds glyph +
   the worst known bud level as `NN%` (case excluded from the number;
   full detail in `tooltipText` as `L 97 / R 99 / CASE 80`). Hidden
   entirely (width 0, no chrome) while `AirpodsService.available` is
   false or no level is known — the self-hiding `indicators` idiom, so
   the cell costs nothing without AirPods. Click → `toggleFrom(root)`
   on the airpods panel; `PanelOpenDot` inverted-aware like
   `BluetoothWidget.qml:63-68`. `bar.widgets.airpods.showLabel`
   respected; ⚠️ any `State` access goes through `import qs.Core as
   Core` (the M24 chevron trap).
2. Wiring: `airpodsPanel` property threaded `shell.qml` → `Bar.qml`,
   widget `Component` + `_builtinComponents` entry + `BUILTIN_WIDGETS`
   name `airpods` (opt-in, NOT added to `DEFAULT_LAYOUT` — the default
   bar stays byte-identical).

**Verify:** `just vm-test`, `just vm-lint`, `just vm-smoke` (default
layout unchanged — Read the PNG and diff mentally against the previous
run's). Commit (`feat(bar): airpods cell`).

### Task 4: DualSense model, service, panel, bar cell

**Files:** create `shell/Dualsense/model.js`,
`shell/Services/DualsenseService.qml`,
`shell/Surfaces/Panels/DualsensePanel.qml`,
`shell/Surfaces/Bar/widgets/DualsenseWidget.qml`,
`tests/tst_dualsense_model.qml`; modify `shell/Services/qmldir`,
`shell/shell.qml`, `shell/Surfaces/Bar/Bar.qml`, `shell/Bar/layout.js`.

**Produces:**
1. `model.js` — pure: `parseSupply(capacityText, statusText)` →
   `{percent, statusLabel, warn, critical}` (warn ≤20, critical ≤10,
   matching the retired script's thresholds), `parseLightbar(text)`
   ("R G B" → `#rrggbb` or null), `parsePlayerLeds([b1..b5])` → lit
   count, `stateLine(...)` for the hero meta. Tests over real-shaped
   fixture strings (`"80\n"`, `"Discharging\n"`, `"255 0 64\n"`,
   missing files).
2. `DualsenseService.qml` (Singleton): one `Process` probe
   (`sh -c` with glob, first match wins — the node-index caveat above)
   reading supply capacity+status, lightbar `multi_intensity`, player
   LED brightnesses in a single exec; `probe()` on demand;
   `present`/`battery`/`lightbar`/`playerLeds` properties; a 30s
   `Timer` that runs ONLY while a consumer is registered (the widget
   visible in the layout or the panel open — a simple refcount
   property), never a standing session poll. Read-only: the shell
   never writes sysfs (the owner's host units own the LEDs).
3. `DualsensePanel.qml` — `panelTitle: "DUALSENSE"`, `panelWidth:
   popupWidthNarrow`, registry name `dualsense`. Hero: gamepad glyph
   (cmap-verified), title `DualSense`, meta `stateLine` (`CHARGING` /
   `DISCHARGING / 2H LEFT`-style only if sysfs actually gives it —
   no invented estimates), readout = the battery percent at `display`
   (here the panel's whole point IS one number, §2.13), rail =
   `percent/100`. Then `LIGHTBAR:` row (a small square swatch of the
   read color — chrome-drawn, not an image — plus the hex at body
   ink; row absent when unreadable) and `PLAYER LEDS:` row (five
   glyph dots, lit = foreground, unlit = foregroundFaint; absent when
   unreadable). Honest `NO CONTROLLER` cell when no supply matches.
   No controls anywhere — display-only by design (host units own
   writes); the panel carries a dim `READ ONLY` meta tag in its
   title-bar band's right side so the absence of controls reads as
   designed.
4. `DualsenseWidget.qml` — standalone cell: gamepad glyph + `NN%`,
   warning/critical full-bleed fills at the model's thresholds
   (`warning`/`urgent` roles per §2.4, like the battery cell), hidden
   while `present` is false, click → panel, `PanelOpenDot`. Opt-in
   name `dualsense`, not in `DEFAULT_LAYOUT`.

**Verify:** `just vm-test`, `just vm-lint`, `just vm-smoke --panel
dualsense` — the VM has no hid-playstation device, so the honest
`NO CONTROLLER` panel IS the expected screenshot; Read it. Commit
(`feat(dualsense): panel, bar cell and sysfs service`).

### Task 5: smoke legs

**Files:** modify `dev/smoke-niri.sh`, `dev/vm.sh` only if a new
artifact class needs pulling (the `SMOKE_*` marker convention should
already cover it).

**Produces:**
1. `--panel airpods` grows a real fixture drive (the calendar-leg
   pattern): before the shell starts, write a schema-true one-line
   sorted-key `status.json` (Pro 3: `is_pro_series:true`,
   `supports_noise_off:false`, both buds `in_ear:true` with high
   levels, case level, `noise_mode:1`, `conversational_awareness:true`,
   `one_bud_anc_mode:false`, `ear_detection_behavior:0`,
   `lid_state:0`) into the isolated HOME's
   `$XDG_STATE_HOME/librepods/` (verify the rig exports
   `XDG_STATE_HOME` into the session env; add it if only
   `XDG_CONFIG_HOME` is isolated today — a leaked host state dir would
   be a host-safety bug anyway). Start a tiny python3 AF_UNIX listener
   at the session's `$XDG_RUNTIME_DIR/librepods.sock` recording every
   received verb to a file (the sni-stub "real external producer"
   pattern; killed by PID at teardown, socket unlinked).
   Drive: `panel open airpods` → `ok`; `panel state` → `airpods`;
   screenshot `airpods-panel.png` (battery rows with three tracks,
   LISTENING MODE with the ANC row selected and NO Off row, CA `ON` in
   accent, ONE-BUD `OFF`, EAR DETECTION row); `qs ipc call airpods
   noise transparency` → recorder file must contain exactly
   `noise:transparency`, one line; rewrite the fixture file in place
   with `noise_mode:2` → settle → screenshot `airpods-live.png` and
   assert the two PNGs differ (the FileView watch actually re-rendered
   — the cheapest guard against a dead binding). `SMOKE_AIRPODS_*`
   marker lines for both PNGs.
2. `--panel dualsense`: drive `panel open dualsense`, assert `ok` +
   `panel state`, screenshot the honest `NO CONTROLLER` card
   (`dualsense-panel.png`, `SMOKE_DUALSENSE` marker). No sysfs
   fixtures — inventing `/sys` entries is banned (CLAUDE.md); the
   read-path proof on real hardware is the owner's g815 after
   rollout.
3. Both legs' settings fixtures add the two opt-in cells to a
   `bar.layout` right region so the same screenshots also prove the
   widgets: airpods visible with the fixture's worst-bud percent,
   dualsense ABSENT from the bar (self-hidden, no empty chrome) — read
   the strip for both. Every other mode keeps omitting the `bar` key,
   so their runs keep proving the default arrangement.

**Verify:** `just vm-smoke --panel airpods`, `just vm-smoke --panel
dualsense`, Read every PNG and the recorder/status artifacts. Commit
(`test(smoke): airpods and dualsense panel legs`).

### Task 6: docs, screenshots, closing sweep

**Files:** `docs/USAGE.md`, `docs/SWITCHOVER.md`, `docs/ARCHITECTURE.md`,
`README.md` + `docs/screenshots/` if the airpods panel earns the grid;
targeted fixes where the sweep finds drift.

**Produces:**
1. USAGE.md: both panels, both bar cells, the `airpods` IPC target,
   presence conditions. SWITCHOVER.md: the host prerequisite is the
   omarchy-pods daemon (`daemon/` subtree, GPL, built out-of-repo)
   running as the `librepods` user service with `--headless`, replacing
   the stock librepods tray app; DualSense needs hid-playstation plus
   the owner's existing udev LED rule for lightbar readability.
   ARCHITECTURE.md: the two services and the panel wiring rows.
2. Full regression pass: `just vm-test`, `just vm-lint`,
   `just vm-smoke --panel airpods`, `--panel dualsense`,
   `--panel bluetooth`, and a plain `just vm-smoke` (default bar
   untouched). Read every PNG against DESIGN.md §1.4/§2. Tree clean,
   all commits pushed.

**Verify:** the commands above, run and read. Commit (`docs: m29 device
panels`).

---

## Review checkpoints

After Task 2 (riskiest: the retirement + new IPC surface) and after
Task 6. Hunt: schema drift against the table in this plan's research
block (diff the QML against it key by key), presence-gate leaks (any
AIRPODS chrome without the status file, any dualsense chrome without a
supply), GPL hygiene (nothing textually ported from omarchy-pods),
design drift (§2.13 hero misuse — an invented readout on the airpods
panel is a defect; §2.14 spacing; bare-label toggles not switches;
named panelWidth), the M24 `Core.State` import trap in any new bar
widget, poll-loop leaks (a DualSense timer running with no consumer),
fake evidence (re-run the smoke legs), unpushed commits.

## After the milestone (orchestrator, not a repo task)

Owner's nix config (`~/.config/nix`): package the omarchy-pods daemon
(Qt6 cmake build of the `daemon/` subtree, installs `librepods` +
`librepods-ctl`), point the existing `librepods` user unit at
`librepods --headless`, add `"airpods"` to the always-visible tier of
`bar.layout.right` (after `"chevron"`, beside `"audio"`) in
`mixins/formalshell.nix`, replace `"custom:dualsense"` with the builtin
`"dualsense"` cell and retire the `dualsense-bar` script + `bar.modules`
entry. Then `nix flake update formalshell` and rebuild g815 (AirPods +
DualSense live there); e1504g follows.
