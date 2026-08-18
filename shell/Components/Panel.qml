import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor

// The shared per-widget popout (DESIGN.md §Panels, spec §2, M6 Task 1): one
// ledger table anchored under the bar cell that opened it — header meta row
// (panelTitle) then whatever rows the instantiating panel (AudioPanel, and
// later network/bluetooth/power/calendar/weather) supplies via its default
// content slot. Same top-layer / OnDemand-keyboard structure as
// Center.qml/Osd.qml, but — unlike either — needs "closes on click-outside"
// too. Quickshell's PopupWindow gives that for free via grabFocus, but its
// xdg_popup grab needs a real pointer/key serial, which panel.open(name)
// (PanelIpc, headless verification) never has. So this stays a plain
// PanelWindow like every other surface: a transparent, exclusiveZone:-1
// layer spanning the whole screen, with a backdrop MouseArea that closes on
// any click landing outside the visible frame (the frame's own nested
// MouseArea eats its clicks first, per Qt Quick's normal nested-MouseArea
// priority, so nothing inside it ever falls through).
PanelWindow {
    id: root

    property bool isOpen: false
    // Off for every panel but MediaPanel (M35): keeps this window mapped
    // even while closed, for a caller that needs the surface alive without
    // it being open — MediaPanel's own Video decode has to keep rendering
    // for grabToImage while the bar's mini cover wants frames, and a
    // closed-but-mapped PanelWindow is otherwise unmapped the instant the
    // exit fade finishes (see `visible` below). Default false so no panel
    // besides MediaPanel changes behavior.
    property bool keepMapped: false
    // Shared cursor-visibility gate (M26 Task 8, upstream's CursorSurface
    // contract — Ui/CursorSurface.qml — restated in Cell terms): each
    // row-navigable panel keeps its own row identity (a numeric index or a
    // string key, whichever survives that panel's own list reshuffling),
    // but every row gates its `hovered` paint on this ONE flag rather than
    // reading `containsMouse`/`containsPointer` directly. A mouse entering
    // a row or the first navigation key both flip it true; a fresh open
    // starts it false, so the highlight stays invisible until the user has
    // actually reached for it instead of a stale or default position
    // painting on open.
    property bool cursorActive: false
    property string panelTitle: ""
    // Forwards into the card title-bar band's own right-side slot
    // (DESIGN.md §2 item 9, CardTitleBar.qml's `actions`) — most panels
    // never set this, so their title band stays the plain label it already
    // was; DualsensePanel's read-only "READ ONLY" tag (M29 Task 4) is the
    // first consumer.
    property alias titleActions: titleCell.actions
    property int panelWidth: Theme.space.popupWidthDefault
    // Screen-relative x of the bar cell that opened this panel, mapped within
    // that cell's OWN window (openFrom below) — Wayland gives clients no
    // cross-window global coordinates, so mapping the cell into this window's
    // coordinate space instead would be meaningless. -1 means "no cell, opened
    // via IPC", which falls back to the bar's right region, where every M6
    // widget cell lives.
    property real anchorX: -1
    // The output this popout belongs on, taken from the window of the cell
    // that opened it (openFrom below): the monitor you clicked is the monitor
    // the popout has to appear on, whatever the compositor calls focused at
    // that moment — a bar cell can be clicked without keyboard focus ever
    // leaving another output. Null means nobody named one (an IPC open), and
    // the focused output decides.
    property var anchorScreen: null
    // Focus-prime phase, read only by the keyboardFocus binding below (which
    // carries the full rationale): false for the brief Exclusive prime that
    // actually acquires keyboard focus, true once the surface can settle on
    // OnDemand without losing it.
    property bool _focusPrimed: false
    default property alias content: contentColumn.data

    // Forwarded from backdrop's own Keys.onPressed (M6 Task 7): the ONE
    // shared keyboard-nav hook every popout's content can listen to —
    // PowerPanel's profile picker is the first consumer. backdrop already
    // owns focus (forceActiveFocus() below), so a picker Item never gets
    // real focus of its own; Escape keeps working unchanged, since this
    // fires ahead of (and never accepts) the specific Keys.onEscapePressed
    // dispatch below.
    signal keyPressed(var event)

    readonly property var _screen: {
        if (root.anchorScreen) return root.anchorScreen;
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    readonly property real _frameX: {
        if (!root._screen) return 0;
        var x = root.anchorX >= 0 ? root.anchorX : (root._screen.width - root.panelWidth - Theme.space.panelGap);
        return Math.max(0, Math.min(x, root._screen.width - root.panelWidth));
    }

    // Content gets a `panelPadding` gutter (DESIGN.md §Panels "card internal
    // padding") on all four sides now — the frame draws its own explicit
    // ring on all four (below), so content's rows sit deliberately inset
    // everywhere instead of the old top/left-only gutter. Rows still draw
    // their own bottom+right per Cell's shared-rule contract (needed for the
    // divider between adjacent rows), which would otherwise double the
    // frame's new right/bottom rule 18px apart — the two `_edgeEraser`
    // rectangles below paint over just that trailing hairline with the
    // frame's own background color, leaving the frame's rule as the single
    // visible line on every edge.
    readonly property real _contentWidth: root.panelWidth - Theme.borderWidth * 2 - Theme.space.panelPadding * 2

    // Caps content to the room actually left on screen — from the frame's
    // own top (`Theme.barHeight + panelGap` below) down to a mirrored
    // `panelGap` above the screen's bottom edge, minus the frame's own
    // chrome — rather than a flat 60% of total screen height, which clipped
    // a panel well within genuinely empty space below it on a short/wide
    // monitor (the M26 calendar hero pushed CalendarPanel past a 693px-tall
    // screen's 60% cap with ~170px of untouched room still below the
    // frame). Content only ever scrolls once it truly can't fit.
    readonly property real _maxContentHeight: root._screen
        ? Math.max(0, root._screen.height - Theme.barHeight - Theme.space.panelGap * 2
            - Theme.borderWidth * 2 - Theme.space.panelPadding * 2 - titleCell.height)
        : 400
    readonly property real _frameHeight: Theme.borderWidth * 2 + Theme.space.panelPadding * 2
        + titleCell.height + Math.min(contentColumn.implicitHeight, root._maxContentHeight)

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

    // The entry point every bar cell uses: both answers a popout needs — which
    // output, and where along it — come off the cell's own window, since
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
    // Held visible through the exit fade (DESIGN.md §4): close() drops
    // isOpen, the frame's opacity Behavior runs to 0, and only then does
    // the window unmap. Keyboard focus and the backdrop release on isOpen
    // itself, so input never lands on a fading-out panel. `keepMapped`
    // extends this past the fade for MediaPanel's grabToImage need (M35).
    visible: root.isOpen || frame.opacity > 0 || root.keepMapped
    color: "transparent"
    // keepMapped alone (closed, fully faded, still mapped) is the one state
    // that must take no input at all: an empty Region resolves to an empty
    // QRegion, which QsWindow.mask turns into WindowTransparentForInput —
    // real click-through, not a disabled MouseArea (Tooltip.qml's own
    // precedent) — so a "closed" panel kept mapped for its Video decode
    // never eats a click meant for whatever is really on screen there.
    mask: (!root.isOpen && frame.opacity <= 0 && root.keepMapped) ? _clickThroughMask : null

    Region { id: _clickThroughMask }

    WlrLayershell.namespace: "formalshell:panel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Keyboard focus follows isOpen, never `visible` — the surface stays
    // mapped through the exit fade above, but input ownership has to release
    // the instant close() fires.
    //
    // OnDemand on its own is not enough to make a keyboard-summoned panel
    // usable: wlroots only hands an OnDemand surface focus once the
    // compositor routes it there, i.e. after a click. `qs ipc call panel open
    // audio` from a compositor keybind therefore produced a panel where
    // Escape did nothing and PowerPanel's arrow keys were dead. So every
    // open() primes with Exclusive — which takes focus unconditionally, both
    // at map time and when an already-mapped fade-out surface is resummoned —
    // then settles back to OnDemand once that focus has landed.
    //
    // ⚠️ Do NOT "simplify" this to the plain Exclusive binding Menu.qml and
    // PolkitDialog.qml can afford. Hyprland routes EVERY pointer event to an
    // exclusive-focus surface regardless of which output the cursor is over,
    // so a permanently-exclusive panel leaves clicks on every other monitor
    // dead — including the DismissTwins catchers below, whose entire job is
    // dismissing this panel from another output. Omarchy hit and documented
    // exactly this (its `shell/Ui/KeyboardPanel.qml` header comment); the
    // prime window is kept short so that grab is never perceptible.
    WlrLayershell.keyboardFocus: root.isOpen
        ? (root._focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    // A cold open flips `visible` before the surface exists, so open()'s own
    // call finds no backing window yet and the timer below never starts —
    // this catches the map itself. A reopen mid-fade never changes this flag
    // (the window stayed mapped throughout), which is why open() arms the
    // prime as well: between them every open path is covered exactly once.
    onBackingWindowVisibleChanged: root._beginFocusPrime()

    function _beginFocusPrime() {
        if (root.isOpen && root.backingWindowVisible)
            focusPrimeTimer.restart();
    }

    Timer {
        id: focusPrimeTimer
        // Room for several Qt/Wayland commit cycles — the compositor grants
        // focus on the commit carrying the Exclusive role, not on the QML
        // property write — while keeping the compositor-wide pointer grab
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
        // regardless — this pins that contract rather than leaning on it.
        Keys.priority: Keys.BeforeItem
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => root.keyPressed(event)
        onClicked: root.close()

        Item {
            id: frame
            x: root._frameX
            y: Theme.barHeight + Theme.space.panelGap
            width: root.panelWidth
            height: root._frameHeight

            // Enter/exit (DESIGN.md §4): fade plus a slide down from under
            // the bar, both driven by the one animated scalar so reopening
            // mid-exit reverses from wherever the fade is.
            opacity: root.isOpen ? 1 : 0
            transform: Translate { y: (frame.opacity - 1) * Theme.motion.slide }

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            // The window itself is transparent (it needs the click-outside
            // backdrop to span the whole screen), so the frame paints its
            // own surface — otherwise every cell in it stays see-through,
            // since Cell.qml's background only opaques on
            // selected/accent/hovered. Center.qml fills for the same reason.
            Rectangle {
                anchors.fill: parent
                color: Theme.color.background
            }

            // Swallows clicks anywhere inside the frame (including padding
            // between rows) before they ever reach the backdrop above —
            // ordinary nested-MouseArea priority, no manual event plumbing.
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                id: topRule
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.borderWidth
                color: Theme.color.rule
            }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: Theme.borderWidth
                color: Theme.color.rule
            }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: Theme.borderWidth
                color: Theme.color.rule
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Theme.borderWidth
                color: Theme.color.rule
            }

            CardTitleBar {
                id: titleCell
                anchors.top: topRule.bottom
                anchors.topMargin: Theme.space.panelPadding
                anchors.left: parent.left
                anchors.leftMargin: Theme.borderWidth + Theme.space.panelPadding
                width: root._contentWidth
                title: root.panelTitle
            }

            Flickable {
                id: contentFlickable
                anchors.top: titleCell.bottom
                anchors.left: parent.left
                anchors.leftMargin: Theme.borderWidth + Theme.space.panelPadding
                anchors.right: parent.right
                anchors.rightMargin: Theme.borderWidth + Theme.space.panelPadding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.borderWidth + Theme.space.panelPadding
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight

                Column {
                    id: contentColumn
                    width: parent.width
                }
            }

            // Erases the trailing hairline every row (and titleCell itself)
            // draws along its own right edge (Cell's shared-rule contract) —
            // without this, that continuous line and the frame's own right
            // rule above would read as two parallel borders `panelPadding`
            // apart, the exact doubling b044c8e fixed for the old flush
            // layout.
            Rectangle {
                anchors.top: titleCell.top
                anchors.right: contentFlickable.right
                anchors.bottom: contentFlickable.bottom
                width: Theme.borderWidth
                color: Theme.color.background
            }

            // Same erasure for the bottom: the last row's own bottom rule
            // sits flush with contentFlickable's own bottom edge whenever
            // content fits without scrolling, which would otherwise double
            // the frame's own bottom rule above.
            Rectangle {
                anchors.left: contentFlickable.left
                anchors.right: contentFlickable.right
                anchors.bottom: contentFlickable.bottom
                height: Theme.borderWidth
                color: Theme.color.background
            }

            // Dog-ear fold mark (DESIGN.md §2 item 7) — every panel popout,
            // including the picker's own reuse of this frame.
            DogEar {}
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
