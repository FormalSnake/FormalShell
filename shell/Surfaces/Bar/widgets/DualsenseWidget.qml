import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Dualsense/model.js" as DualsenseModel

// Bar cell for DualsenseService (DESIGN.md §Bar, M29 Task 4, plan at
// docs/superpowers/plans/2026-08-18-m29-device-panels.md): gamepad glyph
// plus battery NN%, replacing the old `custom:dualsense` command module at
// the same 30s cadence (DualsenseService's own shared timer). Hidden
// entirely (Bar.qml's `shown` pattern) while `DualsenseService.present` is
// false — no controller means no cell, never an empty "0%" stub. Warning/
// critical thresholds go full-bleed exactly like the laptop battery cell
// (Battery.qml), the same DESIGN.md §2.4 full-bleed-fill idiom. Glyph
// codepoint is the same one DualsensePanel.qml's hero carries (pinned
// nerd-fonts-jetbrains-mono cmap, verified via fonttools ttx): md-gamepad_variant
// U+F0297. Registers/unregisters as a DualsenseService consumer for as long
// as this cell exists at all — it only exists while "dualsense" is actually
// in bar.layout, so an ordinary host with no controller pays nothing beyond
// one exec every 30s once opted in.
Cell {
    id: root

    property var panel: null

    readonly property var _battery: DualsenseService.battery
    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent, every other percentage-carrying
    // bar cell): the percentage is content, not a repeat of the glyph.
    readonly property bool _showLabel: Config.get("bar.widgets.dualsense.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: DualsenseService.present

    visible: root.shown
    standalone: true
    urgent: DualsenseService.present && root._battery.critical
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

    // The percent label resizes this cell as it ticks — glide the width
    // instead of shoving the bar's other widgets instantly (DESIGN.md §4,
    // M16 Task 2's contract, extended to every numeric bar cell by M26
    // Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7), matching this cell's siblings even
        // though this glyph itself never swaps.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: "󰊗"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: DualsenseService.present ? root._battery.percent + "%" : ""
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
