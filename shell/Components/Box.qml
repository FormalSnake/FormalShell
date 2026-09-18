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
// rings under the fill, the fill with its border, the face gradient and the
// inset hairlines inside it, an inset ring inside those, the pointer's wash
// over the lot, and the content over that. The border rides on the fill's own Rectangle rather
// than being a layer of its own, which is what keeps a box with no layers
// and no face costing one Rectangle: the face and the hairlines sit a
// border in from the edge so they never paint over it.
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

    // What the box carries, over everything it draws, inset by `padding`.
    // The DEFAULT slot, and it has to be the drawn one: an object declared
    // inside a document whose root is a Box lands in the slot BOX declares
    // default, whatever that document declares for its own consumers, so a
    // default slot that was not drawn would swallow a primitive's own
    // children.
    default property alias content: contentSlot.data
    readonly property alias contentItem: contentSlot
    property real padding: 0

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
    // room the cast layer and its mask need around the box.
    readonly property int _castPad: {
        var pad = 0;
        for (var i = 0; i < root.box.casts.length; i++) {
            var cast = root.box.casts[i];
            pad = Math.max(pad, Math.ceil(cast.blur + Math.max(0, cast.spread)
                + Math.max(Math.abs(cast.x), Math.abs(cast.y))));
        }
        return pad;
    }

    // The radius inside the border, clamped to what the box's own extent
    // can hold: the face, the hairlines and the inset rings all draw there.
    readonly property real _innerRadius: Math.max(0, Math.min(root._radius - root._borderWidth,
        (root.width - root._borderWidth * 2) / 2, (root.height - root._borderWidth * 2) / 2))

    // The wash the current state asks for, or null.
    readonly property var washTone: root.box.wash || null

    // Held through the fade out: the wash rect's colour has to stay where
    // it was while its opacity runs down, or a wash would blink out instead
    // of fading.
    property color _heldWash: "transparent"

    onWashToneChanged: if (root.washTone) root._heldWash = root.washTone;

    // The box's own shape, padded for the casts and never drawn: the mask
    // the cast layer below cuts itself out with. The white is mask alpha,
    // not a colour.
    Item {
        id: castMask
        anchors.fill: parent
        anchors.margins: -root._castPad
        visible: false
        layer.enabled: root.box.casts.length > 0

        Rectangle {
            anchors.fill: parent
            anchors.margins: root._castPad
            radius: root._radius
            color: "white"
        }
    }

    // Every cast, drawn analytically by RectangularShadow (CSS's own blur
    // radius, offset and outward spread) and then masked out of the box as
    // one layer, so a translucent card keeps the blurred desktop it shows
    // instead of its own cast darkening through the fill. The mask has to be
    // soft: MultiEffect's default mask is a step at alpha 0, which cuts the
    // shadow on the whole antialiased rim and leaves the corner arcs as a
    // staircase with the desktop showing through it. A threshold of 0.5
    // with a spread of 1 is the one pair its smoothstep reads as 0 to 1
    // over the mask's alpha (`updateMaskThresholdSpread` in Qt's
    // qquickmultieffect.cpp). A negative spread shrinks the rect instead,
    // which is what RectangularShadow asks for rather than taking one.
    Item {
        objectName: "casts"
        anchors.fill: parent
        anchors.margins: -root._castPad
        z: -1
        visible: root.box.casts.length > 0
        layer.enabled: root.box.casts.length > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: castMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Repeater {
            model: root.box.casts

            delegate: RectangularShadow {
                id: cast
                required property var modelData

                readonly property real _shrink: Math.max(0, -cast.modelData.spread)

                anchors.fill: parent
                anchors.margins: root._castPad + cast._shrink
                radius: Math.max(0, root._radius - cast._shrink)
                blur: cast.modelData.blur
                spread: Math.max(0, cast.modelData.spread)
                offset: Qt.vector2d(cast.modelData.x, cast.modelData.y)
                color: cast.modelData.color
            }
        }
    }

    // One ring per spread layer: a FILLED rounded rectangle at a negative
    // margin of its own spread, under the fill, which is what CSS draws for
    // a spread with no blur and what the keyboard cursor's halo has always
    // been. Filled rather than stroked because the fill over it is
    // translucent: a stroked band would leave the box's own alpha showing
    // the desktop between the ring and the border, and a band whose inner
    // edge is a rounded rectangle of a different radius cannot follow the
    // border's arc anyway. Declared before the fill, which is what puts it
    // under it; the casts carry a negative z and so stay under both.
    Repeater {
        model: root.box.rings

        delegate: Rectangle {
            id: ring
            required property var modelData

            anchors.fill: parent
            anchors.margins: -ring.modelData.spread
            radius: root._radius + ring.modelData.spread
            color: ring.modelData.color
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
            radius: root._innerRadius
            gradient: Gradient {
                GradientStop { position: 0; color: root.box.face.from }
                GradientStop { position: 1; color: root.box.face.to }
            }
        }
    }

    // The inset hairlines, one lit line per layer along the edge its own
    // offset names. Each is the inner outline stroked at the line's
    // thickness and clipped to a band as deep as the corner, so the line
    // runs along its edge and round both arcs into the sides the way a CSS
    // inset shadow follows the radius. A straight line clipped to the box's
    // rect instead ran square into the corners and poked past the rounded
    // border. A layer marked `inset: false` (a lit lower lip outside the
    // box) belongs outside this container and is not drawn: no table
    // carries one yet.
    Item {
        id: hairlineLayer
        objectName: "hairlines"
        anchors.fill: parent
        anchors.margins: root._borderWidth

        Repeater {
            model: root.box.hairlines

            delegate: Item {
                id: hairline
                required property var modelData

                readonly property bool _sideways: hairline.modelData.edge === "left"
                    || hairline.modelData.edge === "right"
                readonly property real _depth: Math.max(hairline.modelData.thickness, root._innerRadius)

                visible: hairline.modelData.inset
                clip: true
                x: hairline.modelData.edge === "right" ? hairlineLayer.width - hairline.width : 0
                y: hairline.modelData.edge === "bottom" ? hairlineLayer.height - hairline.height : 0
                width: hairline._sideways ? hairline._depth : hairlineLayer.width
                height: hairline._sideways ? hairlineLayer.height : hairline._depth

                Rectangle {
                    x: -hairline.x
                    y: -hairline.y
                    width: hairlineLayer.width
                    height: hairlineLayer.height
                    radius: root._innerRadius
                    color: "transparent"
                    border.width: hairline.modelData.thickness
                    border.color: hairline.modelData.color
                }
            }
        }
    }

    // One stroked rounded rectangle per inset ring: CSS draws an inset spread
    // with no blur as a band of that thickness along the inside of the box,
    // which is Gala's own lit stroke a pixel and a half inside the switcher
    // card's rim. A border rather than a fill, so the card's translucency
    // still shows the desktop between the stroke and the middle, and drawn
    // over the face and the hairlines because it is the innermost edge of the
    // rim rather than a layer under it.
    Repeater {
        model: root.box.insetRings

        delegate: Rectangle {
            id: insetRing
            required property var modelData

            anchors.fill: parent
            radius: root._radius
            color: "transparent"
            border.width: insetRing.modelData.spread
            border.color: insetRing.modelData.color
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

    // The content, last and so over every layer above, including the wash:
    // a row's own ink keeps its contrast while the pointer sits on it.
    Item {
        id: contentSlot
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
