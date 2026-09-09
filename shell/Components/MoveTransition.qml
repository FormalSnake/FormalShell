import QtQuick

// The `move` (and `displaced`) half of the layout rule (DESIGN.md §1
// "Motion", M53 D2): an item a positioner re-places because something
// beside it appeared, vanished or changed width travels to its new slot
// instead of arriving there. `spatial`, the default kind, so a bar cell
// sliding along the strip and a panel row sliding down the column read as
// the same movement.
//
// A component rather than an animation per positioner: this is the only
// place the pair of properties is spelled, so a Grid, a Row and a Column
// all move at one rate.
Transition {
    Anim {
        properties: "x,y"
    }
}
