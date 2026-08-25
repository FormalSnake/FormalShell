import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../../Visualizer/model.js" as Model

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
// Per-bar color (M20 Task 4b, owner: "the audio visualizer can potentially
// be colored bar per bar"): each column's fill resolves through
// `Model.levelColorBand` to its own energy band, `root.dimForeground` for
// a quiet bar, `root.foreground` for content-level energy, `Theme.color.
// primary` only past a genuine peak (a meaning, loudness, not a static
// per-index palette). Hover inversion still wins: dim/content already
// collapse to the inverted ink through `root.dimForeground`/`root.
// foreground` (Cell.qml's own logic), and the primary band mirrors
// PanelOpenDot's own `inverted ? primaryForeground : primary` precedent so
// a peak bar never fights the cell's own hover fill.
//
// M20 Task 5b swapped these bands for per-bar colors sampled from the
// playing track's cover; the owner rejected that on the live shell
// 2026-08-10 ("the album cover's colors are ugly just keep it like it was
// before"), so the bands are the shipped default again.
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
                    readonly property string _band: Model.levelColorBand(track._level)

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * track._level
                        color: track._band === "accent"
                            ? (root.invertedNow ? Theme.color.primaryForeground : Theme.color.primary)
                            : track._band === "content"
                                ? root.foreground
                                : root.dimForeground
                    }
                }
            }
        }
    }
}
