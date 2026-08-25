import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Weather/openmeteo.js" as Openmeteo

// Weather panel (DESIGN.md §3 "Panel", spec "Panels"): a hero carrying the
// current condition, today's high and low, and the temperature as the
// display readout, then `FORECAST (n)` as one row per open-meteo daily
// period (weekday in sans, condition icon, high and low in mono). The panel
// header's own icon tracks the live condition too, so the popout says what
// the sky is doing before the reader has looked at anything else.
//
// Bound to LocationService for coordinates and drives its own
// XMLHttpRequest against open-meteo directly, the same "panel binds its
// backend directly" pattern AudioPanel and NetworkPanel establish. Honest
// states throughout: "NO LOCATION" when LocationService has neither a
// geoclue fix nor a settings override (the test VM's permanent case, no
// Wi-Fi radio to associate with), and an "UNAVAILABLE" cell carrying
// openmeteo.js's specific error code when the fetch itself fails, never a
// stale or fabricated forecast.
//
// Keyboard (spec "Keyboard model"): the cursor walks the forecast rows. A
// forecast row has no action of its own, so Enter does nothing here.
//
// Poll ownership (M15 Task 3, GithubPanel/UsagePanel's own pollEnabled
// precedent): WeatherWidget flips pollEnabled on when it's actually present
// in bar.layout, so a custom layout that drops the widget stops the
// background timer. `panel open weather` over IPC still renders honestly
// regardless, since opening always refetches.
Panel {
    id: root

    panelIcon: root.hasCurrent ? Openmeteo.iconForCode(root.currentCode, root._isDay) : "cloud"
    panelTitle: "Weather"
    panelWidth: Theme.space.popupWidthDefault

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

    // A rough local wall-clock day/night split for the current condition's
    // icon: open-meteo's current.is_day isn't requested, so this reads the
    // host's own clock rather than the API's. Good enough for an icon
    // choice; a real sunrise/sunset calculation would need the coordinates
    // anyway.
    readonly property bool _isDay: {
        var h = new Date().getHours();
        return h >= 6 && h < 20;
    }

    // Bound by WeatherWidget for its own live bar-cell icon and temperature;
    // the sentinels (NaN/-1) resolve through iconForCode's own unknown-code
    // fallback, so the widget never needs a second "no data" branch.
    readonly property bool hasCurrent: root._result !== null
    readonly property real currentTemp: root.hasCurrent ? root._result.current.temperature : NaN
    readonly property int currentCode: root.hasCurrent ? root._result.current.code : -1
    readonly property bool currentIsDay: root._isDay

    readonly property var _forecast: root._result ? root._result.forecast : []
    // Today's own high and low, the one reading the big number above it
    // cannot state. Empty until a forecast lands.
    readonly property string _todayRange: root._forecast.length > 0
        ? Math.round(root._forecast[0].high) + "° / " + Math.round(root._forecast[0].low) + "°"
        : ""

    cursorCount: root._forecast.length

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root.cursorIndex = 0;
        root._fetch();
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

    // Public wrapper for WeatherWidget's right-click (M26 Task 9): the bar
    // cell has no business reaching into an underscore-prefixed internal.
    function refresh() {
        root._fetch();
    }

    onPollEnabledChanged: if (root.pollEnabled) root._fetch();

    titleActions: [
        IconButton {
            name: "refresh-cw"
            enabled: LocationService.available
            onClicked: root._fetch()
        }
    ]

    // Runs in the background once the widget opts in (pollEnabled) and also
    // while the panel itself is open, GithubPanel/UsagePanel's own Timer
    // shape. LocationService's streaming updates matter for eventual
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

        SectionLabel { text: "NO LOCATION" }
    }

    Cell {
        visible: LocationService.available && root._error !== ""
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            SectionLabel { text: "UNAVAILABLE" }

            Text {
                width: parent.width
                text: root._error
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.bodySmall
                elide: Text.ElideRight
            }
        }
    }

    Cell {
        visible: LocationService.available && root._error === "" && root._result === null
        width: parent.width

        SectionLabel { text: "LOADING" }
    }

    // The panel's own subject: what it is doing outside right now.
    PanelHero {
        id: hero
        visible: root._result !== null
        width: parent.width
        title: root.hasCurrent ? Openmeteo.conditionText(root.currentCode) : ""
        meta: root._todayRange
        metaMono: true
        readout: root.hasCurrent ? Math.round(root.currentTemp) + "°" : ""

        leading: Component {
            Icon {
                name: root.hasCurrent ? Openmeteo.iconForCode(root.currentCode, root._isDay) : "cloud"
                size: Theme.fontSize.heading
                color: hero.foreground
            }
        }
    }

    Column {
        width: parent.width
        visible: root._forecast.length > 0
        spacing: Theme.space.rowGap

        SectionLabel { text: "FORECAST"; count: root._forecast.length }

        Repeater {
            model: root._forecast

            delegate: Cell {
                id: dayCell
                required property var modelData
                required property int index
                width: parent.width
                // Hover-only: a forecast row has nothing to activate, so the
                // pointer moves the cursor onto it and answers no click.
                interactive: true
                acceptedButtons: Qt.NoButton
                cursor: root.cursorActive && root.cursorIndex === dayCell.index

                onContainsPointerChanged: if (dayCell.containsPointer) {
                    root.cursorActive = true;
                    root.cursorIndex = dayCell.index;
                }

                Item {
                    width: parent.width
                    height: dayName.implicitHeight

                    Icon {
                        id: dayIcon
                        name: Openmeteo.iconForCode(dayCell.modelData.code, true)
                        size: Theme.fontSize.body
                        color: dayCell.foreground
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: dayName
                        anchors.left: dayIcon.right
                        anchors.leftMargin: Theme.space.iconGap
                        anchors.right: dayTemps.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        text: Openmeteo.weekdayLabel(dayCell.modelData.date)
                        color: dayCell.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.body
                        font.weight: Theme.weight.medium
                        elide: Text.ElideRight
                    }

                    Text {
                        id: dayTemps
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(dayCell.modelData.high) + "° / " + Math.round(dayCell.modelData.low) + "°"
                        color: dayCell.dimForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.bodySmall
                    }
                }
            }
        }
    }
}
