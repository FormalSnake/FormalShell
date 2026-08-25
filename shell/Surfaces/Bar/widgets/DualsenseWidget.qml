import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Dualsense/model.js" as DualsenseModel

// Bar cell for DualsenseService (DESIGN.md §3 "Bar"): a gamepad icon plus
// the controller battery in mono, on DualsenseService's own shared 30s
// timer. Hidden entirely (Bar.qml's `shown` pattern) while
// `DualsenseService.present` is false, so no controller means no cell,
// never an empty "0%" stub. Warn and critical put their colour on the
// border and the ink exactly as the laptop battery cell does (DESIGN.md
// §5: colour never fills a row).
//
// Registers as a DualsenseService consumer for as long as this cell exists
// at all, and it only exists while "dualsense" is actually in bar.layout,
// so an ordinary host with no controller pays nothing beyond one exec every
// 30s once opted in.
Cell {
    id: root

    property var panel: null

    readonly property var _battery: DualsenseService.battery
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent, every other percentage-carrying
    // bar cell): the percentage is content, not a repeat of the icon.
    readonly property bool _showLabel: Config.get("bar.widgets.dualsense.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: DualsenseService.present

    visible: root.shown
    destructive: DualsenseService.present && root._battery.critical
    warning: DualsenseService.present && root._battery.warn

    tooltipText: {
        if (!DualsenseService.present)
            return "";
        var head = "DUALSENSE " + root._battery.percent + "%";
        var state = DualsenseModel.stateLine(root._battery);
        return state !== "" ? head + " / " + state : head;
    }

    Component.onCompleted: DualsenseService.acquire()
    Component.onDestruction: DualsenseService.release()

    // The percent label resizes this cell as it ticks: glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §1
    // "Motion").
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xs

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "gamepad-2"
            color: root.foreground
        }

        Text {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: DualsenseService.present ? root._battery.percent + "%" : ""
            color: root.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
