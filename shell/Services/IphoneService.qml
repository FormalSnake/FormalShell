pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
// `qs.Core as Core`: QtQuick exports its own `State`, see
// NotificationService.qml's note on the same collision.
import qs.Core as Core
import qs.Notifications
import "../Iphone/model.js" as IphoneModel
import "../Core/proc.js" as Proc

// Portions from omarchy-iphone (MIT, Copyright (c) 2026 kbbahaPro)

// The iPhone over ANCS (M75 Task 2, plan at
// docs/superpowers/plans/2026-09-28-m75-iphone.md). ancs4linux's observer
// daemon runs as root on the system bus and holds the BLE link;
// `omarchy-iphone-bridge listen` turns its signals into JSONL on stdout,
// and this owns one long-lived child of it, restarted with backoff.
//
// No bridge on PATH is `installed: false`; a bridge whose daemon does not
// own its bus name is `available: false`. Neither fakes a phone.
//
// Mirrored notifications go through NotificationService.notifyPhone(),
// which owns the dedupe against local clients; the Focus verdict, the block
// list and the one-time-code copy are decided here first.
Singleton {
    id: root

    // Waits for settings.json, so a session with the key off never starts
    // the bridge in the moment before the file lands.
    readonly property bool enabled: Core.Config.loaded && Core.Config.get("iphone.enable", true) === true
    readonly property bool _mirror: Core.Config.get("iphone.notifications.enable", true) === true
    readonly property string _focusMode: String(Core.Config.get("iphone.notifications.focus", "respect"))
    readonly property bool _syncDndEnabled: Core.Config.get("iphone.notifications.syncDnd", false) === true
    readonly property real _focusWindow: {
        var n = Number(Core.Config.get("iphone.notifications.focusWindow", IphoneModel.DEFAULT_FOCUS_WINDOW));
        return isFinite(n) && n > 0 ? n : IphoneModel.DEFAULT_FOCUS_WINDOW;
    }
    readonly property var _block: Core.Config.get("iphone.notifications.block", [])
    readonly property bool _copyCodes: Core.Config.get("iphone.copyCodes", false) === true

    readonly property int _historyLimit: 200
    readonly property string _bridge: "omarchy-iphone-bridge"

    // --- state -------------------------------------------------------------

    property bool installed: false
    property bool bridgeRunning: false
    property bool observer: false
    readonly property bool available: root.enabled && root.bridgeRunning && root.observer
    property bool connected: false
    property string deviceName: ""
    // ancs4linux's device handle, the phone's BlueZ object path. Only
    // notifications carry it, so it is "" until the first one arrives.
    property string deviceHandle: ""
    // BlueZ's Battery1 percentage as the bridge polls it, -1 unknown.
    property int _bridgeBattery: -1
    // The connection the newest notification belongs to; ids from an
    // earlier one can no longer be acted on.
    property int session: 0

    readonly property var device: IphoneModel.matchDevice(
        Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices.values : [], root.deviceHandle, root.deviceName)
    // 0..1, like every other Quickshell fraction. The matched Bluetooth
    // device first; the bridge's own poll of the same BlueZ interface when
    // no device matched yet.
    readonly property bool batteryAvailable: root.connected
        && ((root.device !== null && root.device.batteryAvailable) || root._bridgeBattery >= 0)
    readonly property real battery: !root.batteryAvailable ? 0
        : (root.device !== null && root.device.batteryAvailable) ? root.device.battery
        : root._bridgeBattery / 100

    // Newest first, the bridge's own record per notification (Iphone/model.js
    // parseEvent), including ones the Focus verdict kept out of the
    // notification centre. Blocked apps never land here.
    property var recent: []
    property int unread: 0
    property string pairingCode: ""
    property bool advertising: false
    property string lastError: ""

    // ancs4linux renames the whole adapter to the pairing name and keeps it
    // discoverable until DisableAdvertising, so the session is ended here:
    // once the phone is paired, or when BlueZ's default DiscoverableTimeout
    // (180s) has already hidden the classic side anyway.
    property string _hostname: ""
    property string _advertisingHci: ""
    readonly property bool _pairDone: root.advertising && root.device !== null && root.device.paired

    property var _arrivals: []
    property double _now: Date.now()
    readonly property bool inFocus: IphoneModel.inFocus(root._arrivals, root._now, root._focusWindow)

    // --- now-playing (Apple Media Service, M75 Task 4) --------------------
    //
    // A second GATT client, `omarchy-iphone-ams listen`, owned only while a
    // phone is actually connected: it rides the same BLE link ANCS does but
    // is its own process with its own subscribe handshake. `mediaAvailable`
    // is AMS's own signal that the phone's entity-update characteristic
    // exists at all, never guessed from whether a title has arrived yet.
    property bool amsInstalled: false
    property bool mediaAvailable: false
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaAlbum: ""
    property real mediaDuration: 0
    // "playing"/"paused"/"rewinding"/"forwarding"/"" (nothing reported yet).
    property string mediaPlayback: ""
    // -1 unknown; AMS reports the player's own 0..1 volume, not a step size,
    // so `MediaService.setVolume` can only ever pick a direction (Task 4).
    property real mediaVolume: -1
    // iTunes' cover for the track (IphoneModel.pickArtwork), "" until one
    // is found or when none matches; looked up once per track per session.
    property string mediaArtUrl: ""
    property var _artCache: ({})
    property int _artSerial: 0
    readonly property string _artKey: root.mediaTitle !== "" && root.mediaArtist !== ""
        ? root.mediaArtist + "\n" + root.mediaTitle + "\n" + root.mediaAlbum : ""

    on_ArtKeyChanged: {
        root._artSerial++;
        if (root._artKey === "" || root._artKey in root._artCache) {
            root.mediaArtUrl = root._artKey === "" ? "" : root._artCache[root._artKey];
            return;
        }
        root.mediaArtUrl = "";
        var serial = root._artSerial;
        var key = root._artKey;
        var artist = root.mediaArtist;
        var album = root.mediaAlbum;
        var proc = artProc.createObject(root, { command: ["curl", "-sS", "--fail", "--max-time", "5",
            IphoneModel.artworkSearchUrl(artist, root.mediaTitle)] });
        proc.done.connect(body => {
            var url = IphoneModel.pickArtwork(body, artist, album);
            var cache = root._artCache;
            cache[key] = url;
            root._artCache = cache;
            if (serial === root._artSerial)
                root.mediaArtUrl = url;
            proc.destroy();
        });
        proc.running = true;
    }

    Component {
        id: artProc
        Process {
            signal done(string body)
            stdout: StdioCollector {
                id: artCollector
            }
            onExited: exitCode => done(exitCode === 0 ? artCollector.text : "")
        }
    }

    // AMS pushes `elapsed` only on a playback-info change (a rate/track
    // change), the same "position doesn't tick" contract MPRIS documents
    // (MediaService.qml's header note), so this extrapolates forward from
    // the last real reading rather than fabricating a continuous one.
    property real _mediaElapsedBase: 0
    property double _mediaElapsedAt: 0
    property double _mediaTick: Date.now()
    readonly property real mediaPosition: root.mediaPlayback === "playing"
        ? Math.min(root.mediaDuration > 0 ? root.mediaDuration : Infinity,
            root._mediaElapsedBase + (root._mediaTick - root._mediaElapsedAt) / 1000)
        : root._mediaElapsedBase

    Timer {
        interval: 1000
        repeat: true
        running: root.mediaPlayback === "playing"
        onTriggered: root.refreshPosition()
    }

    // MediaService.refreshPosition's half for the phone: the lyrics wipe and
    // the tempo visualizer call it every frame, the Timer above covers the
    // progress row.
    function refreshPosition() {
        root._mediaTick = Date.now();
    }

    signal codeCopied(string code)

    // --- public verbs --------------------------------------------------------

    function _find(id) {
        for (var i = 0; i < root.recent.length; i++)
            if (root.recent[i].id === id)
                return root.recent[i];
        return null;
    }

    // Act on a notification on the phone: `positive` is its positive action
    // (Answer, Reply), false its negative one (Clear, Decline). Answers
    // whether the action was queued.
    function invoke(id, positive) {
        return root._invokeRecord(root._find(Number(id)), positive === true);
    }

    // Clear on the phone and here. The phone's own dismiss that follows
    // finds nothing left to remove.
    function dismiss(id) {
        var entry = root._find(Number(id));
        if (!entry)
            return false;
        root.recent = IphoneModel.removeById(root.recent, entry.id);
        NotificationService.dropPhone(entry.id);
        return entry.negativeAction === "" ? true : root._invokeRecord(entry, false);
    }

    function clear() {
        root.recent.forEach(function (entry) {
            if (entry.negativeAction !== "")
                root._invokeRecord(entry, false);
            NotificationService.dropPhone(entry.id);
        });
        root.recent = [];
        root.unread = 0;
        root._runOnce(["clear"]);
    }

    function markRead() {
        root.unread = 0;
    }

    // A second EnableAdvertising on an advertising adapter tears the advert
    // down before raising it again, which drops it off the phone's list.
    function pair() {
        if (!root.installed)
            return false;
        if (root.advertising || pairProc.running)
            return true;
        root.lastError = "";
        root.pairingCode = "";
        pairProc.command = [root._bridge, "pair", "--name", root._hostname !== "" ? root._hostname : "FormalShell"];
        pairProc.running = true;
        return true;
    }

    // ancs4linux's agent confirms the code on its own, so a paired device is
    // the only signal the phone side accepted. Trusted, or BlueZ asks the
    // agent to authorize every profile on reconnect and ancs4linux's rejects.
    function _finishPairing() {
        if (!root.device.trusted)
            root.device.trusted = true;
        root._endPairing();
    }

    function _endPairing() {
        pairTimer.stop();
        if (root._advertisingHci !== "") {
            unadvertiseProc.command = ["busctl", "call", "--system", "ancs4linux.Advertising", "/",
                "ancs4linux.Advertising", "DisableAdvertising", "s", root._advertisingHci];
            unadvertiseProc.running = true;
        }
        root._advertisingHci = "";
        root.advertising = false;
        root.pairingCode = "";
    }

    on_PairDoneChanged: {
        if (root._pairDone)
            root._finishPairing();
    }

    // One AMS transport command (play/pause/toggle/next/prev/volup/voldown).
    // One in flight at a time: a slider drag or a held key can fire several
    // of these a second, and AMS answers over the same BLE write either way,
    // so queuing would only ever lag behind what the phone is doing now.
    function mediaCommand(name) {
        if (!root.amsInstalled || amsCommandProc.running)
            return false;
        amsCommandProc.command = [root._ams, "command", name];
        amsCommandProc.running = true;
        return true;
    }

    // --- incoming --------------------------------------------------------------

    function _onLine(line) {
        var event = IphoneModel.parseEvent(line);
        if (!event)
            return;
        switch (event.type) {
        case "history":
            var items = event.items.filter(e => !IphoneModel.isBlocked(e, root._block));
            items.sort((a, b) => b.ts - a.ts);
            root.recent = items.slice(0, root._historyLimit);
            break;
        case "status":
            root._backoffMs = root._baseBackoffMs;
            root.observer = event.observer;
            root.connected = event.connected;
            root.deviceName = event.deviceName;
            root._bridgeBattery = event.battery;
            if (event.observer)
                root.lastError = "";
            break;
        case "notification":
            root._receive(event);
            break;
        case "dismiss":
            root.recent = IphoneModel.removeById(root.recent, event.id);
            NotificationService.dropPhone(event.id);
            break;
        case "pairingCode":
            root.pairingCode = event.code;
            break;
        case "advertising":
            root._advertisingHci = event.hci;
            root.advertising = true;
            pairTimer.restart();
            break;
        case "error":
            root.lastError = event.message;
            break;
        }
    }

    function _onAmsLine(line) {
        var event = IphoneModel.parseAmsLine(line);
        if (!event)
            return;
        switch (event.type) {
        case "status":
            root.mediaAvailable = event.available;
            if (event.available) {
                root._amsBackoffMs = root._baseBackoffMs;
                if (root._amsError !== "" && root.lastError === root._amsError)
                    root.lastError = "";
                root._amsError = "";
            } else {
                root.mediaTitle = "";
                root.mediaArtist = "";
                root.mediaAlbum = "";
                root.mediaDuration = 0;
                root.mediaPlayback = "";
                root.mediaVolume = -1;
            }
            break;
        case "nowplaying":
            root.mediaTitle = event.title;
            root.mediaArtist = event.artist;
            root.mediaAlbum = event.album;
            root.mediaDuration = event.duration;
            root.mediaPlayback = event.playback;
            if (event.volume >= 0)
                root.mediaVolume = event.volume;
            root._mediaElapsedBase = event.elapsed;
            root._mediaElapsedAt = Date.now();
            root._mediaTick = root._mediaElapsedAt;
            break;
        case "error":
            root.lastError = event.message;
            root._amsError = event.message;
            break;
        }
    }

    function _receive(entry) {
        if (IphoneModel.isBlocked(entry, root._block))
            return;
        if (entry.deviceHandle !== "")
            root.deviceHandle = entry.deviceHandle;
        if (entry.session !== 0)
            root.session = entry.session;
        var known = root._find(entry.id) !== null;
        root.recent = IphoneModel.upsert(root.recent, entry, root._historyLimit);
        if (!known && IphoneModel.focusVerdict(entry, root._focusMode) !== "drop")
            root.unread += 1;

        if (!entry.preexisting && !known) {
            root._now = Date.now();
            var horizon = root._now - root._focusWindow * 1000;
            root._arrivals = root._arrivals.filter(a => a.at >= horizon)
                .concat([{ at: root._now, silent: entry.silent }]);
            if (root._copyCodes)
                root._copyCode(IphoneModel.extractCode(entry.title + " " + entry.body));
        }

        var verdict = IphoneModel.route(entry, {
            enable: root._mirror,
            block: root._block,
            focus: root._focusMode
        });
        if (verdict === "drop")
            return;
        var mirrored = IphoneModel.toNotification(entry);
        var actions = mirrored.actions.map(a => ({
            key: a.key,
            label: a.label,
            invoke: () => root.invoke(entry.id, a.key === "positive")
        }));
        NotificationService.notifyPhone(mirrored, actions, verdict === "quiet");
    }

    property string _lastCode: ""

    function _copyCode(code) {
        if (code === "" || code === root._lastCode)
            return;
        root._lastCode = code;
        copyProc.command = ["wl-copy", "--", code];
        copyProc.running = true;
        root.codeCopied(code);
    }

    Process {
        id: copyProc
    }

    Connections {
        target: NotificationService
        function onPhoneDismissed(phone) {
            root.recent = IphoneModel.removeById(root.recent, phone.id);
            if (phone.negativeAction !== "")
                root._invokeRecord(phone, false);
        }
    }

    // --- Focus and DND -----------------------------------------------------------

    // Re-reads the window's edge: a silent arrival ageing out of it ends the
    // Focus reading with no event to say so.
    Timer {
        interval: 15000
        repeat: true
        running: root._arrivals.length > 0
        onTriggered: {
            root._now = Date.now();
            var horizon = root._now - root._focusWindow * 1000;
            var kept = root._arrivals.filter(a => a.at >= horizon);
            if (kept.length !== root._arrivals.length)
                root._arrivals = kept;
        }
    }

    property var _dndStep: ({ owned: false, focus: false })

    function _syncDnd() {
        var next = IphoneModel.syncDndStep(root._dndStep, root.inFocus, Core.State.dnd, root._syncDndEnabled);
        // Stored before the write: setDnd() lands back here through
        // onDndChanged, which has to see this step already taken.
        root._dndStep = { owned: next.owned, focus: next.focus };
        if (next.set !== null)
            Core.State.setDnd(next.set);
    }

    onInFocusChanged: root._syncDnd()
    on_SyncDndEnabledChanged: root._syncDnd()

    Connections {
        target: Core.State
        function onDndChanged() { root._syncDnd(); }
    }

    // --- outgoing actions ----------------------------------------------------------

    // One action Process at a time: re-running a Process that is still
    // running is a no-op, so a burst (clear()) would send the first action
    // and drop the rest.
    property var _actionQueue: []

    function _invokeRecord(entry, positive) {
        if (!entry || !root.installed)
            return false;
        if (!IphoneModel.isActionable(entry, root.session)) {
            root.lastError = "The phone reconnected since this arrived, so it can no longer be acted on";
            return false;
        }
        root._actionQueue = root._actionQueue.concat([[root._bridge, "invoke",
            "--handle", String(entry.deviceHandle),
            "--id", String(entry.id),
            "--kind", positive ? "positive" : "negative"]]);
        root._pumpActions();
        return true;
    }

    function _pumpActions() {
        if (actionProc.running || root._actionQueue.length === 0)
            return;
        actionProc.command = root._actionQueue[0];
        root._actionQueue = root._actionQueue.slice(1);
        actionProc.running = true;
    }

    function _runOnce(args) {
        if (!root.installed)
            return;
        onceProc.command = [root._bridge].concat(args);
        onceProc.running = true;
    }

    Process {
        id: actionProc
        stdout: SplitParser {
            onRead: line => root._onLine(line)
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.lastError === "")
                root.lastError = "The phone did not take that action";
            root._pumpActions();
        }
    }

    Process {
        id: onceProc
    }

    Process {
        id: pairProc
        stdout: SplitParser {
            onRead: line => root._onLine(line)
        }
    }

    Process {
        id: unadvertiseProc
    }

    Timer {
        id: pairTimer
        interval: 180000
        onTriggered: root._endPairing()
    }

    Process {
        id: hostnameProc
        command: ["hostname"]
        stdout: StdioCollector {
            onStreamFinished: root._hostname = text.trim()
        }
    }

    // --- the bridge ------------------------------------------------------------------

    readonly property int _baseBackoffMs: 2000
    readonly property int _maxBackoffMs: 60000
    property int _backoffMs: root._baseBackoffMs

    // 127 from the probe is "no bridge on PATH", the one exit that means
    // installed: false rather than a bridge that started and died.
    Process {
        id: bridgeProc
        command: Proc.dieWithParent(["sh", "-c",
            'command -v "$0" >/dev/null 2>&1 || exit 127; exec "$0" listen --limit "$1"',
            root._bridge, String(root._historyLimit)])
        stdout: SplitParser {
            onRead: line => {
                root.installed = true;
                root._onLine(line);
            }
        }
        stderr: SplitParser {
            onRead: line => {
                var text = String(line || "").trim();
                if (text !== "")
                    root.lastError = text;
            }
        }
        onRunningChanged: root.bridgeRunning = bridgeProc.running
        onExited: exitCode => {
            root.installed = exitCode !== 127;
            root.observer = false;
            root.connected = false;
            if (root.enabled)
                retryTimer.start();
        }
    }

    Timer {
        id: retryTimer
        interval: root._backoffMs
        onTriggered: {
            root._backoffMs = Math.min(root._maxBackoffMs, root._backoffMs * 2);
            if (root.enabled)
                bridgeProc.running = true;
        }
    }

    function _applyEnabled() {
        if (root.enabled) {
            if (!bridgeProc.running && !retryTimer.running)
                bridgeProc.running = true;
            root._applyAms();
            return;
        }
        retryTimer.stop();
        bridgeProc.running = false;
        root._actionQueue = [];
        root._applyAms();
    }

    onEnabledChanged: root._applyEnabled()
    onConnectedChanged: root._applyAms()
    Component.onCompleted: {
        hostnameProc.running = true;
        root._applyEnabled();
    }

    // --- Apple Media Service (M75 Task 4) ---------------------------------

    readonly property string _ams: "omarchy-iphone-ams"
    property int _amsBackoffMs: root._baseBackoffMs
    property string _amsError: ""

    Process {
        id: amsProc
        command: Proc.dieWithParent(["sh", "-c",
            'command -v "$0" >/dev/null 2>&1 || exit 127; exec "$0" listen',
            root._ams])
        stdout: SplitParser {
            onRead: line => {
                root.amsInstalled = true;
                root._onAmsLine(line);
            }
        }
        onExited: exitCode => {
            root.amsInstalled = exitCode !== 127;
            root.mediaAvailable = false;
            if (root.enabled && root.connected)
                amsRetryTimer.start();
        }
    }

    Timer {
        id: amsRetryTimer
        interval: root._amsBackoffMs
        onTriggered: {
            root._amsBackoffMs = Math.min(root._maxBackoffMs, root._amsBackoffMs * 2);
            if (root.enabled && root.connected)
                amsProc.running = true;
        }
    }

    Process {
        id: amsCommandProc
        stdout: SplitParser {
            onRead: line => root._onAmsLine(line)
        }
    }

    // Owned exactly while a phone is connected: AMS is a second GATT client
    // against whichever iPhone BlueZ currently holds, so there is nothing
    // for it to subscribe to before ANCS itself reports a connection.
    function _applyAms() {
        if (root.enabled && root.connected) {
            root._amsBackoffMs = root._baseBackoffMs;
            if (!amsProc.running && !amsRetryTimer.running)
                amsProc.running = true;
            return;
        }
        amsRetryTimer.stop();
        amsProc.running = false;
        root.mediaAvailable = false;
        root.mediaTitle = "";
        root.mediaArtist = "";
        root.mediaAlbum = "";
        root.mediaDuration = 0;
        root.mediaPlayback = "";
        root.mediaVolume = -1;
    }
}
