import QtQuick

// One tooltip's worth of state, shared by every item on an output (M53
// D10). A cell no longer owns a card of its own: it asks the group on its
// output to describe its item, and the group decides whether that costs
// the show delay or lands on the frame the pointer arrived.
//
// The rule it encodes is Emil Kowalski's, and Vercel's own tooltips read
// the same way: the first tooltip in a group waits, the rest do not.
// `grace` is how long after a hide the group still counts as being walked
// through, so a pointer crossing the bar pays the delay once instead of
// once per cell, and each hand-off is one card moving rather than a fade
// out, dead time, and a fade in somewhere else.
//
// `delay` is deliberately not motion (a card that appeared the instant the
// pointer crossed a cell would flash on every pass along the bar), so it
// holds with `motion.enabled: false` exactly as it did when every cell
// owned a card. Nothing delays the way out: hide() is immediate.
//
// No Quickshell types here. The surface (Tooltip.qml) is a layer-shell
// window, this is the bookkeeping it draws, and the split is what lets
// tst_tooltip_group.qml drive the whole state machine under a plain
// qmltestrunner.
QtObject {
    id: root

    // What the surface draws: the item the card describes, the line it
    // carries, and the bar edge it opens away from (Cell.barEdge, empty off
    // the bar). Committed rather than pending, and left alone by a hide, so
    // the card keeps describing what it is still drawing on the way out.
    property Item anchorItem: null
    property string text: ""
    property string barEdge: ""
    property bool shown: false

    // Whether the card is on screen at all, exit fade included: the surface
    // binds this to its own Presence. A show landing while it is true is a
    // hand-off, and the card travels to the new item; one landing while it
    // is false is an entrance at the new item.
    property bool drawn: false

    // Read by the surface's own geometry Behaviors, which is why it is set
    // before the commit rather than derived after it: a card that is not
    // changing hands has to take its new rect in one frame, not glide in
    // from wherever the last one stood.
    property bool travel: false

    // omarchy's own tooltip delay, read as a reference
    // (omarchy/shell/Ui/PanelToolTip.qml's `delay: 400`).
    readonly property int delay: 400
    readonly property int grace: 500

    // The surface measures the item's rect off this rather than binding to
    // it: mapToItem is not reactive (quickshell documents that of the whole
    // map* family), and every commit is a new rect to capture.
    signal commit()

    // Who owns the group right now, shown or still waiting the delay out.
    // Separate from `anchorItem` above for the exit fade's sake.
    property Item _target: null
    property string _pendingText: ""
    property string _pendingEdge: ""

    property Timer _delayTimer: Timer {
        id: delayTimer
        interval: root.delay
        onTriggered: {
            if (root._target)
                root._commit();
        }
    }

    // Runs from a hide, never from a show: it is the window inside which
    // the NEXT item skips the delay.
    property Timer _graceTimer: Timer {
        id: graceTimer
        interval: root.grace
    }

    function show(item, text, barEdge) {
        if (!item || text === "")
            return;
        root._pendingText = text;
        root._pendingEdge = barEdge;
        // The same item again is a value ticking under a parked pointer (a
        // volume readout, a battery estimate), never a fresh show: it must
        // not restart the delay, and it reaches the card live once the card
        // is up.
        if (item === root._target) {
            if (root.shown) {
                root.text = text;
                root.barEdge = barEdge;
            }
            return;
        }
        root._target = item;
        if (root.shown || root.drawn || graceTimer.running) {
            delayTimer.stop();
            root._commit();
        } else {
            delayTimer.restart();
        }
    }

    // `item` is the one asking, so a leave fired by a cell the pointer has
    // already moved off cannot drop the card the next cell just took.
    function hide(item) {
        if (item && item !== root._target)
            return;
        delayTimer.stop();
        // Only a card that actually stood opens the grace window: a pointer
        // crossing cells faster than the delay has shown nothing, and every
        // cell it passes should still have to wait its turn.
        if (root.shown)
            graceTimer.restart();
        root.shown = false;
        root._target = null;
    }

    // A cell destroyed under a card it owns (a bar layout change, a plugin
    // rescan) nulls both handles on it, which leaves the surface drawing a
    // rect nothing stands at any more.
    onAnchorItemChanged: {
        if (!root.anchorItem && root.shown)
            root.hide(null);
    }

    function _commit() {
        root.travel = root.drawn;
        root.anchorItem = root._target;
        root.text = root._pendingText;
        root.barEdge = root._pendingEdge;
        root.commit();
        root.shown = true;
    }
}
