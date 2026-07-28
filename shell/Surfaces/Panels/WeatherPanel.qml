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
Panel {
    id: root

    panelTitle: "WEATHER"
    panelWidth: 260

    property var _result: null
    property string _error: ""
    property bool _loading: false

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

    // Re-fetch periodically while open — mirrors CalendarPanel's own
    // minute Timer for "today" — rather than wiring a dedicated
    // location-changed handler: LocationService's streaming updates matter
    // for eventual accuracy, not for retriggering a forecast fetch on every
    // GPS tick.
    Timer {
        interval: 10 * 60 * 1000
        running: root.isOpen
        repeat: true
        onTriggered: root._fetch()
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
            spacing: Theme.spacing.xs

            MetaLabel { text: "UNAVAILABLE" }

            Text {
                text: root._error.toUpperCase()
                color: Theme.color.foregroundDim
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
            }
        }
    }

    Cell {
        visible: LocationService.available && root._error === "" && root._result === null
        width: parent.width

        MetaLabel { text: "LOADING" }
    }

    Cell {
        id: currentCell
        visible: root._result !== null
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.spacing.xs

            MetaLabel { text: root._result ? Openmeteo.conditionLabel(root._result.current.code) : "" }

            Row {
                spacing: Theme.spacing.sm

                Text {
                    text: root._result ? root._glyphFor(root._result.current.code) : ""
                    color: currentCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }

                Text {
                    text: root._result ? Math.round(root._result.current.temperature) + "°" : ""
                    color: currentCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }

    Cell {
        visible: root._result !== null
        width: parent.width

        MetaLabel { text: "FORECAST" }
    }

    Component {
        id: forecastRow

        Cell {
            id: dayCell
            required property var modelData
            width: parent.width

            Row {
                width: parent.width
                spacing: Theme.spacing.sm

                Text {
                    id: glyphText
                    text: root._glyphFor(dayCell.modelData.code)
                    color: dayCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }

                Text {
                    width: parent.width - glyphText.width - tempsText.width - parent.spacing * 2
                    text: Openmeteo.weekdayLabel(dayCell.modelData.date)
                    color: dayCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                    elide: Text.ElideRight
                }

                Text {
                    id: tempsText
                    text: Math.round(dayCell.modelData.high) + "° / " + Math.round(dayCell.modelData.low) + "°"
                    color: dayCell.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }

    Repeater {
        model: root._result ? root._result.forecast : []
        delegate: forecastRow
    }
}
