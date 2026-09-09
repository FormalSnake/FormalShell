pragma Singleton
import Quickshell
import QtQuick

// Cross-panel mutual exclusion (M6 Task 1 follow-up): every Panel.qml
// instance is a standalone top-level PanelWindow (AudioPanel, CalendarPanel,
// ...) with no knowledge of its siblings, and panels open from two
// unrelated entry points, a bar widget's click handler calling
// panel.toggle() directly, and PanelIpc's `panel open <name>` calling
// panel.open(), neither of which knows what else is open. This singleton
// is the one thing both paths share: Panel.qml's open() closes whatever
// `current` still points at before taking the slot itself, so at most one
// panel is ever open regardless of how it was opened.
Singleton {
    id: root

    property var current: null

    // Every mapped bar strip, in creation order. An open with no click
    // behind it (PanelIpc's `toggle`/`toggleAt`, a compositor keybind) still
    // has to find the cell its panel hangs off, and Bar.qml exists once per
    // output inside a Variants delegate that nothing outside can address,
    // while PanelIpc answers for the whole shell: this singleton is again
    // the one thing both ends already share. Reassigned rather than mutated
    // in place, so a consumer binding to it re-evaluates.
    property var bars: []

    function addBar(bar) {
        if (root.bars.indexOf(bar) < 0)
            root.bars = root.bars.concat([bar]);
    }

    function removeBar(bar) {
        root.bars = root.bars.filter(function (other) { return other !== bar; });
    }
}
