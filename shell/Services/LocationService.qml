pragma Singleton
import QtQuick
import Quickshell
import QtPositioning
import qs.Core as Core

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
Singleton {
    id: root

    readonly property var _overrideLatitude: Core.Config.get("location.latitude", undefined)
    readonly property var _overrideLongitude: Core.Config.get("location.longitude", undefined)
    readonly property bool _hasOverride: typeof root._overrideLatitude === "number" && typeof root._overrideLongitude === "number"

    readonly property bool available: root._hasOverride || positionSource.valid
    readonly property real latitude: root._hasOverride ? root._overrideLatitude : positionSource.position.coordinate.latitude
    readonly property real longitude: root._hasOverride ? root._overrideLongitude : positionSource.position.coordinate.longitude

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
    }
}
