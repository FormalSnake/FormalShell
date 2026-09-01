import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for AirpodsService (DESIGN.md §3 "Bar"): a headphones icon plus
// the worst known bud level in mono. The case battery is excluded from the
// headline number (it is not a bud, and a full case beside a near-dead bud
// would read backwards), but joins left/right in tooltipText's full
// breakdown. Hidden entirely (Bar.qml's `shown` pattern, its own header
// comment explains why not a bare `visible`) while AirpodsService.available
// is false or neither bud has reported a level yet, so an opt-in cell costs
// nothing on a host with no daemon. Click toggles the airpods panel
// anchored under this cell, marked open by the same `panelOpen` underline
// as every other panel-bearing cell.
//
// Registers as an AirpodsService consumer for as long as this cell exists
// at all, and it only exists while "airpods" is actually in bar.layout,
// which is what keeps that service's rewatch loop from spinning on a host
// that never opted in (DualsenseWidget.qml registers for the same reason).
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
    // the percentage is content, not a repeat of the icon.
    readonly property bool _showLabel: Config.get("bar.widgets.airpods.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: AirpodsService.available && (root._leftKnown || root._rightKnown)

    visible: root.shown

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

    // The worst-bud percentage resizes this cell as it ticks: glide the
    // width instead of shoving the bar's other widgets instantly
    // (DESIGN.md §1 "Motion").
    Behavior on implicitWidth {
        enabled: root.animateSize
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

    CellRow {
        spacing: Theme.space.xs

        Icon {
            name: "headphones"
            color: root.foreground
        }

        CellLabel {
            visible: root._showLabel
            text: root._worstLevel + "%"
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
