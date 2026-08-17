import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Weather/openmeteo.js" as Openmeteo

// Weather panel (DESIGN.md §Panels, spec §2's Location→Weather chain, M6
// Task 8): current conditions as a header meta row (condition label +
// temperature + glyph), then a FORECAST ledger — one row per open-meteo
// daily period, glyph + weekday on the left, high/low as mono text pinned
// right (NetworkPanel's own computed-width trick for a right-pinned
// action/value cell). Modeled on Omarchy's weather panel (read-reference
// only, per CLAUDE.md). Bound to LocationService for coordinates and drives
// its own XMLHttpRequest against open-meteo directly — no separate
// WeatherService, the same "panel binds its backend directly" pattern
// AudioPanel/NetworkPanel already establish. Honest states throughout: "NO
// LOCATION" when LocationService has neither a geoclue fix nor a settings
// override (the test VM's permanent case — no Wi-Fi radio to associate
// with), and an "UNAVAILABLE" cell carrying openmeteo.js's specific error
// code when the fetch itself fails (network/HTTP/malformed-JSON/missing
// fields) — never a stale or fabricated forecast. Icon glyphs are the
// "weather-*" set inside the pinned nerd-fonts-jetbrains-mono cmap
// (nix/testvm.nix), taken from its actual cmap via fonttools ttx, not
// memory: weather-day_sunny U+E30D, weather-day_cloudy U+E302,
// weather-cloudy U+E312, weather-fog U+E313, weather-sprinkle U+E31B,
// weather-rain_mix U+E316, weather-rain U+E318, weather-snow U+E31A,
// weather-showers U+E319, weather-thunderstorm U+E31D, weather-na U+E374.
// The forecast ledger keeps these generic (no time-of-day) glyphs since a
// daily high/low row isn't "now"; the current-conditions row below uses
// openmeteo.js's day/night-aware glyphForCode instead (M15 Task 3), the
// same function WeatherWidget.qml binds for its own live bar-cell glyph.
//
// Poll ownership (M15 Task 3, GithubPanel/UsagePanel's own pollEnabled
// precedent — see GithubPanel.qml's header for the IPC-open rationale):
// WeatherWidget flips pollEnabled on when it's actually present in
// bar.layout (never part of DEFAULT_LAYOUT's absence — weather IS in the
// default arrangement, so pollEnabled ends up true whenever the bar looks
// like it does today; a custom layout that drops the widget stops the
// background timer, same as GitHub/Usage). `panel open weather` over IPC
// still renders honestly regardless, since opening always refetches.
Panel {
    id: root

    panelTitle: "WEATHER"
    panelWidth: Theme.space.popupWidthNarrow

    // Flipped true by WeatherWidget's Component.onCompleted, mirroring
    // GithubWidget/UsageWidget.
    property bool pollEnabled: false

    property var _result: null
    property string _error: ""
    property bool _loading: false

    readonly property int _interval: {
        var v = Config.get("weather.intervalMs", 900000);
        return (typeof v === "number" && v > 0) ? v : 900000;
    }

    // A rough local wall-clock day/night split for the current-conditions
    // glyph — open-meteo's current.is_day isn't requested (openmeteo.js's
    // URL/parsing stay untouched by this task), so this reads the host's
    // own clock rather than the API's. Good enough for a glyph choice; a
    // real sunrise/sunset calculation would need the coordinates anyway.
    readonly property bool _isDay: {
        var h = new Date().getHours();
        return h >= 6 && h < 20;
    }

    // Bound by WeatherWidget for its own live bar-cell glyph/temp; the
    // sentinels (NaN/-1) resolve through glyphForCode's own unknown-code
    // fallback, so the widget never needs a second "no data" branch.
    readonly property bool hasCurrent: root._result !== null
    readonly property real currentTemp: root.hasCurrent ? root._result.current.temperature : NaN
    readonly property int currentCode: root.hasCurrent ? root._result.current.code : -1
    readonly property bool currentIsDay: root._isDay

    function _glyphFor(code) {
        switch (Openmeteo.conditionKey(code)) {
        case "clear": return "";
        case "partly-cloudy": return "";
        case "overcast": return "";
        case "fog": return "";
        case "drizzle": return "";
        case "freezing-rain": return "";
        case "rain": return "";
        case "snow": return "";
        case "showers": return "";
        case "thunderstorm": return "";
        default: return "";
        }
    }

    function _fetch() {
        if (!LocationService.available) {
            root._result = null;
            root._error = "";
            return;
        }
        var url = Openmeteo.buildUrl(LocationService.latitude, LocationService.longitude);
        if (!url) {
            root._result = null;
            root._error = "invalid_location";
            return;
        }
        root._loading = true;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            root._loading = false;
            var parsed = Openmeteo.parseResponse(xhr.status, xhr.responseText);
            if (parsed.ok) {
                root._result = parsed;
                root._error = "";
            } else {
                root._result = null;
                root._error = parsed.error;
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    onIsOpenChanged: if (root.isOpen) root._fetch();
    onPollEnabledChanged: if (root.pollEnabled) root._fetch();

    // Runs in the background once the widget opts in (pollEnabled) and
    // also while the panel itself is open — GithubPanel/UsagePanel's own
    // Timer shape. LocationService's streaming updates matter for eventual
    // accuracy, not for retriggering a forecast fetch on every GPS tick.
    Timer {
        interval: root._interval
        running: root.pollEnabled || root.isOpen
        repeat: true
        onTriggered: root._fetch()
    }

    // Wifi coming back should not leave an UNAVAILABLE forecast sitting out
    // the rest of a 15-minute tick (ConnectivityService's whole purpose);
    // gate matches the Timer's own running condition.
    Connections {
        target: ConnectivityService
        function onReconnected() {
            if (root.pollEnabled || root.isOpen)
                root._fetch();
        }
    }

    Cell {
        visible: !LocationService.available
        width: parent.width

        MetaLabel { text: "NO LOCATION" }
    }

    Cell {
        visible: LocationService.available && root._error !== ""
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            MetaLabel { text: "UNAVAILABLE" }

            MetaLabel { text: root._error }
        }
    }

    Cell {
        visible: LocationService.available && root._error === "" && root._result === null
        width: parent.width

        MetaLabel { text: "LOADING" }
    }

    PanelHero {
        visible: root._result !== null
        width: parent.width
        glyph: root._result ? Openmeteo.glyphForCode(root._result.current.code, root._isDay) : ""
        title: "Weather"
        meta: root._result ? Openmeteo.conditionLabel(root._result.current.code) : ""
        readout: root._result ? Math.round(root._result.current.temperature) + "°" : ""
        readoutSize: "displayLarge"
    }

    Cell {
        visible: root._result !== null
        width: parent.width

        MetaLabel { text: "FORECAST"; colon: true }
    }

    Component {
        id: forecastRow

        Cell {
            id: dayCell
            required property var modelData
            width: parent.width

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    id: glyphText
                    text: root._glyphFor(dayCell.modelData.code)
                    color: dayCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Text {
                    width: parent.width - glyphText.width - tempsText.width - parent.spacing * 2
                    text: Openmeteo.weekdayLabel(dayCell.modelData.date)
                    color: Theme.color.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    elide: Text.ElideRight
                }

                Text {
                    id: tempsText
                    text: Math.round(dayCell.modelData.high) + "° / " + Math.round(dayCell.modelData.low) + "°"
                    color: dayCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }
        }
    }

    Repeater {
        model: root._result ? root._result.forecast : []
        delegate: forecastRow
    }
}
