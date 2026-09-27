pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Core as Core
import "../Overnight/model.js" as Overnight

// Overnight: the machine left compiling while its owner sleeps. Screens to
// 1%, every LED the shell may touch off, fans down to the Balanced tier. The
// tier is Balanced rather than power-saver on purpose: under tuned-ppd,
// power-saver maps to TuneD's `powersave` profile, which also pins the
// CPU's energy_performance_preference to `power` and drags a long build out
// far more than the fans it quiets. On an ASUS laptop Balanced is asus-wmi's
// `balanced` platform profile, which is the fan curve as well as the TDP.
// A profile already below Performance is left where it is.
//
// Everything changed is recorded in Core.State.overnight before or as it
// lands, so disable() restores it even after a shell restart. The record's
// shape: { profile, backlight, ddc: { connector: percent }, leds: { name:
// brightness }, aura }. backlight is -1 when there was no backlight to dim.
//
// DDC monitors are async: ddcutil's detect takes seconds, so enable() and
// disable() each open a window during which every DDC row BrightnessService
// appends is dimmed or restored. Aura needs asusctl on PATH (it ships with
// asusd, never with the shell); with none, `aura` stays false and nothing
// is restored there.
Singleton {
    id: root

    readonly property bool active: Core.State.overnight !== null && Core.State.overnight !== undefined

    // "dim", "restore" or "" while no DDC window is open.
    property string _ddcMode: ""
    property var _ddcRestore: ({})

    function toggle() {
        if (root.active)
            root.disable();
        else
            root.enable();
    }

    function enable() {
        if (root.active)
            return;
        const profile = PowerProfiles.profile;
        Core.State.setOvernight({
            profile: profile,
            backlight: BrightnessService.available ? BrightnessService.percent : -1,
            ddc: {},
            leds: {},
            aura: false
        });
        if (profile === PowerProfile.Performance)
            PowerProfiles.profile = PowerProfile.Balanced;
        if (BrightnessService.available)
            BrightnessService.set(Overnight.SCREEN_PERCENT);
        root._openDdcWindow("dim");
        ledListProc.running = true;
        auraOffProc.running = true;
    }

    function disable() {
        if (!root.active)
            return;
        const snap = Core.State.overnight;
        Core.State.setOvernight(null);
        if (snap.profile !== undefined && PowerProfiles.profile !== snap.profile)
            PowerProfiles.profile = snap.profile;
        if (snap.backlight >= 0) {
            if (BrightnessService.available)
                BrightnessService.set(snap.backlight);
            else
                root._pendingBacklight = snap.backlight;
        }
        root._ddcRestore = snap.ddc || {};
        if (Object.keys(root._ddcRestore).length > 0)
            root._openDdcWindow("restore");
        else
            root._closeDdcWindow();
        root._pendingLeds = Overnight.restoreArgs(snap.leds);
        if (snap.aura)
            auraOnProc.running = true;
        else
            root._restoreLeds();
    }

    property var _pendingLeds: []
    // Set when disable() lands before BrightnessService's first device list
    // does, which is the case right after a shell restart.
    property int _pendingBacklight: -1

    Connections {
        target: BrightnessService
        enabled: root._pendingBacklight >= 0
        function onAvailableChanged() {
            if (!BrightnessService.available)
                return;
            BrightnessService.set(root._pendingBacklight);
            root._pendingBacklight = -1;
        }
    }

    function _restoreLeds() {
        if (root._pendingLeds.length === 0)
            return;
        ledRestoreProc.command = ["sh", "-c", "while [ $# -ge 2 ]; do brightnessctl -q -d \"$1\" set \"$2\"; shift 2; done", "sh"].concat(root._pendingLeds);
        root._pendingLeds = [];
        ledRestoreProc.running = true;
    }

    // Merges one key into the stored record. State's JsonAdapter only
    // notices assignment, so the object is rebuilt rather than mutated.
    function _record(key, value) {
        const current = Core.State.overnight;
        if (current === null || current === undefined)
            return;
        const next = Object.assign({}, current);
        next[key] = value;
        Core.State.setOvernight(next);
    }

    function _openDdcWindow(mode) {
        root._ddcMode = mode;
        ddcWindow.restart();
        for (let i = 0; i < BrightnessService.devices.count; i++)
            root._onDdcRow(i);
        BrightnessService.refreshDevices();
    }

    function _closeDdcWindow() {
        root._ddcMode = "";
        root._ddcRestore = {};
        ddcWindow.stop();
    }

    function _onDdcRow(index) {
        const row = BrightnessService.devices.get(index);
        if (!row || row.deviceId === "backlight")
            return;
        if (root._ddcMode === "dim" && root.active) {
            const ddc = Core.State.overnight.ddc || {};
            // A row BrightnessService re-reads after this window already
            // dimmed it reports 1%; the first reading is the one to keep.
            if (ddc[row.deviceId] === undefined && row.percent > Overnight.SCREEN_PERCENT) {
                const next = Object.assign({}, ddc);
                next[row.deviceId] = row.percent;
                root._record("ddc", next);
                BrightnessService.setDevicePercent(row.deviceId, Overnight.SCREEN_PERCENT);
            }
        } else if (root._ddcMode === "restore" && root._ddcRestore[row.deviceId] !== undefined) {
            BrightnessService.setDevicePercent(row.deviceId, root._ddcRestore[row.deviceId]);
        }
    }

    Connections {
        target: BrightnessService.devices
        enabled: root._ddcMode !== ""
        function onRowsInserted(parent, first, last) {
            for (let i = first; i <= last; i++)
                root._onDdcRow(i);
        }
    }

    // Long enough for ddcutil to detect and read every bus on a desk with a
    // few monitors; BrightnessService queues the reads one bus at a time.
    Timer {
        id: ddcWindow
        interval: 30000
        onTriggered: root._closeDdcWindow()
    }

    Process {
        id: ledListProc
        command: ["sh", "-c", "for d in /sys/class/leds/*; do printf '%s\\t%s\\t%s\\n' \"${d##*/}\" \"$(cat \"$d/trigger\" 2>/dev/null)\" \"$(cat \"$d/brightness\" 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const leds = Overnight.parseLeds(text);
                if (leds.length === 0 || !root.active)
                    return;
                root._record("leds", Overnight.ledSnapshot(leds));
                ledOffProc.command = ["sh", "-c", "for n; do brightnessctl -q -d \"$n\" set 0; done", "sh"].concat(leds.map(l => l.name));
                ledOffProc.running = true;
            }
        }
    }

    Process {
        id: ledOffProc
    }

    Process {
        id: ledRestoreProc
    }

    // `asusctl aura power <zone>` with no flags clears every power state for
    // that zone, which is off. Exit 3 is this script's own "no asusctl".
    Process {
        id: auraOffProc
        command: ["sh", "-c", "command -v asusctl >/dev/null || exit 3; for z; do asusctl aura power \"$z\" >/dev/null 2>&1; done; exit 0", "sh"].concat(Overnight.AURA_ZONES)
        onExited: exitCode => {
            if (exitCode === 0)
                root._record("aura", true);
        }
    }

    // The states the host's asus-aura unit sets at boot (sleep left off, so
    // the zones stay dark while suspended).
    Process {
        id: auraOnProc
        command: ["sh", "-c", "for z; do asusctl aura power \"$z\" --boot --awake --shutdown >/dev/null 2>&1; done; exit 0", "sh"].concat(Overnight.AURA_ZONES)
        onRunningChanged: {
            if (!auraOnProc.running)
                root._restoreLeds();
        }
    }
}
