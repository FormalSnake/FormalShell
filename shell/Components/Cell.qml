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
// `warning` (DESIGN.md §1.5/§2.4, M18 Task 7) is the third full-bleed
// sibling — a degraded-but-not-critical state, e.g. low (not yet critical)
// battery — filling with `Theme.color.warning`/`onWarning`. Spent only where
// a caller's own service layer already distinguishes a middle severity band;
// see Battery.qml for the one consumer.
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
// swaps its fill and content to the accent pair (`Theme.inverted()`, same
// `{ bg: accent, fg: onAccent }` the ledger's `selected` fill already uses
// below) instead of the fill-alpha tint + border every other cell still
// uses. `foreground` below is the one place that swap has to happen: every
// widget's own Text/glyph already reads `root.foreground` (or a Cell id's
// `.foreground` alias), so the inversion flows through with no per-widget
// edit needed.
Item {
    id: root

    default property alias data: content.data

    property bool selected: false
    property bool accent: false
    property bool urgent: false
    property bool warning: false
    property bool hovered: false
    property bool standalone: false
    // Dithered resting backdrop (DESIGN.md §2.8) for a still-unseen row —
    // NotificationCard.qml's pending notification-center rows, currently the
    // only consumer. Rendered here, not by a child dropped into the default
    // `data` slot below: that slot forwards into `content`, which is inset
    // by the control padding, so a `DitherFill { anchors.fill: parent }`
    // declared from outside would fill the padded text box instead of the
    // row. Loader-gated like the tooltip below — most cells never set this,
    // so most cells never pay for the Canvas.
    property bool pending: false

    // Hover tooltip (owner directive, reversing the M16 audit's "bar
    // tooltips" skip): a short uppercase line naming what this cell is and
    // what it currently reads, shown after Tooltip.qml's own delay once the
    // pointer settles and dropped the instant it leaves. Empty — the default
    // — means no tooltip at all, so every cell that doesn't opt in is
    // untouched, including the ones that never set `hovered`.
    //
    // ⚠️ The surface deliberately does not live in `content`: _measure()
    // below sizes the cell off EVERY direct child of `content` regardless of
    // visibility, so a tooltip drawn as a child item would widen (and
    // heighten) every cell it was attached to by its own card. Tooltip.qml
    // is a layer-shell window of its own instead, held by the Loader below,
    // which sits outside `content` and carries no size either way.
    property string tooltipText: ""

    // Set when `tooltipText` is a foreign process's own string rather than
    // wording this shell chose (tray item titles). Renders it verbatim instead
    // of uppercasing it — see Tooltip.qml's label for the reasoning.
    property bool tooltipVerbatim: false

    // Bar cells only: hovered, and not already carrying one of the other
    // full-bleed states (selected/accent/urgent/warning keep their own fill
    // — no double treatment, DESIGN.md §2.4).
    readonly property bool _hoverFillActive: root.hovered && !root.selected && !root.accent && !root.urgent && !root.warning
    readonly property bool _hoverInverted: root.standalone && root._hoverFillActive

    readonly property color foreground: urgent
        ? Theme.color.onUrgent
        : accent
            ? Theme.color.onAccent
            : warning
                ? Theme.color.onWarning
                : ((root._hoverInverted || selected) ? Theme.inverted().fg : Theme.color.foreground)

    // Band-2 (meta) ink that stays legible when this cell is itself
    // full-bleed or inverted (DESIGN.md §1.4 ink hierarchy): `foregroundDim`
    // is the default resting color, but a dim caption drawn straight onto
    // an accent/urgent/warning fill or the inverted cursor fill measures
    // under 1.1:1 contrast (M18 Task 2/4 regression) — so any of those
    // states promote a meta label to the same ink `foreground` above
    // already resolves for content, matching the single-band-loudness
    // model the inversion itself uses. Every meta caption bound to a
    // Cell's own state (MenuRow's desc/dim text, MetaLabel captions on
    // Battery/UsageWidget/NotificationCard/Osd) reads this instead of
    // hardcoding `Theme.color.foregroundDim`.
    readonly property color dimForeground: (urgent || accent || warning || root._hoverInverted || selected)
        ? foreground
        : Theme.color.foregroundDim

    readonly property var _hoverAppearance: Theme.stateAppearance("hover-cursor")

    // The borderWidth term reserves room for the bottom/right rules below —
    // a standalone cell draws neither, so reserving it anyway leaves the
    // content sitting visibly high-left of the cell's true center.
    readonly property real _ruleReserve: standalone ? 0 : Theme.borderWidth

    implicitWidth: root._measure(false) + Theme.space.controlPaddingX * 2 + _ruleReserve
    implicitHeight: root._measure(true) + Theme.space.controlPaddingY * 2 + _ruleReserve

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

    function _openTooltip() {
        if (!root.hovered || root.tooltipText === "")
            return;
        tooltipLoader.active = true;
        tooltipLoader.item.anchorItem = root;
        tooltipLoader.item.verbatim = root.tooltipVerbatim;
        tooltipLoader.item.text = root.tooltipText;
        tooltipLoader.item.show();
    }

    onHoveredChanged: {
        if (root.hovered)
            root._openTooltip();
        else if (tooltipLoader.item)
            tooltipLoader.item.hide();
    }

    // Live while shown: a cell's value moves under a parked pointer (volume
    // ticking, a battery estimate settling), and the card is meant to read
    // as the cell's own state, not a snapshot of when the pointer arrived.
    // Never re-opens through _openTooltip() once the surface exists — that
    // would restart its show delay and blink the card on every tick. The
    // else branch covers the one case a text change IS an open: the cell had
    // nothing to say when the pointer arrived and now does.
    onTooltipTextChanged: {
        if (tooltipLoader.item)
            tooltipLoader.item.text = root.tooltipText;
        else
            root._openTooltip();
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
                : root.warning
                    ? Theme.color.warning
                    : root.selected
                        ? Theme.inverted().bg
                        : "transparent"
    }

    // Pending backdrop (DESIGN.md §2.8): dropped the instant a fuller-bleed
    // state already owns the cell — §2.4's "no double treatment" applies to
    // this ornament too. `active` gates the Canvas itself, not just
    // visibility, so the common case (pending false) never allocates one.
    Loader {
        anchors.fill: parent
        active: root.pending && !root.urgent && !root.accent && !root.warning && !root.selected
        sourceComponent: DitherFill {
            anchors.fill: parent
        }
    }

    // Hover fill on its own layer so it can fade (DESIGN.md §4.1,
    // Theme.motion.fast) without ever animating the state fills above —
    // the fade stays on this layer even for the standalone/bar case below;
    // only the swap itself (this fill's own color, and `foreground` above)
    // is instant, matching every other ledger inversion (DESIGN.md §4.3).
    // Standalone (bar) cells get a full opaque accent fill — `Theme.inverted().bg`,
    // the same pair the ledger's `selected` fill below uses — instead of
    // every other cell's low-alpha tint.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.standalone
            ? Theme.inverted().bg
            : Qt.rgba(Theme.color.foreground.r, Theme.color.foreground.g, Theme.color.foreground.b, root._hoverAppearance.fillAlpha)
        opacity: root._hoverFillActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.space.controlPaddingX
        anchors.topMargin: Theme.space.controlPaddingY
        anchors.rightMargin: Theme.space.controlPaddingX + root._ruleReserve
        anchors.bottomMargin: Theme.space.controlPaddingY + root._ruleReserve

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

    // Loaded by URL rather than declared as a `Tooltip {}`, for two reasons.
    // Tooltip.qml pulls in Quickshell and Quickshell.Wayland, while Cell.qml
    // is instantiated head-on by tests/tst_cell_geometry.qml and
    // tst_cell_hover_inversion.qml under a plain qmltestrunner that has no
    // Quickshell module at all; and Tooltip.qml's card is itself built from
    // a Cell, so a type reference would ask QML to resolve each of the two
    // files while compiling the other. A URL resolves only when the Loader
    // activates — which no test ever does, and which the tooltip's own inner
    // Cell never does either, since nothing gives it a tooltipText.
    //
    // `active` starts false (Loader's own default is true) and is written
    // imperatively from onHoveredChanged above, never bound: that load has
    // to have completed by the next statement, which only a synchronous
    // activation guarantees. It then stays loaded — unloading on pointer
    // exit would cut the exit fade short and re-pay the surface's creation
    // on every pass along the bar, while every cell in the shell loading one
    // up front would cost a layer-shell window per cell per output for cells
    // that may never be hovered at all.
    Loader {
        id: tooltipLoader
        active: false
        source: "Tooltip.qml"
    }
}
