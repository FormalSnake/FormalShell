import QtQuick

// The CompositorBackend contract. Every per-compositor backend (niri, hyprland, ...)
// composes on top of this as its root object. CompositorService holds one active
// backend and delegates the same surface to it.
QtObject {
    id: root

    readonly property bool available: false // backend detected its compositor and is connected

    property var workspaces: [] // [{ id:string, idx:int, name:string, output:string, isActive:bool, isFocused:bool, isUrgent:bool }]
    property var windows: [] // [{ id:string, title:string, appId:string, workspaceId:string, isFocused:bool, isFloating:bool, isUrgent:bool }]
    property var outputs: [] // [{ name:string, x:int, y:int, width:int, height:int, scale:real }]

    property string focusedWindowId: ""
    property string focusedWorkspaceId: ""
    property string focusedOutputName: ""

    signal configReloaded(bool failed)

    function focusWorkspace(id) {}
    function focusWindow(id) {}
    function closeWindow(id) {}
    function spawn(argv) {} // argv: list<string>, no shell interpolation
    function powerOffMonitors() {}
    function powerOnMonitors() {}
}
