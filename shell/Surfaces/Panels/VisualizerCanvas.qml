import QtQuick
import qs.Core
import qs.Services
import "../../Visualizer/styles.js" as Styles

// The media panel's spectrum (M73): one Canvas drawing
// VisualizerService.levels in whichever style VisualizerService.style
// names (styles.js). It repaints every screen frame only while cava runs
// and the panel is open, plus one frame when either stops, which draws the
// style's resting state over the all-zero baseline.
Canvas {
    id: root

    property int columns: 12

    // The owner's open state: an item in a closed panel's window still
    // reads as visible, and the bar cell alone can keep cava running.
    property bool active: true

    readonly property string style: VisualizerService.style
    readonly property var ink: ({
            groove: Theme.color.muted,
            dim: Theme.color.mutedForeground,
            content: Theme.color.foreground,
            accent: Theme.color.primary,
            mono: Theme.fontFamilyMono,
            columns: root.columns,
            gap: Theme.space.xxs,
            radius: Theme.radiusSm
        })
    readonly property bool _live: VisualizerService.running && root.active && root.visible

    renderStrategy: Canvas.Cooperative

    property var _state: Styles.freshState()
    // Frame time not yet drawn, so a paint the scene graph coalesces still
    // advances the caps and particles by the whole interval.
    property real _pending: 0
    property real _clock: 0

    function _reset() {
        root._state = Styles.freshState();
        root._pending = 0;
        root._clock = 0;
        root.requestPaint();
    }

    onStyleChanged: root._reset()
    on_LiveChanged: root._reset()
    onInkChanged: root.requestPaint()

    FrameAnimation {
        running: root._live
        onTriggered: {
            root._pending += frameTime;
            root.requestPaint();
        }
    }

    onPaint: {
        var ctx = root.getContext("2d");
        ctx.reset();
        root._clock += root._pending;
        Styles.draw(root.style, ctx, root.width, root.height, VisualizerService.levels, root._state, root.ink, root._pending, root._clock, VisualizerService.levelsLeft, VisualizerService.levelsRight);
        root._pending = 0;
    }
}
