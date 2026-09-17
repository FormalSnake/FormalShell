import QtQuick
import QtQuick.Effects
import qs.Core

// The one chrome renderer (M59 T4): it draws the box its role's entry in
// `Theme.style` describes and knows nothing else. A primitive states which
// role and which state it is in and keeps its behaviour (the pointer, the
// measurement, the morphs); what a fill, a border, a gradient, a hairline,
// a ring or a cast look like is the theme's answer, in one place, for every
// theme.
//
// Draw order, outermost first: the casts under everything (`z: -1`), the
// rings around the box, the fill with its border, the face gradient and the
// inset hairlines inside it, and the pointer's wash over the lot. The
// border rides on the fill's own Rectangle rather than being a seventh
// layer, which is what keeps a box with no layers and no face costing one
// Rectangle: the face and the hairlines sit a border in from the edge so
// they never paint over it.
//
// Fill and border colours cross on `CAnim`, the way `Cell` and `Button`
// crossed their own ternaries before this file existed: a state change on a
// box already on screen arrives as a colour travelling. `border.width` is
// not in on it, since a border growing from nothing would be the box
// changing shape rather than colour.
Item {
    id: root

    // The role in the table, and the state within it. An unknown state
    // reads as the role's base state (shell/Theme/style.js), so a primitive
    // passes its own state through without knowing which ones a given
    // theme describes.
    //
    // `state` shadows QQuickItem's own on purpose, the same concession
    // Picture.qml makes for `smooth` and Cell.qml for `data`: it is the
    // word the table uses, and a Box declares no `states`, so the item's
    // state machine has nothing to lose by it.
    property string role: ""
    property string state: "rest"

    // What this draws. The role's own entry by default; a surface that
    // resolved a box itself assigns one instead.
    property var box: Theme.box(root.role, root.state)

    // A radius of the consumer's own choosing, -1 for the table's. The
    // concentric rule (a box nested inside a bordered one takes the outer
    // radius minus the padding between them) is geometry, so it belongs to
    // whoever knows that padding.
    property int radius: -1

    // The shape a cast is cast from, for a box that is not a rounded
    // rectangle (`Shoulders`' own outline). ⚠️ This is the DEFAULT slot and
    // it is never drawn: what lands in it is the source and the inverted
    // mask of every cast, nothing more. Content goes in the consumer's own
    // slot (`Card`'s `content`), and an empty slot here falls back to a
    // rounded rectangle of this box's radius.
    default property alias silhouette: silhouetteSlot.data

    // `pill` needs the extent of the thing being drawn, so it survives
    // resolution as itself and lands here.
    readonly property real _radius: root.radius >= 0
        ? root.radius
        : (root.box.radius === "pill"
            ? Theme.pillRadius(Math.min(root.width, root.height))
            : root.box.radius)

    readonly property real _borderWidth: root.box.border ? root.box.border.width : 0
    readonly property color _borderColor: root.box.border ? root.box.border.color : "transparent"

    // How far outside its own rect the widest cast reaches, which is the
    // room the silhouette needs around the box for the blur not to be
    // clipped, and the kernel `shadowBlur` is a fraction of.
    readonly property int _castPad: {
        var pad = 0;
        for (var i = 0; i < root.box.casts.length; i++) {
            var cast = root.box.casts[i];
            pad = Math.max(pad, Math.ceil(cast.blur + Math.abs(cast.spread)
                + Math.max(Math.abs(cast.x), Math.abs(cast.y))));
        }
        return pad;
    }

    // The wash the current state asks for, or null.
    readonly property var washTone: root.box.wash || null

    // Held through the fade out: the wash rect's colour has to stay where
    // it was while its opacity runs down, or a wash would blink out instead
    // of fading.
    property color _heldWash: "transparent"

    onWashToneChanged: if (root.washTone) root._heldWash = root.washTone;

    // The shape every cast is cast from, padded for the blur and never
    // drawn: `visible: false` with a layer of its own is what makes it a
    // texture rather than a picture (the same pairing LyricsPane's sung-word
    // mask uses). The white is mask alpha, not a colour.
    Item {
        id: silhouetteLayer
        anchors.fill: parent
        anchors.margins: -root._castPad
        visible: false
        layer.enabled: root.box.casts.length > 0

        Loader {
            anchors.fill: parent
            anchors.margins: root._castPad
            active: root.box.casts.length > 0 && silhouetteSlot.children.length === 0
            sourceComponent: Rectangle {
                color: "white"
                radius: root._radius
            }
        }

        Item {
            id: silhouetteSlot
            anchors.fill: parent
            anchors.margins: root._castPad
        }
    }

    // One cast per blurred layer. The shadow is cast from the silhouette
    // and the silhouette is then masked back out of it (`maskInverted`), so
    // a translucent card keeps the blurred desktop it shows instead of its
    // own cast darkening through the fill. `autoPaddingEnabled` is off
    // because the padding is the silhouette's, sized off what this box
    // actually asks for rather than off `blurMax`.
    //
    // MultiEffect's blur is a kernel fraction and CSS's is a radius, so a
    // cast is a close reading of its layer rather than an exact one; the
    // spread scales the shadow about its own centre, taken against the
    // box's shorter side, which is as near as one scalar gets to CSS's
    // outward grow.
    Repeater {
        model: root.box.casts

        delegate: MultiEffect {
            id: cast
            required property var modelData

            readonly property real _extent: Math.max(1, Math.min(root.width, root.height))

            anchors.fill: silhouetteLayer
            z: -1
            source: silhouetteLayer
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: silhouetteLayer
            maskInverted: true
            blurMax: Math.max(1, root._castPad)
            shadowEnabled: true
            shadowColor: cast.modelData.color
            shadowBlur: Math.min(1, cast.modelData.blur / cast.blurMax)
            shadowHorizontalOffset: cast.modelData.x
            shadowVerticalOffset: cast.modelData.y
            shadowScale: Math.max(0, (cast._extent + cast.modelData.spread * 2) / cast._extent)
        }
    }

    // One ring per spread layer: a bordered rectangle at a negative margin
    // of its own spread, so only the band outside the box's edge is ever
    // painted. The keyboard cursor's halo is one of these.
    Repeater {
        model: root.box.rings

        delegate: Rectangle {
            id: ring
            required property var modelData

            anchors.fill: parent
            anchors.margins: -ring.modelData.spread
            radius: root._radius + ring.modelData.spread
            color: "transparent"
            border.width: ring.modelData.spread
            border.color: ring.modelData.color
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: root._radius
        color: root.box.fill
        border.width: root._borderWidth
        border.color: root._borderColor

        Behavior on color {
            CAnim {}
        }

        Behavior on border.color {
            CAnim {}
        }
    }

    // The face: the one gradient a material has, top to bottom, inside the
    // border.
    Loader {
        anchors.fill: parent
        anchors.margins: root._borderWidth
        active: !!root.box.face
        sourceComponent: Rectangle {
            radius: Math.max(0, root._radius - root._borderWidth)
            gradient: Gradient {
                GradientStop { position: 0; color: root.box.face.from }
                GradientStop { position: 1; color: root.box.face.to }
            }
        }
    }

    // The inset hairlines, one line per layer along the edge its own offset
    // names. Clipped, so a line thicker than the box it is lit against
    // cannot run out of it; the clip is rectangular, so a line still runs
    // the full length of its edge rather than stopping where the corner arc
    // starts. A layer marked `inset: false` (a lit lower lip outside the
    // box) belongs outside this container and is not drawn: no table
    // carries one yet.
    Item {
        anchors.fill: parent
        anchors.margins: root._borderWidth
        clip: true

        Repeater {
            model: root.box.hairlines

            delegate: Rectangle {
                id: hairline
                required property var modelData

                readonly property bool _sideways: hairline.modelData.edge === "left"
                    || hairline.modelData.edge === "right"

                visible: hairline.modelData.inset
                x: hairline.modelData.edge === "right" ? parent.width - hairline.width : 0
                y: hairline.modelData.edge === "bottom" ? parent.height - hairline.height : 0
                width: hairline._sideways ? hairline.modelData.thickness : parent.width
                height: hairline._sideways ? parent.height : hairline.modelData.thickness
                color: hairline.modelData.color
            }
        }
    }

    // The pointer's own layer, over the border as well as the fill: a wash
    // of the surface's ink rather than an opaque chip, since every surface
    // that takes a hover is drawn at the surface alpha and an opaque fill
    // on top of it lands at a delta the wallpaper decides (the table's
    // `wash` entry carries the arithmetic). A control that carries a colour
    // of its own takes a `tint` on its fill instead and never reaches here.
    Rectangle {
        anchors.fill: parent
        radius: root._radius
        color: root._heldWash
        opacity: root.washTone ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim { kind: "effects" }
        }
    }
}
