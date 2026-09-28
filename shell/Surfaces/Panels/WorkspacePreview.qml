import QtQuick
import Quickshell
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../Bar/workspaces.js" as WorkspacesModel

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// The Spaces cell's workspace preview (M74, DESIGN.md §3 Bar): a card
// hanging off a workspace slot with each of that workspace's windows drawn
// as a box at its own place on the output, scaled down, carrying its icon
// and title. Click a box (or Enter on the cursor) to focus that window.
//
// Schematic on purpose. omarchy-spaces draws live ScreencopyViews here,
// which this shell never uses anywhere (LockSurface.qml's header: it takes
// the whole shell down), and a box per window is the part of the picture
// that says where things are.
//
// Two ways in, and they close differently. The pointer (`show(..., true)`,
// the slot's own hover delay) narrows this window's input to the card
// alone, so the bar under the rest of the output keeps its hover and a
// pointer walking along the slots moves the card between them; it closes
// once the pointer is on neither the slot nor the card. `workspaces peek`
// over IPC has no pointer to follow, so it is an ordinary panel: Escape or
// a click outside.
//
// Not in PanelIpc's registry: without a workspace to show there is nothing
// to open, so `workspaces peek <n>` is the summon path.
Panel {
    id: root

    showHeader: false
    panelWidth: Theme.space.popupWidthDefault

    // The Bar/workspaces.js slot on show, never bound: the card keeps the
    // workspace it was opened on while the bar's model republishes under it.
    property var slot: null
    property bool fromPointer: false

    // Every bar's Spaces cell, one per output, registered by the cells
    // themselves: `workspaces peek` and `status` need the one on the
    // focused output, and a cell lives inside a Variants delegate nothing
    // outside can address. Reassigned rather than mutated, so a binding on
    // it re-evaluates.
    property var cells: []

    function addCell(cell) {
        if (root.cells.indexOf(cell) < 0)
            root.cells = root.cells.concat([cell]);
    }

    function removeCell(cell) {
        root.cells = root.cells.filter(function (other) { return other !== cell; });
    }

    readonly property string workspaceId: root.slot ? root.slot.id : ""
    readonly property int idx: root.slot ? root.slot.idx : -1

    function show(slotItem, slotData, pointer) {
        closeTimer.stop();
        root.slot = slotData;
        root.fromPointer = pointer === true;
        root.cursorIndex = 0;
        // Hyprland's rects go stale between refreshes (BackendBase's
        // refreshWindows), and every box here is placed by one.
        CompositorService.refreshWindows();
        root.openFrom(slotItem);
    }

    // The pointer is back on the slot, or on the card.
    function hold() {
        closeTimer.stop();
    }

    // The pointer left the slot. The card is `barMargin` off the cell, so
    // the pointer crossing that band on its way into the card is a leave
    // too; the grace covers the crossing.
    function release() {
        if (root.isOpen && root.fromPointer)
            closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 200
        onTriggered: if (!cardHover.hovered) root.close()
    }

    // Input on the card alone while the pointer drives it (see the header),
    // and nowhere while a handoff cuts this card for the next one, which is
    // Panel's own rule.
    mask: root.handingOver ? passThrough : (root.fromPointer ? cardRegion : null)

    Region {
        id: passThrough
    }

    Region {
        id: cardRegion
        x: root.frameRect.x
        y: root.frameRect.y
        width: root.frameRect.width
        height: root.frameRect.height
    }

    // On the whole window rather than the card: with the mask above the
    // card is the only place the pointer can be over it at all, and the
    // card's own padding counts.
    HoverHandler {
        id: cardHover
        parent: root.contentItem
        enabled: root.fromPointer
        onHoveredChanged: {
            if (cardHover.hovered)
                root.hold();
            else
                root.release();
        }
    }

    readonly property var _windows: (root.isOpen || root.visible) && root.workspaceId !== ""
        ? CompositorService.windows.filter(function (w) { return w.workspaceId === root.workspaceId; })
        : []

    on_WindowsChanged: if (root.isOpen) AppIconService.probe(root._windows)

    readonly property var _area: root._screen
        ? ({ x: root._screen.x, y: root._screen.y, width: root._screen.width, height: root._screen.height })
        : null

    readonly property real _miniWidth: root._contentWidth
    readonly property real _miniHeight: root._area && root._area.width > 0
        ? Math.round(root._miniWidth * root._area.height / root._area.width)
        : Math.round(root._miniWidth * 9 / 16)

    readonly property var _layout: WorkspacesModel.previewLayout(root._windows, root._area,
        root._miniWidth, root._miniHeight, Theme.space.controlHeight)

    cursorCount: root._layout.length
    onCursorActivated: index => root._focus(index)

    function _focus(index) {
        var place = root._layout[index];
        if (!place)
            return;
        CompositorService.focusWindow(place.id);
        root.close();
    }

    // The workspace closes its own preview by becoming the one on screen.
    Connections {
        target: CompositorService
        function onFocusedWorkspaceIdChanged() {
            if (root.isOpen && root.workspaceId !== "" && CompositorService.focusedWorkspaceId === root.workspaceId)
                root.close();
        }
    }

    SectionLabel {
        width: parent.width
        text: root.slot ? "Workspace " + root.slot.label : ""
        count: root._windows.length
    }

    Item {
        id: mini
        visible: root._layout.length > 0
        width: root._miniWidth
        height: root._miniHeight

        Repeater {
            model: root._layout.length

            // A window's own box, drawn as any other row is: a `Cell`,
            // `selected` on the one that holds focus, the keyboard's ring
            // on the cursor. `xxs` in from its neighbours, since two tiled
            // windows share an edge on screen and two borders drawn on one
            // line read as one.
            Cell {
                id: box
                required property int index
                readonly property var place: root._layout[box.index] || ({ id: "", x: 0, y: 0, width: 0, height: 0 })
                readonly property var win: CompositorService.windowById(box.place.id)
                readonly property string iconSource: box.win ? AppIconService.forWindow(box.win) : ""

                x: box.place.x + Theme.space.xxs
                y: box.place.y + Theme.space.xxs
                width: Math.max(0, box.place.width - Theme.space.xxs * 2)
                height: Math.max(0, box.place.height - Theme.space.xxs * 2)

                selected: !!box.win && box.win.isFocused
                cursor: root.cursorActive && root.cursorIndex === box.index
                interactive: true
                onClicked: root._focus(box.index)

                readonly property real _iconSize: Math.min(Theme.space.huge * 2, box.width / 2, box.height / 2)

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.space.xs

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: box._iconSize
                        height: box._iconSize

                        Picture {
                            id: boxIcon
                            anchors.fill: parent
                            visible: box.iconSource !== "" && boxIcon.status !== Image.Error
                            source: box.iconSource
                            sourceSize.width: box._iconSize * (root._screen ? root._screen.devicePixelRatio : 1)
                            sourceSize.height: box._iconSize * (root._screen ? root._screen.devicePixelRatio : 1)
                            fillMode: Image.PreserveAspectFit
                        }

                        // Nothing in AppIconService's chain answered: the
                        // generic window mark, dim, as the switcher draws it.
                        Icon {
                            anchors.centerIn: parent
                            visible: !boxIcon.visible
                            name: "app-window"
                            size: box._iconSize * 0.75
                            color: box.dimForeground
                        }
                    }

                    // Dropped rather than squeezed on a box too short to
                    // carry it; the icon still says which window it is.
                    Text {
                        visible: box.height >= box._iconSize + Theme.space.xs + implicitHeight + Theme.space.md * 2
                        width: Math.max(0, box.width - Theme.space.md * 2)
                        horizontalAlignment: Text.AlignHCenter
                        text: box.win ? box.win.title : ""
                        elide: Text.ElideRight
                        color: box.foreground
                        font.family: Theme.fontFamilySans
                        font.pixelSize: Theme.fontSize.caption
                    }
                }
            }
        }
    }

    // A workspace with nothing on it, or one the compositor has not created
    // yet (a persistent placeholder): one dim cell saying so.
    Box {
        visible: root._layout.length === 0
        role: "cell"
        state: "rest"
        width: root._miniWidth
        height: Theme.space.controlHeight

        SectionLabel {
            anchors.centerIn: parent
            text: "No windows"
        }
    }
}
