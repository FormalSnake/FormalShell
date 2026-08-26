pragma Singleton
import QtQuick
import "../../../../shell/Theme/palette.js" as Palette
import "../../../../shell/Theme/tokens.js" as Tokens

// Test-only stand-in for shell/Core/Theme.qml, which is a Quickshell
// Singleton (it reads settings.json, the state file and the live matugen
// palette) and so cannot load under plain qmltestrunner. Every value here
// comes from the same palette.js/tokens.js the real singleton derives its
// own from, at the shell's default fontBaseSize (no invented numbers), so
// a component instantiated against this stub lays out exactly as it does
// against an unthemed shell. Only the members the components under test
// actually read are mirrored.
QtObject {
    id: root

    // Not readonly: tst_cell_hover_inversion.qml overrides this per-test with
    // a palette whose roles are pairwise distinct, since a fallback set can
    // coincidentally share a hex across two different roles, which makes a
    // hex-equality assertion against it unable to tell a correct role from
    // a swapped one.
    property var color: Palette.fallback()

    // The shadcn preset's own table, written out: this stub cannot import
    // Config, and shell/Theme/presets.js resolves against it. A component
    // under test therefore sees exactly what an unconfigured shell renders.
    readonly property string preset: "shadcn"
    readonly property string iconSet: "lucide"
    readonly property string fonts: "pair"
    readonly property bool dither: false
    readonly property bool wallpaperDither: false
    readonly property bool lockDither: false
    readonly property bool blurBehind: true

    readonly property int borderWidth: 1
    readonly property int radius: 10
    readonly property var _radiusTokens: Tokens.radiusTokens(radius)
    readonly property int radiusSm: _radiusTokens.sm
    readonly property int radiusMd: _radiusTokens.md
    readonly property int radiusLg: _radiusTokens.lg
    readonly property int radiusXl: _radiusTokens.xl
    readonly property int ringWidth: 3
    readonly property real ringAlpha: 0.5

    function pillRadius(extent) {
        return root.radius > 0 ? extent / 2 : 0;
    }

    // The corner a picture takes at its own size (`Tokens.coverRadius`): the
    // radius ladder is sized for controls, and `radiusSm` on the bar's 17px
    // album art reads as a lozenge rather than a rounded square. `Cover` is
    // the only caller.
    function coverRadius(extent) {
        return Tokens.coverRadius(root.radiusSm, extent);
    }

    readonly property var weight: Tokens.WEIGHTS

    readonly property real fontBaseSize: 13
    readonly property real fontScale: Tokens.fontScale(fontBaseSize)
    readonly property var fontSize: Tokens.fontTokens(fontBaseSize)
    readonly property var space: Tokens.spacingTokens(fontScale)
    readonly property var letterSpacing: Tokens.letterSpacingTokens(fontScale)

    readonly property string fontFamilySans: "sans-serif"
    readonly property string fontFamilyMono: "monospace"
    readonly property string fontFamily: root.fontFamilyMono

    readonly property real surfaceOpacity: Tokens.clamp(0.85, 0, 1, 0.85)

    // The bar's edge, as shipped: a top bar, its thickness off the top.
    readonly property string barPosition: "top"
    readonly property bool barVertical: false
    readonly property real barThickness: space.barCellHeight + space.barMargin * 2
    readonly property var barInset: ({ top: root.barThickness, bottom: 0, left: 0, right: 0 })
    readonly property real frameThickness: 0
    readonly property bool frameEnabled: false
    readonly property real frameRadius: 20
    readonly property var edgeInset: root.barInset

    // Qt.alpha rather than Qt.rgba: `color` arrives from theme.json as hex
    // strings, which have no .r/.g/.b to read, and Qt.rgba on those three
    // undefined values silently paints black at the right alpha.
    function surface(c) {
        return Qt.alpha(c, root.surfaceOpacity);
    }

    readonly property var _stateAlpha: Tokens.stateAlpha(root.color.mode)
    readonly property color hoverFill: Qt.alpha(root.color.foreground, root._stateAlpha.hover)
    readonly property color pressFill: Qt.alpha(root.color.foreground, root._stateAlpha.press)

    function hoverFilled(c) {
        return Qt.tint(c, Qt.alpha(root.color.background, root._stateAlpha.filledHover));
    }

    function pressFilled(c) {
        return Qt.tint(c, Qt.alpha(root.color.background, root._stateAlpha.filledPress));
    }

    readonly property bool motionEnabled: true

    readonly property var motion: {
        var m = Tokens.motionTokens(true);
        return {
            fast: m.fast,
            standard: m.standard,
            slide: m.slide,
            easing: Easing.OutCubic,
            reveal: m.reveal,
            revealEasing: Easing.InOutQuad,
            marqueePxPerSec: m.marqueePxPerSec,
            marqueeHoldMs: m.marqueeHoldMs
        };
    }
}
