import QtQuick

// The `add` half of the layout rule (DESIGN.md §1 "Motion", M53 D2): an item
// a positioner has just taken in fades up where it lands rather than being
// there already. Opacity only, so `effects`: the slot it arrives in is the
// one the siblings around it have just travelled to open, and a new row that
// also slid in from somewhere would be two movements telling one story.
Transition {
    Anim {
        kind: "effects"
        property: "opacity"
        from: 0
        to: 1
    }
}
