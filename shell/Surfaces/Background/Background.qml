import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core as Core

// Per-screen wallpaper surface, pinned to the wlr-layer-shell Background
// layer (below Bottom, i.e. below every other surface including windows) —
// verified against quickshell's own WlrLayer::Enum source, not guessed.
// Shows State.wallpaper when set; otherwise just the live Theme.color.background
// fill, so the layer is always present even before a wallpaper is picked.
PanelWindow {
    id: background
    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    color: Core.Theme.color.background
    WlrLayershell.layer: WlrLayer.Background

    Image {
        anchors.fill: parent
        visible: Core.State.wallpaper !== ""
        source: Core.State.wallpaper !== "" ? "file://" + Core.State.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
    }
}
