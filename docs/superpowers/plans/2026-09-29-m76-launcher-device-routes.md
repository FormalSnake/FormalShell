# M76: launcher device routes

Owner rule (2026-09-29): if the job is picking one item from a list, it
lives in the launcher so the eyes never leave where you typed; if it is
glancing at live state or moving a slider, it stays a bar panel. Four new
launcher routes, each reading the same Quickshell objects and services its
panel already reads, never a copy of the panel's card: rows, search, Enter.

- `wifi`: scanned networks, Enter connects or disconnects, a secured
  network asks for its password through the launcher's own input step,
  saved networks marked, Shift+Enter forgets.
- `bluetooth`: paired devices, Enter connects or disconnects, the connected
  ones ticked.
- `audio`: output and input devices, Enter makes one the default, the
  current default ticked. Volume stays in the panel.
- `radio`: favourite stations plus a station search, Enter plays, the
  playing station ticked, Shift+Enter adds or removes a favourite.

Work happens on branch `feat/launcher-device-routes` in
`../FormalShell-device-routes`; main is edited by other sessions, rebase
before merge. One subagent per task, sequential, in order: every route task
leans on Task 1.

## Codebase facts this leans on (read 2026-09-29 at 1c9ddf7)

- Two ways a route gets rows. `lights` (c044ae4) merges a node fragment
  into `Menu.qml`'s `_defaultObj`, which goes through `Model.buildTree`;
  `buildTree` (`shell/Menu/model.js:158-181`) copies a fixed list of keys
  and drops everything else, `desc` included. A provider fn registered in
  `_tree`'s `Providers.applyProviders(...)` map (`clipboard`, `tray`,
  `gpu`) returns finished node objects that skip `buildTree`, so `desc`,
  `section`, `dim` and any new field reach `MenuRow` as written. The four
  routes are flat lists, so they are provider fns.
- A jsonc node with a `provider` key and no registered fn stays kind
  `provider` and stays listed while childless (`default-menu.jsonc`'s
  `monitor` header); a childless `submenu` is filtered out of its parent.
  `Hints.countFor` shows a provider's child count as the row's hint.
- `checked` is either a shell command (run once per open through
  `ConditionEvaluator._run`) or `@state:<path>`, resolved live from
  `conditions.stateSnapshot` against the closed lists in
  `shell/Menu/toggles.js`. Lights added `ENUM_PATHS` matched as
  `@state:<path>=<value>`. A literal boolean would be run through `sh -c`,
  so a dynamic row's tick has to be an `@state:` path.
- `routeOnly` (`shell/Menu/search.js:145`) hides a node's children from a
  search typed outside it; the node itself still scores. Nothing hides one
  leaf from root search while leaving its siblings visible.
- Shift+Enter is `Menu.qml`'s `_activateRowAlternate`: two bespoke cases
  (clipssh image, app on the discrete GPU), each with its own flag in
  `shell/Menu/actions.js`'s `hints()`.
- The input step (`Menu.openInput(prompt, token)`, `_submitInput`,
  `_writeSelection`) writes every answer to
  `$XDG_STATE_HOME/formalshell/menu-selection.txt` as `{token, value}`
  and emits `selectionResolved(token, value, cancelled)`, routed in
  `shell/shell.qml:320-326` to `ReminderService` and `LightsService`. The
  field (`searchInput`, a raw `TextInput`) has no echo mode set, and
  `_emptyTitle` (`Menu.qml:974`) quotes `searchInput.text` back. As it
  stands a Wi-Fi password would land on disk in plain text.
- Wi-Fi has no service. `NetworkPanel.qml:755-936` owns the whole action
  state machine (`_runAction`, `_clearAction`, `_checkActionCompletion`,
  `_failAction`, `actionTimeout`, `enterpriseProc`, `_activateWifiRow`,
  `_forgetNetwork`, `_submitPassword`), and the `connectionFailed` and
  state-change `Connections` live inside the row delegate
  (`NetworkPanel.qml:1140-1150`), so they only exist while the panel is
  open. `NetworkIpc.qml` reaches that state through `panel.load()`.
  `scannerEnabled` follows the panel's `isOpen` (`_applyScanner`).
- Bluetooth has no service either, by design: `BluetoothPanel.qml` and
  `BluetoothIpc.qml` bind `Quickshell.Bluetooth` directly.
  `BluetoothModel.buckets(devices, discovering)` gives connected, known and
  available; known is paired, bonded or trusted.
- Audio: `AudioService` binds the default sink and source.
  `AudioPanel.qml` lists devices off `Pipewire.nodes` (`audio !== null &&
  !isStream`, `isSink` splits them) and switches with
  `Pipewire.preferredDefaultAudioSink/Source = node` (`_makeDefault`,
  `AudioPanel.qml:202`). Labels are `description || name`.
- Radio: `RadioService.favorites` (saved records, `uuid` is the id),
  `playFromSaved(station, list)`, `play(station, list)`,
  `toggleFavorite(station)`, `isFavorite(uuid)`, `stop()`, `station`,
  `running`, and the async `search(query, done)` (three Radio Browser
  requests unioned, `done(null)` when all three failed).
- Honest empty rows: a `kind: "note", dim: true` row is pulled out of the
  rows by `_resolve` and drawn as the body's empty state
  (`Menu.qml:556-563`); when live rows exist beside it, it is dropped.
  `menu status` does not report it today.
- Route-local async search: `NixSearchProvider.qml` (debounce, one
  process, stale answers dropped, `rowsFor(q)` returning note rows for
  searching, empty and failed). Triggers in use: `:e`, `:nix`, `:k`.
- `MenuIcons.iconFor` matches exact ids only (`shell/Menu/icons.js`); a
  dynamic row falls back to `fallbackFor(kind)`, which is `terminal` for
  an action. Both icon sets have `wifi`, `lock`, `bluetooth`,
  `bluetooth-connected`, `volume-2`, `mic`, `radio`, `star`, `search`.
  Only Lucide has `speaker`.
- The VM (`nix/testvm.nix`) has two hostapd radios (`FORMALTEST` WPA2-PSK
  `formaltest-psk`, `FORMALTEST-EAP` PEAP `formaltest`/`formaltest-eap-pw`),
  PipeWire with one null sink (`virtual-sink`) and pulse, bluez with no
  adapter, and no route to Radio Browser guaranteed.

## Decisions (owner should know)

- WifiService is extracted (Task 2). The launcher cannot drive a panel
  that is not open, and duplicating the state machine would put two
  answers to "is this connect done" in the shell. The panel keeps its
  prompt and cursor state and renders the service's action state;
  `NetworkIpc` calls the service and loses its `panel` property.
- Secret input mode (Task 1). `openInput(prompt, token, secret)`:
  masked field, the answer only ever goes out through the in-process
  `selectionResolved` signal, the selection file gets a cancel-shaped
  record with no value, the field is cleared on the way out, and the empty
  body never quotes it.
- After a password is submitted the launcher reopens on `wifi`, so the
  row's "Connecting" and then its tick or its failure text are read where
  the password was typed.
- Shift+Enter becomes a row field: `alternate` (an action string) and
  `alternateLabel` (the hint). Wi-Fi forget and radio favourite use it;
  the two existing bespoke cases stay as they are.
- `localOnly` rows: scored by a search only while their parent level
  is open. Unknown nearby SSIDs and radio search results are `localOnly`;
  saved networks, paired devices, audio devices and favourites are
  reachable from a root query.
- Route labels differ from the panel rows a root query already finds:
  `Wi-Fi`, `Bluetooth Devices`, `Audio Devices`, `Radio Stations` against
  `Network`, `Bluetooth`, `Audio`, `Radio` under Panels.
- Only radio search gets a trigger, `:r <query>`. The other three are
  tree rows a plain root query already walks; the `:` prefixes exist for
  route-local datasets (`:e`, `:nix`, `:k`) and radio search is the only
  one here.
- No pairing from the launcher. Discovery is watching a list fill in,
  which is the panel's job; the route lists what is already paired.
- `NetworkModel.failureText` goes sentence case ("Wrong password"): the
  launcher row shows it and DESIGN.md §5 bans uppercase. The panel shows
  the same string.

## Shared shapes (every task uses these)

- Row ids: `<route>.<kind>.<Providers.idPart(key)>`, where `idPart(s)` is
  `encodeURIComponent(String(s)).replace(/\./g, "%2E")`. SSIDs and
  PipeWire node names carry dots, and a dot in an id is a tree level.
- Actions: `@ipc:<route>.<verb>:<raw value>`, parsed in
  `_dispatchInternal` like lights: the verb runs to the first `:`, the
  value is everything after it, unencoded.
- Every action row is `keepOpen: true` so its tick or state text changes
  under the cursor, except radio search results (Task 5 says why not).
- Ticks: `checked: "@state:<path>=<value>"` with the raw value.
- Live data comes through `LiveMenuSources.qml`, gated on `active` like
  `clipboardItems` and republished only when the fields the rows read
  change (the `_windowsKey` pattern), so a signal-strength tick or a
  volume change never rebuilds the tree.
- Empty and unavailable rows are `kind: "note", dim: true`, sentence case,
  ids `<route>.unavailable`, `<route>.off`, `<route>.empty`.

## Task 1: shared launcher plumbing (sonnet)

Mirror: c044ae4's `ENUM_PATHS` change for ticks; `NixSearchProvider.qml`
stays untouched here.

- `shell/Menu/toggles.js`: add `LIST_PATHS` (`"bluetooth.connected"`,
  commented with its source). `snapshot()` normalises a list path to an
  array of strings (non-strings dropped, a non-array becomes `[]`).
  `resolveState` on `path=value`: an enum path compares equal, a list path
  tests membership, an unknown path is false. `isKnownListPath`, and
  `unknownKeys` accepts list paths. Add enum paths `wifi.ssid`,
  `audio.sink`, `audio.source`, `radio.station`, each commented with the
  service field that feeds it.
- `shell/Surfaces/Menu/ConditionEvaluator.qml`: the four enum keys and the
  list key in `stateSnapshot`. `wifi.ssid` reads
  `WifiService.connectedSsid`, `audio.sink`/`audio.source` read
  `AudioService.sinkName`/`sourceName`, `radio.station` reads
  `RadioService.station ? RadioService.station.uuid : ""`, and
  `bluetooth.connected` reads a new `property var bluetoothConnected: []`
  that `Menu.qml` binds to `liveSources.bluetoothConnected`. Each service
  field is added by the task that owns it; until then the key reads `""`
  or `[]`. Write the keys now with those placeholders so later tasks only
  swap the right-hand side.
- `shell/Menu/search.js` `rank`: a node with `localOnly === true` is not
  scored unless `open[node.parentId] === true`; its own children are
  walked as before. Header comment beside `routeOnly`'s.
- `shell/Menu/providers.js`: `idPart(s)`, above `lightsEntries`.
- `shell/Menu/icons.js`: `ROUTE_ICON_PREFIXES`, an ordered list of
  `[prefix, name]` consulted by `iconFor` after an exact miss:
  `wifi.net.` -> `wifi`, `bluetooth.dev.` -> `bluetooth`,
  `audio.output.` -> `volume-2`, `audio.input.` -> `mic`,
  `radio.fav.` -> `radio`, `radio.result.` -> `radio`. Exact entries for
  the route rows: `wifi` `wifi`, `bluetooth` `bluetooth`, `audio`
  `volume-2`, `radio` `radio`, `radio.search` `search`, `radio.stop`
  `square`, `wifi.off` `wifi-off`, `bluetooth.off` `bluetooth`.
- Alternate activation: `_activateRowAlternate` in `Menu.qml` checks
  `node.alternate` first (after the app-view guard, before the clipssh
  branch): `_runAction(node.alternate)`, then `close()` unless
  `node.keepOpen === true`. `shell/Menu/actions.js` `hints()` takes
  `alternateLabel` (a string, "" for none) and pushes
  `{ keys: KEY_SHIFT_ENTER, label: alternateLabel }` when it is non-empty
  and not confirming; `Menu.qml`'s `_actionBar` passes
  `root._cursorNode ? (root._cursorNode.alternateLabel || "") : ""`.
  Update `actions.js`' header comment list.
- Secret input: `openInput(prompt, token, secret)` sets
  `property bool _inputSecret` (false for the two existing callers,
  which pass two arguments). `searchInput.echoMode: root._mode === "input"
  && root._inputSecret ? TextInput.Password : TextInput.Normal`.
  `_writeSelection`: when `_inputSecret`, write
  `{token, cancelled: true, secret: true}` to the file (so an external
  poller never waits forever and never reads a value), emit the signal
  with the real value, then clear `searchInput.text` and `_inputSecret`.
  Every path out of input mode (`_abandonPendingSelect`, `close`, a new
  `open`) clears `_inputSecret` and the field. `_emptyTitle` returns
  "" in input mode. Grep `DebugIpc.qml` and `MenuIpc.qml` for
  `searchInput.text` or `query` reads and make each report `""` while
  `_inputSecret`. `MenuIpc.input` keeps its two-argument contract and
  stays non-secret: secret input is internal only. Update the header
  comment at `MenuIpc.qml` that documents the file contract.
- `menu status` gains `empty`: `menu.emptyId`, a new readonly on
  `Menu.qml` returning `root._emptyNote ? root._emptyNote.id : ""`. Every
  route task asserts its unavailable row through it. It also gains
  `mode` (`menu._mode`: menu, select or input), which Task 6 reads to
  know the password step is up.
- Tests:
  - `tests/tst_menu_toggles.qml`: list path membership true and false,
    list path with a non-array snapshot, each new enum path, an unknown
    `path=value` false, `unknownKeys` quiet for the new keys.
  - `tests/tst_menu_search.qml`: a `localOnly` child is absent from a root
    rank, present when `withinId` is its parent, and a `localOnly`
    node's non-local sibling is found from root.
  - `tests/tst_menu_icons.qml`: every `ROUTE_ICON_PREFIXES` name exists
    in both icon sets (extend the existing `ROUTE_ICONS` loop), and
    `iconFor({id: "wifi.net.x"})` is `wifi`.
  - `tests/tst_menu_devices.qml` (new, Task 2 to 5 extend it):
    `idPart` round trip through `decodeURIComponent` for `a.b`, `a:b`,
    `a b`, `ü`, and no `.` in the output.
  - Find the test that covers `actions.js` hints (grep `hints(` under
    `tests/`; if none, add the cases to `tests/tst_menu_devices.qml`):
    Shift+Enter hint present with `alternateLabel`, absent when
    confirming, absent in input mode.
- Verify: `just test`, `just lint`. `dev/vm-lock.sh just vm-smoke --menu
  --lights --clipssh-image` still passes (ticks, the input step and the
  existing Shift+Enter case are the three things this task touches), PNGs
  read.

## Task 2: Wi-Fi route and WifiService (opus)

Mirror: `LightsService`'s `inputToken`/`resolveInput` for the password
step; the state machine is moved, not rewritten.

- `shell/Services/WifiService.qml` singleton (add to `qmldir`), bound to
  `Quickshell.Networking`:
  - Moved verbatim from `NetworkPanel.qml:755-936` with `root._x` renamed
    to public `x`: `actionSsid`, `actionKind`, `failureSsid`,
    `failureText`, `runAction`, `clearAction`, `checkActionCompletion`,
    `failAction`, `actionTimeout`, `enterpriseProc`, `connectEnterprise`.
    New public entry points with the panel's own rules:
    `activate(network)` (connected -> disconnect; secured and unknown, or
    its last failure was a secret one (`NoSecrets`, `WifiAuthTimeout`) ->
    returns `"needsSecret"` and does nothing, so a wrong password is
    retyped rather than retried; else connect),
    `connectPsk(network, psk)`, `forget(network)`,
    `findNetwork(ssid)`, `wifiNetworks()` (lifted from `NetworkIpc`).
  - Per-network `Connections` for `connectionFailed`, `connectedChanged`,
    `knownChanged`, `stateChangingChanged` move out of the panel delegate
    into an `Instantiator` over the wifi devices' networks here, so a
    connect started with the panel closed still settles.
  - `failAction` no longer opens the panel prompt itself; it emits
    `secretRequired(ssid)` on `NoSecrets`, and the panel's handler opens
    its inline prompt when it is open.
  - `connectedSsid` (the connected network's name or ""), `hasDevice`,
    `enabled` (`Networking.wifiEnabled`), `setEnabled(on)`.
  - Scanning: `holdScan(holder, on)` keeps a set of holder names and sets
    every wifi device's `scannerEnabled` to "set non-empty", reapplied when
    the device list changes. The panel holds `"panel"` while open (its
    `_applyScanner` goes), the launcher holds `"launcher"` while
    `isOpen && currentNodeId === "wifi"`.
  - Launcher password step: `passwordToken` (`"wifi-password"`),
    `identityToken` (`"wifi-identity"`), `_pendingSsid`,
    `_pendingIdentity`. `requestSecret(ssid)` stores the ssid and returns
    the prompt to open: identity first for an enterprise network.
    `resolveInput(token, value, cancelled)` returns one of `""` (not
    ours or cancelled), `"identity"` (open the password prompt next),
    `"submitted"` (connect started). Values never logged, `_pending*`
    cleared on every outcome.
- `NetworkPanel.qml`: renders `WifiService.actionSsid/actionKind/
  failureSsid/failureText`, calls `WifiService.activate/connectPsk/
  forget/connectEnterprise`, keeps `_passwordSsid/_passwordText/
  _identityText/_cursorSsid` and the QR and speed-test code. Its header
  comment's scanner paragraph now points at `WifiService`.
- `NetworkIpc.qml`: `connect/connectEap/forget` call the service
  directly and keep their error strings (busy, unknown ssid);
  `status()` unchanged in shape. Drop `panel` here and in `shell.qml:364`.
  Rewrite the header paragraph that explains routing through the panel:
  the reason (failure handling armed by the action) now lives in the
  service both paths share.
- `shell/Network/model.js` `failureText`: "Passphrase required", "Wrong
  password", "Network lost", "Connection failed"; `"Timed out"` and
  `"nmcli is not installed"` for the two literals the service sets.
  Update `tests/tst_network_model.qml`.
- `shell/Menu/providers.js` `wifiRows(state)`, pure, `state` =
  `{ hasDevice, enabled, networks: [{name, known, connected, secured,
  enterprise, signal}], actionSsid, actionKind, failureSsid, failureText }`:
  - No device: `wifi.unavailable` "No Wi-Fi device". Off: one action row
    `wifi.off` "Turn Wi-Fi on", `@ipc:wifi.enable`. On with no networks:
    `wifi.empty` "No networks found".
  - Else `NetworkModel.sortWifiRows` order, one row per network, id
    `wifi.net.<idPart(name)>`, label the SSID, `action
    "@ipc:wifi.activate:<name>"`, `checked "@state:wifi.ssid=<name>"`,
    `keepOpen: true`, `localOnly: !known`, `section` "Saved" for known
    and "Nearby" for the rest. `desc`, first that applies: the action in
    flight ("Connecting", "Disconnecting", "Forgetting"), the failure
    text for `failureSsid`, "Enterprise" for an unknown enterprise
    network, "Secured" for an unknown secured one, "" otherwise. Known
    rows carry `alternate "@ipc:wifi.forget:<name>"`, `alternateLabel
    "Forget"`. Hidden SSIDs (empty name) are skipped.
- `LiveMenuSources.qml`: `wifi` (the state object above), built from
  `WifiService` and its networks only while `active`, republished when
  the JSON of everything except `signal` changes. Signal only feeds the
  sort, so the sort runs on each republish and a strength tick alone does
  not republish.
- `Menu.qml`: register `wifi: function () { return
  Providers.wifiRows(liveSources.wifi); }`; `_dispatchInternal` handles
  `wifi.activate:<ssid>` (find the network; `"needsSecret"` opens
  `root.openInput("Password for " + ssid, WifiService.passwordToken, true)`
  or the identity prompt, deferred with `Qt.callLater` as `lights.colorInput`
  is), `wifi.forget:<ssid>`, `wifi.enable`. The `holdScan("launcher", ...)`
  binding. `shell.qml`'s `onSelectionResolved` adds
  `WifiService.resolveInput`: `"identity"` opens the secret password
  prompt, `"submitted"` calls `menuInstance.open("wifi")` in `Qt.callLater`.
- `shell/Menu/default-menu.jsonc`: `"wifi": { "label": "Wi-Fi",
  "provider": "wifi", "aliases": ["wifi", "wlan", "network", "ssid",
  "internet"], "prompt": "Search networks" }` after `keybinds`, with a
  header comment in the file's style.
- Tests (`tests/tst_menu_devices.qml`): each unavailable shape; order
  connected, saved, nearby; `localOnly` on nearby only; a dotted SSID
  `a.b` giving one row whose id has no second dot; the tick condition;
  forget only on saved rows; each `desc` case including a failure on one
  row not leaking to another; hidden SSID skipped.
  `tests/tst_menu_reachability.qml`: `wifi` is a root node with provider
  `wifi`.
- Verify: `just test`, `just lint`, `dev/vm-lock.sh just vm-smoke --wifi`
  (the existing leg, now through the service with no panel behind the
  IPC: it has to stay green, and `wifi-wrong.png` has to show "Wrong
  password" on the row), PNGs read.

## Task 3: Bluetooth route (sonnet)

Mirror: `BluetoothIpc.qml` for the device lookup and the no-adapter
error; `trayProvider` for the empty-row shape.

- `shell/Bluetooth/model.js`: `findByAddress(devices, address)`
  (case-insensitive, the indexed-loop copy `buckets` uses for QML
  sequences) and `connectedAddresses(devices)` (uppercase, sorted).
  `BluetoothIpc._findDevice` calls `findByAddress`.
- `shell/Menu/providers.js` `bluetoothRows(state)`, pure, `state` =
  `{ available, enabled, devices: [{address, name, connected, paired,
  bonded, trusted, activity, battery}] }` where `activity` is
  `BluetoothModel.activityText` and `battery` is `batteryText`:
  - No adapter: `bluetooth.unavailable` "No Bluetooth adapter". Off:
    `bluetooth.off` "Turn Bluetooth on", `@ipc:bluetooth.power:on`.
    No paired devices: `bluetooth.empty` "No paired devices".
  - Else `BluetoothModel.buckets(devices, false)` connected then known,
    id `bluetooth.dev.<idPart(address)>`, label the device name, `action
    "@ipc:bluetooth.toggle:<address>"`, `checked
    "@state:bluetooth.connected=<ADDRESS>"`, `keepOpen: true`, `desc`
    the activity text, else the battery, else "".
- `LiveMenuSources.qml`: `bluetooth` (state above) and
  `bluetoothConnected` (`connectedAddresses`), gated, key-guarded like
  `wifi`. Swap Task 1's `bluetoothConnected` placeholder in `Menu.qml`.
- `Menu.qml`: register `bluetooth`; `_dispatchInternal`
  `bluetooth.toggle:<address>` (connected -> `disconnect()`, else
  `connect()`, a miss does nothing) and `bluetooth.power:on`.
- `default-menu.jsonc`: `"bluetooth": { "label": "Bluetooth Devices",
  "provider": "bluetooth", "aliases": ["bt", "headphones", "earbuds",
  "speaker"], "prompt": "Search devices" }`. Check that root id
  `bluetooth` does not shadow `panels.bluetooth` in `_resolveRoute`
  (`menu summon bluetooth` must land on the route, `panel open bluetooth`
  still opens the panel).
- Tests: `tests/tst_bluetooth_model.qml` for both helpers (a QML-sequence
  shaped object with `length` and indices, mixed-case addresses);
  `tests/tst_menu_devices.qml` for the three unavailable shapes, order,
  unnamed devices dropped, `desc` precedence, tick condition;
  `tests/tst_menu_toggles.qml` a lowercase address in the snapshot still
  matches because `connectedAddresses` uppercases.
- Verify: `just test`, `just lint`, `dev/vm-lock.sh just vm-smoke --menu`
  PNG read. The VM has no adapter, so the route's live path is read on
  g815 by eye after a push, never by running the shell against its
  session.

## Task 4: Audio route (sonnet)

Mirror: `AudioPanel._makeDefault` for the switch, which moves into
`AudioService` so both call one function.

- `shell/Audio/model.js` `deviceRows(nodes)`: nodes with `audio` set and
  `isStream` false, as `{ name, label: description || name, isSink }`,
  outputs first, each half sorted by label. Pre-bind-safe fields only,
  same constraint as `isPlaybackStream`.
- `AudioService.qml`: `sinkName`, `sourceName` (the default nodes'
  `name` or ""), `setDefaultSink(name)`, `setDefaultSource(name)` (find
  in `Pipewire.nodes.values` by `name`, set `preferredDefaultAudioSink/
  Source`, return false on a miss). `AudioPanel._makeDefault` calls them.
- `shell/Menu/providers.js` `audioRows(devices)`:
  - None at all: `audio.unavailable` "No audio devices".
  - Outputs: id `audio.output.<idPart(name)>`, `section` "Output",
    `action "@ipc:audio.sink:<name>"`, `checked "@state:audio.sink=<name>"`.
    Inputs the same with `audio.input.`, "Input", `audio.source`. All
    `keepOpen: true`. No input devices with outputs present: nothing,
    not a note (the note would be dropped beside live rows anyway).
- `LiveMenuSources.qml`: `audioDevices`, gated, key-guarded on the
  `deviceRows` JSON.
- `Menu.qml`: register `audio`; dispatch `audio.sink:<name>`,
  `audio.source:<name>`.
- `default-menu.jsonc`: `"audio": { "label": "Audio Devices", "provider":
  "audio", "aliases": ["sound", "output", "input", "speakers",
  "microphone", "mic", "sink", "source"], "prompt": "Search devices" }`.
- Tests: `tests/tst_audio_model.qml` (streams and audio-less nodes out,
  label fallback, order); `tests/tst_menu_devices.qml` (sections, a
  dotted node name like `alsa_output.pci-0000_00_1f.3.analog-stereo`
  giving one row, both tick conditions, the unavailable row).
- Verify: `just test`, `just lint`, `dev/vm-lock.sh just vm-smoke --menu
  --osd` (the OSD reads `AudioService`; it must still show on a real
  `wpctl` change), PNGs read.

## Task 5: Radio route (sonnet)

Mirror: `NixSearchProvider.qml` and `nixTriggerQuery`/`nixRows`/the nix
note rows for the search; `RadioIpc.play` for the saved-station lookup.

- `shell/Surfaces/Menu/RadioSearchProvider.qml`: the nix provider's
  shape over `RadioService.search(q, done)` instead of a Process:
  500ms debounce, one request at a time, an answer kept only when it
  still answers the latest query, `rowsFor(q)` returning the searching,
  no-results and failed notes, or result rows. `results` holds the last
  station records for dispatch. Queries under 2 characters return [].
- `shell/Menu/providers.js`:
  - `radioTriggerQuery(text)`: `":r"` -> "", `":r <q>"` -> q, else null.
  - `radioRows(state)`, `state` = `{ favorites, running }`: `radio.stop`
    "Stop" (`@ipc:radio.stop`, only while running), then one
    row per favourite: id `radio.fav.<idPart(uuid)>`, label the name,
    `desc` country, `action "@ipc:radio.fav:<uuid>"`, `checked
    "@state:radio.station=<uuid>"`, `keepOpen: true`, `alternate
    "@ipc:radio.unfavorite:<uuid>"`, `alternateLabel "Remove favorite"`.
    No favourites: no rows, and the jsonc `radio.search` row below is
    what the level shows.
  - `radioResultRows(results, favoriteSet)`: id `radio.result.<idPart(uuid)>`,
    label name, `desc` country and codec joined with a space, `action
    "@ipc:radio.play:<uuid>"`, the same tick, `localOnly: true`,
    `alternate` favourite or unfavourite by `favoriteSet`, labels "Add
    favorite" and "Remove favorite". Result rows close the launcher on
    Enter: a stream starting is the answer, and the list is a one-off
    search, not a set to flip through. `_radioNoteRow` ids
    `radio.searching` "Searching", `radio.noresults` "No results",
    `radio.failed` "Search failed".
- `Menu.qml`:
  - `RadioSearchProvider { id: radioSearch }`. In `_resolve`, `routeRows`
    also covers `level === "radio.search"`; `_levelRows` returns
    `radioSearch.rowsFor(...)` for that level or a `:r` query, ahead of
    the `q.length === 0` branch and after the keybinds one; the
    `searching` flag excludes a `:r` query as it does `:nix`. `query()`
    (the debug verb) gets the same `:r` branch as `:k`. The search field's
    `onTextChanged` calls `radioSearch.requestSearch` for the level or the
    trigger, next to the nix call.
  - `_dispatchInternal`: `radio.fav:<uuid>` (`playFromSaved(station,
    RadioService.favorites)`), `radio.play:<uuid>` (`play(station,
    radioSearch.results)`), `radio.favorite:<uuid>` and
    `radio.unfavorite:<uuid>` (`toggleFavorite(station)` when the state
    differs, the station looked up in favourites then results),
    `radio.stop`.
- `LiveMenuSources.qml`: `radio` (`{ favorites: RadioService.favorites,
  running: RadioService.running }`), gated.
- `default-menu.jsonc`: `"radio": { "label": "Radio Stations",
  "provider": "radio", "aliases": ["stations", "fm", "stream"], "prompt":
  "Search favorites" }`, `"radio.search": { "label": "Search Stations",
  "provider": "radioSearch", "prompt": "Search Radio Browser" }`.
  `radio.search` has no registered fn, so it stays a listed provider node
  while childless and `menu summon radio.search` enters it; declaring it
  here lets a user `menu.jsonc` hide it. Header comment naming the `:r`
  trigger.
- Tests (`tests/tst_menu_devices.qml`): trigger parsing (`:r`, `:r jazz`,
  `:radio` is not the trigger, `:rx` is not); favourite rows, ticks,
  alternates; stop only while running; result rows `localOnly` with the
  right alternate label per favourite set. `tests/tst_menu_reachability.qml`:
  the four route ids exist at root with their provider names, and a root
  rank for a favourite's name finds it while a result row's does not.
- Verify: `just test`, `just lint`, `dev/vm-lock.sh just vm-smoke --radio`
  (the radio leg is untouched and must stay green), PNGs read.

## Task 6: smoke leg and docs (sonnet)

- `dev/smoke.d/device_routes.sh` `--device-routes`, order 217 (after
  lights), needs `wtype pactl ffmpeg mpv`. `leg_device_routes_validate`
  refuses `--wifi` and `--radio` in the same run: all three change the
  same radios, the same `radio-atlas.json` and the default sink.
  `need_pactl` as `radio.sh` defines it (copy it; two legs, two copies,
  until a third wants it). Everything strictly ordered, one drive
  script, each poll writing over its own path.
  - Fixture: a favourite in `radio-atlas.json` pointing at an ffmpeg
    loopback listener on port 18100 (radio.sh's fixture shape, its own
    id `routes-radio-1` and name `FormalShell Routes Radio`).
  - Wi-Fi: poll `network status` until both FORMALTEST SSIDs are
    scanned (wifi.sh's self-heal loop, copied). `menu summon wifi`,
    `menu filter FORMALTEST`, read `menu status` for the row's index and
    id (`wifi.net.FORMALTEST` in `cells`), `menu activate <index>`.
    Assert `menu status` `mode` is `input`. Type `wrong-formaltest-psk` with
    `wtype`, `wtype -k Return`, poll `network status` until FORMALTEST
    settles disconnected; grim the reopened launcher (the row reading
    "Wrong password"). Enter again, type `formaltest-psk`, Return, poll
    until `connected:true`; `debug query FORMALTEST` from root has the
    row with `checked:true`; `debug query FORMALTEST-EAP` does not
    contain `wifi.net.FORMALTEST-EAP` (nearby rows are local). Grim the
    password field mid-typing once and read it: bullets, no text. Then
    `menu summon wifi`, filter, `menu activateAlternate <index>`, poll
    `known:false`.
  - Secret: after both password rounds, `menu-selection.txt` has no
    `formaltest` in it, and neither does `$shell_log_path`.
  - Audio: `pactl load-module module-null-sink sink_name=formalshell-routes
    sink_properties=device.description=RoutesSink`. Confirm by hand in the
    VM (`dev/vm.sh run pactl list short sources`) which command creates a
    real PipeWire source node before wiring the input half; if none does
    on this rig, assert the output half only and say so in the leg's
    header. `menu summon audio`, filter `RoutesSink`, activate, poll
    `pactl get-default-sink` for `formalshell-routes`; `debug query
    RoutesSink` row `checked:true`; `debug query 'Virtual Sink'` row
    `checked:false`. Unload the module in `add_cleanup`.
  - Bluetooth: `menu summon bluetooth`, `menu status` `empty` is
    `bluetooth.unavailable` and `rows` is 0. Grim it.
  - Radio: `menu summon radio`, filter `Routes Radio`, activate, poll
    `radio status` until `station` is the fixture name and `running`;
    `debug query 'Routes Radio'` `checked:true`. `menu activateAlternate`
    on the same row, `radio status` `favorites` 0. `debug query ':r jazz'`
    polled up to 20s until it no longer holds `radio.searching`: either
    result rows or `radio.failed` passes (the VM's route to Radio Browser
    is not guaranteed), a row stuck on searching fails. `radio stop`.
  - Every JSON read printed as `SMOKE_DEVICE_ROUTES_<NAME> <path>` and
    every frame as its own `SMOKE_` line.
- `CLAUDE.md`: the leg's entry in the alphabetical list, in the house
  style: what each part proves, not how.
- `docs/DESIGN.md` §5 **Launcher**: one sentence naming the owner rule
  (pick from a list in the launcher, watch live state in a panel), so the
  next route or panel has it written down.
- Verify: `dev/vm-lock.sh just vm-smoke --device-routes`, then
  `dev/vm-lock.sh just vm-smoke --device-routes --pantheon` (the tick,
  the Shift+Enter hint and the masked field under the other habit set),
  every PNG in `artifacts/` read, `just test`, `just lint`.
