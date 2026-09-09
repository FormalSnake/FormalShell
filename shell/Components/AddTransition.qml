import QtQuick
import qs.Core

// The `add` half of the layout rule (DESIGN.md §1 "Motion", M53 D2): an item
// a positioner has just taken in fades up where it lands rather than being
// there already. Opacity only, on the enter curve: the slot it arrives in is
// the one the siblings around it have just travelled to open, so a new row
// that also slid in from somewhere would be two movements telling one story.
Transition {
    NumberAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.motion.standard
        easing.type: Theme.motion.easing
    }
}
