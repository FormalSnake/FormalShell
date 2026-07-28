pragma Singleton
import Quickshell
import QtQuick

// Cross-panel mutual exclusion (M6 Task 1 follow-up): every Panel.qml
// instance is a standalone top-level PanelWindow (AudioPanel, CalendarPanel,
// ...) with no knowledge of its siblings, and panels open from two
// unrelated entry points — a bar widget's click handler calling
// panel.toggle() directly, and PanelIpc's `panel open <name>` calling
// panel.open() — neither of which knows what else is open. This singleton
// is the one thing both paths share: Panel.qml's open() closes whatever
// `current` still points at before taking the slot itself, so at most one
// panel is ever open regardless of how it was opened.
Singleton {
    property var current: null
}
