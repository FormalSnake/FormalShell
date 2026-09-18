import QtQuick
import qs.Core

// The popover drawer (`emerge: "popover"`, the 2026-09-17 spec's Part 2):
// elementary's own way in. The card is a plain `Box` of the consumer's role,
// resting where the drawer's rect says, and it drops into place out of the
// cell that summoned it: a fade from nothing over a `Theme.space.md` travel
// toward rest, on Gala's menu map (`Theme.motion.emerge`, the table's own
// clock), running backwards on the way out.
//
// What the joined recipe does and this one does not, all of it for the same
// reason, that this card never touches the line: no `Joint`, so no gap is
// published and the bar's own hairline stays whole under an open panel; no
// `Shoulders`, so the card is a rounded rectangle on all four sides; no
// slit, so the card's casts reach past its own rect and draw; and no
// `Deform`, since nothing here arrives at a surface to squash into.
Item {
    id: root

    // The facade this draws for; see Components/Drawer.qml.
    required property var drawer

    readonly property alias frameItem: frame
    readonly property rect frameRect: Qt.rect(frame.x + root.drawer.origin.x,
        frame.y + root.drawer.origin.y, frame.width, frame.height)
    readonly property alias contentHost: inner

    // The drop itself, and the whole of it: a card this far off its rest is
    // still legible under the fade, and any further reads as the card
    // arriving from somewhere it was never summoned from.
    readonly property real travelExtent: Theme.space.md

    // No line, so nothing to attach to; `Drawer` hands a consumer the
    // floating join instead.
    readonly property var joint: null

    Box {
        id: frame
        role: root.drawer.role
        radius: Math.round(root.drawer.radius)
        padding: root.drawer.padding
        x: root.drawer.rect.x - root.drawer.origin.x
        y: root.drawer.rect.y - root.drawer.origin.y
        width: root.drawer.rect.width
        height: root.drawer.rect.height
        opacity: root.drawer.presence.opacity * root.drawer.frameOpacity

        // A move that comes with a resize (a measured panel widening, a
        // route changing the card's height) travels rather than jumps, on
        // the same clock and curve the size itself rides.
        Behavior on x {
            enabled: root.drawer.travel
            Anim {}
        }

        Behavior on y {
            enabled: root.drawer.travel
            Anim {}
        }

        transform: Translate {
            x: root.drawer.presence.emergeX
            y: root.drawer.presence.emergeY
        }

        // What `Card`'s own default slot does: the contents inside the
        // card's padding, reaching back out through it by negative margins
        // where they need to.
        Item {
            id: inner
            anchors.fill: parent

            // Swallows clicks anywhere inside the frame (the card's own
            // padding included) before they reach the backdrop the consumer
            // put this drawer in: ordinary nested MouseArea priority, no
            // manual event plumbing. Every button, so a right-click on the
            // card cannot dismiss it either.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -root.drawer.padding
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }
        }
    }
}
