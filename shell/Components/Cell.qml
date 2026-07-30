import QtQuick
import qs.Core

// THE ledger cell (DESIGN.md "cells not cards"): every row on every M4+
// surface is one of these, so cell styling and the shared-rule border
// contract exist in exactly one place.
//
// Shared-rule contract: a cell draws only its bottom and right rule: the
// container arranging a grid of cells is responsible for the outer top/left
// rule, so adjacent cells never double up their shared border.
//
// `urgent` (DESIGN.md §2.4, M8b Task 5) is `accent`'s sibling for the other
// full-bleed case — a critical notification — filling with `Theme.color.urgent`
// (a distinct palette role from `accent`, both matugen-driven) instead.
//
// `standalone` (DESIGN.md §3 Bar retrofit) swaps that contract for
// omarchy's own module chrome: borderless at rest, a hover-cursor fill and
// border that only appear on mouseover, no persistent rule at all — the
// bar's discrete widget cells opt into this. Every fused-ledger consumer
// (menu rows, panel device lists, notification center, the lock field)
// keeps the shared-rule default until its own scheduled retrofit task.
Item {
    id: root

    default property alias data: content.data

    property bool selected: false
    property bool accent: false
    property bool urgent: false
    property bool hovered: false
    property bool standalone: false

    readonly property color foreground: (accent || urgent)
        ? Theme.color.onAccent
        : (selected ? Theme.inverted().fg : Theme.color.foreground)

    readonly property var _hoverAppearance: Theme.stateAppearance("hover-cursor")

    // The borderWidth term reserves room for the bottom/right rules below —
    // a standalone cell draws neither, so reserving it anyway leaves the
    // content sitting visibly high-left of the cell's true center.
    readonly property real _ruleReserve: standalone ? 0 : Theme.borderWidth

    implicitWidth: content.implicitWidth + Theme.spacing.md * 2 + _ruleReserve
    implicitHeight: content.implicitHeight + Theme.spacing.sm * 2 + _ruleReserve

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.urgent
            ? Theme.color.urgent
            : root.accent
                ? Theme.color.accent
                : root.selected
                    ? Theme.inverted().bg
                    : root.hovered
                        ? Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.fillAlpha)
                        : "transparent"
        border.width: root.standalone && root.hovered && !root.selected && !root.accent && !root.urgent ? root._hoverAppearance.borderWidth : 0
        border.color: Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.borderAlpha)
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.topMargin: Theme.spacing.sm
        anchors.rightMargin: Theme.spacing.md + root._ruleReserve
        anchors.bottomMargin: Theme.spacing.sm + root._ruleReserve

        // Item never derives implicit size from children — only positioners
        // and Text/Image do that automatically — so without this,
        // content.implicit* (read by root.implicit* above) is permanently 0
        // no matter what's inside. childrenRect is the collective bounding
        // box of content's actual children, which gives a bare Item the
        // same auto-sizing behavior.
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    Rectangle {
        visible: !root.standalone
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.borderWidth
        color: Theme.color.rule
    }

    Rectangle {
        visible: !root.standalone
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Theme.borderWidth
        color: Theme.color.rule
    }
}
