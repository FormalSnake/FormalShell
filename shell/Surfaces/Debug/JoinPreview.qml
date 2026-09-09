import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Components

// The `debug join` verb's own surface (M54 Task 2): one Components/
// Shoulders.qml hung on the bar's inner line at the rect the verb published,
// and nothing else. No panel joins the bar until M54 Task 3, so without this
// the rig could not see either half of the join, and a shape nothing draws
// is a shape nobody has checked.
//
// Mapped only while a debug join exists, which is only ever after an IPC
// call: an ordinary session pays for one unmapped window.
//
// On the Overlay layer rather than Top, where the bar and the panels are.
// The join is one silhouette across two windows: the card's anchored edge
// lands ON the bar's line row, filling the gap the bar opened there, so this
// window has to be above the strip. A real panel gets that by mapping after
// the bar; a debug surface says it outright rather than depending on the
// order two layer surfaces happened to arrive in.
PanelWindow {
    id: preview

    // { edge, x, width, screen }, straight off Ipc/DebugIpc.qml.
    property var join: null

    // How far the test card hangs off the bar. Nothing measures it: the leg
    // reads the gap along the bar and the two ends of it, and this is only
    // what gives the shoulders something to be the shoulders of.
    readonly property real depth: 140

    readonly property real _overhang: card.overhang
    readonly property real _line: Theme.borderWidth
    readonly property bool _vertical: preview.join
        && (preview.join.edge === "left" || preview.join.edge === "right")

    readonly property var _screen: {
        if (!preview.join)
            return null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++)
            if (screens[i].name === preview.join.screen)
                return screens[i];
        return null;
    }

    screen: preview._screen
    visible: preview.join !== null
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "formalshell:debug-join"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // An empty Region resolves to WindowTransparentForInput (Panel.qml's own
    // precedent), so a preview covering the output never eats a click meant
    // for the leg's fixture window under it.
    mask: emptyMask

    Region { id: emptyMask }

    Shoulders {
        id: card
        visible: preview.join !== null
        edge: preview.join ? preview.join.edge : "top"

        // The card's rect plus a fillet at either end, hung so its anchored
        // edge sits on the bar's own line row: `edgeInset` is the strip's
        // thickness on the bar's edge, and the line is the last row of it.
        x: {
            if (!preview.join)
                return 0;
            if (preview.join.edge === "left")
                return Theme.edgeInset.left - preview._line;
            if (preview.join.edge === "right")
                return preview.width - Theme.edgeInset.right + preview._line - preview.depth;
            return preview.join.x - preview._overhang;
        }
        y: {
            if (!preview.join)
                return 0;
            if (preview.join.edge === "top")
                return Theme.edgeInset.top - preview._line;
            if (preview.join.edge === "bottom")
                return preview.height - Theme.edgeInset.bottom + preview._line - preview.depth;
            return preview.join.x - preview._overhang;
        }
        width: preview._vertical
            ? preview.depth
            : (preview.join ? preview.join.width + preview._overhang * 2 : 0)
        height: preview._vertical
            ? (preview.join ? preview.join.width + preview._overhang * 2 : 0)
            : preview.depth
    }
}
