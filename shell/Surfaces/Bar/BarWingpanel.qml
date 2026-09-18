import QtQuick
import qs.Compositor
import qs.Components
import qs.Core as Core
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

    readonly property string paint: sampler.paint
    readonly property bool pinned: sampler.pinned

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
    // frame.
    function paintState() {
        var s = sampler.stats;
        return {
            paint: root.paint,
            pin: sampler.pin,
            pinned: sampler.pinned,
            mean: s.mean,
            std: s.std,
            acutance: s.acutance,
            sampled: s.sampled,
            fullscreen: sampler.fullscreen
        };
    }

    BarPaint {
        id: sampler
        source: Core.State.wallpaper !== "" ? "file://" + Core.State.wallpaper : ""
        edge: root.owner._position
        thickness: root.owner._strip.thickness
        screenSize: root.owner.screen
            ? Qt.size(root.owner.screen.width, root.owner.screen.height)
            : Qt.size(0, 0)
        mode: Core.Theme.color.mode
        // `bar.paint`: the theme's own policy by default (pantheon says
        // transparent), and the one thing on this surface a user can
        // overrule. Read here rather than in Theme.qml because it decides
        // a paint rather than a token, and the band is the only thing that
        // resolves one.
        pin: Paint.pin(Core.Config.get("bar.paint", Core.Theme.habit.paint))
        // The raw set, not `outputCoveredByFullscreen`: whether the chrome
        // hides is the auto-hide's business, and the band's paint is the
        // same question either way.
        // The set is read first and the name second on purpose: a binding
        // that short-circuits before reading `fullscreenOutputs` registers
        // no dependency on it and never re-evaluates.
        fullscreen: CompositorService.fullscreenOutputs
            .indexOf(root.owner.modelData ? root.owner.modelData.name : "") >= 0
    }

    Box {
        anchors.fill: parent
        box: root._box
    }
}
