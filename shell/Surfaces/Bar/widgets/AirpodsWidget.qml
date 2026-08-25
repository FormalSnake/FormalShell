import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for AirpodsService (DESIGN.md §Bar, M29 Task 3, plan at
// docs/superpowers/plans/2026-08-18-m29-device-panels.md): earbuds glyph
// plus the worst known bud level as NN% — case battery is excluded from
// the headline number (it isn't a bud, and a fully-charged case sitting
// next to a near-dead bud would read backwards), but joins left/right in
// tooltipText's full breakdown. Hidden entirely (Bar.qml's `shown`
// pattern, its own header comment explains why not a bare `visible`) while
// AirpodsService.available is false or neither bud has reported a level
// yet — an opt-in cell that costs nothing on a host with no daemon. Glyph
// codepoint is the same one AirpodsPanel.qml's hero already carries
// (pinned nerd-fonts-jetbrains-mono cmap, verified via fonttools ttx in
// M29 Task 2): md-earbuds U+F184F. Click toggles the airpods panel
// anchored under this cell, marked open by the same `panelOpen` underline
// as every other panel-bearing cell (BluetoothWidget.qml). Registers/unregisters as an
// AirpodsService consumer for as long as this cell exists at all — it
// only exists while "airpods" is actually in bar.layout, which is what
// keeps that service's rewatch loop from spinning on a host that never
// opted in (DualsenseWidget.qml's own consumer registration, same
// reason).
Cell {
    id: root

    property var panel: null

    readonly property var _status: AirpodsService.status
    readonly property bool _leftKnown: root._status.left.available && root._status.left.level >= 0
    readonly property bool _rightKnown: root._status.right.available && root._status.right.level >= 0
    readonly property bool _caseKnown: root._status.caseBattery.available && root._status.caseBattery.level >= 0
    readonly property int _worstLevel: {
        if (root._leftKnown && root._rightKnown)
            return Math.min(root._status.left.level, root._status.right.level);
        if (root._leftKnown)
            return root._status.left.level;
        if (root._rightKnown)
            return root._status.right.level;
        return -1;
    }

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent, Battery/Github/Usage/SystemUpdate):
    // the percentage is content, not a repeat of the glyph.
    readonly property bool _showLabel: Config.get("bar.widgets.airpods.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: AirpodsService.available && (root._leftKnown || root._rightKnown)

    visible: root.shown
    standalone: true

    Component.onCompleted: AirpodsService.acquire()
    Component.onDestruction: AirpodsService.release()

    tooltipText: {
        var parts = [];
        if (root._leftKnown)
            parts.push("L " + root._status.left.level);
        if (root._rightKnown)
            parts.push("R " + root._status.right.level);
        if (root._caseKnown)
            parts.push("CASE " + root._status.caseBattery.level);
        return "AIRPODS / " + parts.join(" / ");
    }

    // The worst-bud percentage resizes this cell as it ticks — glide the
    // width instead of shoving the bar's other widgets instantly
    // (DESIGN.md §4, M16 Task 2's contract, extended to every numeric bar
    // cell by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7), matching this cell's siblings even
        // though this glyph itself never swaps — one idiom for the bar's
        // leading icon column rather than two.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: "󱡏"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root._worstLevel + "%"
            color: root.dimForeground
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
