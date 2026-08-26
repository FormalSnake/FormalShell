import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import "cursor.js" as Cursor
import "geometry.js" as Geometry

// The shared per-widget popout (DESIGN.md §3 "Panel", spec "Panels"): a
// bordered card anchored under the bar cell that opened it, opening with a
// header row (icon, title, ghost icon buttons) and holding whatever sections
// the instantiating panel supplies through its default content slot. Same
// top-layer / OnDemand-keyboard structure as Center.qml/Osd.qml, but, unlike
// either, needs "closes on click-outside" too. Quickshell's PopupWindow gives
// that for free via grabFocus, but its xdg_popup grab needs a real pointer/key
// serial, which panel.open(name) (PanelIpc, headless verification) never has.
// So this stays a plain PanelWindow like every other surface: a transparent,
// exclusiveZone:-1 layer spanning the whole screen, with a backdrop MouseArea
// that closes on any click landing outside the visible frame (the frame's own
// nested MouseArea eats its clicks first, per Qt Quick's normal nested-
// MouseArea priority, so nothing inside it ever falls through).
PanelWindow {
    id: root

    property bool isOpen: false
    // Off for every panel but MediaPanel (M35): keeps this window mapped
    // even while closed, for a caller that needs the surface alive without
    // it being open. MediaPanel's own Video decode has to keep rendering for
    // grabToImage while the bar's mini cover wants frames, and a
    // closed-but-mapped PanelWindow is otherwise unmapped the instant the
    // exit fade finishes (see `visible` below). Default false so no panel
    // besides MediaPanel changes behavior.
    property bool keepMapped: false
    // Shared cursor-visibility gate (upstream's CursorSurface contract):
    // every row gates its cursor paint on this ONE flag rather than reading
    // `containsMouse`/`containsPointer` directly. A mouse entering a row or
    // the first navigation key both flip it true; a fresh open starts it
    // false, so the cursor stays invisible until the user has actually
    // reached for it instead of a stale or default position painting on
    // open.
    property bool cursorActive: false
    property string panelTitle: ""
    // A Lucide name (shell/Theme/icons.js) drawn before the title. Empty
    // leaves the header text-only.
    property string panelIcon: ""
    // The header's own right-side slot, ahead of the close button every
    // panel gets for free. Meant for `IconButton`s.
    property alias titleActions: actionsRow.data
    property int panelWidth: Theme.space.popupWidthDefault
    // The frame's own fill and corner. A panel is a `card` at `radiusXl`
    // (DESIGN.md §3); the tray menu is the one popout that is a menu rather
    // than a panel and takes the `popover` fill at `radiusMd` instead.
    property color frameColor: Theme.surface(Theme.color.card)
    property int frameRadius: Theme.radiusXl
    // Screen-relative x of the bar cell that opened this panel, mapped within
    // that cell's OWN window (openFrom below). Wayland gives clients no
    // cross-window global coordinates, so mapping the cell into this window's
    // coordinate space instead would be meaningless. -1 means "no cell, opened
    // via IPC", which falls back to the bar's right region, where every
    // widget cell lives.
    property real anchorX: -1
    // The output this popout belongs on, taken from the window of the cell
    // that opened it (openFrom below): the monitor you clicked is the monitor
    // the popout has to appear on, whatever the compositor calls focused at
    // that moment, since a bar cell can be clicked without keyboard focus
    // ever leaving another output. Null means nobody named one (an IPC open),
    // and the focused output decides.
    property var anchorScreen: null
    // Focus-prime phase, read only by the keyboardFocus binding below (which
    // carries the full rationale): false for the brief Exclusive prime that
    // actually acquires keyboard focus, true once the surface can settle on
    // OnDemand without losing it.
    property bool _focusPrimed: false
    default property alias content: contentColumn.data

    // --- Keyboard cursor -------------------------------------------------
    //
    // The bookkeeping every keyboard-driven panel shares (spec "Keyboard
    // model"): `cursorCount` is set by the consuming panel to its row count,
    // `cursorIndex` is the row the arrows sit on, and `cursorSection` is
    // which block of the panel Tab has reached (0 is the row list; a panel
    // with a footer control sets `sectionCount: 2`). The maths is in
    // cursor.js.
    property int cursorIndex: 0
    property int cursorCount: 0
    property int cursorSection: 0
    property int sectionCount: 1
    // Set by the panel while one of its `Input`s holds focus: the keys are
    // that field's then, not the cursor's.
    property bool inlineEditorFocused: false

    // Left/Right steps the value on the cursor row rather than walking the
    // list, for a panel whose rows carry an adjustable track (Audio).
    property bool cursorStepsHorizontally: false

    // Above 1, `cursorIndex` addresses a grid of this many columns rather
    // than a list (Calendar's month): Up/Down step a whole week and
    // Left/Right stop at the ends of their own week.
    property int cursorColumns: 1

    signal cursorActivated(int index)
    // `x` on a row that has a destructive action (Bluetooth's forget).
    signal cursorDeleted(int index)
    // A step on the cursor row, `direction` -1 or 1.
    signal cursorStepped(int index, int direction)
    // Any printable key the catcher does not bind itself, for a panel with
    // a single-letter action of its own (Audio's `m`).
    signal cursorTextKey(string text)

    // Forwarded from backdrop's own Keys.onPressed: the raw-event hook for a
    // panel whose keyboard model predates the cursor above (PowerPanel's
    // profile picker, BluetoothPanel's row list). It runs BEFORE the
    // KeyCatcher: a consumer that accepts the event keeps it, and only what
    // nobody claimed reaches the catcher's dispatch. The reverse order would
    // have the catcher swallow Up/Down/Enter out from under every panel that
    // still reads them here.
    signal keyPressed(var event)

    function moveCursor(dx, dy) {
        if (Cursor.isStep(dx, dy, root.cursorStepsHorizontally, root.cursorActive)) {
            root.cursorStepped(root.cursorIndex, dx > 0 ? 1 : -1);
            return;
        }
        var next = Cursor.move(root.cursorIndex, root.cursorCount, root.cursorActive, dx, dy, root.cursorColumns);
        root.cursorIndex = next.index;
        root.cursorActive = next.active;
    }

    function activateCursor() {
        var index = Cursor.activation(root.cursorIndex, root.cursorCount, root.cursorActive, root.cursorSection);
        if (index >= 0)
            root.cursorActivated(index);
    }

    function deleteCursor() {
        var index = Cursor.activation(root.cursorIndex, root.cursorCount, root.cursorActive, root.cursorSection);
        if (index >= 0)
            root.cursorDeleted(index);
    }

    function moveSection(direction) {
        root.cursorSection = Cursor.section(root.cursorSection, root.sectionCount, direction);
        root.cursorActive = true;
    }

    // Hands the keyboard back to the panel after an inline editor gave it
    // up: a field that goes invisible leaves the window with no focus item
    // at all, and the surface would stop answering keys entirely.
    function takeKeyboard() {
        backdrop.forceActiveFocus();
    }

    readonly property var _screen: {
        if (root.anchorScreen) return root.anchorScreen;
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // One padding rule (DESIGN.md §1, M48 D3): every floating surface sits
    // `barMargin` under the bar and `screenPadding` in from the screen edge
    // it hangs from. An IPC open has no cell to anchor to and falls back to
    // the right edge, at the same `screenPadding`; a cell-anchored open is
    // clamped so neither edge can push the frame past it.
    readonly property real _frameX: root._screen
        ? Geometry.frameX(root.anchorX, root._screen.width, root.panelWidth, Theme.space.screenPadding)
        : 0

    readonly property real _contentWidth: root.panelWidth - Theme.space.panelPadding * 2

    // The tallest the frame may be: the screen minus the bar, the
    // `barMargin` the frame hangs off it by, and one `screenPadding` above
    // the bottom edge. Content beyond that scrolls (contentFlickable below)
    // rather than the panel running off the display, which the notification
    // centre and a long calendar month both did.
    readonly property real _maxFrameHeight: root._screen
        ? Geometry.maxFrameHeight(root._screen.height, Theme.barHeight,
            Theme.space.barMargin, Theme.space.screenPadding)
        : 400
    // Header, the rule under it, then the content column (DESIGN.md §3
    // "Panel"): one `panelPadding` either side of the seam, so the header
    // sits in the same gutter the card's own padding gives every other edge.
    readonly property real _headerGap: Theme.space.panelPadding * 2 + Theme.borderWidth

    readonly property real _maxContentHeight: Geometry.maxContentHeight(root._maxFrameHeight,
        Theme.space.panelPadding, header.height, root._headerGap)
    readonly property real _frameHeight: Geometry.frameHeight(contentColumn.implicitHeight,
        root._maxContentHeight, Theme.space.panelPadding, header.height, root._headerGap)

    function open(x, screen) {
        if (PanelRegistry.current && PanelRegistry.current !== root)
            PanelRegistry.current.close();
        PanelRegistry.current = root;
        root.anchorX = x !== undefined ? x : -1;
        root.anchorScreen = screen !== undefined ? screen : null;
        root.isOpen = true;
        root._focusPrimed = false;
        root._beginFocusPrime();
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    function close() {
        root.isOpen = false;
        root.cursorActive = false;
        if (PanelRegistry.current === root)
            PanelRegistry.current = null;
    }

    function toggle(x, screen) {
        if (root.isOpen) root.close();
        else root.open(x, screen);
    }

    // The entry point every bar cell uses: both answers a popout needs, which
    // output and where along it, come off the cell's own window, since
    // Wayland hands clients no cross-window geometry. Same `QsWindow.window`
    // idiom Tooltip.qml resolves its own anchor through.
    function openFrom(item) {
        var window = item ? item.QsWindow.window : null;
        root.open(item ? item.mapToItem(null, 0, 0).x : -1, window ? window.screen : null);
    }

    function toggleFrom(item) {
        if (root.isOpen) root.close();
        else root.openFrom(item);
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §1 "Motion"): close()
    // drops isOpen, the frame's opacity Behavior runs to 0, and only then
    // does the window unmap. Keyboard focus and the backdrop release on
    // isOpen itself, so input never lands on a fading-out panel.
    // `keepMapped` extends this past the fade for MediaPanel's grabToImage
    // need (M35).
    visible: root.isOpen || frame.opacity > 0 || root.keepMapped
    color: "transparent"
    // keepMapped alone (closed, fully faded, still mapped) is the one state
    // that must take no input at all: an empty Region resolves to an empty
    // QRegion, which QsWindow.mask turns into WindowTransparentForInput, real
    // click-through rather than a disabled MouseArea (Tooltip.qml's own
    // precedent), so a "closed" panel kept mapped for its Video decode never
    // eats a click meant for whatever is really on screen there.
    mask: (!root.isOpen && frame.opacity <= 0 && root.keepMapped) ? _clickThroughMask : null

    Region { id: _clickThroughMask }

    WlrLayershell.namespace: "formalshell:panel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Keyboard focus follows isOpen, never `visible`: the surface stays
    // mapped through the exit fade above, but input ownership has to release
    // the instant close() fires.
    //
    // OnDemand on its own is not enough to make a keyboard-summoned panel
    // usable: wlroots only hands an OnDemand surface focus once the
    // compositor routes it there, i.e. after a click. `qs ipc call panel open
    // audio` from a compositor keybind therefore produced a panel where
    // Escape did nothing and PowerPanel's arrow keys were dead. So every
    // open() primes with Exclusive, which takes focus unconditionally, both
    // at map time and when an already-mapped fade-out surface is resummoned,
    // then settles back to OnDemand once that focus has landed.
    //
    // ⚠️ Do NOT "simplify" this to the plain Exclusive binding Menu.qml and
    // PolkitDialog.qml can afford. Hyprland routes EVERY pointer event to an
    // exclusive-focus surface regardless of which output the cursor is over,
    // so a permanently-exclusive panel leaves clicks on every other monitor
    // dead, including the DismissTwins catchers below, whose entire job is
    // dismissing this panel from another output. Omarchy hit and documented
    // exactly this (its `shell/Ui/KeyboardPanel.qml` header comment); the
    // prime window is kept short so that grab is never perceptible.
    WlrLayershell.keyboardFocus: root.isOpen
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    // A cold open flips `visible` before the surface exists, so open()'s own
    // call finds no backing window yet and the timer below never starts:
    // this catches the map itself. A reopen mid-fade never changes this flag
    // (the window stayed mapped throughout), which is why open() arms the
    // prime as well. Between them every open path is covered exactly once.
    onBackingWindowVisibleChanged: root._beginFocusPrime()

    function _beginFocusPrime() {
        if (root.isOpen && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        // Room for several Qt/Wayland commit cycles (the compositor grants
        // focus on the commit carrying the Exclusive role, not on the QML
        // property write) while keeping the compositor-wide pointer grab
        // described above far too brief to notice.
        interval: 75
        onTriggered: if (root.isOpen) root._focusPrimed = true
    }

    anchors { top: true; left: true; right: true; bottom: true }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: root.isOpen
        focus: true
        // Explicit despite matching Item's own default: states outright that
        // row navigation has to win over contentFlickable's scroll, which is
        // a descendant of this MouseArea and never holds focus of its own
        // (open() always forces it here), so key events land here first
        // regardless. This pins that contract rather than leaning on it.
        Keys.priority: Keys.BeforeItem
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            root.keyPressed(event);
            if (!event.accepted)
                keyCatcher.handle(event);
        }
        onClicked: root.close()

        Card {
            id: frame
            x: root._frameX
            y: Theme.barHeight + Theme.space.barMargin
            width: root.panelWidth
            height: root._frameHeight
            color: root.frameColor
            radius: root.frameRadius

            opacity: root.isOpen ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            // Enter is the fade plus a slide down from the bar edge; exit is
            // opacity alone (DESIGN.md §1 "Motion"). Nothing writes this
            // during the exit, so the only visible run is the one on the way
            // in; the re-arm below happens behind a frame that has already
            // finished fading out.
            property real slide: -Theme.motion.slide

            transform: Translate { y: frame.slide }

            Behavior on slide {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            onOpacityChanged: if (frame.opacity <= 0) frame.slide = -Theme.motion.slide

            Connections {
                target: root
                function onIsOpenChanged() {
                    if (root.isOpen)
                        frame.slide = 0;
                }
            }

            // Swallows clicks anywhere inside the frame (the card's own
            // padding included) before they ever reach the backdrop above:
            // ordinary nested-MouseArea priority, no manual event plumbing.
            // The negative margins undo the card's content inset, which this
            // has to cover.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -frame.padding
                onClicked: {}
            }

            // A header row is `controlHeight` tall (DESIGN.md §1 Padding),
            // stated rather than inferred from whichever control inside it
            // happens to be tallest.
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.space.controlHeight

                Icon {
                    id: headerIcon
                    visible: root.panelIcon !== ""
                    name: root.panelIcon
                    size: Theme.fontSize.subtitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: titleText
                    anchors.left: headerIcon.visible ? headerIcon.right : parent.left
                    anchors.leftMargin: headerIcon.visible ? Theme.space.iconGap : 0
                    anchors.right: actionsRow.left
                    anchors.rightMargin: Theme.space.iconGap
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.panelTitle
                    color: Theme.color.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.subtitle
                    font.weight: Theme.weight.semibold
                    elide: Text.ElideRight
                }

                Row {
                    id: actionsRow
                    anchors.right: closeButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.xs
                }

                IconButton {
                    id: closeButton
                    name: "x"
                    tooltipText: "Close"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.close()
                }
            }

            // The header's seam (DESIGN.md §1's ladder rung 4, §3 "Panel"):
            // every panel draws it, so the card reads as a titled sheet
            // rather than as a title floating over a list. Full-bleed, which
            // the negative margins buy back out of the Card's own padding:
            // a rule stopping short of the border would read as a division
            // of the rows rather than of the card.
            Separator {
                id: headerRule
                anchors.top: header.bottom
                anchors.topMargin: Theme.space.panelPadding
                anchors.left: parent.left
                anchors.leftMargin: -frame.padding
                anchors.right: parent.right
                anchors.rightMargin: -frame.padding
            }

            // The ring reservation (DESIGN.md §1 "Ring", M48 D2): a clipping
            // container grows its clip rect by `ringWidth` on every side and
            // insets its content by the same, so the halo a cursor row draws
            // outside its own border has somewhere to land and every row
            // keeps the x, width and top it had without one. The overhang
            // eats `ringWidth` of the card's own padding and of the gap under
            // the header, both of which are several times that.
            Flickable {
                id: contentFlickable
                anchors.top: headerRule.bottom
                anchors.topMargin: Theme.space.panelPadding - Theme.ringWidth
                anchors.left: parent.left
                anchors.leftMargin: -Theme.ringWidth
                anchors.right: parent.right
                anchors.rightMargin: -Theme.ringWidth
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -Theme.ringWidth
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight + Theme.ringWidth * 2

                WheelScroll { flickable: contentFlickable }

                // Never focused: the backdrop owns the keyboard (see its
                // Keys.onPressed, which drives this by hand so `keyPressed`
                // consumers get first refusal).
                KeyCatcher {
                    id: keyCatcher
                    focus: false
                    x: Theme.ringWidth
                    y: Theme.ringWidth
                    width: contentFlickable.width - Theme.ringWidth * 2
                    height: contentColumn.implicitHeight
                    blocked: Cursor.catcherBlocked(root.isOpen, root.inlineEditorFocused)

                    onMoveRequested: (dx, dy) => root.moveCursor(dx, dy)
                    onActivateRequested: root.activateCursor()
                    onDeleteRequested: root.deleteCursor()
                    onCloseRequested: root.close()
                    onTabRequested: direction => root.moveSection(direction)
                    onTextKey: text => root.cursorTextKey(text)

                    Column {
                        id: contentColumn
                        width: parent.width
                        spacing: Theme.space.sectionGap
                    }
                }
            }
        }
    }

    // Multi-monitor dismiss (M16 Task 7): backdrop above only ever catches
    // clicks on this panel's own output.
    DismissTwins {
        active: root.isOpen
        ownScreen: root.screen
        onDismissed: root.close()
    }
}
