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

    readonly property var color: Palette.fallback()

    readonly property int borderWidth: 2
    readonly property int radius: 0

    readonly property real fontBaseSize: 13
    readonly property real fontScale: Tokens.fontScale(fontBaseSize)
    readonly property var fontSize: Tokens.fontTokens(fontBaseSize)
    readonly property var space: Tokens.spacingTokens(fontScale)
    readonly property var letterSpacing: Tokens.letterSpacingTokens(fontScale)

    readonly property var font: ({ family: "monospace", display: "monospace" })

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

    function inverted(useAccent) {
        return Tokens.invertedPair(color, !!useAccent);
    }

    function stateAppearance(state) {
        return Tokens.stateAppearance(state);
    }

    function resolveState(flags) {
        return Tokens.resolveState(flags);
    }
}
