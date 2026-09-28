import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../Bar/workspaces.js" as WorkspacesModel

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// The Spaces cell's workspace preview (M74, DESIGN.md §3 Bar): a card
// hanging off a workspace's bar cell, under the panel header naming the
// workspace and its window count, holding a miniature of the output with each window at its own
// place, drawn live, and a footer naming the window under the pointer.
// Click a window (or Enter on the cursor) to focus it.
//
// The thumbnails are ScreencopyViews on each window's toplevel handle,
// through hyprland-toplevel-export-v1, live while the card is open and torn
// down with the window when it closes. This is the one ScreencopyView in the
// shell (owner, 2026-09-28): LockSurface.qml's header is why none may ever
// sit on or near the lock. A window with no handle, or one the compositor
// has not sent a frame for, is drawn as a schematic box instead, its icon
// and title on the cell fill.
//
// Two ways in, and they close differently. The pointer (`show(..., true)`,
// the cell's own hover delay) opens a card that takes no keyboard at all
// (Panel's `takesKeyboard`) and narrows this window's input to the card's
// resting rect, so the bar keeps its hover and a pointer walking along the
// cells moves the card between them; it closes once the pointer is on
// neither a cell that previews nor the card. `workspaces peek` over IPC has
// no pointer to follow, so it is an ordinary panel: Escape or a click
// outside.
//
// Not in PanelIpc's registry: without a workspace to show there is nothing
// to open, so `workspaces peek <n>` is the summon path.
Panel {
    id: root

    panelTitle: root.slot ? "Workspace " + root.slot.label : ""
    panelIcon: "layout-grid"
    panelWidth: Theme.space.popupWidthWide
    takesKeyboard: !root.fromPointer

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
        root._onSlot = root.fromPointer;
        root.cursorIndex = 0;
        root.hoveredId = "";
        // Hyprland's rects go stale between refreshes (BackendBase's
        // refreshWindows), and every thumbnail is placed by one.
        CompositorService.refreshWindows();
        root.openFrom(slotItem);
    }

    // Where the pointer is, as the cells and the card report it. Two flags
    // rather than one hover: the pointer crosses from a cell to the card
    // over the `barMargin` between them, and the two windows report their
    // leave and enter in either order.
    property bool _onSlot: false

    // The pointer is on a cell that previews (the one shown, or the next
    // one taking the card over).
    function hold() {
        root._onSlot = true;
        closeTimer.stop();
    }

    // The pointer left the cell, or is on one that does not preview.
    function release() {
        root._onSlot = false;
        if (root.isOpen && root.fromPointer)
            closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 200
        onTriggered: if (!root._onSlot && !cardHover.hovered) root.close()
    }

    // Input on the card alone while the pointer drives it (see the header),
    // and nowhere while a handoff cuts this card for the next one, which is
    // Panel's own rule. The resting rect rather than the drawn one: the card
    // emerges from under the bar's line, and a region following it would sit
    // over the cell the pointer is on for the length of the emerge.
    mask: root.handingOver ? passThrough : (root.fromPointer ? cardRegion : null)

    Region {
        id: passThrough
    }

    Region {
        id: cardRegion
        x: root._frameX
        y: root._frameY
        width: root._morphWidth
        height: root._morphHeight
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
                closeTimer.stop();
            else if (root.isOpen && root.fromPointer)
                closeTimer.restart();
        }
    }

    readonly property var _windows: (root.isOpen || root.visible) && root.workspaceId !== ""
        ? CompositorService.windows.filter(function (w) { return w.workspaceId === root.workspaceId; })
        : []

    on_WindowsChanged: if (root.isOpen) AppIconService.probe(root._windows)

    readonly property var _area: root._screen
        ? ({ x: root._screen.x, y: root._screen.y, width: root._screen.width, height: root._screen.height })
        : null

    // The miniature is the output's own shape at the card's content width;
    // the windows are laid out `xs` inside it.
    readonly property real _miniWidth: root._contentWidth
    readonly property real _miniHeight: root._area && root._area.width > 0
        ? Math.round(root._miniWidth * root._area.height / root._area.width)
        : Math.round(root._miniWidth * 9 / 16)
    readonly property real _miniInset: Theme.space.xs

    readonly property var _layout: WorkspacesModel.previewLayout(root._windows, root._area,
        root._miniWidth - root._miniInset * 2, root._miniHeight - root._miniInset * 2,
        Theme.space.controlHeight)

    // The window the pointer is on, for the footer.
    property string hoveredId: ""

    cursorCount: root._layout.length
    onCursorActivated: index => root._focus(index)

    function _focus(index) {
        var place = root._layout[index];
        if (!place)
            return;
        CompositorService.focusWindow(place.id);
        root.close();
    }

    // How many thumbnails are drawing real window pixels, for
    // `workspaces status`.
    function capturedCount() {
        var n = 0;
        for (var i = 0; i < thumbRepeater.count; i++) {
            var thumb = thumbRepeater.itemAt(i);
            if (thumb && thumb.captured)
                n++;
        }
        return n;
    }

    // The workspace closes its own preview by becoming the one on screen.
    Connections {
        target: CompositorService
        function onFocusedWorkspaceIdChanged() {
            if (root.isOpen && root.workspaceId !== "" && CompositorService.focusedWorkspaceId === root.workspaceId)
                root.close();
        }
    }

    // The workspace's window count beside the header's own title.
    titleActions: SectionLabel {
        text: root._windows.length + (root._windows.length === 1 ? " window" : " windows")
    }

    // The miniature: the output's own frame, the windows inside it.
    Box {
        id: mini
        visible: root._layout.length > 0
        role: "cell"
        state: "rest"
        width: root._miniWidth
        height: root._miniHeight

        Repeater {
            id: thumbRepeater
            model: root._layout.length

            Item {
                id: thumb
                required property int index
                readonly property var place: root._layout[thumb.index] || ({ id: "", x: 0, y: 0, width: 0, height: 0 })
                readonly property var win: CompositorService.windowById(thumb.place.id)
                readonly property string iconSource: thumb.win ? AppIconService.forWindow(thumb.win) : ""
                readonly property bool captured: capture.hasContent
                readonly property bool lit: thumbPointer.containsMouse || thumb.cursor
                // What Panel's cursor halo finds a row by.
                readonly property bool cursor: root.cursorActive && root.cursorIndex === thumb.index
                readonly property real radius: Theme.coverRadius(Math.min(thumb.width, thumb.height))

                // `xxs` in from its neighbours: two tiled windows share an
                // edge on screen, and two borders on one line read as one.
                x: root._miniInset + thumb.place.x + Theme.space.xxs
                y: root._miniInset + thumb.place.y + Theme.space.xxs
                width: Math.max(0, thumb.place.width - Theme.space.xxs * 2)
                height: Math.max(0, thumb.place.height - Theme.space.xxs * 2)
                z: thumb.place.floating ? 1 : 0

                // The schematic, under the capture and in its place until
                // the first frame lands: the window's own box, `selected` on
                // the one holding focus, its icon and title in it.
                Cell {
                    id: box
                    anchors.fill: parent
                    visible: !thumb.captured
                    selected: !!thumb.win && thumb.win.isFocused
                    cursor: thumb.cursor

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
                                visible: thumb.iconSource !== "" && boxIcon.status !== Image.Error
                                source: thumb.iconSource
                                sourceSize.width: box._iconSize * 2
                                sourceSize.height: box._iconSize * 2
                                fillMode: Image.PreserveAspectFit
                            }

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
                            text: thumb.win ? thumb.win.title : ""
                            elide: Text.ElideRight
                            color: box.foreground
                            font.family: Theme.fontFamilySans
                            font.pixelSize: Theme.fontSize.caption
                        }
                    }
                }

                // The window itself, rounded the way any picture is
                // (Theme.coverRadius), its border lit in `ring` under the
                // pointer or the cursor.
                ClippingRectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: thumb.radius
                    border.width: Theme.borderWidth
                    border.color: thumb.lit ? Theme.color.ring : Theme.color.border
                    contentInsideBorder: true
                    opacity: thumb.captured ? 1 : 0

                    Behavior on opacity {
                        Anim { kind: "effects" }
                    }

                    ScreencopyView {
                        id: capture
                        anchors.fill: parent
                        captureSource: (root.isOpen || root.visible) ? CompositorService.toplevelHandle(thumb.place.id) : null
                        live: root.isOpen
                    }
                }

                // The app's icon in the corner, so a small thumbnail is
                // still a window you can name.
                Box {
                    visible: thumb.captured && thumb.iconSource !== ""
                        && thumb.width > Theme.space.controlHeight * 2 && thumb.height > Theme.space.controlHeight * 1.5
                    role: "cell"
                    state: "rest"
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.space.sm
                    width: Theme.space.controlHeight - Theme.space.sm
                    height: width

                    Picture {
                        anchors.centerIn: parent
                        width: parent.width - Theme.space.sm * 2
                        height: width
                        source: thumb.iconSource
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectFit
                    }
                }

                MouseArea {
                    id: thumbPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: {
                        if (thumbPointer.containsMouse)
                            root.hoveredId = thumb.place.id;
                        else if (root.hoveredId === thumb.place.id)
                            root.hoveredId = "";
                    }
                    onClicked: root._focus(thumb.index)
                }
            }
        }
    }

    // A workspace with nothing on it: one dim line saying so, no box.
    Item {
        visible: root._layout.length === 0
        width: root._miniWidth
        height: Theme.space.controlHeight

        SectionLabel {
            anchors.centerIn: parent
            text: "No windows"
        }
    }

    // The window under the pointer, or what the card is for.
    Text {
        readonly property var hovered: root.hoveredId !== "" ? CompositorService.windowById(root.hoveredId) : null
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: hovered ? (hovered.title || hovered.appId) : "Click a window to jump to it"
        color: hovered ? Theme.color.foreground : Theme.color.mutedForeground
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.caption
    }
}
