import QtQuick
import qs.Core
import qs.Components

// One row of the unified menu — a Cell carrying an optional icon glyph, the
// label (or a "CONFIRM <label>?" swap while a confirm-gated action awaits its
// second Enter), and a trailing indicator: "▸" for anything that descends
// (submenu/link/provider), "✓" when the node's `checked` condition resolved
// true, or a full-bleed accent tag when the node carries `meta` (the CALC
// result row). Menu.qml owns cursor/condition state; this row only paints it
// and reports intent back via signals.
Cell {
    id: root

    required property var modelData
    required property int index
    readonly property var node: modelData

    property bool current: false
    property bool checkedState: false
    property bool confirming: false

    signal activate
    signal hoverIn

    readonly property bool isBranch: node.kind === "submenu" || node.kind === "link" || node.kind === "provider"

    selected: root.current
    accent: root.confirming
    hovered: hoverArea.containsMouse

    width: ListView.view ? ListView.view.width : implicitWidth
    height: label.implicitHeight + Theme.spacing.sm * 2 + Theme.borderWidth

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.sm

        Text {
            visible: root.node.icon !== ""
            text: root.node.icon
            color: root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        Text {
            id: label
            text: root.confirming ? ("CONFIRM " + root.node.label + "?") : root.node.label
            // `dim: true` marks a non-activatable honest-empty row (the nix
            // provider's NO NIX) — foregroundDim reads on both the normal
            // and the inverted cursor fill.
            color: root.node.dim === true ? Theme.color.foregroundDim : root.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        // Dimmed trailing description (nix search rows) — pre-truncated by
        // the provider, same contract as clipboardProvider's previewLabel,
        // so no elision is needed here.
        Text {
            visible: (root.node.desc || "") !== ""
            text: root.node.desc || ""
            color: Theme.color.foregroundDim
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.md + Theme.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.confirming && (root.checkedState || root.isBranch)
        text: root.checkedState ? "✓" : "▸"
        color: root.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.fontSize.body
    }

    // DESIGN.md §2.4: accent reads as a full-bleed fill with onAccent text,
    // never a tinted label — independent of the row's own cursor inversion.
    Rectangle {
        visible: (root.node.meta || "") !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.md + Theme.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        width: metaTag.implicitWidth + Theme.spacing.sm * 2
        height: metaTag.implicitHeight + Theme.spacing.xs * 2
        color: Theme.color.accent

        MetaLabel {
            id: metaTag
            anchors.centerIn: parent
            text: root.node.meta || ""
            color: Theme.color.onAccent
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: root.hoverIn()
        onClicked: root.activate()
    }
}
