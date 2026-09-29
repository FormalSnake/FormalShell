import QtQuick
import Quickshell
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../Bar/workspaces.js" as WorkspacesModel
import "../../Components/cursor.js" as Cursor

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// The Spaces cell's workspace preview (M74, DESIGN.md §3 Bar): a card
// hanging off a workspace's bar cell, under the panel header naming the
// workspace and its window count, holding a miniature of the output with each window at its own
// place and full size, drawn live, and a footer naming the window under the
// pointer. Windows past the output's edge (a scrolling layout parks them
// there) sit outside the miniature, which scrolls over the union of the
// output and every window and opens on the output's own region.
// Click a window (or Enter on the cursor) to focus it.
//
// The thumbnails are Components/WindowThumb.qml, a ScreencopyView on each
// window's toplevel handle, live while the card is open and torn down with
// the window when it closes. A window with no handle, or one the compositor
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
        root._scrolled = false;
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
    // it is the viewport onto the windows, laid out `xs` inside it at the
    // scale the output would have at that width.
    readonly property real _miniWidth: root._contentWidth
    readonly property real _miniHeight: root._area && root._area.width > 0
        ? Math.round(root._miniWidth * root._area.height / root._area.width)
        : Math.round(root._miniWidth * 9 / 16)
    readonly property real _miniInset: Theme.space.xs
    readonly property real _viewWidth: root._miniWidth - root._miniInset * 2
    readonly property real _viewHeight: root._miniHeight - root._miniInset * 2

    readonly property var _plan: WorkspacesModel.previewLayout(root._windows, root._area,
        root._viewWidth, root._viewHeight, Theme.space.controlHeight)
    readonly property var _layout: root._plan.windows

    // Set once the wheel, a drag or the keyboard cursor has moved the view,
    // so a rect refresh landing after the open does not pull it back.
    property bool _scrolled: false

    on_PlanChanged: if (!root._scrolled) root._home()

    // Opens on what is on screen now: the output's own region of the strip.
    function _home() {
        view.contentX = root._plan.home.x;
        view.contentY = root._plan.home.y;
    }

    function _scrollBy(dx, dy) {
        var mx = Math.max(0, view.contentWidth - view.width);
        var my = Math.max(0, view.contentHeight - view.height);
        view.contentX = Math.max(0, Math.min(mx, view.contentX + dx));
        view.contentY = Math.max(0, Math.min(my, view.contentY + dy));
        root._scrolled = true;
    }

    // The thumbnail under the keyboard cursor, brought into the viewport.
    function _followCursor() {
        var place = root._layout[root.cursorIndex];
        if (!root.isOpen || !root.cursorActive || !place)
            return;
        var x = Cursor.follow(place.x, place.width, view.contentX, view.width, view.contentWidth, 0);
        var y = Cursor.follow(place.y, place.height, view.contentY, view.height, view.contentHeight, 0);
        if (x === view.contentX && y === view.contentY)
            return;
        view.contentX = x;
        view.contentY = y;
        root._scrolled = true;
    }

    onCursorIndexChanged: Qt.callLater(root._followCursor)
    onCursorActiveChanged: Qt.callLater(root._followCursor)

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

    // The miniature's scroll position and extent beside the viewport, and
    // each thumbnail's drawn box with the window's real one, for
    // `workspaces status`.
    function viewState() {
        var thumbs = [];
        for (var i = 0; i < thumbRepeater.count; i++) {
            var thumb = thumbRepeater.itemAt(i);
            var win = thumb ? thumb.win : null;
            if (!thumb || !win || !win.rect)
                continue;
            thumbs.push({
                id: thumb.place.id,
                x: Math.round(thumb.x), y: Math.round(thumb.y),
                width: Math.round(thumb.width), height: Math.round(thumb.height),
                rect: { x: win.rect.x, y: win.rect.y, width: win.rect.width, height: win.rect.height }
            });
        }
        return {
            scale: root._area && root._area.width > 0 ? root._viewWidth / root._area.width : 0,
            inset: Theme.space.xxs,
            view: { width: Math.round(view.width), height: Math.round(view.height) },
            content: { width: Math.round(view.contentWidth), height: Math.round(view.contentHeight) },
            scroll: { x: Math.round(view.contentX), y: Math.round(view.contentY) },
            home: { x: Math.round(root._plan.home.x), y: Math.round(root._plan.home.y) },
            thumbs: thumbs
        };
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

        Flickable {
            id: view
            anchors.fill: parent
            anchors.margins: root._miniInset
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width, root._plan.bounds.width)
            contentHeight: Math.max(height, root._plan.bounds.height)
            onMovementStarted: root._scrolled = true

            // A vertical notch moves the strip along whichever axis
            // overflows; a sideways one (or a vertical one with both
            // overflowing) keeps its own axis.
            WheelHandler {
                readonly property bool wide: view.contentWidth > view.width
                readonly property bool tall: view.contentHeight > view.height
                enabled: wide || tall
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120) * Theme.space.controlHeight;
                    var dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : (event.angleDelta.x / 120) * Theme.space.controlHeight;
                    if (wide && !tall && dx === 0) {
                        dx = dy;
                        dy = 0;
                    }
                    root._scrollBy(-dx, -dy);
                }
            }

            Repeater {
                id: thumbRepeater
                model: root._layout.length

                Item {
                    id: thumb
                    required property int index
                    readonly property var place: root._layout[thumb.index] || ({ id: "", x: 0, y: 0, width: 0, height: 0 })
                    readonly property var win: CompositorService.windowById(thumb.place.id)
                    readonly property string iconSource: thumb.win ? AppIconService.forWindow(thumb.win) : ""
                    readonly property bool captured: picture.captured
                    readonly property bool lit: thumbPointer.containsMouse || thumb.cursor
                    // What Panel's cursor halo finds a row by.
                    readonly property bool cursor: root.cursorActive && root.cursorIndex === thumb.index

                    // `xxs` in from its neighbours: two tiled windows share an
                    // edge on screen, and two borders on one line read as one.
                    x: thumb.place.x + Theme.space.xxs
                    y: thumb.place.y + Theme.space.xxs
                    width: Math.max(0, thumb.place.width - Theme.space.xxs * 2)
                    height: Math.max(0, thumb.place.height - Theme.space.xxs * 2)
                    z: thumb.place.floating ? 1 : 0

                    WindowThumb {
                        id: picture
                        anchors.fill: parent
                        win: thumb.win
                        iconSource: thumb.iconSource
                        capturing: root.isOpen || root.visible
                        live: root.isOpen
                        lit: thumb.lit
                        selected: !!thumb.win && thumb.win.isFocused
                        cursor: thumb.cursor
                        badge: true
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
