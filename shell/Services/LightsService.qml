pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "../Lights/model.js" as Model

// Keyboard RGB. The one backend is asusd: state is read off its Aura object
// over busctl (LedMode, LedModeData, Brightness, SupportedBasicModes) and
// written through asusctl, which is what asusd's own CLI does. asusd keeps
// the effect across reboots itself, so the effect, colour and brightness
// here are always what the last probe read back; only the colour source,
// the custom colour and the toggle's restore level live in Core.State.lights.
//
// `source: "wallpaper"` repaints a colour-taking effect with the theme's
// primary each time the palette changes; picking a colour switches it to
// "custom". Effects with no colour (the rainbows, rain) ignore both.
//
// No asusctl, or no Aura object on the bus, leaves `available` false and
// every setter a no-op; the launcher route is absent then.
Singleton {
    id: root

    property bool available: false
    property string effect: ""
    property string colour: ""
    property string speed: "med"
    property int brightness: -1
    property var effects: []
    property string lastError: ""

    readonly property bool on: root.brightness > 0
    readonly property var _record: Core.State.lights || ({})
    readonly property string source: Model.SOURCES.indexOf(root._record.source) >= 0 ? root._record.source : "wallpaper"
    readonly property string customColour: Model.normalizeHex(root._record.colour) || "ffffff"
    readonly property int _onLevel: root._record.onLevel > 0 ? root._record.onLevel : Model.BRIGHTNESS.length - 1

    readonly property string paletteColour: {
        const c = Core.Theme.color.primary;
        return Model.hexFromRgb(c.r * 255, c.g * 255, c.b * 255);
    }

    // The menu's custom colour prompt answers through shell.qml's
    // selectionResolved Connections, the same path ReminderService takes.
    readonly property string inputToken: "lights-colour"

    function refresh() {
        if (!probeProc.running)
            probeProc.running = true;
    }

    function toggle() {
        root.setBrightness(root.on ? 0 : root._onLevel);
    }

    function setBrightness(level) {
        const args = Model.brightnessArgs(level);
        if (!root.available || args === null)
            return false;
        if (level === 0 && root.brightness > 0)
            root._save({ onLevel: root.brightness });
        root.brightness = level;
        root._send(args);
        return true;
    }

    function setEffect(id) {
        if (!root.available || !root.effects.some(e => e.id === id))
            return false;
        root._applyEffect(id, root._wantedColour(), root.speed);
        return true;
    }

    function setSpeed(value) {
        if (!root.available || Model.SPEEDS.indexOf(value) < 0)
            return false;
        root.speed = value;
        if (root.effect !== "" && Model.effect(root.effect).speed)
            root._applyEffect(root.effect, root._wantedColour(), value);
        return true;
    }

    function setColour(text) {
        const hex = Model.normalizeHex(text);
        if (!root.available || hex === "")
            return false;
        root._save({ source: "custom", colour: hex });
        root._applyEffect(Model.usesColour(root.effect) ? root.effect : "static", hex, root.speed);
        return true;
    }

    function setSource(value) {
        if (!root.available || Model.SOURCES.indexOf(value) < 0)
            return false;
        root._save({ source: value });
        if (Model.usesColour(root.effect))
            root._applyEffect(root.effect, root._wantedColour(), root.speed);
        return true;
    }

    function resolveInput(token, value, cancelled) {
        if (token !== root.inputToken || cancelled)
            return;
        if (!root.setColour(value))
            NotificationService.notify("Keyboard Lights", "\"" + value + "\" is not a hex colour like ff8800", 1);
    }

    function _wantedColour() {
        return root.source === "custom" ? root.customColour : root.paletteColour;
    }

    // Updates what the menu shows first, so a checkmark moves in the same
    // turn as the key press; the probe after the write corrects it if asusd
    // disagreed.
    function _applyEffect(id, hex, speed) {
        const args = Model.effectArgs(id, hex, speed);
        if (args === null)
            return;
        root.effect = id;
        if (Model.usesColour(id))
            root.colour = hex;
        root._send(args);
    }

    function _save(fields) {
        Core.State.setLights(Object.assign({}, root._record, fields));
    }

    // One write at a time, and a newer write of the same kind replaces a
    // queued one, so holding Down through the effect list sends the last.
    property var _queue: []

    function _send(args) {
        root._queue = root._queue.filter(a => a[1] !== args[1]).concat([args]);
        root._pump();
    }

    function _pump() {
        if (writeProc.running || root._queue.length === 0)
            return;
        writeProc.command = root._queue[0];
        root._queue = root._queue.slice(1);
        writeProc.running = true;
    }

    function _followPalette() {
        if (!root.available || root.source !== "wallpaper" || !Model.usesColour(root.effect) || !Core.Theme.paletteReady)
            return;
        if (root.colour !== root.paletteColour)
            root._applyEffect(root.effect, root.paletteColour, root.speed);
    }

    onPaletteColourChanged: paletteSettle.restart()

    // Theme.color.primary crossfades over motion.reveal, so every frame of
    // the fade is a new value; this waits for the last one.
    Timer {
        id: paletteSettle
        interval: 1000
        onTriggered: root._followPalette()
    }

    Component.onCompleted: root.refresh()

    // Exit 3 is this script's own "no asusctl", 4 "no Aura object".
    Process {
        id: probeProc
        command: ["sh", "-c",
            'command -v asusctl >/dev/null || exit 3; ' +
            'p=$(busctl --system --list tree xyz.ljones.Asusd 2>/dev/null | grep -m1 "^/xyz/ljones/aura/"); ' +
            '[ -n "$p" ] || exit 4; ' +
            'g() { busctl --system get-property xyz.ljones.Asusd "$p" xyz.ljones.Aura "$1" 2>/dev/null; }; ' +
            'echo "MODE=$(g LedMode)"; echo "DATA=$(g LedModeData)"; ' +
            'echo "BRIGHT=$(g Brightness)"; echo "MODES=$(g SupportedBasicModes)"']
        stdout: StdioCollector {
            id: probeOut
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.available = false;
                return;
            }
            const probe = Model.parseProbe(probeOut.text);
            const current = Model.effectForMode(probe.mode);
            root.effects = Model.supported(probe.modes).map(e => ({ id: e.id, label: e.label }));
            root.effect = current ? current.id : "";
            root.colour = probe.colour;
            if (Model.SPEEDS.indexOf(probe.speed) >= 0)
                root.speed = probe.speed;
            root.brightness = probe.brightness;
            root.available = true;
            root._followPalette();
        }
    }

    Process {
        id: writeProc
        stderr: StdioCollector {
            id: writeErr
        }
        onExited: exitCode => {
            root.lastError = exitCode === 0 ? "" : (writeErr.text.trim() || ("asusctl exited " + exitCode));
            if (root._queue.length > 0)
                root._pump();
            else
                root.refresh();
        }
    }
}
