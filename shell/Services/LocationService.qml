pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import QtPositioning
import qs.Core as Core
import "../Location/model.js" as Loc

// Location for WeatherPanel (M6 Task 8, spec §Surfaces 2's Location→Weather
// chain): geoclue2 by default via QtPositioning's PositionSource, left
// continuously `active` with a repeating updateInterval rather than a
// one-shot update(), the spec cites PR #2914's lesson by name, so
// latitude/longitude stay live bindings off positionSource.position for as
// long as the source runs, and an early inaccurate seed is just replaced by
// the next fix instead of freezing in. `location.latitude`/
// `location.longitude` in settings.json override geoclue entirely when
// both are present, the documented fallback for geoclue's own known
// failure mode (stale/empty wpa_supplicant BSS cache), and the only fix
// path exercisable in the test VM, which has no Wi-Fi radio to associate
// with in the first place.
//
// With no override and no geoclue fix 15s in, the shell asks beaconDB
// itself (Location/model.js has why geoclue cannot under iwd), again every
// ten minutes while geoclue stays silent. `source` says which of the three
// answered. `placeName` is Nominatim's name for the spot, rounded to a
// kilometre so it is looked up once per place.
Singleton {
    id: root

    readonly property var _overrideLatitude: Core.Config.get("location.latitude", undefined)
    readonly property var _overrideLongitude: Core.Config.get("location.longitude", undefined)
    readonly property bool _hasOverride: typeof root._overrideLatitude === "number" && typeof root._overrideLongitude === "number"

    readonly property bool _geoclueFix: positionSource.valid && positionSource.position.latitudeValid
        && positionSource.position.longitudeValid
    property var _lookup: null

    readonly property bool available: root._hasOverride || root._geoclueFix || root._lookup !== null
    readonly property real latitude: root._hasOverride ? root._overrideLatitude
        : root._geoclueFix ? positionSource.position.coordinate.latitude
        : root._lookup ? root._lookup.latitude : NaN
    readonly property real longitude: root._hasOverride ? root._overrideLongitude
        : root._geoclueFix ? positionSource.position.coordinate.longitude
        : root._lookup ? root._lookup.longitude : NaN
    // "settings", "geoclue", "wifi" or "ip" (beaconDB's two answers), "".
    readonly property string source: root._hasOverride ? "settings" : root._geoclueFix ? "geoclue"
        : root._lookup ? root._lookup.source : ""

    property string placeName: ""
    property var _places: ({})
    readonly property string _placeKey: root.available ? Loc.placeKey(root.latitude, root.longitude) : ""

    on_PlaceKeyChanged: {
        if (root._placeKey === "") {
            root.placeName = "";
            return;
        }
        if (root._placeKey in root._places) {
            root.placeName = root._places[root._placeKey];
            return;
        }
        var key = root._placeKey;
        root._run(["curl", "-sS", "--fail", "--max-time", "8",
            "-H", "User-Agent: FormalShell (https://github.com/FormalSnake/FormalShell)", Loc.reverseUrl(key)], body => {
            var name = Loc.parsePlace(body);
            if (name !== "") {
                var places = root._places;
                places[key] = name;
                root._places = places;
            }
            if (key === root._placeKey)
                root.placeName = name;
        });
    }

    Timer {
        interval: root._lookup === null ? 15000 : 600000
        repeat: true
        running: Core.Config.loaded && !root._hasOverride && !root._geoclueFix
        onTriggered: root._geolocate()
    }

    function _geolocate() {
        root._run(["sh", "-c",
            'if busctl --system status net.connman.iwd >/dev/null 2>&1; then echo iwd; '
            + 'busctl --system --json=short call net.connman.iwd / org.freedesktop.DBus.ObjectManager GetManagedObjects; '
            + 'elif command -v nmcli >/dev/null 2>&1; then echo nm; nmcli -t -f BSSID,SSID,SIGNAL,FREQ dev wifi list; '
            + 'else echo none; fi'], scan => {
            root._run(["curl", "-sS", "--fail", "--max-time", "8", "-H", "Content-Type: application/json",
                "-d", Loc.geolocateBody(Loc.accessPointsFromScan(scan)), Loc.GEOLOCATE_URL], body => {
                var fix = Loc.parseGeolocate(body);
                if (fix)
                    root._lookup = fix;
            });
        });
    }

    // One short-lived Process per step, answering stdout or "" on failure.
    function _run(command, onDone) {
        var proc = runner.createObject(root, { command: command });
        proc.done.connect(text => {
            onDone(text);
            proc.destroy();
        });
        proc.running = true;
    }

    Component {
        id: runner
        Process {
            signal done(string text)
            stdout: StdioCollector {
                id: collected
            }
            onExited: exitCode => done(exitCode === 0 ? collected.text : "")
        }
    }

    PositionSource {
        id: positionSource
        // No point running geoclue at all once a manual override is set,
        // it would only ever be overridden right back. Gated on
        // Config.loaded too: settings.json hasn't resolved yet means
        // _hasOverride reads false regardless of what the file actually
        // says, which would D-Bus-activate geoclue2 at boot for anyone
        // who does set an override.
        active: Core.Config.loaded && !root._hasOverride
        updateInterval: 60000
        // geoclue authorizes by desktop id; the NixOS module allowlists
        // this one (services.formalshell.geoclue).
        PluginParameter {
            name: "desktopId"
            value: "formalshell"
        }
    }
}
