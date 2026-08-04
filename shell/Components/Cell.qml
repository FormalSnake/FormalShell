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
// omarchy's own module chrome: borderless at rest, no persistent rule at
// all — the bar's discrete widget cells opt into this. Every fused-ledger
// consumer (menu rows, panel device lists, notification center, the lock
// field) keeps the shared-rule default until its own scheduled retrofit
// task.
//
// Bar-cell hover = full inversion (DESIGN.md §1.1/§3 amendment, owner
// directive over a tint/underline): a standalone cell's hover-cursor state
// swaps its fill to `foreground` and its content to `background` — the
// same fg/bg swap the ledger accent already uses elsewhere in this file —
// instead of the fill-alpha tint + border every other cell still uses.
// `foreground` below is the one place that swap has to happen: every
// widget's own Text/glyph already reads `root.foreground` (or a Cell id's
// `.foreground` alias), so the inversion flows through with no per-widget
// edit needed.
Item {
    id: root

    default property alias data: content.data

    property bool selected: false
    property bool accent: false
    property bool urgent: false
    property bool hovered: false
    property bool standalone: false

    // Bar cells only: hovered, and not already carrying one of the other
    // full-bleed states (selected/accent/urgent keep their own fill — no
    // double treatment, DESIGN.md §2.4).
    readonly property bool _hoverFillActive: root.hovered && !root.selected && !root.accent && !root.urgent
    readonly property bool _hoverInverted: root.standalone && root._hoverFillActive

    readonly property color foreground: (accent || urgent)
        ? Theme.color.onAccent
        : (root._hoverInverted ? Theme.color.background : (selected ? Theme.inverted().fg : Theme.color.foreground))

    readonly property var _hoverAppearance: Theme.stateAppearance("hover-cursor")

    // The borderWidth term reserves room for the bottom/right rules below —
    // a standalone cell draws neither, so reserving it anyway leaves the
    // content sitting visibly high-left of the cell's true center.
    readonly property real _ruleReserve: standalone ? 0 : Theme.borderWidth

    implicitWidth: root._measure(false) + Theme.space.lg * 2 + _ruleReserve
    implicitHeight: root._measure(true) + Theme.space.sm * 2 + _ruleReserve

    // How big the content wants to be. This used to be `content`'s own
    // childrenRect, which closes a cycle, since content is anchored to fill
    // the cell: childrenRect measures a fill-anchored child (every cell's
    // hit area) at exactly the width of the cell the measurement is sizing,
    // and it measures each child's x/y, so a centered child's offset (half
    // the leftover room) lands back in the size that leftover room came
    // from. QML answers a looping binding by aborting it, which leaves the
    // cell at whatever size it had reached: never smaller than the widest
    // transient it ever saw, and on a first-pass abort, nothing at all.
    //
    // So measure each child's own extent and drop the two terms that feed
    // back. Nothing else changes: a child's position never described how
    // much room the content needs, and a child anchored to fill the cell
    // takes its size from the cell, so it can't be what determines it.
    //
    // `vertical` picks the axis, one function, since the two differ by
    // nothing but the property pair.
    function _measure(vertical) {
        var max = 0;
        for (var i = 0; i < content.children.length; i++) {
            var child = content.children[i];
            if (child.anchors.fill === content)
                continue;
            var extent = vertical ? child.height : child.width;
            if (extent > max)
                max = extent;
        }
        return max;
    }

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
    // Theme.motion.fast) without ever animating the state fills above —
    // the fade stays on this layer even for the standalone/bar case below;
    // only the swap itself (this fill's own color, and `foreground` above)
    // is instant, matching every other ledger inversion (DESIGN.md §4.3).
    // Standalone (bar) cells get a full opaque `foreground` fill — the
    // inversion — instead of every other cell's low-alpha tint.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.standalone
            ? Theme.color.foreground
            : Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.fillAlpha)
        opacity: root._hoverFillActive ? 1 : 0

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

        // Deliberately no implicit size of its own: root._measure() reads
        // the children directly, so nothing ever writes an implicit size
        // onto an item whose geometry those same children track.
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
