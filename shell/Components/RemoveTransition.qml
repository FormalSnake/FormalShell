import QtQuick
import qs.Core

// The `remove` half of the layout rule (DESIGN.md §1 "Motion", M53 D2/D6): a
// row the model has stopped holding fades where it stood while the rows below
// it travel up into its slot, rather than the whole list snapping shut around
// it. Opacity only, on the exit clock, so a leaving row is gone by the time
// the move that explains its going has finished.
//
// The item is still on screen after the model has released it, so a view
// using this must resolve what a delegate draws by identity rather than by
// index, and must put the delegate's opacity back when it is pooled.
Transition {
    NumberAnimation {
        property: "opacity"
        to: 0
        duration: Theme.motion.surfaceExit
        easing.type: Theme.motion.easing
    }
}
