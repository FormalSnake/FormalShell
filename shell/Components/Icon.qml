import QtQuick
import qs.Core
import "../Theme/icons.js" as Icons

// Named icon glyph (spec "Icons", D2): `Icon { name: "wifi" }`. The set is
// `Theme.iconSet`, which the preset picks and `theme.icons` overrides
// (`lucide` on shadcn, an installed icon font; `nerd` on retro, which
// renders in the mono font itself). Surface files never contain a raw
// codepoint here, which is the point: the glyph-corruption-on-rewrite
// hazard (CLAUDE.md) only threatens files that carry raw codepoints at all.
Text {
    id: root

    required property string name
    property real size: Theme.fontSize.body

    readonly property string _set: Theme.iconSet
    readonly property string _family: Icons.family(root._set)

    text: Icons.glyph(root._set, root.name)
    color: Theme.color.foreground
    font.family: root._family === "" ? Theme.fontFamilyMono : root._family
    font.pixelSize: root.size
    // A square the size of the neighbouring text, so a row lays the glyph
    // out like a character whatever advance width the icon font gives it.
    // Written as `width`, not `implicitWidth`: QQuickText redeclares that one
    // read-only, since its implicit size is the text metric.
    width: root.size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
