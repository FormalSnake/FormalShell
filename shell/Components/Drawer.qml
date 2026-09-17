import QtQuick
import qs.Core
import "drawer.js" as Geometry
import "../Bar/layout.js" as BarLayout

// The drawer every edge-anchored card is (DESIGN.md §1 "Motion", M57 D4):
// the `Presence`, the `Joint`, the `Deform`, the slit the card comes out of,
// the travelled frame, the deformed card and its `Shoulders`, assembled once.
// A consumer fills a full-output window with one of these, states the edge it
// comes out of and its resting rect, and puts its contents in the default
// slot; everything between the line and the card's own padding is here.
//
// What follows from those two statements, and so is never stated: where that
// edge's line is (the bar's hairline, the frame ring's, or the far edge of
// the surface this card hangs off), the depth the shape reaches back to it,
// the band the card is cut at, which of its sides are walled (M57 D2), the
// span an owner's edge can give it (M57 D3) and the deform's two pivots. A
// surface that moves, resizes or changes edge while it is open is followed
// without being told.
//
// The card's contents travel with the frame, but the silhouette does not: it
// is drawn from the line to the card's far edge, so the fillets sit on the
// line from the first frame and what comes out is one shape budding off the
// strip. The slit is what hides the rest of it: everything the card paints is
// cut at the line, and a closed card is displaced behind that line by its
// whole extent, shoulders included, so it comes out from under the bar rather
// than passing over it. Along the line the band closes onto the bud a nested
// card is clamped into, so its contents come out of the owner's own span
// rather than beside it; the contents themselves are laid out at the card's
// full width throughout, and what the widening reveals is already drawn.
//
// The deform's matrix goes on an item INSIDE the frame rather than on the
// frame itself: `Deform` samples its target through `mapToItem`, which reads
// back any transform on that target, so sampling and deforming the same item
// would leave the deform driving itself. The frame's own rect is untouched by
// either, so everything measured off it (a handoff, the content, `panel
// state`) is what it was.
Item {
    id: root

    // The surface this drawer belongs to, for the registry: a join is
    // cleared by its owner alone, and a card hanging off this one finds its
    // gap by this key.
    required property var owner
    property bool open: false
    // The card's OWN anchored side, the one that meets the line.
    property string edge: "top"
    // Where the card is right now, in the output's own coordinates, which
    // this item shares with it.
    property rect rect: Qt.rect(0, 0, 0, 0)
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
    property real radius: Theme.radiusXl
    property color color: Theme.surface(Theme.color.card)
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

    default property alias content: inner.data

    readonly property alias presence: presence
    readonly property alias joint: joint
    // The frame item itself, for a HoverHandler over the card's whole box or
    // a handoff reading where it is.
    readonly property alias frameItem: frame
    // And its rect in the output's coordinates, which is what a handoff hands
    // over and what a child buds from.
    readonly property rect frameRect: Qt.rect(frame.x, frame.y, frame.width, frame.height)

    readonly property bool _vertical: BarLayout.isVertical(root.edge)
    readonly property real _screenWidth: root.screen ? root.screen.width : 0
    readonly property real _screenHeight: root.screen ? root.screen.height : 0
    readonly property string _screenName: root.screen ? root.screen.name : ""

    // The owner's own live rect, for the span this card may bud from (M57
    // D3). Live rather than resting: a second bar goes on measuring its cells
    // after the open, and a bud pinned to where the owner was would come away
    // from the gap it budded out of.
    readonly property var _targetRect: (root.target && root.target.isOpen
        && root.target.frameRect !== undefined) ? root.target.frameRect : null

    // A line to meet: the owner's far edge, or a band on this edge of the
    // output. A bare edge with neither is no line at all, and the card comes
    // out from behind the output itself.
    readonly property bool _joined: root.joined && root.screen !== null
        && (root._targetRect !== null || Theme.edgeInset[root.edge] > 0)

    readonly property real _lineAt: Geometry.lineAt(root.edge, root._screenWidth,
        root._screenHeight, Theme.edgeInset, root._targetRect)
    readonly property real _depth: root._joined
        ? Geometry.depth(root.edge, root.restRect, root._lineAt, Theme.borderWidth)
        : 0

    readonly property var _band: Geometry.clipAlong(
        Geometry.clipBand(root.edge, Geometry.cut(root.edge, root.restRect, root._depth),
            root._screenWidth, root._screenHeight),
        root.edge, joint.clip)

    // A card coming out of THIS one, for the gap in the far edge's border.
    readonly property var _childJoin: PanelRegistry.joinOn(root.edge, root._screenName, root.owner)

    // The frame's enter/exit recipe (Presence.qml, DESIGN.md §1 "Motion"): a
    // drawer out of the line's edge. The extent is the whole shape and not
    // just the card, the fillets reaching `_depth` further toward the line,
    // so a closed card sits behind it with those too.
    Presence {
        id: presence
        open: root.open
        bypass: root.bypass
        edge: root.edge
        // The travel waits for the surface: a cold window takes long enough
        // to come up that an emerge started on the open would be over before
        // anything of it was on screen.
        mapped: root.mapped
        mode: "emerge"
        extent: Geometry.across(root.edge, root.restRect) + root._depth
    }

    // The join itself (Components/Joint.qml): the silhouette drawn from the
    // line rather than travelling with the frame, the let-go once the card is
    // nearly at rest, and the gap published to the line (Core/PanelRegistry.qml,
    // Surfaces/Bar/Bar.qml, Surfaces/Frame/FrameRing.qml). The rect along the
    // line is read off the frame's live rect rather than its resting place, so
    // a size morph and a handoff travel both carry the gap with them frame by
    // frame.
    Joint {
        id: joint
        owner: root.owner
        presence: presence
        edge: root.edge
        joined: root._joined
        target: root.target
        targetAlong: root._targetRect ? Geometry.alongStart(root.edge, root._targetRect) : 0
        targetLength: root._targetRect ? Geometry.alongLength(root.edge, root._targetRect) : 0
        targetRadius: (root.target && root.target.frameRadius !== undefined)
            ? root.target.frameRadius : 0
        depth: root._depth
        radius: root.radius
        extent: Geometry.across(root.edge, root.frameRect)
        along: Geometry.alongStart(root.edge, root.frameRect)
        length: Geometry.alongLength(root.edge, root.frameRect)
        screen: root._screenName
        restAlong: Geometry.alongStart(root.edge, root.restRect)
        restLength: Geometry.alongLength(root.edge, root.restRect)
        across: root._vertical ? root.restRect.x : root.restRect.y
        // The one gate on the wall rule: a line with no length to it is a
        // line with no ends for the card to run into.
        outputAlong: root.walls ? (root._vertical ? root._screenHeight : root._screenWidth) : 0
        insetStart: root._vertical ? Theme.edgeInset.top : Theme.edgeInset.left
        insetEnd: root._vertical ? Theme.edgeInset.bottom : Theme.edgeInset.right
    }

    // The card squashes into the line as it arrives and springs back (M54 D7).
    Deform {
        id: deform
        target: frame
        edge: root.edge
        amount: root.deformAmount
        // The pivot on the line rather than on the card's own edge, which is
        // behind the line for most of the travel: the card squashes into the
        // bar, and the shoulders, pinned to the line, stay on it under the
        // matrix. Back on the card's edge once it has let go.
        inset: joint.pivotInset
        // And pinned along the line to the wall a walled card runs into, so
        // the squash cannot pull the run-out off it.
        alongPivot: joint.alongPivot
        active: !presence.settled || root.moving || frameX.running || frameY.running
    }

    Item {
        id: clipper
        x: root._band.x
        y: root._band.y
        width: root._band.width
        height: root._band.height
        clip: true

        // Puts the output's own coordinates back for everything under it, so
        // the frame's x and y stay window coordinates rather than becoming
        // offsets into the band.
        Item {
            x: -clipper.x
            y: -clipper.y
            width: root.width
            height: root.height

            // The card's own rect, and nothing drawn: the shape, the contents
            // and the deform all sit inside it, so what this item carries is
            // the geometry every other part of the surface measures itself
            // against, unsquashed.
            Item {
                id: frame
                x: root.rect.x
                y: root.rect.y
                width: root.rect.width
                height: root.rect.height
                // The card is displaced toward the line by its whole extent
                // while closed and travels out from under `clipper`'s cut,
                // with no fade and no zoom of its own, so what opens is a card
                // coming out of the bar rather than one materialising under
                // it.
                opacity: presence.opacity * root.frameOpacity

                // A move that comes with a resize (a centred frame growing, a
                // measured panel widening, the owner under it changing height)
                // travels rather than jumps, on the same clock and curve the
                // size itself rides.
                Behavior on x {
                    enabled: root.travel
                    Anim { id: frameX }
                }

                Behavior on y {
                    enabled: root.travel
                    Anim { id: frameY }
                }

                transform: Translate {
                    x: presence.emergeX
                    y: presence.emergeY
                }

                // Everything drawn, under the deform's matrix (M54 D7): the
                // frame and its contents squash together, so the card stays
                // one object rather than a shape with a rigid list inside it.
                Item {
                    id: deformed
                    anchors.fill: parent
                    transform: Matrix4x4 { matrix: deform.matrix }

                    // The card (M54 D6, Components/Shoulders.qml): joined to
                    // the line, its three free edges rounded, the edge facing
                    // the line open, and a concave fillet outside each of that
                    // edge's corners running out to the gap the line opened;
                    // let go, the plain card `Card` draws. Longer by a fillet
                    // at either end than the rect it is drawn on, which is the
                    // card's own once it has let go and the bud its owner's
                    // edge can give while it is attached (`joint.clampedAlong`,
                    // M57 D3), and pinned to the line rather than to the frame:
                    // `joint.slide` undoes the frame's own travel on the
                    // anchored axis and `joint.shapeDepth` is what is out from
                    // under the line, so at rest it is the card plus `_depth`,
                    // and mid travel a shorter shape whose far edge is still
                    // the card's.
                    Shoulders {
                        id: frameShape
                        edge: root.edge
                        radius: root.radius
                        color: root.color
                        attach: joint.attach
                        nearInset: joint.nearInset
                        wallStart: joint.wallStart
                        wallEnd: joint.wallEnd
                        // A gap in the far edge's border for the card hanging
                        // off this one, its rect along the line put into this
                        // item's own coordinates.
                        farGap: {
                            var j = root._childJoin;
                            if (!j)
                                return null;
                            return [j.x - j.reach - frameShape._origin,
                                j.x + j.width + j.reach - frameShape._origin];
                        }
                        x: root._vertical
                            ? (root.edge === "left"
                                ? joint.slide - root._depth
                                : frame.width + root._depth - joint.slide - frameShape._span)
                            : frameShape._along
                        y: root._vertical
                            ? frameShape._along
                            : (root.edge === "top"
                                ? joint.slide - root._depth
                                : frame.height + root._depth - joint.slide - frameShape._span)
                        width: root._vertical ? frameShape._span : frameShape._length
                        height: root._vertical ? frameShape._length : frameShape._span

                        // What the item spans across the line: from the line to
                        // the card's far edge, and one more fillet past it while
                        // a side is walled, for the concave corner that side
                        // carries against the wall.
                        readonly property real _span: joint.shapeDepth + frameShape.farOverhang

                        // And along it: the card's own rect at rest, the bud its
                        // owner's edge can give while it is attached, a fillet
                        // past either end either way. `_origin` is where that
                        // starts in the output's own coordinates, which is what
                        // a gap published against this card is measured in.
                        readonly property real _origin: joint.clampedAlong - frameShape.overhang
                        readonly property real _along: frameShape._origin
                            - Geometry.alongStart(root.edge, root.frameRect)
                        readonly property real _length: joint.clampedLength + frameShape.overhang * 2
                    }

                    // What `Card`'s own default slot does: the contents inside
                    // the card's padding, reaching back out through it by
                    // negative margins where they need to.
                    Item {
                        id: inner
                        anchors.fill: parent
                        anchors.margins: root.padding

                        // Swallows clicks anywhere inside the frame (the card's
                        // own padding included) before they reach the backdrop
                        // the consumer put this drawer in: ordinary nested
                        // MouseArea priority, no manual event plumbing.
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -root.padding
                            onClicked: {}
                        }
                    }
                }
            }
        }
    }
}
