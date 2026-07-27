import QtQuick
import qs.Core

// THE ledger cell (DESIGN.md "cells not cards"): every row on every M4+
// surface is one of these, so cell styling and the shared-rule border
// contract exist in exactly one place.
//
// Shared-rule contract: a cell draws only its bottom and right rule: the
// container arranging a grid of cells is responsible for the outer top/left
// rule, so adjacent cells never double up their shared border.
Item {
    id: root

    default property alias data: content.data

    property bool selected: false
    property bool accent: false
    property bool hovered: false

    readonly property color foreground: accent
        ? Theme.color.onAccent
        : (selected ? Theme.inverted().fg : Theme.color.foreground)

    implicitWidth: content.implicitWidth + Theme.spacing.md * 2 + Theme.borderWidth
    implicitHeight: content.implicitHeight + Theme.spacing.sm * 2 + Theme.borderWidth

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.accent
            ? Theme.color.accent
            : root.selected
                ? Theme.inverted().bg
                : root.hovered
                    ? Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, Theme.control("hover").fillAlpha)
                    : "transparent"
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.topMargin: Theme.spacing.sm
        anchors.rightMargin: Theme.spacing.md + Theme.borderWidth
        anchors.bottomMargin: Theme.spacing.sm + Theme.borderWidth
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.borderWidth
        color: Theme.color.rule
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Theme.borderWidth
        color: Theme.color.rule
    }
}
