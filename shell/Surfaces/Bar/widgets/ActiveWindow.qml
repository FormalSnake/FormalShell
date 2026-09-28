import QtQuick
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services

// Icon and app name of the focused window (DESIGN.md §3 "Bar", the bar's
// one image-icon exception): the desktop entry behind the focused window
// (AppIconService.entryFor, the same class/process/title chain the launcher
// and the switcher use) supplies the themed icon and the display name, which
// leads in foreground; the window title follows dimmed. Both are words, so
// both are sans. No entry resolves: falls back to the dim raw appId, the
// foreground title and no icon. No focused window: hidden. The app name
// elides past a fixed width, and the title marquee-scrolls once it outgrows
// `labelBudget`, the room Bar.qml works out the strip actually has for it
// (Bar/layout.js's labelBudgets). Text
// colours resolve through `foreground`/`dimForeground` rather than
// hardcoded roles, so a filled cell carries every one of them.
//
// Clicking the cell toggles the app menu (AppMenuPanel) under it, macOS's
// app-name menu in the same place the app name already sits. The window it
// names is CompositorService.heldFocusedWindowId, not the raw focused id, so
// opening that menu (or any other panel) doesn't empty the cell it was
// opened from, see Compositor/focus.js.
Cell {
    id: root

    property var panel: null

    // Assigned by Bar.qml's label refit, never bound: the budget is worked
    // out from this cell's own extent, so a binding would close a loop. The
    // default holds wherever no bar hands one out (the chevron's second
    // bar), where there is no strip to run out of.
    property real labelBudget: Theme.space.popupWidthWide
    readonly property real labelCap: Number.POSITIVE_INFINITY
    // What the title draws along the strip now and would draw uncapped,
    // the two numbers the refit reads. Zero while hidden, so an absent cell
    // claims no room.
    readonly property real labelExtent: root.shown ? titleText.width : 0
    readonly property real naturalLabelWidth: root.shown ? titleText._fullWidth : 0
    readonly property bool labelScrolling: titleText._marquee

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false
    // Set from Bar.qml (`windowVisible: bar.visible`) so the title marquee
    // below can gate on the bar's own PanelWindow actually being on screen,
    // same rationale as NowPlaying.qml's own windowVisible. Defaults true so
    // any other embedding still animates.
    property bool windowVisible: true

    readonly property var focusedWindow: CompositorService.windowById(CompositorService.heldFocusedWindowId)

    readonly property string appId: focusedWindow ? focusedWindow.appId : ""
    readonly property string title: focusedWindow ? focusedWindow.title : ""

    readonly property var desktopEntry: root.focusedWindow ? AppIconService.entryFor(root.focusedWindow) : null

    // "" when the entry names no icon, the Image slot below then simply
    // doesn't render, the same missing-texture-free contract as MenuRow's
    // app rows.
    readonly property string iconSource: root.desktopEntry ? AppIconService.source(root.desktopEntry.icon) : ""

    // A class-less window (empty appId and initialClass, the process chain's
    // job) needs its /proc read before entryFor's second tier can answer;
    // Switcher.qml probes the same way for its tiles.
    onFocusedWindowChanged: if (root.focusedWindow) AppIconService.probe([root.focusedWindow]);

    readonly property bool shown: root.focusedWindow !== null
    visible: root.shown

    // The app name's own ceiling. Fixed rather than a share of the budget:
    // the title is what gives ground, and a name that shrank with it would
    // leave the cell unable to say which app it is.
    readonly property real _nameMaxWidth: Theme.space.popupWidthNarrow / 2

    // Focus/title changes resize this cell (window switch, title rename),
    // animate the extent instead of shoving the bar's other widgets
    // instantly (DESIGN.md §4, M16 Task 2). Both axes, since which one the
    // cell grows along is the bar's edge.
    Behavior on implicitWidth {
        enabled: root.animateSize
        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.animateSize
        Anim {}
    }

    CellRow {
        id: row
        spacing: Theme.space.xxs
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
                Anim { kind: "effects" }
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
                // An entry name (or a raw appId in the no-entry fallback)
                // long enough to eat the whole cell otherwise starves the
                // title and gets hard-cut mid-glyph by the row's own clip,
                // since a Row won't shrink it.
                width: Math.min(implicitWidth, root._nameMaxWidth)
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
                width: Math.min(implicitWidth, root._nameMaxWidth)
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
                maxWidth: root.labelBudget
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
