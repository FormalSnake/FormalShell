import QtQuick
import qs.Compositor
import qs.Components
import qs.Core as Core
import qs.Services
import qs.Theme
import "../../Theme/barpaint.js" as Paint

// The band under `bar.kind: wingpanel` (the 2026-09-17 spec's Part 2, M60
// T3): no strip card, no hairline, no ghost cell borders. What the band is
// painted with is decided by what is under it, the way wingpanel's own
// panel decides it (`wingpanel-interface/BackgroundManager.vala`): the
// wallpaper band beneath the bar is sampled, and its mean luminance, spread
// and acutance pick one of the five `bar` paints the table describes. The
// sampling and the decision are shell/Theme/BarPaint.qml and its
// barpaint.js; every number is in the table or in that library, and nothing
// about either is in this file.
//
// One reading for the session, not one per monitor (owner, 2026-09-18):
// wingpanel samples each panel against its own screen, and a two-output desk
// then shows one bar in dark ink and the other in white. The sampler runs on
// the main display alone and publishes to Theme/BarPaintService.qml; every
// band here reads it back. The window over an output stays that output's
// own, so a maximized window still blackens its own band and no other.
//
// The ink comes with the paint and is the one thing the band hands the cells
// on it (Bar.qml passes it down, Components/Cell.qml resolves it): white
// over a dark band, dark over a light one, with the text shadow that lifts
// it off a wallpaper it is drawn straight onto.
//
// The paint answers for the band whether or not the band is on screen: a
// window covering the output makes it solid, and the same window takes the
// bar off the overlay layer entirely under `fullscreen.hideChrome`, so that
// paint is only ever seen by a session that turned the auto-hide off.
Item {
    id: root

    // The bar window this paints. Named `owner` rather than `bar` for the
    // reason BarStrip.qml gives: inside the Component that instantiates it,
    // a property called `bar` shadows the window's own id.
    required property var owner

    readonly property string paint: Paint.decideFor(BarPaintService.stats,
        Core.Theme.color.mode, CompositorService.fullscreenOutputs, root._output, root._pin)
    readonly property bool pinned: root._pin !== "auto"

    readonly property string _output: root.owner.modelData ? root.owner.modelData.name : ""

    // `bar.paint`: the theme's own policy by default (pantheon says
    // transparent), and the one thing on this surface a user can overrule.
    // Read here rather than in Theme.qml because it decides a paint rather
    // than a token, and the band is the only thing that resolves one.
    readonly property string _pin: Paint.pin(Core.Config.get("bar.paint", Core.Theme.habit.paint))

    readonly property var _box: Core.Theme.box("bar", root.paint)

    readonly property color ink: root._box.ink
    readonly property color inkShadow: root._box.inkShadow

    // No line along the desktop's edge to report: the band is what separates
    // the bar from the wallpaper, and a joined card has nothing to break.
    function lineRects() {
        return [];
    }

    // `bar paint` and `debug dump`'s `bar[].paint` (Ipc/BarIpc.qml,
    // Ipc/DebugIpc.qml): the paint and the three numbers behind it, so a rig
    // leg reads the decision off the shell rather than inferring it from a
    // frame. `source` is the output the numbers were read on, which is the
    // same one in every entry of the list.
    function paintState() {
        var s = BarPaintService.stats;
        return {
            paint: root.paint,
            source: BarPaintService.source,
            pin: root._pin,
            pinned: root.pinned,
            mean: s.mean,
            std: s.std,
            acutance: s.acutance,
            sampled: s.sampled,
            fullscreen: CompositorService.fullscreenOutputs.indexOf(root._output) >= 0
        };
    }

    // The one sampler in the session. Every other output's bar loads nothing
    // here and reads the service, so a four-monitor desk decodes the
    // wallpaper once rather than four times.
    Loader {
        active: MainOutputService.isMain(root._output)
        sourceComponent: samplerRecipe
    }

    Component {
        id: samplerRecipe

        BarPaint {
            id: sampler

            source: Core.State.wallpaper !== "" ? "file://" + Core.State.wallpaper : ""
            edge: root.owner._position
            thickness: root.owner._strip.thickness
            screenSize: root.owner.screen
                ? Qt.size(root.owner.screen.width, root.owner.screen.height)
                : Qt.size(0, 0)
            onStatsChanged: {
                BarPaintService.source = root._output;
                BarPaintService.stats = sampler.stats;
            }
        }
    }

    Box {
        anchors.fill: parent
        box: root._box
    }
}
