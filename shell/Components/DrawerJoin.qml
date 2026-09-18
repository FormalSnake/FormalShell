import QtQuick
import qs.Core
import "drawer.js" as Geometry
import "../Bar/layout.js" as BarLayout
import "../Frame/geometry.js" as FrameGeometry

// The joined drawer (`emerge: "join"`, DESIGN.md §1 "Motion", M57 D4): the
// `Joint`, the `Deform`, the slit the card comes out of, the travelled
// frame, the deformed card and its `Shoulders`, assembled once. `Drawer`
// loads one of these by the theme's own habit and states the edge, the
// resting rect and the surface this card hangs off; everything between the
// line and the card's own padding is here.
//
// What follows from those statements, and so is never stated: where that
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
// than passing over it. Along the line it is the contents alone that close
// onto the bud a nested card is clamped into, under the deform rather than at
// the line, so they come out of the owner's own span rather than beside it
// while the silhouette the deform stretches keeps its border; the contents
// themselves are laid out at the card's full width throughout, and what the
// widening reveals is already drawn.
//
// The deform's matrix goes on an item INSIDE the frame rather than on the
// frame itself: `Deform` samples its target through `mapToItem`, which reads
// back any transform on that target, so sampling and deforming the same item
// would leave the deform driving itself. The frame's own rect is untouched by
// either, so everything measured off it (a handoff, the content, `panel
// state`) is what it was.
Item {
    id: root

    // The facade this draws for: its whole contract is read off it, its
    // `presence` is the clock everything here is a function of, and the
    // contents it holds are parented into `contentHost`.
    required property var drawer

    // The card's own rect, for a handoff reading where it is and for a
    // child budding off its far edge, in the output's own coordinates.
    readonly property alias frameItem: frame
    readonly property rect frameRect: Qt.rect(frame.x + drawer.origin.x,
        frame.y + drawer.origin.y, frame.width, frame.height)
    readonly property alias joint: joint
    readonly property alias contentHost: inner

    // How far behind the line a closed card sits: its own size across the
    // line plus the reach back to it, since the shape hides behind the line
    // with its fillets.
    readonly property real travelExtent: root._restExtent + root._depth

    readonly property bool _vertical: BarLayout.isVertical(drawer.edge)
    readonly property real _screenWidth: drawer.screen ? drawer.screen.width : 0
    readonly property real _screenHeight: drawer.screen ? drawer.screen.height : 0
    readonly property string _screenName: drawer.screen ? drawer.screen.name : ""

    // The owner's own live rect, for the span this card may bud from (M57
    // D3). Live rather than resting: a second bar goes on measuring its cells
    // after the open, and a bud pinned to where the owner was would come away
    // from the gap it budded out of.
    readonly property var _targetRect: (drawer.target && drawer.target.isOpen
        && drawer.target.frameRect !== undefined) ? drawer.target.frameRect : null

    // A line to meet: the owner's far edge, or a band on this edge of the
    // output. A bare edge with neither is no line at all, and the card comes
    // out from behind the output itself.
    readonly property bool _joined: drawer.joined && drawer.screen !== null
        && (root._targetRect !== null || Theme.edgeInset[drawer.edge] > 0)

    // The card's own size across the line, which is both how far behind it a
    // closed card sits and what the depth back to the line is weighed against.
    readonly property real _restExtent: Geometry.across(drawer.edge, drawer.restRect)

    readonly property real _borderWidth: {
        var box = Theme.box(drawer.role);
        return box.border ? box.border.width : 0;
    }

    readonly property real _lineAt: Geometry.lineAt(drawer.edge, root._screenWidth,
        root._screenHeight, Theme.edgeInset, root._targetRect)
    // The reach back to that line, which a card takes whether or not there is
    // anything drawn on it to join: an edge with no bar and no ring is still
    // the output's own, and a card resting hundreds of pixels in from it has
    // to come out from behind it rather than wipe out of an empty row at its
    // own edge. With no line to join, `Joint` pins `attach` at 0 and the
    // shape is the card's own rect drawn inside a taller item. The reach
    // goes one border past the line, the row the line itself paints, and
    // that thickness is the card's own: it is the border `Shoulders` holds
    // the fill in from while the card is attached.
    readonly property real _depth: drawer.screen
        ? Geometry.depth(drawer.edge, drawer.restRect, root._lineAt, root._borderWidth)
        : 0

    // Where on the travel the card lets go of the line. The let-go is a clock
    // of its own started at that mark, so the two overlap by less and less the
    // further the card has to come: a card still on the line four fifths of
    // the way through a long travel finishes well after the travel itself
    // does, and the open reads as slower for it. Scaled by how deep the line
    // is against the card's own size across it, so a panel a `barMargin` off
    // the bar keeps the mark the join was drawn against and a centre-floating
    // card hundreds of pixels down the output takes the early one.
    readonly property real _releaseAt: 0.85 - 0.35 * Math.max(0, Math.min(1,
        root._depth / Math.max(1, root._restExtent)))

    readonly property var _band: Geometry.clipAlong(
        Geometry.clipBand(drawer.edge, Geometry.cut(drawer.edge, drawer.restRect, root._depth),
            root._screenWidth, root._screenHeight),
        drawer.edge, joint.spanClip)

    // And the bud the contents are held to inside the card, which is applied
    // under the deform rather than at the line; see `budRect`.
    readonly property var _bud: Geometry.budRect(drawer.edge, root.frameRect, joint.budClip)

    // A card coming out of THIS one, for the gap in the far edge's border.
    readonly property var _childJoin: PanelRegistry.joinOn(drawer.edge, root._screenName, drawer.owner)

    // The corner a walled side runs into (M57 D2): the frame ring ends the
    // line this card comes out of and the line it runs into in one rounded
    // corner, and the silhouette follows it rather than squaring it off over
    // the band inside it. The ring's own number, off the same geometry the
    // ring is drawn from, so a `frame.radius` change carries. An output edge
    // with no ring on it ends square and the run-out goes a radius past the
    // screen, which is where it has always gone.
    readonly property real _wallRadius: (Theme.frameEnabled && drawer.screen)
        ? FrameGeometry.frameGeometry(root._screenWidth, root._screenHeight,
            Theme.edgeInset, Theme.frameRadius).radius
        : 0

    // The join itself (Components/Joint.qml): the silhouette drawn from the
    // line rather than travelling with the frame, the let-go once the card is
    // nearly at rest, and the gap published to the line (Core/PanelRegistry.qml,
    // Surfaces/Bar/Bar.qml, Surfaces/Frame/FrameRing.qml). The rect along the
    // line is read off the frame's live rect rather than its resting place, so
    // a size morph and a handoff travel both carry the gap with them frame by
    // frame.
    Joint {
        id: joint
        owner: drawer.owner
        presence: drawer.presence
        edge: drawer.edge
        joined: root._joined
        target: drawer.target
        targetAlong: root._targetRect ? Geometry.alongStart(drawer.edge, root._targetRect) : 0
        targetLength: root._targetRect ? Geometry.alongLength(drawer.edge, root._targetRect) : 0
        targetRadius: (drawer.target && drawer.target.frameRadius !== undefined)
            ? drawer.target.frameRadius : 0
        depth: root._depth
        releaseAt: root._releaseAt
        radius: drawer.radius
        extent: Geometry.across(drawer.edge, root.frameRect)
        along: Geometry.alongStart(drawer.edge, root.frameRect)
        length: Geometry.alongLength(drawer.edge, root.frameRect)
        screen: root._screenName
        restAlong: Geometry.alongStart(drawer.edge, drawer.restRect)
        restLength: Geometry.alongLength(drawer.edge, drawer.restRect)
        across: root._vertical ? drawer.restRect.x : drawer.restRect.y
        // The one gate on the wall rule: a line with no length to it is a
        // line with no ends for the card to run into.
        outputAlong: drawer.walls ? (root._vertical ? root._screenHeight : root._screenWidth) : 0
        insetStart: root._vertical ? Theme.edgeInset.top : Theme.edgeInset.left
        insetEnd: root._vertical ? Theme.edgeInset.bottom : Theme.edgeInset.right
    }

    // The card squashes into the line as it arrives and springs back (M54 D7).
    Deform {
        id: deform
        target: frame
        edge: drawer.edge
        // The consumer's figure is the squash it wants on arrival, and a deep
        // drawer arrives faster: it covers its own extent AND the depth back
        // to the line inside one clock, so the same figure squashes a
        // centre-floating card half again as hard as a panel a `barMargin`
        // off the bar, and leaves its spring unwinding long after the travel
        // has stopped. Scaled back by that ratio, so what a consumer states
        // is what the card does however far it has come.
        amount: drawer.deformAmount * root._restExtent
            / Math.max(1, root._restExtent + root._depth)
        // The pivot on the line rather than on the card's own edge, which is
        // behind the line for most of the travel: the card squashes into the
        // bar, and the shoulders, pinned to the line, stay on it under the
        // matrix. Back on the card's edge once it has let go.
        inset: joint.pivotInset
        // And pinned along the line to the wall a walled card runs into, so
        // the squash cannot pull the run-out off it.
        alongPivot: joint.alongPivot
        active: !drawer.presence.settled || drawer.moving || frameX.running || frameY.running
    }

    Item {
        id: clipper
        x: root._band.x - drawer.origin.x
        y: root._band.y - drawer.origin.y
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
                x: drawer.rect.x - drawer.origin.x
                y: drawer.rect.y - drawer.origin.y
                width: drawer.rect.width
                height: drawer.rect.height
                // The card is displaced toward the line by its whole extent
                // while closed and travels out from under `clipper`'s cut,
                // with no fade and no zoom of its own, so what opens is a card
                // coming out of the bar rather than one materialising under
                // it.
                opacity: drawer.presence.opacity * drawer.frameOpacity

                // A move that comes with a resize (a centred frame growing, a
                // measured panel widening, the owner under it changing height)
                // travels rather than jumps, on the same clock and curve the
                // size itself rides.
                Behavior on x {
                    enabled: drawer.travel
                    Anim { id: frameX }
                }

                Behavior on y {
                    enabled: drawer.travel
                    Anim { id: frameY }
                }

                transform: Translate {
                    x: drawer.presence.emergeX
                    y: drawer.presence.emergeY
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
                        edge: drawer.edge
                        radius: drawer.radius
                        role: drawer.role
                        attach: joint.attach
                        nearInset: joint.nearInset
                        wallStart: joint.wallStart
                        wallEnd: joint.wallEnd
                        wallRadius: root._wallRadius
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
                            ? (drawer.edge === "left"
                                ? joint.slide - root._depth
                                : frame.width + root._depth - joint.slide - frameShape._span)
                            : frameShape._along
                        y: root._vertical
                            ? frameShape._along
                            : (drawer.edge === "top"
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
                            - Geometry.alongStart(drawer.edge, root.frameRect)
                        readonly property real _length: joint.clampedLength + frameShape.overhang * 2
                    }

                    // Cut at the card's own rect, and along the line at the
                    // bud the silhouette is clamped into while it is attached
                    // (M57 D3): contents size to their own target the instant
                    // a route changes while the rect trails behind on its
                    // morph, so without this the taller instant would paint
                    // past an edge still catching up (M51 D5), and the same
                    // cut is what makes a card that grows a reveal. The
                    // silhouette is longer and deeper than the rect by
                    // construction and is drawn outside it, uncut: it is
                    // already the bud's own shape, and a cut taken from the
                    // undeformed rect is one the deform carries it past on a
                    // fast widening, taking its border with it.
                    Item {
                        id: contentClip
                        x: root._bud.x
                        y: root._bud.y
                        width: root._bud.width
                        height: root._bud.height
                        clip: true

                        // The card's own coordinates back, so the contents
                        // keep their full-width layout inside the bud and the
                        // widening reveals what is already drawn.
                        Item {
                            x: -contentClip.x
                            y: -contentClip.y
                            width: frame.width
                            height: frame.height

                            // What `Card`'s own default slot does: the
                            // contents inside the card's padding, reaching
                            // back out through it by negative margins where
                            // they need to.
                            Item {
                                id: inner
                                anchors.fill: parent
                                anchors.margins: drawer.padding

                                // Swallows clicks anywhere inside the frame
                                // (the card's own padding included) before
                                // they reach the backdrop the consumer put
                                // this drawer in: ordinary nested MouseArea
                                // priority, no manual event plumbing. Every
                                // button, so a right-click on the card cannot
                                // dismiss it either.
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -drawer.padding
                                    acceptedButtons: Qt.AllButtons
                                    onClicked: {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
