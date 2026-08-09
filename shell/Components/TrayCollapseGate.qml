import QtQuick

// Arm/cancel state machine for the tray drawer's auto-collapse timer (M20
// Task 5d, owner: "auto close after an interval if no cursor is on it
// anymore or no system tray menu is open" — shell/Surfaces/Bar/widgets/
// Tray.qml). Owns no MouseArea, no Timer, no Quickshell service reference:
// Tray.qml drives it from its own aggregated row hover, the shared
// QsMenuAnchor's `visible`, and TrayService.drawerExpanded, and reads
// `armed` to gate its real Timer's `running` — the same separation
// PointerMoveGate.qml uses for its own pointer decision, so this machine is
// unit-testable without a real pointer or a real elapsed interval.
//
// Contract:
//  - freshExpansion() on every transition INTO the expanded state: a new
//    expansion starts unvisited, so a drawer the pointer never enters never
//    arms (an expanded drawer this repo's smoke rig only ever opens over
//    IPC — no synthetic pointer crosses it — must stay open, or the rig's
//    expanded screenshot would flap shut mid-run).
//  - collapsed() on every transition OUT of the expanded state, so a stale
//    visited flag can never leak into a later expansion.
//  - rowEntered() / rowExited() from the caller's own aggregated row hover.
//  - menuOpened() / menuClosed() from an open tray-item context menu.
//  - `armed` is true only once the row has been visited AND then left AND
//    no menu is open. Re-entering the row or a menu opening both clear it
//    immediately; leaving again, or the menu closing, re-arms it from
//    scratch (a full restart, not a resume) as long as the row stayed
//    visited.
QtObject {
    id: root

    property bool _visited: false
    property bool _hovered: false
    property bool _menuOpen: false

    readonly property bool armed: root._visited && !root._hovered && !root._menuOpen

    function freshExpansion() {
        root._visited = false;
    }

    function collapsed() {
        root._visited = false;
    }

    function rowEntered() {
        root._hovered = true;
        root._visited = true;
    }

    function rowExited() {
        root._hovered = false;
    }

    function menuOpened() {
        root._menuOpen = true;
    }

    function menuClosed() {
        root._menuOpen = false;
    }
}
