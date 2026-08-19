import QtQuick
import qs.Core

// The shared panel-opening block (DESIGN.md §2 addendum, M26 Task 1): one
// glyph, one bold noun, one uppercase state line, an optional oversized
// readout, an optional trailing control, an optional progress rail. Built on
// Cell, so the block's whole border is Cell's own shared-rule bottom/right
// contract — no second box drawn here, and no fixed height: everything below
// sizes off its own content like every other panel row.
//
// All properties are optional except `title`. `glyph` sits in a fixed-width
// slot (`Theme.space.xxl * 2`) so a wider Nerd Font codepoint never shifts
// the title next to it, the same jitter guard Task 7 gives the bar's own
// glyph-only cells. `readout` renders at `readoutSize`, right-aligned ahead
// of `trailing` when both are set.
//
// `leading` (M28 Task 2) is `trailing`'s mirror: a Component that replaces
// the glyph text in that same slot, for a panel whose subject has real
// imagery instead of an icon (MediaPanel's album art). The slot's width
// stays the shared `Theme.space.xxl * 2` either way — a caller-provided
// component sizes itself to that same token rather than PanelHero handing
// out its own internal geometry, so a Media panel with no art (falling
// back to `glyph`) and every other panel's hero still line up their titles
// at the identical x.
//
// `railInteractive` (M28 review fix) opts the rail into press/drag/wheel,
// reporting through `railPressed`/`railStepped` rather than writing state
// itself — the rail stays a dumb readout of whatever `rail` says either
// way. Default false, so Weather/Calendar/Power/Usage keep the plain
// readout DESIGN.md §2 item 13 describes; Audio is the one panel whose
// subject is itself an adjustable value, not a metric, so its hero opts in
// to restore the press/drag/wheel volume control the old master-slider row
// carried before the hero absorbed it.
Cell {
    id: root

    property string glyph: ""
    property string title: ""
    property string meta: ""
    property string readout: ""
    // "display" (26px) or "displayLarge" (30px), DESIGN.md §1.3.
    property string readoutSize: "display"
    property Component leading: null
    property Component trailing: null
    // 0..1 fills the rail; -1 (default) leaves it undrawn.
    property real rail: -1
    property bool railInteractive: false
    signal railPressed(real fraction)
    signal railStepped(int direction)

    readonly property real _glyphSlotWidth: (root.glyph !== "" || root.leading !== null) ? Theme.space.xxl * 2 : 0

    Column {
        width: parent.width
        // `xxs`, the same text-block-to-track gap every panel row with its
        // own DitherFill uses (AudioPanel's stream rows, DisplayPanel's
        // brightness, UsagePanel's meters) — the hero's rail is that same
        // structural element, so it takes that same token.
        spacing: Theme.space.xxs

        Item {
            id: heroRow
            width: parent.width
            height: Math.max(glyphSlot.height, textColumn.height,
                readoutText.visible ? readoutText.implicitHeight : 0,
                trailingLoader.active ? trailingLoader.height : 0)

            Item {
                id: glyphSlot
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root._glyphSlotWidth
                height: leadingLoader.active ? leadingLoader.height : glyphText.implicitHeight

                Text {
                    id: glyphText
                    visible: !leadingLoader.active
                    anchors.centerIn: parent
                    text: root.glyph
                    color: root.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.heading
                }

                Loader {
                    id: leadingLoader
                    anchors.centerIn: parent
                    active: root.leading !== null
                    sourceComponent: root.leading
                }
            }

            Column {
                id: textColumn
                anchors.left: glyphSlot.right
                anchors.leftMargin: (root.glyph !== "" || root.leading !== null) ? Theme.space.md : 0
                anchors.right: root.readout !== ""
                    ? readoutText.left
                    : (trailingLoader.active ? trailingLoader.left : parent.right)
                anchors.rightMargin: (trailingLoader.active || root.readout !== "") ? Theme.space.md : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.xxs

                // Sentence case, not uppercase: the panel's noun is content,
                // not a meta label, so MetaLabel's forced capitalization
                // does not apply here.
                Text {
                    width: parent.width
                    text: root.title
                    color: root.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.subtitle
                    elide: Text.ElideRight
                }

                MetaLabel {
                    width: parent.width
                    visible: root.meta !== ""
                    text: root.meta
                    color: root.dimForeground
                    elide: Text.ElideRight
                }
            }

            // Monospace tabular digits by construction (DESIGN.md §2 item
            // 5): the readout never jitters as its value ticks.
            Text {
                id: readoutText
                anchors.right: trailingLoader.active ? trailingLoader.left : parent.right
                anchors.rightMargin: trailingLoader.active ? Theme.space.md : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: root.readout !== ""
                text: root.readout
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: root.readoutSize === "displayLarge" ? Theme.fontSize.displayLarge : Theme.fontSize.display
            }

            Loader {
                id: trailingLoader
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                active: root.trailing !== null
                sourceComponent: root.trailing
            }
        }

        // Flat accent fill over the dither remainder, the same idiom
        // PowerPanel's own battery track and CalendarPanel's year-progress
        // bar already use. No knob either way; no MouseArea unless a
        // caller opts into `railInteractive` (AudioPanel's volume rail).
        DitherFill {
            id: railTrack
            width: parent.width
            height: Theme.space.trackThickness
            visible: root.rail >= 0

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.rail))
                height: parent.height
                color: Theme.color.accent
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.railInteractive
                hoverEnabled: root.railInteractive
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => root.railPressed(Math.max(0, Math.min(1, mouse.x / railTrack.width)))
                onPositionChanged: mouse => { if (pressed) root.railPressed(Math.max(0, Math.min(1, mouse.x / railTrack.width))); }
                onWheel: wheel => {
                    root.railStepped(wheel.angleDelta.y > 0 ? 1 : -1);
                    wheel.accepted = true;
                }
            }
        }
    }
}
