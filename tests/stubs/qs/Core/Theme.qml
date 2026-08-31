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

    // Mirrors the real Theme.qml's structural shape (M51 D6): one
    // `property color` per key on a nested QtObject rather than a plain map,
    // so `.background` etc. resolve to the same typed `color` value a
    // component under test would get against the real singleton. No
    // Behaviors here, unlike the real one: nothing in this stub ever
    // retargets these values on a running palette pipeline, only a whole-
    // object swap between tests (below), so there is nothing to crossfade.
    readonly property var _bootFallback: Palette.fallback()

    // Not readonly: tst_cell_hover_inversion.qml overrides this per-test with
    // a palette whose roles are pairwise distinct, since a fallback set can
    // coincidentally share a hex across two different roles, which makes a
    // hex-equality assertion against it unable to tell a correct role from
    // a swapped one.
    property var color: QtObject {
        property string mode: root._bootFallback.mode
        property color background: root._bootFallback.background
        property color foreground: root._bootFallback.foreground
        property color card: root._bootFallback.card
        property color cardForeground: root._bootFallback.cardForeground
        property color popover: root._bootFallback.popover
        property color popoverForeground: root._bootFallback.popoverForeground
        property color primary: root._bootFallback.primary
        property color primaryForeground: root._bootFallback.primaryForeground
        property color secondary: root._bootFallback.secondary
        property color secondaryForeground: root._bootFallback.secondaryForeground
        property color muted: root._bootFallback.muted
        property color mutedForeground: root._bootFallback.mutedForeground
        property color accent: root._bootFallback.accent
        property color accentForeground: root._bootFallback.accentForeground
        property color destructive: root._bootFallback.destructive
        property color destructiveForeground: root._bootFallback.destructiveForeground
        property color warning: root._bootFallback.warning
        property color warningForeground: root._bootFallback.warningForeground
        property color border: root._bootFallback.border
        property color input: root._bootFallback.input
        property color ring: root._bootFallback.ring
        property color chart1: root._bootFallback.chart1
        property color chart2: root._bootFallback.chart2
        property color chart3: root._bootFallback.chart3
        property color chart4: root._bootFallback.chart4
        property color chart5: root._bootFallback.chart5
    }

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

    // Qt.alpha rather than Qt.rgba(c.r, c.g, c.b, alpha): no channel
    // extraction needed to add an alpha on top of a color already in hand.
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

    // Not readonly: tst_presence.qml overrides this per-test to prove the
    // motion.enabled=false reduced-motion switch, the same way tst_track.qml
    // and tst_switch.qml reassign `color` above.
    property bool motionEnabled: true

    readonly property var motion: {
        var m = Tokens.motionTokens(root.motionEnabled);
        return {
            fast: m.fast,
            standard: m.standard,
            surface: m.surface,
            surfaceExit: m.surfaceExit,
            emphasized: m.emphasized,
            emphasizedEasing: Easing.OutQuint,
            slide: m.slide,
            zoom: m.zoom,
            easing: Easing.OutQuint,
            easingInOut: Easing.InOutQuart,
            reveal: m.reveal,
            revealEasing: Easing.InOutQuad,
            pulseDuration: 900,
            pulseEasing: Easing.InOutQuad,
            marqueePxPerSec: m.marqueePxPerSec,
            marqueeHoldMs: m.marqueeHoldMs
        };
    }
}
