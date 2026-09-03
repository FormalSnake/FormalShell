import Quickshell
import Quickshell.Wayland
import qs.Compositor
import qs.Core

// The screen frame's reservations, one per output: four 1px windows, one
// on each edge, each reserving what its edge holds (the bar's thickness on
// the bar's edge, the band's `frame.thickness` on the other three), which
// is how a tiling compositor keeps windows inside the ring's cut-out
// (Caelestia's Exclusions.qml does exactly this; a surface anchored on all
// four edges has no single edge to reserve against, and with the frame on
// the bar's own window is one of those). They paint nothing and take no
// input: an empty `mask` builds an empty input region, the same
// click-through Tooltip.qml relies on. The ring itself is FrameRing.qml,
// drawn inside the bar's window.
Scope {
    id: root
    required property var modelData
    // shell.qml's startup reveal gate. Every number a zone reserves comes
    // out of settings.json, so a zone mapped before it lands reserves a
    // default band and then republishes, which is a reflow of every tiled
    // window on the output.
    property bool ready: false

    readonly property bool _on: Theme.frameEnabled

    component Zone: PanelWindow {
        id: zone
        required property string edge
        screen: root.modelData
        // Also down while a fullscreen window covers this output: the zones
        // sit on the overlay layer and would otherwise block its scanout.
        visible: root._on && root.ready && !CompositorService.outputCoveredByFullscreen(root.modelData.name)
        anchors {
            top: zone.edge !== "bottom"
            bottom: zone.edge !== "top"
            left: zone.edge !== "right"
            right: zone.edge !== "left"
        }
        implicitWidth: 1
        implicitHeight: 1
        exclusiveZone: Theme.barPosition === zone.edge ? Theme.barThickness : Theme.frameThickness
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "formalshell:frame-zone"
        // Overlay, deliberately: Hyprland arranges exclusive surfaces
        // background, bottom, top, overlay (IHyprRenderer::
        // arrangeLayersForMonitor), each one boxed by what the ones before
        // it left, and nothing else the shell maps sits up here to be
        // boxed by these. Which of the four takes a corner does not matter:
        // the area they leave between them is the same either way. A 1px
        // window that paints nothing and takes no input is all the overlay
        // layer ever sees of them.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    Zone { edge: "top" }
    Zone { edge: "bottom" }
    Zone { edge: "left" }
    Zone { edge: "right" }
}
