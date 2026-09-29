import QtQuick

// The Mirror's picture for an IR camera. A laptop IR sensor's emitter lights
// every other frame (the g815's ASUS IR camera streams lit and unlit frames
// in strict alternation from the first frame, no extension-unit control
// needed), so drawn raw the feed strobes and, in the dark, half of it is
// black. This keeps the lit frames only and levels them for a greyscale NIR
// image; see Camera/irpick.frag and Camera/irshow.frag for the maths.
//
// QVideoFrame carries no pixels into QML, so the decision is made in the
// scene graph. Each decoded frame (`frame()`, called from the video sink's
// own signal) is captured into one of two slots in turn, and one pass of
// `pick` compares it with the other slot and writes either it or the frame
// already held into `held`, which feeds `pick` back. Two frames decoded
// between renders land in both slots as the same picture, which `pick` reads
// as not lit and holds through.
Item {
    id: root

    // The VideoOutput the capture session draws into, and the rect inside it
    // the picture fills (its contentRect), so letterboxing never counts
    // toward a mean.
    required property Item source
    property rect sourceRect

    property int _phase: 0

    function frame() {
        root._phase = 1 - root._phase;
        (root._phase === 0 ? slotA : slotB).scheduleUpdate();
        held.scheduleUpdate();
    }

    ShaderEffectSource {
        id: slotA
        visible: false
        sourceItem: root.source
        sourceRect: root.sourceRect
        textureSize: Qt.size(root.width, root.height)
        hideSource: true
        live: false
        mipmap: true
    }

    ShaderEffectSource {
        id: slotB
        visible: false
        sourceItem: root.source
        sourceRect: root.sourceRect
        textureSize: Qt.size(root.width, root.height)
        hideSource: true
        live: false
        mipmap: true
    }

    ShaderEffect {
        id: pick
        width: root.width
        height: root.height
        blending: false
        property var slotA: slotA
        property var slotB: slotB
        property var held: held
        property real phase: root._phase
        // Measured on the g815: a lit frame's mean is 10 to 24% over the
        // unlit frame before it in a daylit room, far more in the dark.
        property real litRatio: 1.03
        property real holdStep: 0.25
        fragmentShader: Qt.resolvedUrl("../../../Camera/irpick.frag.qsb")
    }

    ShaderEffectSource {
        id: held
        visible: false
        sourceItem: pick
        hideSource: true
        recursive: true
        live: false
        mipmap: true
    }

    ShaderEffect {
        anchors.fill: parent
        property var source: held
        property real target: 0.45
        property real maxGain: 6
        property real gamma: 0.8
        fragmentShader: Qt.resolvedUrl("../../../Camera/irshow.frag.qsb")
        transform: Scale {
            origin.x: root.width / 2
            xScale: -1
        }
    }
}
