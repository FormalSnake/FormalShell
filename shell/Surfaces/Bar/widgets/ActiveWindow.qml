import QtQuick
import Quickshell
import qs.Core
import qs.Compositor
import qs.Components

// Icon and app name of the focused window (DESIGN.md §3 "Bar", the bar's
// one image-icon exception): the desktop entry behind the focused window's
// appId (DesktopEntries.heuristicLookup, the same lookup the launcher uses)
// supplies the themed icon and the display name, which leads in foreground;
// the window title follows dimmed. Both are words, so both are sans. No
// entry resolves: falls back to the dim raw appId, the foreground title and
// no icon. No focused window: hidden. The app name elides and the title
// marquee-scrolls once the combined label would exceed maxWidth, which the
// whole pill (padding included) is capped to, the bar setting it to a
// quarter of its own width under a hard ceiling. Text colours resolve
// through `foreground`/`dimForeground` rather than hardcoded roles, so a
// filled cell carries every one of them.
//
// Clicking the cell toggles the app menu (AppMenuPanel) under it, macOS's
// app-name menu in the same place the app name already sits. The window it
// names is CompositorService.heldFocusedWindowId, not the raw focused id, so
// opening that menu (or any other panel) doesn't empty the cell it was
// opened from, see Compositor/focus.js.
Cell {
    id: root

    property real maxWidth: 320
    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    // Set from Bar.qml (`windowVisible: bar.visible`) so the title marquee
    // below can gate on the bar's own PanelWindow actually being on screen,
    // same rationale as NowPlaying.qml's own windowVisible. Defaults true so
    // any other embedding still animates.
    property bool windowVisible: true

    readonly property var focusedWindow: CompositorService.windowById(CompositorService.heldFocusedWindowId)

    readonly property string appId: focusedWindow ? focusedWindow.appId : ""
    readonly property string title: focusedWindow ? focusedWindow.title : ""

    readonly property var desktopEntry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null

    // check=true so a theme that can't resolve the entry's icon name
    // yields "", the Image slot below then simply doesn't render, the
    // same missing-texture-free contract as MenuRow's app rows.
    readonly property string iconSource: (root.desktopEntry && root.desktopEntry.icon)
        ? Quickshell.iconPath(root.desktopEntry.icon, true)
        : ""

    readonly property bool shown: root.focusedWindow !== null
    visible: root.shown

    // `maxWidth` is the whole pill's ceiling, so the row content gets it
    // minus the cell's own control padding.
    readonly property real _contentMaxWidth: Math.max(0, root.maxWidth - Theme.space.controlPaddingX * 2)

    // Focus/title changes resize this cell (window switch, title rename),
    // animate the extent instead of shoving the bar's other widgets
    // instantly (DESIGN.md §4, M16 Task 2). Both axes, since which one the
    // cell grows along is the bar's edge.
    Behavior on implicitWidth {
        enabled: root.animateSize
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

    Behavior on implicitHeight {
        enabled: root.animateSize
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
    }

    CellRow {
        id: row
        spacing: Theme.space.xxs
        width: root.vertical ? implicitWidth : Math.min(implicitWidth, root._contentMaxWidth)
        height: root.vertical ? Math.min(implicitHeight, root._contentMaxWidth) : implicitHeight
        clip: true

        // The bar's one image-icon exception (DESIGN.md §3 "Bar"), sized to
        // the label beside it, and only when the entry resolves one.
        Picture {
            id: appIcon
            visible: root.iconSource !== ""
            source: root.iconSource
            width: nameSlot.implicitHeight
            height: nameSlot.implicitHeight
            sourceSize.width: nameSlot.implicitHeight
            sourceSize.height: nameSlot.implicitHeight
            fillMode: Image.PreserveAspectFit
        }

        // Two slots, Icon.qml's own pattern (DESIGN.md §1 Motion, M53 D3):
        // the outgoing name stays in whichever slot is idle and fades while
        // the incoming one rises, so a focus change reads as this label
        // changing under the cell's width morph rather than as a cut. Each
        // slot holds its own ink as well as its own string, so the name that
        // is leaving keeps the colour it was written in.
        Item {
            id: nameSlot
            // Entry found: its name leads in foreground. No entry: the raw
            // appId, dimmed, today's exact fallback rendering.
            readonly property string _name: root.desktopEntry ? (root.desktopEntry.name || root.appId) : root.appId
            readonly property bool _dim: !root.desktopEntry

            // 1 draws slot A, 0 draws slot B; the Behavior is on the driver
            // rather than on each slot's opacity so the two can never fall
            // out of step, and a name that changes again mid-fade retargets
            // this animation instead of restarting it.
            property real _cross: nameSlot._frontIsA ? 1 : 0
            property bool _frontIsA: true
            property bool _armed: false
            // The bindings below are evaluated during creation, which emits
            // a change of its own before the first install has run; without
            // this the very first name would arrive as a crossfade out of an
            // empty slot.
            property bool _ready: false
            property string _textA: ""
            property bool _dimA: false
            property string _textB: ""
            property bool _dimB: false

            Behavior on _cross {
                NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
            }

            // Dropped on a vertical bar: an app name is words, and 44px of
            // strip holds none of them upright. The icon above it says which
            // app this is and the tooltip spells it out, so the strip spends
            // its length on the title instead.
            visible: nameSlot._name !== "" && !root.vertical
            implicitWidth: nameSlot._frontIsA ? nameA.width : nameB.width
            // The row's icon is sized off this, so it stays the line's own
            // height whichever slot is in front and whether or not there is
            // a name to draw at all.
            implicitHeight: nameA.implicitHeight

            Component.onCompleted: {
                nameSlot._install(false);
                nameSlot._ready = true;
            }
            on_NameChanged: {
                if (nameSlot._ready)
                    nameSlot._install(true);
            }
            on_DimChanged: {
                if (nameSlot._ready)
                    nameSlot._install(true);
            }

            function _install(animate) {
                // Two windows of the same app carry one name, and a
                // crossfade between a string and itself is a frame of
                // nothing happening.
                if (animate && nameSlot._name === (nameSlot._frontIsA ? nameSlot._textA : nameSlot._textB)
                        && nameSlot._dim === (nameSlot._frontIsA ? nameSlot._dimA : nameSlot._dimB))
                    return;

                if (!animate || !nameSlot._frontIsA) {
                    nameSlot._textA = nameSlot._name;
                    nameSlot._dimA = nameSlot._dim;
                } else {
                    nameSlot._textB = nameSlot._name;
                    nameSlot._dimB = nameSlot._dim;
                }
                if (!animate)
                    return;
                nameSlot._armed = true;
                nameSlot._frontIsA = !nameSlot._frontIsA;
            }

            Text {
                id: nameA
                text: nameSlot._textA
                color: nameSlot._dimA ? root.dimForeground : root.foreground
                opacity: nameSlot._cross
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
                // Never more than half the row's own budget: an entry name (or
                // a raw appId in the no-entry fallback) long enough to eat the
                // whole thing otherwise starves the title of every pixel and
                // gets hard-cut mid-glyph by the row's own clip, since a Row
                // won't shrink it.
                width: Math.min(implicitWidth, root._contentMaxWidth * 0.5)
                elide: Text.ElideRight
            }

            Text {
                id: nameB
                visible: nameSlot._armed
                text: nameSlot._textB
                color: nameSlot._dimB ? root.dimForeground : root.foreground
                opacity: 1 - nameSlot._cross
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
                width: Math.min(implicitWidth, root._contentMaxWidth * 0.5)
                elide: Text.ElideRight
            }
        }

        // M-polish batch item A: the window title scrolls on overflow via
        // the shared MarqueeText mechanism (Components/MarqueeText.qml,
        // extracted from NowPlaying.qml's M16 Task 11 now-playing ticker).
        // `leftPadding` widens the gap to the app name without touching
        // `row.spacing`, that stays tight (xxs) for the icon+name lockup.
        //
        // It is also the one thing on the bar that turns rather than
        // stacking: a title is free text of no fixed length, so 44px of
        // strip cannot hold it upright and abbreviating it would leave the
        // cell saying nothing (Bar/layout.js's labelRotation). The slot
        // swaps the marquee's own box, since a rotated item still measures
        // by the box it had before the turn.
        Item {
            id: titleSlot
            width: root.vertical ? titleText.height : titleText.width
            height: root.vertical ? titleText.width : titleText.height

            MarqueeText {
                id: titleText
                anchors.centerIn: parent
                rotation: root.labelRotation
                text: root.title
                // Roles swap once an entry is found: the title follows dimmed
                // instead of leading foreground.
                color: root.desktopEntry ? root.dimForeground : root.foreground
                leftPadding: root.vertical ? 0 : Theme.space.md
                windowVisible: root.windowVisible
                maxWidth: {
                    var used = 0;
                    if (appIcon.visible)
                        used += appIcon.width + row.spacing;
                    if (nameSlot.visible)
                        used += nameSlot.width + row.spacing;
                    return Math.max(0, root._contentMaxWidth - used);
                }
            }
        }
    }

    panelOpen: root._panelOpen

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
