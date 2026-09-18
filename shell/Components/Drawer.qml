import QtQuick
import qs.Core

// The drawer every edge-anchored card is (DESIGN.md §1 "Motion", M57 D4),
// and since M60 T2 the facade over two recipes rather than one of them: a
// consumer fills a window with one of these, states the edge it comes out
// of and its resting rect, and puts its contents in the default slot. Which
// shape that takes is the live theme's `emerge` habit and never a theme
// name: `join` (Components/DrawerJoin.qml) is the metamorphosis, a card
// budding off the line it came out of; `popover`
// (Components/DrawerPopover.qml) is elementary's, a card dropping out of
// its cell with the line left whole. A window that is a band along its own
// edge rather than the whole output states `origin` with it, and nothing
// else changes either way.
//
// What stays here is the contract and the one clock behind it: the
// `Presence` both recipes are a function of, the contents, and the
// read-outs a consumer binds to. A recipe reads this object, draws, and
// hands back its frame; nothing a consumer touches moved.
Item {
    id: root

    // The surface this drawer belongs to, for the registry: a join is
    // cleared by its owner alone, and a card hanging off this one finds its
    // gap by this key.
    required property var owner
    property bool open: false
    // The card's OWN anchored side, the one that meets the line.
    property string edge: "top"
    // Where the card is right now, in the OUTPUT's own coordinates, whatever
    // window this item sits in.
    property rect rect: Qt.rect(0, 0, 0, 0)
    // And where this item's own top left sits on that output. A consumer
    // filling the output leaves it at zero; one filling a band along its own
    // edge (Surfaces/Osd/Osd.qml) states it, so the line, the slit and the
    // gap published to the line stay in the output's coordinates while
    // everything drawn moves into the band's.
    property point origin: Qt.point(0, 0)
    // And where it rests, which is the rect every derived number is taken
    // from. They part company only while a consumer is drawing its own
    // trajectory (Panel's handoff), where a card mid-travel would otherwise
    // wall and unwall itself as it goes.
    property rect restRect: root.rect
    property var screen: null
    // The surface this card hangs off rather than the screen's own line, if
    // any: it opens the gap in its own far edge and lends the span this card
    // may bud from.
    property var target: null
    // A consumer's veto on joining at all. The line itself is derived, so
    // this is for a surface that has one and must not use it (a card being
    // handed over).
    property bool joined: true
    // Whether a side of the card resting closer than `radius` to the end of
    // its line runs out to it (M57 D2). Off for the notification centre,
    // which rests a `screenPadding` off either end of its line and has never
    // run out to them.
    property bool walls: true
    // Which box in the theme's table the card is a shape of, and its corner:
    // the chrome is the table's, the radius the consumer's, since every
    // number derived from it here is geometry.
    property string role: "card"
    // The clock the entrance rides, when the theme's table names one for
    // this card rather than the habit's own (Components/Presence.qml).
    property string clock: ""
    property real radius: Theme.box(root.role).radius
    property real padding: Theme.space.panelPadding
    property bool bypass: false
    property bool mapped: true
    // A second term on the frame's opacity, for a card that is cut rather
    // than faded (Panel's handed-over half).
    property real frameOpacity: 1
    // Whether a change of place travels rather than jumps. A fresh open has
    // to land where it belongs instead of gliding there from wherever the
    // last one left the card, so the consumer owns the gate.
    property bool travel: false
    // Anything else the consumer is moving that the deform has to see: its
    // own size morphs, a handoff's travel.
    property bool moving: false
    property real deformAmount: 0.15
    // A card in the middle of the output rather than on an edge (the window
    // switcher, `edge: "center"`): there is no line to join, and the join
    // recipe's geometry is cut per edge, so it takes the popover's under
    // every habit, which with no edge to drop from is a fade on `clock`.
    property bool floating: false

    default property alias content: host.data

    readonly property alias presence: presence
    // The join, for the scrim that dims the band a card is still attached
    // to. A recipe with no line to join hands back the floating one below,
    // so a consumer reads `attach` without asking which habit is live.
    readonly property var joint: (recipe.item && recipe.item.joint)
        ? recipe.item.joint : root._floating
    // The frame item itself, for a HoverHandler over the card's whole box or
    // a handoff reading where it is.
    readonly property Item frameItem: recipe.item ? recipe.item.frameItem : root
    // And its rect in the output's coordinates, which is what a handoff hands
    // over and what a child buds from.
    readonly property rect frameRect: recipe.item
        ? recipe.item.frameRect : Qt.rect(0, 0, 0, 0)

    readonly property bool _popover: root.floating || Theme.habit.emerge === "popover"

    // A card that never meets a line: nothing attached, nothing published.
    readonly property QtObject _floating: QtObject {
        readonly property real attach: 0
    }

    // The frame's enter/exit recipe (Presence.qml, DESIGN.md §1 "Motion"),
    // shared by both habits so a consumer's `presence.shown`,
    // `presence.settled` and `presence.contentOpacity` mean what they always
    // did. The travel is the recipe's own: the whole shape behind the line
    // for a join, the few pixels a popover drops through.
    Presence {
        id: presence
        open: root.open
        bypass: root.bypass
        clock: root.clock
        edge: root.edge
        // The travel waits for the surface: a cold window takes long enough
        // to come up that an emerge started on the open would be over before
        // anything of it was on screen.
        mapped: root.mapped
        mode: root._popover ? "popover" : "emerge"
        extent: recipe.item ? recipe.item.travelExtent : 0
    }

    Component {
        id: joinRecipe

        DrawerJoin {
            drawer: root
        }
    }

    Component {
        id: popoverRecipe

        DrawerPopover {
            drawer: root
        }
    }

    Loader {
        id: recipe
        anchors.fill: parent
        sourceComponent: root._popover ? popoverRecipe : joinRecipe
    }

    // The contents, held here and parented into whichever recipe is loaded:
    // the slot a consumer fills has to be the drawn one, and where a card's
    // own padding sits is the recipe's business.
    Item {
        id: host
        parent: recipe.item ? recipe.item.contentHost : root
        anchors.fill: parent
    }
}
