import QtQuick
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components
import "../../../Bar/tray.js" as TrayFit

// Bar region for the SNI tray (DESIGN.md §Bar, spec §Surfaces-1, M10 Task 1).
// Quickshell.Services.SystemTray both hosts and watches
// org.kde.StatusNotifierWatcher once referenced (its own module doc: merely
// referencing the singleton "will make quickshell start tracking system
// tray contents"), so every real StatusNotifierItem registered on the
// session bus shows up in .items with no extra wiring on our end. Each item
// renders as its own standalone TrayCell.
//
// M32: the menu is TrayMenu.qml (`menu` below, one shared instance wired in
// from shell.qml/Bar.qml), a shell-owned QsMenuOpener surface, not the old
// QsMenuAnchor/native-QMenu path this file used to open directly. That
// native QMenu was also an xdg_popup with its own keyboard+pointer grab
// (platformmenu.cpp); Hyprland's grab code never adds the layer-shell parent
// to the grab's accept set on the path Qt takes to map it (`m_parent` stays
// null, XDGShell.cpp), and its popup grab is pointer+keyboard rather than
// keyboard-only, so a click anywhere outside the accept set, including the
// tray icon's own pixmap, inside the same Cell's hit area the surrounding
// padding shares, tore the grab down and closed the menu instantly (the same
// shell worked before the owner's hosts moved to Hyprland, 2026-08-17). A
// layer-shell popout takes no such grab, so this class of bug is gone by
// construction rather than patched.
// Hidden entirely (the rail's implicit extent is naturally 0 with nothing
// visible in it) when nothing has registered, never an empty box.
//
// The strip is not allowed to run out from under the rest of the bar: a tray
// that does not fit moves WHOLE into a second bar hanging off this rail's own
// toggle (TrayOverflow.qml), the way Ice and Bartender give the macOS menu
// bar a second row rather than letting the tray eat the clock. All or
// nothing (owner, 2026-08-28): the strip shows every icon or it shows the
// toggle alone, never some of each, so one tray never reads across two
// surfaces and the cut never moves under the user when something else on the
// bar resizes.
//
// By default it is the toggle, on any bar, with room or without it (owner,
// 2026-08-28): the dots are where the tray lives, not a state a crowded bar
// falls into. `tray.maxVisible` is the whole of the configuration
// (Bar/tray.js): -1 puts as many icons on the strip as fit, N puts up to N
// there, and room still has the last word over both. That room question
// alone reads `slackAlong`, what the bar has left over (Bar.qml's own
// `_slack`), so the budget is this rail's current extent plus that: a term
// the answer below cannot move, since anything the rail gives up the slack
// takes back.
//
// Spec deviation, owner's call (M24, the same class as the `panel` IPC
// addendum): spec §Surfaces-1 says "SNI tray (grouped drawer)", and this
// file used to cap the strip at four cells with a "+N" chevron the rest
// collapsed behind. There is still no per-item pinned/drawer/hidden split
// (M23's buckets, removed the day after they shipped) and no user-ordered
// drawer: what overflows is decided by measurement and by one count, never
// per item. Collapsing the WHOLE bar stays the bar's own chevron
// (ChevronWidget.qml), a different affordance at a different altitude.
Rail {
    id: root

    property var menu: null
    // The one shared TrayOverflow instance (shell.qml, through Bar.qml).
    // Null means no second bar was wired in, and the fit below then keeps
    // every item inline rather than hiding items behind a toggle that can
    // open nothing.
    property var overflow: null

    // Room the strip has left over along its own axis, handed in by Bar.qml.
    // Infinity is "nobody has measured a strip yet", which is not a budget
    // and is not answered: the rail waits rather than guessing, and paints
    // nothing until it has a real number (`_refit` below).
    property real slackAlong: Number.POSITIVE_INFINITY

    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity. `.values` is read here for the count alone, never
    // as a model (a fresh JS array snapshot on every read, per Quickshell's
    // own ObjectModel docs; see the Repeater below for why that matters).
    //
    // `shown` is the raw count and nothing else. It must never fall to false
    // (or to a rail that measures 0) while items exist: Bar.qml's region
    // delegate gates a collapsible entry on `_along > 0`, which reads this
    // rail's own implicit extent, and an entry that measures 0 while hidden
    // never produces the width that would reveal it again. That deadlock is
    // this file's, historically (Bar.qml's own comment names it, and
    // tests/tst_bar_entry_reveal.qml pins it), and gating this on the fit
    // walked straight back into it: a tray behind the bar chevron came back
    // from an expand with nothing in its slot at all (owner, 2026-08-28).
    // Whatever the answer is or is not yet, this rail always has a cell in
    // it.
    readonly property int _total: SystemTray.items.values.length
    readonly property bool shown: root._total > 0

    // Bar.qml sets these on the widget it loads; this rail is not a Cell
    // itself, so it hands them to each cell it holds (DESIGN.md §3 Bar).
    property bool ghost: false
    property string barEdge: ""

    // The rail follows the bar: a column on a left or right bar, where
    // Bar.qml's region delegate sizes it across the strip by width rather
    // than height.
    vertical: root.barEdge === "left" || root.barEdge === "right"
    spacing: Theme.space.sm
    visible: root.shown

    // --- The fit ---------------------------------------------------------
    //
    // The rail draws the last ANSWER, never the current inputs. Three
    // properties carry it, all three written by `_refit()` rather than bound,
    // which is the whole reason this converges: the budget the answer comes
    // from reads the rail's own extent, which reads the answer, and a binding
    // round that circle is a loop QML would abort. Assigning makes the pass
    // one-way, and it settles in a single step because the budget cannot move
    // when the answer does (extent + slack is invariant: whatever the rail
    // gives up, the bar's leftover room gains).
    //
    // The cost of assigning is that the answer lands after its inputs, so
    // nothing is drawn from the inputs directly. `_decidedTotal` is the item
    // count the standing answer was worked out for, and it, not `_total`,
    // decides what is on the rail: an icon that arrives and pushes the tray
    // over the edge is never drawn and then taken away, it simply never
    // appears on the strip.
    //
    // Before the first answer the rail is the toggle, which is both where the
    // tray lives by default and the one starting state that is never wrong to
    // look at: it is one cell wide whatever the item count, so nothing
    // rearranges when the answer lands, and it keeps the rail measurable,
    // which `shown` above explains is not optional. Only `-1` and a ceiling
    // ever move off it, and only once (owner, 2026-08-28: "why are you doing
    // it on load").
    property bool _decided: false
    property bool _fits: false
    property int _decidedTotal: 0

    readonly property int _inline: (root._decided && root._fits) ? Math.min(root._decidedTotal, root._total) : 0
    readonly property int _hidden: root._total - root._inline

    // One cell's extent along the strip, measured off the toggle rather
    // than restated as arithmetic here: it is the same square slot every
    // item cell is, it exists whether or not it is visible, and a cell's own
    // implicit size never depends on how many cells there are, so reading it
    // adds nothing to the circle above.
    readonly property real _unit: root.vertical ? overflowCell.implicitHeight : overflowCell.implicitWidth

    // The most icons the strip may carry (`tray.maxVisible`, Bar/tray.js):
    // 0, the default, is none and the tray lives in the second bar. With no
    // second bar wired in there is nowhere to put it, so the ceiling comes
    // off and the strip carries whatever it has.
    readonly property int _ceiling: root.overflow ? Config.get("tray.maxVisible", 0) : -1

    function _refit() {
        // Only the room question needs a measured strip, and Bar.qml hands
        // over an infinite slack until it has one. A slack worked out against
        // a zero-length strip is not a tight budget, it is no answer, and
        // answering it would put the toggle over a tray with room to spare.
        // A ceiling has already decided without it, so a tray that always
        // lives in the second bar never waits for a frame to say so.
        if (TrayFit.needsRoom(root._total, root._ceiling) && !isFinite(root.slackAlong))
            return;
        var own = root.vertical ? root.implicitHeight : root.implicitWidth;
        var fit = TrayFit.fit(root._total, own + root.slackAlong, root._unit, root.spacing,
            root._ceiling);
        root._fits = fit.inline === root._total;
        root._decidedTotal = root._total;
        root._decided = true;
        // Kept current whether or not the second bar is up: it is where the
        // answer is published (TrayIpc's `status`), and a bar left open while
        // the fit moves under it has to follow. Every output's Tray writes
        // the one shared surface, so on a multi-output rig this is whichever
        // bar refitted last until a click sets it to the bar that opened it
        // (openOverflow below).
        if (root.overflow)
            root.overflow.inlineCount = root._inline;
    }

    // Long enough to outlast the one animation that moves this rail's inputs
    // without changing where they end up: the bar chevron's collapse and
    // reveal (Bar.qml's `Behavior on _along`), during which every cell on the
    // governed side is between two widths and the bar's leftover room is
    // whatever the frame happened to catch. Each restart pushes the pass past
    // the last of those, so the answer is worked out once, against the layout
    // the bar settled on, rather than against the room a half-open group has
    // not taken back yet. That was the tray showing every icon through an
    // expand and swapping to the toggle after it (owner, 2026-08-28: "i see
    // all icons, the expand stops, after a few ms i see the three dots").
    // Nothing is drawn from a stale answer meanwhile, since the rail draws
    // `_decidedTotal` and not `_total`.
    Timer {
        id: refitTimer
        interval: Theme.motion.standard + 32
        onTriggered: root._refit()
    }

    Component.onCompleted: refitTimer.restart()
    onSlackAlongChanged: refitTimer.restart()
    on_TotalChanged: refitTimer.restart()
    on_UnitChanged: refitTimer.restart()
    on_CeilingChanged: refitTimer.restart()
    onVerticalChanged: refitTimer.restart()

    function openOverflow() {
        if (!root.overflow)
            return;
        root.overflow.inlineCount = root._inline;
        root.overflow.menu = root.menu;
        root.overflow.toggleFrom(overflowCell);
    }

    // Bound to the live ObjectModel itself, not a `.values` snapshot slice:
    // `.values` returns a fresh array on every read (Quickshell's own
    // docs), and Quickshell re-notifies it far more often than the item set
    // actually changes (observed in-VM: a static 6-item tray still saw each
    // delegate destroyed and recreated 4-7 times over one run). A
    // plain-array `Repeater.model` treats every new array as a full reset,
    // so each icon's async load kept restarting mid-decode before a single
    // frame ever painted, every pinned cell rendered blank. The live model
    // gives Repeater real add/remove diffing instead, so a delegate
    // survives an upstream re-notify that didn't actually add or remove
    // anything. It is also why an overflowing tray is hidden in place rather
    // than sliced out of the model: the second bar renders the same live
    // model (TrayOverflow.qml).
    Repeater {
        model: SystemTray.items

        delegate: TrayCell {
            id: itemCell
            required property var modelData
            required property int index

            item: itemCell.modelData
            menu: root.menu
            ghost: root.ghost
            barEdge: root.barEdge
            visible: itemCell.index < root._inline

            // Bar.qml's region delegate stretches this rail to the bar's
            // shared cell thickness, and a positioner manages position,
            // never size, so the cell's own icon-only content would
            // otherwise measure shorter than that. It binds to the rail's
            // own forced extent (`root` here IS the rail Bar.qml
            // stretches), not `Theme.barThickness`, which routes back
            // through the same implicit-size chain Bar.qml measures this
            // rail by; Workspaces.qml's fix is the same.
            width: root.vertical ? root.width : implicitWidth
            height: root.vertical ? implicitHeight : root.height
        }
    }

    // The second bar's own handle, last on the rail so it sits where the
    // strip runs out. Always instantiated, since `_unit` measures itself off
    // it, and drawn only once the tray has moved behind it, which is also the
    // only time anything else on this rail is drawn at all.
    Cell {
        id: overflowCell
        ghost: root.ghost
        barEdge: root.barEdge
        visible: root._hidden > 0
        width: root.vertical ? root.width : implicitWidth
        height: root.vertical ? implicitHeight : root.height
        tooltipText: "TRAY / " + root._hidden + " ITEMS"
        panelOpen: root.overflow ? root.overflow.isOpen : false

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            // The dots run the way the strip does, so the toggle reads as
            // the rail continuing past its own end rather than as a cell
            // turned on its side.
            name: root.vertical ? "more-vertical" : "ellipsis"
            color: overflowCell.foreground
        }

        interactive: true
        onClicked: root.openOverflow()
    }
}
