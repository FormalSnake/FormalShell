import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for a live dithered spectrum next to NowPlaying (owner ask:
// "next to the now playing it would be nice to have an ASCII style audio
// visualizer"; M20 Task 4 follow-up: "for consistency, the audio
// visualizer can also have the dithered ASCII effect like progress bars").
// VisualizerService's shared cava frame renders as six per-column tracks,
// each the same DitherFill-plus-solid-fill idiom every other flat-fill
// track in the shell uses (MediaPanel's progress bar, the OSD/panel
// sliders): a faint dithered checker for the whole column height, with a
// fill rising from the bottom to that bar's own level. Opt-in via
// bar.layout (never part of layout.js's DEFAULT_LAYOUT, the
// github/usage/tailscale precedent) since it spawns a real background
// process.
//
// Per-bar color (M20 Task 5b, owner: "i also meant that it uses the
// dithered album cover colors ... i dont want different options just one
// default here" — supersedes Task 4b's level-band coloring outright, not
// as an option): each column fills with the current cover's own palette,
// `coverPalette.colors[index % n]`, an `ArtPalette` extraction over
// `MediaService.artUrl` posterized to the same steps DitherImage's
// "retro" mode paints the mini cover with, so the bars read as an
// extension of the cover sitting next to them. No art, or a palette that
// hasn't resolved any distinct steps yet, falls back to `root.foreground`
// — an honest neutral, not an invented color. Content ruling, same as the
// mini cover: these colors do NOT swap under hover inversion.
//
// Hidden until VisualizerService's one-shot `cava` PATH probe answers
// (same pre-first-answer hidden state GithubWidget/UsageWidget use). Once
// answered: `cava` missing renders a dim NO CAVA cell regardless of
// playback (CommandModule's honest-failure idiom — the opt-in itself is
// what's broken, not a transient poll), while `cava` present mirrors
// NowPlaying's own shown condition (MediaService.available) so the two
// widgets appear and disappear together. The tracks render empty (zero
// fill, pure dither) whenever VisualizerService's process isn't actually
// running — paused, this bar off-screen, or motion disabled — since
// that's the shared process's own hard gate, not something this cell can
// paint around (DESIGN.md §4 item 8's honesty rule).
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

    // Column width reuses `trackThickness`, the one token every other
    // flat-fill track in the shell sizes its cross-axis by; height matches
    // `Theme.fontSize.body`, the same glyph size every neighboring bar
    // widget's own Text renders at, so this cell's footprint stays
    // consistent with the cells around it.
    readonly property real _trackWidth: Theme.space.trackThickness
    readonly property real _trackHeight: Theme.fontSize.body

    // Cover-color extraction (M20 Task 5b): left at its default 0x0 size
    // (no `anchors.fill`) so it never factors into Cell._measure() below —
    // it exists to populate `colors`, not to be seen.
    ArtPalette {
        id: coverPalette
        source: MediaService.artUrl
    }

    // A Loader, not two always-present siblings: Cell's own _measure()
    // sizes the cell off every direct child of its content slot regardless
    // of that child's `visible` (see Cell.qml's header), and the NO CAVA
    // caption and the live tracks are genuinely different shapes now (a
    // Text vs a Row of columns), not swappable content on one element the
    // way the old single-Text version was. Loading exactly one of them
    // keeps _measure reading only the shape that's actually shown.
    Loader {
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: root._state === "missing" ? noCavaComponent : tracksComponent
    }

    Component {
        id: noCavaComponent
        Text {
            text: "NO CAVA"
            color: root.dimForeground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Theme.letterSpacing.meta
        }
    }

    Component {
        id: tracksComponent
        Row {
            spacing: Theme.space.xxs

            Repeater {
                model: VisualizerService.levels.length

                DitherFill {
                    id: track
                    width: root._trackWidth
                    height: root._trackHeight

                    readonly property real _level: VisualizerService.levels[index] || 0

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * track._level
                        color: coverPalette.colors.length > 0
                            ? coverPalette.colors[index % coverPalette.colors.length]
                            : root.foreground
                    }
                }
            }
        }
    }
}
