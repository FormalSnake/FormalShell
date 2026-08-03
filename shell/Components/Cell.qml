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

    implicitWidth: content.implicitWidth + Theme.space.lg * 2 + _ruleReserve
    implicitHeight: content.implicitHeight + Theme.space.sm * 2 + _ruleReserve

    // Full-bleed state fills snap (DESIGN.md §4.3: accent/selection swaps
    // are states, not transitions) — only the hover layer below fades.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.urgent
            ? Theme.color.urgent
            : root.accent
                ? Theme.color.accent
                : root.selected
                    ? Theme.inverted().bg
                    : "transparent"
    }

    // Hover fill on its own layer so it can fade (DESIGN.md §4.1,
    // Theme.motion.fast) without ever animating the state fills above.
    // The standalone hover border rides the same opacity, so it fades in
    // step with the fill instead of snapping.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.fillAlpha)
        border.width: root.standalone ? root._hoverAppearance.borderWidth : 0
        border.color: Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.borderAlpha)
        opacity: root.hovered && !root.selected && !root.accent && !root.urgent ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.space.lg
        anchors.topMargin: Theme.space.sm
        anchors.rightMargin: Theme.space.lg + root._ruleReserve
        anchors.bottomMargin: Theme.space.sm + root._ruleReserve

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
