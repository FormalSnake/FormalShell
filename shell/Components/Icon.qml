import QtQuick
import qs.Core
import "../Theme/icons.js" as Icons

// Named icon glyph (spec "Icons", D2): `Icon { name: "wifi" }`. The set is
// `Theme.iconSet`, which the preset picks and `theme.icons` overrides
// (`lucide` on shadcn, an installed icon font; `nerd` on retro, which
// renders in the mono font itself). Surface files never contain a raw
// codepoint here, which is the point: the glyph-corruption-on-rewrite
// hazard (CLAUDE.md) only threatens files that carry raw codepoints at all.
//
// Two slots rather than one (M53 D3, the content rule): nineteen live
// consumers bind `name` to a ternary, and a glyph that changed in one frame
// was the cell's only piece of chrome that cut. The incoming glyph is
// installed in whichever slot is idle and `_cross` carries both opacities
// to their new ends, so a name that changes again mid-fade retargets the
// same animation instead of restarting it. The second slot is not visible
// until the first change, so an icon that never swaps costs one node.
//
// The public surface is a Text's, minus the text: `name`, `size`, `color`,
// a `size`-wide box as tall as the glyph's own line, and the glyph centred
// in whatever box a consumer sets instead.
Item {
    id: root

    required property string name
    property real size: Theme.fontSize.body
    property color color: Theme.color.foreground

    readonly property string _set: Theme.iconSet

    // One key for both halves of a glyph's identity: the icon set decides
    // the font as well as the codepoint, so a set swap has to move through
    // the same install as a name change or the outgoing glyph would be
    // redrawn in a font its codepoint means nothing in.
    readonly property string _key: root._set + "|" + root.name

    // 1 draws slot A, 0 draws slot B; the Behavior is on the driver rather
    // than on each slot's opacity so the two can never fall out of step.
    property real _cross: root._frontIsA ? 1 : 0
    property bool _frontIsA: true
    property bool _armed: false

    // Each slot's own content, held here rather than assigned onto the Text:
    // the codepoint and the family it belongs to are one value, so the
    // outgoing glyph keeps the font it was written for while it fades, and
    // an icon-set swap never draws the old codepoint in the new font.
    property string _glyphA: ""
    property string _familyA: ""
    property string _glyphB: ""
    property string _familyB: ""
    // `_key`'s own binding is evaluated during creation, which emits a
    // change of its own before the first install has run; without this the
    // very first glyph would arrive as a crossfade out of an empty slot.
    property bool _ready: false

    Behavior on _cross {
        Anim { kind: "effects" }
    }

    // A square the size of the neighbouring text, so a row lays the glyph
    // out like a character whatever advance width the icon font gives it.
    width: root.size
    implicitWidth: root.size
    implicitHeight: root._frontIsA ? slotA.implicitHeight : slotB.implicitHeight

    Component.onCompleted: {
        root._install(false);
        root._ready = true;
    }
    on_KeyChanged: {
        if (root._ready)
            root._install(true);
    }

    function _install(animate) {
        var glyph = Icons.glyph(root._set, root.name);
        var family = Icons.family(root._set);
        // Two names can resolve to one glyph (every unknown name falls back
        // to the same question mark), and a crossfade between a glyph and
        // itself is a frame of nothing happening.
        if (animate && glyph === (root._frontIsA ? root._glyphA : root._glyphB)
                && family === (root._frontIsA ? root._familyA : root._familyB))
            return;

        // The idle slot takes the incoming glyph, and the first install has
        // no idle slot to speak of.
        if (!animate || !root._frontIsA) {
            root._glyphA = glyph;
            root._familyA = family;
        } else {
            root._glyphB = glyph;
            root._familyB = family;
        }
        if (!animate)
            return;
        root._armed = true;
        root._frontIsA = !root._frontIsA;
    }

    // An empty family is `nerd`, whose codepoints live in the mono font the
    // shell already renders words in; that fallback stays a binding, since
    // the mono family itself moves under a font setting.
    Text {
        id: slotA
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.size
        text: root._glyphA
        color: root.color
        opacity: root._cross
        font.family: root._familyA === "" ? Theme.fontFamilyMono : root._familyA
        font.pixelSize: root.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        id: slotB
        visible: root._armed
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.size
        text: root._glyphB
        color: root.color
        opacity: 1 - root._cross
        font.family: root._familyB === "" ? Theme.fontFamilyMono : root._familyB
        font.pixelSize: root.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
