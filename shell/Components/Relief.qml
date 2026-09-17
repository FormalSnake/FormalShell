import QtQuick
import qs.Core

// The pantheon relief (DESIGN.md §1 "Depth", `theme.depth`): what makes a
// control read as a raised or a sunken object rather than a filled rect.
// Raised, a light line runs just inside the top edge and round the two top
// corners, and `lift` lays a wash over the face that is lighter at the top
// than at the bottom; sunken, the line is dark instead, the shadow the top
// edge casts into a well. Laid over the body it belongs to (`anchors.fill`
// the rectangle, the same `radius`), above the fill and below the content.
// Under a preset without depth it draws nothing and costs nothing.
Item {
    id: root

    property real radius: Theme.radiusMd
    property bool sunken: false
    property bool lift: false
    // The body's own border, which the line sits just inside. 0 for a body
    // drawn without one.
    property real inset: Theme.borderWidth
    // A consumer's own gate on top of the preset's: a cell shows its relief
    // only while it is active, a button only on its filled variants.
    property bool shown: true

    visible: Theme.depth && root.shown

    // The line is a ring one pixel wide, cut to the band the top corners
    // span: elementary's `inset 0 1px` box-shadow is exactly the top arc of
    // such a ring, and this is that arc without a shader. The band ends
    // where the corners do, so the straight sides never show.
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.inset + Math.max(1, root.radius)
        clip: true

        Rectangle {
            x: root.inset
            y: root.inset
            width: root.width - root.inset * 2
            height: root.height - root.inset * 2
            radius: Math.max(0, root.radius - root.inset)
            color: "transparent"
            border.width: 1
            border.color: root.sunken ? Theme.insetLine : Theme.highlight
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.inset
        visible: root.lift
        radius: Math.max(0, root.radius - root.inset)
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.lift }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
