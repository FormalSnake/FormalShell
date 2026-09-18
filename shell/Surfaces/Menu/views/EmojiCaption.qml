import QtQuick
import qs.Components

// What the cursor cell is (M48 D5). A grid cell is a picture with no room
// for a name, so the name goes here, under the grid and above the footer,
// where it changes as the cursor moves rather than waiting for a pointer to
// hover something. Absent entirely (zero height, no reserved gutter) on
// every other route.
SectionLabel {
    id: root

    // The route's own answer, read by the height and the gap rather than
    // by `visible`, which now outlives it while the band closes.
    property bool wanted: false
    // Gates the open/close Behavior below: an open seeds this at the
    // landing level's height and a close freezes it, so neither is a
    // change to glide.
    property bool animGate: false

    height: root.wanted ? implicitHeight : 0
    visible: root.wanted || root.height > 0
    clip: true
    elide: Text.ElideRight

    // The caption's band on the card's clock (M54 D10), on the same gate as
    // the morphs: Menu.qml's `_captionBand` reads this height straight into
    // `_cardHeight`, so the card's own edge and the band travel together.
    Behavior on height {
        enabled: root.animGate
        Anim {}
    }
}
