import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Earbuds/model.js" as Model

// Bar cell for EarbudsService (DESIGN.md §3 "Bar"): a headphones icon plus
// the active device's worst bud level in mono (Model.worstLevel leaves the
// case out of the headline; the tooltip carries the full breakdown). Hidden
// entirely (Bar.qml's `shown` pattern, its own header comment explains why
// not a bare `visible`) until a bud has reported a level. Click toggles the
// earbuds panel anchored under this cell, marked open by the same
// `panelOpen` underline as every other panel-bearing cell.
//
// Holds EarbudsService for as long as this cell exists at all, and it only
// exists while "earbuds" is in bar.layout, which is what keeps every
// backend idle on a host that never opted in (DualsenseWidget.qml holds its
// service for the same reason).
Cell {
    id: root

    property var panel: null

    readonly property var _dev: EarbudsService.active
    readonly property int _worstLevel: Model.worstLevel(root._dev)

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    // Visible by default (M23 precedent, Battery/Github/Usage/SystemUpdate):
    // the percentage is content, not a repeat of the icon.
    readonly property bool _showLabel: Config.get("bar.widgets.earbuds.showLabel", true)

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment.
    readonly property bool shown: root._worstLevel >= 0

    visible: root.shown

    Component.onCompleted: EarbudsService.acquire()
    Component.onDestruction: EarbudsService.release()

    tooltipText: root._dev ? root._dev.name.toUpperCase() + " / " + Model.batterySummary(root._dev) : ""

    // The worst-bud percentage resizes this cell as it ticks: glide the
    // width instead of shoving the bar's other widgets instantly
    // (DESIGN.md §1 "Motion").
    Behavior on implicitWidth {
        enabled: root.animateSize
        Anim {}
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
