import QtQuick
import qs.Core

// The shared panel-opening block (DESIGN.md §3 "Panel"): the inner card a
// panel leads with, holding one icon or image, the subject's name, a caption
// line under it, an optional oversized readout, an optional trailing control
// and an optional progress track. Built on Cell, so it is already the
// `radiusMd` bordered card the design asks for, concentric inside the
// panel's own `radiusXl` frame, and it sizes off its own content like every
// other row.
//
// All properties are optional except `title`. `glyph` sits in a fixed-width
// slot (`Theme.space.xxl * 2`) so a wider codepoint never shifts the title
// next to it. `readout` renders at `readoutSize`, right-aligned ahead of
// `trailing` when both are set.
//
// `leading` is `trailing`'s mirror: a Component that replaces the glyph text
// in that same slot, for a panel whose subject has real imagery or a named
// Icon instead of a raw codepoint (MediaPanel's album art, NetworkPanel's
// wifi icon). The slot's width stays the shared `Theme.space.xxl * 2` either
// way, so every panel's hero lines its title up at the identical x.
//
// `railInteractive` opts the track into press/drag/wheel, reporting through
// `railPressed`/`railStepped` rather than writing state itself: the track
// stays a dumb readout of whatever `rail` says either way. Default false, so
// every panel but Audio keeps the plain readout. Audio is the one panel whose
// subject is itself an adjustable value rather than a metric.
Cell {
    id: root

    property string glyph: ""
    property string title: ""
    property string meta: ""
    // A meta line carrying an identifier or a number is a value, so it takes
    // the mono face (DESIGN.md §1 "Type"). Words stay sans.
    property bool metaMono: false
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
        // The same text-block-to-track gap every panel row with a track of
        // its own uses.
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
                    font.family: Theme.fontFamilyMono
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
                anchors.leftMargin: (root.glyph !== "" || root.leading !== null) ? Theme.space.iconGap : 0
                anchors.right: root.readout !== ""
                    ? readoutText.left
                    : (trailingLoader.active ? trailingLoader.left : parent.right)
                anchors.rightMargin: (trailingLoader.active || root.readout !== "") ? Theme.space.iconGap : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.xxs

                // Sentence case: the panel's noun is content, not a
                // section label.
                Text {
                    width: parent.width
                    text: root.title
                    color: root.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.subtitle
                    elide: Text.ElideRight
                }

                // Sentence case as well: only a SectionLabel uppercases
                // (DESIGN.md §5), and a mode line read back as `1920X1080@60`
                // is what that rule exists to stop.
                Text {
                    width: parent.width
                    visible: root.meta !== ""
                    text: root.meta
                    color: root.dimForeground
                    font.family: root.metaMono ? Theme.fontFamilyMono : Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.bodySmall
                    elide: Text.ElideRight
                }
            }

            // Mono, so the digits stay tabular and the readout never jitters
            // as its value ticks.
            Text {
                id: readoutText
                anchors.right: trailingLoader.active ? trailingLoader.left : parent.right
                anchors.rightMargin: trailingLoader.active ? Theme.space.iconGap : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: root.readout !== ""
                text: root.readout
                color: root.foreground
                font.family: Theme.fontFamilyMono
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

        // The one progress groove (DESIGN.md §2). No knob either way, and no
        // MouseArea unless a caller opts into `railInteractive`.
        Track {
            id: railTrack
            width: parent.width
            visible: root.rail >= 0
            value: root.rail

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
