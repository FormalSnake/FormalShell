import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for a live ASCII spectrum next to NowPlaying (owner ask: "next
// to the now playing it would be nice to have an ASCII style audio
// visualizer"): VisualizerService's shared cava frame rendered as N block
// glyphs (U+2581..U+2588, verified present in the pinned
// nerd-fonts-jetbrains-mono cmap via fonttools ttx — they're standard
// Unicode Block Elements, not PUA nerd-font glyphs) in ONE monospace Text,
// no Canvas/Rectangle bars. Opt-in via bar.layout (never part of
// layout.js's DEFAULT_LAYOUT — the github/usage/tailscale precedent)
// since it spawns a real background process.
//
// Hidden until VisualizerService's one-shot `cava` PATH probe answers
// (same pre-first-answer hidden state GithubWidget/UsageWidget use). Once
// answered: `cava` missing renders a dim NO CAVA cell regardless of
// playback (CommandModule's honest-failure idiom — the opt-in itself is
// what's broken, not a transient poll), while `cava` present mirrors
// NowPlaying's own shown condition (MediaService.available) so the two
// widgets appear and disappear together. The glyphs freeze at their
// all-baseline (lowest) row whenever VisualizerService's process isn't
// actually running — paused, this bar off-screen, or motion disabled —
// since that's the shared process's own hard gate, not something this
// cell can paint around.
Cell {
    id: root

    // Set from Bar.qml (`windowVisible: bar.visible`, ActiveWindow/
    // NowPlaying's own precedent): registers with VisualizerService so the
    // shared process only runs while a bar showing this widget is
    // genuinely on screen.
    property bool windowVisible: true
    property bool _registered: false

    function _sync() {
        if (root.windowVisible === root._registered)
            return;
        VisualizerService.setBarVisible(root._registered, root.windowVisible);
        root._registered = root.windowVisible;
    }

    readonly property string _state: VisualizerService.state

    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment.
    readonly property bool shown: root._state === "missing" || (root._state === "available" && MediaService.available)

    visible: root.shown
    standalone: true

    onWindowVisibleChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: {
        if (root._registered)
            VisualizerService.setBarVisible(true, false);
    }

    // A single Text for the whole cell, not a Text-for-bars plus a
    // MetaLabel-for-error pair: Cell's own _measure() sizes the cell off
    // every direct child's width regardless of that child's `visible`
    // (see Cell.qml's header — nothing here filters on visibility), so two
    // alternately-shown siblings would size the cell to fit BOTH, leaving
    // the shorter one sitting in leftover space. Swapping content/color/
    // capitalization on one Text (GithubWidget's own pattern) avoids that
    // and keeps the bars themselves in "ONE monospace Text — no Canvas, no
    // Rectangle bars" for every state, not just the live one. The NO CAVA
    // state borrows MetaLabel's own tokens (`Components/MetaLabel.qml`)
    // rather than the component itself, for the same reason.
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root._state === "missing" ? "NO CAVA" : VisualizerService.frameText
        color: root._state === "missing" ? Theme.color.foregroundDim : root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.caption
        font.capitalization: root._state === "missing" ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root._state === "missing" ? Theme.letterSpacing.meta : 0
    }
}
