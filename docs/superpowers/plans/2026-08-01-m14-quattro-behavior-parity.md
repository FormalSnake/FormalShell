# FormalShell M14: quattro behavior parity (network, bluetooth, AI usage, active window, clipboard images)

> Workflow-driven per `docs/superpowers/workflow-template.md`. Read
> `CLAUDE.md` and `docs/DESIGN.md` first, both binding. M13b
> (`2026-07-30-m13b-trial-feedback-round-two.md`) landed immediately before
> this plan; its task notes are context for every file touched here.

**Origin, owner ask (2026-08-01, continued daily-drive):** "I had no wifi
connection paired, and I had to use nmcli instead. I want the bluetooth and
wifi panels to look and behave like omarchy quattro. I want their Claude
Code/Codex usage widget too (they just updated, you need to reclone the
repo). And the active app should show the icon and the app name, not the
ID. Just like the app launcher. Also add image support to the clipboard
manager. Generally polish the entire experience, use omarchy quattro as a
close reference."

**Research already done (2026-08-01), do not re-derive:**

- Fresh omarchy quattro clone at `~/Developer/omarchy` (fa95901, 2026-07-31)
  and DMS at `~/Developer/DankMaterialShell`. Both are read-references; the
  omarchy findings below carry file:line pointers into that clone.
- Quickshell `Networking` covers the whole omarchy wifi flow natively
  (pinned source `/nix/store/zxnaal0jk0qcha2z2nbcdi8cya9iz4bz-source`):
  `WifiNetwork.connectWithPsk(psk)` (`src/network/wifi.hpp:39`),
  `WifiDevice.scannerEnabled` (`wifi.hpp:65`), `Network.known/connected/
  state/stateChanging`, `connect()/disconnect()/forget()`
  (`network.hpp:36-60`), `Networking.wifiEnabled` (`qml.hpp:90`),
  `WifiSecurityType` (Open=10, Owe=9; everything else is secured;
  WpaEap=4/Wpa2Eap are enterprise — `enums.hpp:116-126`), and a
  `connectionFailed(reason)` signal with `ConnectionFailReason`
  (NoSecrets=1, WifiClientFailed=3, WifiAuthTimeout=4, WifiNetworkLost=5 —
  `enums.hpp:75-85`, signal documented at `wifi.hpp:31`).
- Quickshell `Bluetooth` is equally complete: `adapter.discovering`
  (writable, `src/bluetooth/adapter.hpp:74`), `device.pair()/cancelPair()/
  forget()/connect()/disconnect()` (`device.hpp:112-122`), `paired/bonded/
  pairing/trusted/blocked` (`device.hpp:83-95`), `battery` **0..1**
  (`device.hpp:101` — CLAUDE.md fraction rule applies).
- `DesktopEntries.heuristicLookup(name)` / `byId(id)` exist
  (`src/core/desktopentry.hpp:309-313`).
- Omarchy wifi UX (`shell/plugins/panels/network/Panel.qml`, `Model.js`):
  scanner enabled while panel open, disabled on close (Panel.qml:352,463);
  one sorted list — connected first, then known, then signal desc
  (Model.js:282-290) — with section headers derived from the sort; rows
  show signal, SSID (blank → "Hidden"), lock glyph when secured, a status
  sub-line ("Connecting…", "Wrong password", …); click on connected →
  disconnect, secured+unknown → **inline password prompt expanding under
  the row** (masked TextField, Enter connects via `connectWithPsk`, Esc
  cancels), otherwise `connect()` (Panel.qml:1852-1869); failure reasons
  mapped NoSecrets→"Passphrase required" (reopens the prompt),
  WifiAuthTimeout→"Wrong password", WifiNetworkLost→"Network lost"
  (Model.js:335-343, Panel.qml:1801-1803); a 15s client-side timeout clears
  a stuck busy state (Panel.qml:1025-1041). Enterprise (EAP) networks go
  through an nmcli stdin script there — out of scope here (see Task 2).
- Omarchy bluetooth UX (`shell/plugins/panels/bluetooth/Panel.qml`,
  `Model.js`): discovery kept alive by a 1s self-healing timer that keeps
  nudging `adapter.discovering = true` while the panel is open and the
  adapter enabled (BlueZ rejects StartDiscovery while powering up and
  times discovery out on its own — Panel.qml:457-464); three buckets —
  connected / known (paired||bonded||trusted) / discovered (rest, shown
  only while discovering, filtered to human-readable names, MAC-shaped
  labels rejected — Model.js:36-39,83-102); row click: connected →
  disconnect, known → connect, discovered → pair; omarchy shells out to
  bluetoothctl for pair→trust→connect sequencing with timeouts
  (`bin/omarchy-bluetooth-device:31-51`) but quickshell's native
  `pair()`/`trusted = true`/`connect()` express the same sequence — stay
  native (CLAUDE.md: pure QML, prefer toolkit over subprocess).
- Omarchy AI usage widget (`shell/plugins/model-usage/`): Claude limits
  come from `GET https://api.anthropic.com/api/oauth/usage` with headers
  `Authorization: Bearer <accessToken>` + `anthropic-beta: oauth-2025-04-20`
  + `Accept: application/json`, token read from
  `~/.claude/.credentials.json` → `.claudeAiOauth.accessToken` (also
  `.expiresAt`, `.subscriptionType`, `.rateLimitTier`) — see
  `providers/Claude.qml:267-305,439-496`. Response carries `five_hour` and
  `seven_day` (plus `seven_day_oauth_apps`) buckets, each with
  `.utilization` and `.resets_at` (Claude.qml:460-463). Codex limits come
  from spawning `codex -s read-only -a untrusted app-server` and speaking
  JSON-RPC over stdio (`account/read`, `account/rateLimits/read`) —
  `scripts/codex_usage_scanner.py:271-316` has the exact framing. Bar cell
  is a single glyph (`󱚣`) that alarms at ≥90% utilization; popout shows a
  LIMITS section (per-window row: title, percent, meter, "Resets in Xh Ym")
  — Panel.qml:291-302,586-645. Polling: 15min default, denser while open.
  Honest no-auth: "Waiting for auth" with limits at -1, never invented.
  Omarchy's local-stats python scanners are NOT ported (no python, no
  compiled helpers here); limits + tier are the load-bearing feature.
- Omarchy's own bar shows title text only; the icon + app-name treatment
  the owner wants is DMS's `FocusedApp` pattern
  (`quickshell/Modules/DankBar/Widgets/FocusedApp.qml:130-137`):
  `DesktopEntries.heuristicLookup(appId)` → `entry.name` for the label,
  entry icon via themed icon lookup, raw appId only as fallback.
- Omarchy clipboard images (`shell/plugins/clipboard/capture.sh:19-43`,
  `Clipboard.qml:283-299`): a SECOND `wl-paste --type image/png --watch`
  process alongside the text watcher; image bytes written to a
  content-addressed `$XDG_STATE_HOME/omarchy/clipboard-images/<sha256>.<ext>`
  file (dedupe by hash), history entry stores `{type:"image", mime, path}`;
  previews are plain `Image` elements reading the file (no data URIs);
  copy-back is `wl-copy --type <mime> < <path>`
  (`bin/omarchy-clipboard-paste-file:26-33`); sensitive captures
  (`CLIPBOARD_STATE=sensitive`) skipped exactly like text.

## Constraints

- Same as M13/M13b: `CLAUDE.md` binds (host-session safety, D-Bus
  isolation, honest unavailable states, 0..1 fractions, opaque window ids,
  glyphs from the pinned cmap via fonttools ttx — never memory), DESIGN.md
  is the authority, verification ONLY on the VM rig (`just vm-test`,
  `just vm-smoke *FLAGS`), never ssh to e1504g/g815, additive smoke
  changes, one conventional commit per task, tree clean before finishing,
  no CLAUDE.md/CLAUDE-*.md in commits.
- New IPC verbs added here (`network` target, `usage` panel name) are spec
  addendums in the `panel`-target tradition (CLAUDE.md hard-rules section):
  document them in USAGE.md, unknown args return error strings, never
  silent no-ops.
- Secrets discipline: a wifi PSK typed into the panel goes straight to
  `connectWithPsk`, is never logged, never echoed into `debug` IPC dumps,
  never written to state.json. The `network connect` IPC verb takes the
  PSK as an argument for the headless rig only — USAGE.md documents that
  argv is world-readable and the interactive prompt is the real path.
- The usage widget's OAuth token stays in memory, is never logged, and the
  `usage` IPC/debug surfaces expose percentages and reset times only,
  never the token or raw credentials JSON.

---

### Task 1: Pure model groundwork (network sort/sections, bluetooth buckets, clipboard image entries)

**Files:** create `shell/Network/model.js`, `shell/Bluetooth/model.js`,
`tests/tst_network_model.qml`, `tests/tst_bluetooth_model.qml`; modify
`shell/Clipboard/history.js`, `tests/tst_clipboard_history.qml`,
`shell/Menu/providers.js` (clipboardProvider image mapping),
`tests/tst_menu_model.qml` if provider shape assertions live there.

**Produces:**
1. `shell/Network/model.js` (pure, `.pragma library`, mirrors
   `workspaces.js` style): `sortWifiRows(rows)` (connected → known →
   signal desc), `sectionOf(row)` / a section splitter (KNOWN vs
   AVAILABLE), `failureText(reason)` mapping ConnectionFailReason ints to
   uppercase status strings (`PASSPHRASE REQUIRED`, `WRONG PASSWORD`,
   `NETWORK LOST`, `CONNECTION FAILED`), `isSecured(security)` /
   `isEnterprise(security)` over the WifiSecurityType ints, and
   `signalBar(strength)` moved out of NetworkPanel.qml (same █░ five-cell
   rendering, 0..1 input).
2. `shell/Bluetooth/model.js`: `buckets(devices, discovering)` →
   `{connected, known, available}` per the omarchy rules above (known =
   paired||bonded||trusted; available only while discovering),
   `hasHumanName(name)` rejecting empty/MAC-shaped/UUID-shaped labels,
   alphabetical sort within buckets, `statusText(device)` (PAIRING…,
   CONNECTING…, battery % from the 0..1 fraction when connected and
   batteryAvailable).
3. `history.js` learns image entries: an entry is
   `{id, kind: "text"|"image", text?, path?, mime?, capturedAt}` (existing
   entries without `kind` read as text — migration is a pure normalize on
   load, no file rewrite pass). `add()` dedupes text by `text`, images by
   `path` (content-addressed upstream, so path equality IS content
   equality); eviction/clear/remove return the evicted image paths
   (`{state, removedPaths}` or equivalent) so the service can delete files
   — history.js itself stays pure, no I/O.
4. `clipboardProvider` maps image entries to nodes with `label: "IMAGE"`,
   a dimmed captured-at time in the `desc` slot, `thumbSource: <path>`
   (new node field), same self-targeting `clipboard copy <id>` action.

**Verify:** `just vm-test` green with the three new/extended test files
actually asserting the sort order, bucket membership, name filter, image
dedupe, eviction path reporting, and provider node shape. Commit
(`feat(model): …`).

### Task 2: Wifi panel — scan, connect, inline passphrase, forget

**Files:** modify `shell/Surfaces/Panels/NetworkPanel.qml`,
`shell/Surfaces/Bar/widgets/NetworkWidget.qml` (only if the glyph needs a
secured/connecting variant), `docs/USAGE.md` (network panel section).

**Produces:**
1. `WifiDevice.scannerEnabled` tracks `isOpen` (on for every wifi device
   while the panel is open, off on close — omarchy's idiom, so the list is
   live while you look at it and the radio idles after).
2. `Networking.wifiEnabled` toggle as a `WI-FI POWER`-style action cell in
   the panel header region, mirroring BluetoothPanel's POWER cell.
3. Rows rebuilt on `Network/model.js`: WIRED section unchanged; wifi rows
   in one sorted pass under `KNOWN` and `AVAILABLE` meta headers; each row
   shows the mono signal bar, SSID (empty → `HIDDEN`, dim), a lock glyph
   for secured networks (codepoint verified from the pinned
   nerd-fonts-jetbrains-mono cmap via fonttools ttx, per the GithubWidget
   precedent — never from memory), and the connected row is the inverted/
   selected cell per the ledger contract.
4. Row activation: connected → `disconnect()`; known or open →
   `connect()`; secured+unknown → the row expands an inline passphrase
   cell (masked `TextInput`, `●` U+25CF echo, uppercase dim
   `ENTER PASSPHRASE` placeholder, Enter → `connectWithPsk(text)`, Escape
   collapses — AuthPrompt's field idiom at ledger-row scale, one prompt
   open at a time). Enterprise networks render a dim `ENTERPRISE` meta tag
   instead of a prompt (honest limitation, documented in USAGE.md; omarchy
   needs an nmcli side-script for these and we are not shelling out).
5. Status sub-line per row driven by `state`/`stateChanging` and the
   `connectionFailed` signal: `CONNECTING…`, `DISCONNECTING…`,
   `FORGETTING…`, and failureText mappings; `NoSecrets` reopens the
   passphrase prompt with `PASSPHRASE REQUIRED`; wrong-password shows
   `WRONG PASSWORD` in `urgent` italic (the lock screen's error idiom). A
   15s per-action fallback timer clears a stuck busy state as `TIMED OUT`.
6. `FORGET` action cell on known rows (hover-visible like the row's other
   action, urgent-colored) calling `forget()`.
7. Keyboard nav via the existing `Panel.keyPressed` hook (PowerPanel's
   consumer pattern): arrow cursor over wifi rows (hover-cursor state,
   DESIGN.md §1.1 unified), Enter activates, Escape closes prompt first,
   panel second. Typing while the passphrase prompt is open goes to the
   prompt, not the cursor.

**Verify:** `just vm-lint` (qmllint); `just vm-test`; `just vm-smoke
--panel network` — the VM's virtio NIC still renders the honest
WIRED-only/no-wifi state, Read the PNG. Real connect behavior is proven in
Task 3's rig, not here. Commit (`feat(network): …`).

### Task 3: hwsim wifi rig + `network` IPC target + `--wifi` smoke leg

**Files:** modify `nix/testvm.nix`, `dev/smoke-niri.sh`, `dev/vm.sh` (only
if artifact pulls need it), `docs/USAGE.md` (IPC table); create
`shell/Ipc/NetworkIpc.qml`; modify `shell/shell.qml`.

**Produces:**
1. `nix/testvm.nix`: `mac80211_hwsim` (2 radios) + hostapd on the second
   radio broadcasting `FORMALTEST` (WPA2-PSK, throwaway psk in-file, e.g.
   `formaltest-psk`), NetworkManager managing the first radio but
   explicitly not the AP interface (`unmanaged`), and a DHCP server
   (dnsmasq or networkd) on the AP interface so a successful association
   reaches full `Connected` state honestly — this is the sanctioned
   "enable a real service in testvm.nix" path, giving the shell a genuine
   scannable, joinable, wrong-password-capable network.
2. `NetworkIpc.qml` (spec addendum, `panel` tradition): `status()` →
   compact JSON (wifi enabled, per-network name/known/connected/secured/
   signal), `connect(ssid, psk)` (empty psk = plain `connect()`),
   `forget(ssid)`, `wifi(enabled)`. Unknown ssid → error string. These
   drive the headless rig and give compositor keybinds a target; the
   argv-visibility caveat lands in USAGE.md.
3. `--wifi` smoke leg: waits for the scan to surface `FORMALTEST` in
   `network status`, drives `connect` with a WRONG psk and polls status
   until the failure lands (NM retry cycles take a while — allow ~45s),
   screenshots the panel showing `WRONG PASSWORD` (`wifi-wrong.png`), then
   connects with the real psk, polls to `connected:true`, screenshots
   (`wifi-connected.png`), then `forget`s and confirms the network drops
   back to not-known. Panel opened via the existing `panel open network`
   route so the screenshots show the real surface.

**Verify:** `just vm-build` (rebuilds the VM image — budget for the
rebuild+reboot cycle via `dev/vm.sh stop/start`), then `just vm-smoke
--wifi`: Read both PNGs (wrong-password urgent row visible; connected
inverted row visible) and the status JSON artifacts. `just vm-smoke
--panel network` still green (additive). Commit (`feat(network): …` or
split rig/ipc commits if cleaner — but tree clean at the end either way).

### Task 4: Bluetooth panel — discovery, pair, connect, forget

**Files:** modify `shell/Surfaces/Panels/BluetoothPanel.qml`,
`docs/USAGE.md` (bluetooth section).

**Produces:**
1. Discovery self-heal: while `isOpen` and adapter enabled, a 1s repeating
   timer sets `adapter.discovering = true` whenever it reads false
   (omarchy's BlueZ-quirk workaround); discovery drops when the panel
   closes.
2. Sections rebuilt on `Bluetooth/model.js` buckets: `CONNECTED`,
   `PAIRED`, `AVAILABLE` (available only while discovering, human-named
   devices only). Adapter POWER cell stays. Honest states: `NO ADAPTER`
   (unchanged), adapter off → dim `TURN ON TO SCAN`, discovering with
   nothing found → dim `SCANNING…`.
3. Row status sub-line from `model.js.statusText`: `PAIRING…`,
   `CONNECTING…`, `DISCONNECTING…`, battery % (0..1 → %) when connected
   and available.
4. Actions: available row → native pair-trust-connect sequence (`pair()`;
   on `pairedChanged` → `trusted = true` then `connect()` — the omarchy
   bluetoothctl sequence expressed natively; a 20s fallback timer clears a
   stuck `PAIRING…` honestly), paired row → `connect()`/`disconnect()`,
   `FORGET` action on paired rows → `forget()`. Same keyboard-nav
   treatment as Task 2 via `Panel.keyPressed`.

**Verify:** `just vm-test`; `just vm-lint`; `just vm-smoke --panel
bluetooth` — the VM has no adapter, so the honest `NO ADAPTER` cell is the
expected screenshot; Read it. Pairing flow correctness rides on the
model.js tests (bucket transitions) plus qmllint, stated honestly in the
commit. Commit (`feat(bluetooth): …`).

### Task 5: Active window — desktop icon + app name

**Files:** modify `shell/Surfaces/Bar/widgets/ActiveWindow.qml`,
`docs/DESIGN.md` (one amendment line), `nix/testvm.nix` + `dev/smoke-niri.sh`
(fixture window for the assertion), `docs/USAGE.md` if it names the widget.

**Produces:**
1. `DesktopEntries.heuristicLookup(appId)` on the focused window (DMS's
   FocusedApp pattern): label becomes `entry.name`, rendered foreground;
   the window title follows dimmed (roles swap from today's dim-appId +
   title); icon image resolved from the entry via the same check-resolved
   `Quickshell.iconPath` path the launcher uses, rendered at the glyph
   cell size, radius 0. Fallbacks, in order: entry without icon → name
   only; no entry at all → raw appId exactly as today; no focused window →
   hidden.
2. DESIGN.md amendment: the bar's active-window cell joins launcher rows
   as a sanctioned image-icon surface (owner-requested, this plan).
3. Smoke assertion: the nested session spawns a real windowed app carrying
   a desktop entry + themed icon (reuse/extend the M13b fixture approach in
   testvm.nix if none exists), and one existing leg's screenshot is taken
   with that window focused so the bar shows icon + name — Read the PNG
   and confirm the label is the entry name, not the appId.

**Verify:** `just vm-test`; `just vm-smoke` leg with the fixture window,
PNG read. Commit (`feat(bar): …`).

### Task 6: Clipboard images end to end

**Files:** modify `shell/Services/ClipboardService.qml`,
`shell/Surfaces/Menu/MenuRow.qml`, `shell/Ipc/ClipboardIpc.qml` (list dump
gains kind/path), `dev/smoke-niri.sh` (`--clipboard` leg), `docs/USAGE.md`.

**Produces:**
1. A second watcher Process: `wl-paste --type image/png --watch sh -c …`
   which (a) skips `CLIPBOARD_STATE=sensitive`, (b) streams stdin to a
   mktemp file under `$XDG_STATE_HOME/formalshell/clipboard-images/`,
   (c) content-addresses it to `<sha256>.png` (existing hash → drop the
   temp, reuse), (d) emits the final path NUL-terminated on its own
   channel (separate Process = separate handler; no in-band tagging).
   Startup/restart handling mirrors the existing text watcher, including
   the backoff timer. Verify flag/env behavior against the wl-clipboard
   man page in the store, as the existing header comment did.
2. `ClipboardService` gains `_captureImage(path)` → `history.js.add` with
   `kind:"image"`; `copy(id)` branches: image entries run
   `sh -c 'exec wl-copy --type image/png < "$0"' <path>`; eviction/remove/
   clear delete newly-orphaned image files via the paths history.js now
   reports (an rm Process; never rm anything outside the
   clipboard-images dir).
3. `MenuRow` renders `thumbSource` nodes as a taller image row: thumbnail
   `Image` at twice the body row height, width capped, PreserveAspectFit,
   radius 0, no border, sharing the ledger rule contract; `IMAGE` label +
   dimmed time ride beside it. Text rows are pixel-identical to today.
4. `--clipboard` smoke leg additions: generate a small imagemagick PNG,
   `wl-copy --type image/png < fixture`, assert `clipboard list` shows the
   image entry (kind + path under the isolated HOME), activate `clipboard
   copy <id>` on it, read back `wl-paste --type image/png | sha256sum` ==
   fixture hash, and take the menu-route screenshot with the thumbnail row
   visible.

**Verify:** `just vm-test` (Task 1's history tests already cover the model;
extend if service-shaped gaps emerged); `just vm-smoke --clipboard`, Read
the PNG (thumbnail row) and the hash comparison in the log. Commit
(`feat(clipboard): …`).

### Task 7: AI usage widget + panel (Claude Code / Codex)

**Files:** create `shell/Surfaces/Panels/UsagePanel.qml`,
`shell/Surfaces/Bar/widgets/UsageWidget.qml`, `shell/Usage/usage.js`,
`tests/tst_usage.qml`; modify `shell/Bar/layout.js` (BUILTIN_WIDGETS gains
`usage`, NOT in DEFAULT_LAYOUT — opt-in like `github`),
`shell/Surfaces/Bar/Bar.qml`, `shell/shell.qml`, `shell/Ipc/PanelIpc.qml`
(registry gains `usage`), `docs/USAGE.md`.

**Produces:**
1. `shell/Usage/usage.js` (pure): `parseCredentials(json)` (accessToken/
   expiresAt/subscriptionType/rateLimitTier out of `.claudeAiOauth`),
   `parseUsage(json)` (five_hour/seven_day/seven_day_oauth_apps →
   `{label, percent 0..1, resetsAt}` rows), `tierLabel()`,
   `formatReset(nowMs, resetsAtIso)` → `RESETS 2H 14M` strings, plus the
   equivalent parsers for the Codex `account/read` +
   `account/rateLimits/read` JSON-RPC replies (shape verified from
   `~/Developer/omarchy/shell/plugins/model-usage/scripts/codex_usage_scanner.py`).
2. `UsagePanel.qml` (GithubPanel's poll-in-panel pattern verbatim:
   opt-in `pollEnabled` flipped by the widget, open always re-polls,
   honest states): Claude leg reads `~/.claude/.credentials.json` via
   FileView (missing/expired → `NO AUTH`), hits the oauth usage endpoint
   with XMLHttpRequest exactly per the research header, renders a `CLAUDE`
   section: tier meta row, then one row per window — uppercase window
   label (`5-HOUR`, `WEEKLY`), percent, a full-width flat `accent` fill
   track (DESIGN.md slider idiom — flat block, radius 0, NOT omarchy's
   pill meter), dim `RESETS …` meta — ≥90% windows swap the track fill to
   `urgent`. Codex leg: spawn `codex -s read-only -a untrusted app-server`
   as a Process, speak the JSON-RPC framing the scanner script documents
   over stdin/stdout (verify quickshell Process stdin-write support
   against the pinned source; if the framing genuinely cannot be spoken
   from QML, render a dim `CODEX UNAVAILABLE` honest state and record why
   in the commit — never a fake number), `codex` missing from PATH →
   `NO CODEX`. Poll interval `usage.intervalMs` (default 900000), settings
   toggles `usage.claude`/`usage.codex` (default true).
3. `UsageWidget.qml` (GithubWidget's shape): glyph verified from the
   pinned cmap + the worst window's percent as the cell text; whole cell
   goes full-bleed `urgent` at ≥90% (DESIGN.md §2.4); hidden until first
   data like github (`shown` pattern); click toggles the panel (accent
   dot idiom); named in PanelIpc as `usage` so `panel open usage` works
   headlessly.
4. Token/secrets discipline per Constraints.

**Verify:** `just vm-test` (usage.js parsers against fixture JSON copied
into the tests — the oauth response shape and codex RPC replies from the
research, plus malformed/missing-field cases); `just vm-lint`; `just
vm-smoke --panel usage` — the VM has no `~/.claude` credentials and no
codex binary, so the honest `NO AUTH` + `NO CODEX` cells are the expected
screenshot; Read it. Live percentages are owner-verified on the real host
post-switchover, stated honestly in the commit. Commit (`feat(usage): …`).

### Task 8: Polish sweep, docs, screenshots

**Files:** modify `docs/USAGE.md`, `docs/SWITCHOVER.md`, `README.md` +
`docs/screenshots/*` as touched; targeted QML fixes anywhere the sweep
finds drift.

**Produces:**
1. Full smoke matrix re-run; Read every PNG against DESIGN.md's checkable
   rules (§2's six checks, §3's surface translations, §4 motion) and the
   omarchy chrome reference; fix confirmed drift in bounded, per-surface
   commits (no restyling surfaces this plan didn't touch unless a §2
   check outright fails — DESIGN.md's closing rule).
2. USAGE.md: network panel behavior + `network` IPC verbs + psk caveat,
   bluetooth pairing flow, clipboard images, `usage` widget/panel +
   settings keys, active-window change. SWITCHOVER.md gains the usage
   widget opt-in note beside github's. README/screenshots recaptured for
   surfaces whose look changed (`--panel network`, `--panel bluetooth`,
   `--clipboard` menu route, bar with active-window fixture).
3. Final `just vm-test`, `just vm-lint`, full-default `just vm-smoke`
   green; tree clean; every commit pushed.

**Verify:** the commands above, run and read. Commit(s)
(`docs: …` / `fix(<scope>): …`).

---

## Review checkpoints

After Task 3 (the hwsim rig is this plan's riskiest infrastructure — a
reviewer re-runs `--wifi` and hunts fake evidence in the PNGs/JSON) and
after Task 8 (full sweep: design drift, host-safety leaks, secrets in
logs/dumps, contract drift on the new IPC verbs, unpushed commits).
