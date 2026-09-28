import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../../Bar/workspaces.js" as WorkspacesModel

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// The workspace row, Spaces (DESIGN.md §3 Bar, M74): one ghost `Cell` per
// workspace on this bar's output, each its ordinal (mono) followed by the
// icons of the windows on it, drawn the way every other cell on the strip
// is. Which workspaces show, in what order, and which windows each one
// lists is ../../../Bar/workspaces.js's call; the icons come off
// AppIconService, the same chain the switcher's tiles use, and the agent
// badges off HerdrService.
//
// A group rail rather than a Cell, like Indicators.qml: each workspace is
// its own cell and answers the pointer as one (the hover wash, the ink
// lifted off `dimForeground`), and Bar.qml's ghost, band ink and edge are
// handed down to them. Every occupied workspace shows its icons
// (`workspaces.showApps`, `all` by default; `active` and `hover` narrow
// it). Resting on another occupied workspace for the tooltip's own delay
// opens its preview (Surfaces/Panels/WorkspacePreview.qml), live
// thumbnails of its windows.
//
// The focused workspace is marked by the `cell` role's `active` fill, one
// item under the cells that moves rather than a fill each cell owns (M48):
// a switch reads as the pill travelling from the old workspace to the new
// one. Its two edges take different clocks (`emphasized` for the edge
// arriving, twice that for the edge leaving), so it stretches across the
// gap and closes up behind itself. Cells differ in length, so each end is
// its own pair of edges chasing the same end of the target cell, and
// whichever of a pair is ahead falls out of min/max rather than needing
// the direction. Both are zeroed by `motion.enabled=false` like every other
// transition, and at zero the pill simply appears on its cell.
//
// On a left or right bar nothing turns: the cells stack down the strip, a
// cell's icons stack under its number, and the number stands upright, like
// every other cell's content (Bar/layout.js's labelRotation). The same pill
// runs along the strip's own axis.
Item {
    id: root

    property string outputName: ""
    // shell.qml's single WorkspacePreview, through Bar.qml.
    property var preview: null

    // Bar.qml sets these on the widget it loads; this rail is not a Cell
    // itself, so it hands them to each cell it holds (DESIGN.md §3 Bar).
    property bool ghost: false
    property string barEdge: ""
    property color barInk: "transparent"
    property var barInkShadow: []
    property bool animateSize: true

    readonly property bool vertical: root.barEdge === "left" || root.barEdge === "right"

    implicitWidth: root.vertical ? Theme.space.barCellWidth : slotGrid.width
    implicitHeight: root.vertical ? slotGrid.height : Theme.space.barCellHeight

    // --- Settings (workspaces.*). Look is the theme's; these are what the
    // cell holds, never how it draws it.
    function _int(value, low, high, fallback) {
        var n = Math.round(Number(value));
        return isFinite(n) ? Math.max(low, Math.min(high, n)) : fallback;
    }

    readonly property string _showApps: String(Config.get("workspaces.showApps", "all"))
    readonly property int _maxIcons: root._int(Config.get("workspaces.maxIcons", 8), 1, 20, 8)
    readonly property int _persistent: root._int(Config.get("workspaces.persistent", 5), 0, 10, 5)
    readonly property bool _agents: Config.get("workspaces.agents", true) !== false
    readonly property bool _previewEnabled: Config.get("workspaces.preview", true) !== false

    // Maintained rather than a raw binding on CompositorService.workspaces/
    // windows: HyprlandBackend.qml keeps windows apart from workspaces so a
    // title-only tick can't republish the workspace list, but slots() reads
    // both. Recomputed on either input and published only when the resolved
    // model actually differs, which a title or a rect never makes it do
    // (workspaces.js keeps both out of it).
    property var slots: []
    property string _slotsJson: "[]"

    function _updateSlots() {
        var next = WorkspacesModel.slots(CompositorService.workspaces, CompositorService.windows,
            root.outputName, { persistent: root._persistent, maxIcons: root._maxIcons });
        var json = JSON.stringify(next);
        if (json === root._slotsJson)
            return;
        root._slotsJson = json;
        root.slots = next;
        var all = [];
        for (var i = 0; i < next.length; i++)
            all = all.concat(next[i].windows);
        AppIconService.probe(all);
    }

    onOutputNameChanged: root._updateSlots()
    on_MaxIconsChanged: root._updateSlots()
    on_PersistentChanged: root._updateSlots()
    Component.onCompleted: {
        root._updateSlots();
        if (root.preview)
            root.preview.addCell(root);
    }
    Component.onDestruction: if (root.preview) root.preview.removeCell(root)
    onPreviewChanged: if (root.preview) root.preview.addCell(root)

    Connections {
        target: CompositorService
        function onWorkspacesChanged() { root._updateSlots(); }
        function onWindowsChanged() { root._updateSlots(); }
    }

    readonly property int _focusedIndex: {
        for (var i = 0; i < root.slots.length; i++) {
            if (root.slots[i].isFocused)
                return i;
        }
        return -1;
    }

    // --- Geometry: every workspace is a bar cell, so its padding, its
    // thickness and the `sm` between it and the next are the strip's own.
    // The icons are the height of the number's line, as the window title's
    // app icon is sized to its name.
    readonly property real _cellGap: Theme.space.sm
    readonly property real _iconGap: Theme.space.xs
    readonly property real _badgeSize: Theme.fontSize.caption

    // Each cell's settled length, in order, and where each starts. Read off
    // the cells' own targets rather than their animated extents, so the pill
    // travels to where the cell is going instead of chasing it there.
    property var _extents: []

    function _start(index) {
        var at = 0;
        for (var i = 0; i < index && i < root._extents.length; i++)
            at += root._extents[i] + root._cellGap;
        return at;
    }

    function _measureSlots() {
        var next = [];
        for (var i = 0; i < slotRepeater.count; i++) {
            var item = slotRepeater.itemAt(i);
            next.push(item ? item.targetAlong : 0);
        }
        if (JSON.stringify(next) !== JSON.stringify(root._extents))
            root._extents = next;
        pill._syncTarget();
    }

    function _remeasure() {
        Qt.callLater(root._measureSlots);
    }

    on_FocusedIndexChanged: pill._syncTarget()
    on_ExtentsChanged: pill._syncTarget()

    // --- Preview (Surfaces/Panels/WorkspacePreview.qml). The pointer opens
    // it after the tooltip's own delay (Components/TooltipGroup.qml, 400ms);
    // once one is up, moving to another cell moves the card with no second
    // wait, the way a tooltip hands off inside its grace. The number and the
    // icons are one target for this: each cell tracks the pointer with a
    // HoverHandler of its own, which stays hovered under an icon's
    // MouseArea where the cell's own MouseArea does not.
    readonly property bool _previewUp: !!root.preview && root.preview.isOpen && root.preview.fromPointer

    function _previews(ws) {
        return root._previewEnabled && !!root.preview && !ws.current && ws.windows.length > 0;
    }

    Timer {
        id: hoverTimer
        property Item slotItem: null
        interval: 400
        onTriggered: {
            var item = hoverTimer.slotItem;
            if (item && item.slotHovered && root._previews(item.ws))
                root.preview.show(item, item.ws, true);
        }
    }

    function _slotEntered(item) {
        if (!root.preview)
            return;
        if (!root._previews(item.ws)) {
            hoverTimer.stop();
            if (root._previewUp)
                root.preview.release();
            return;
        }
        if (root._previewUp) {
            if (root.preview.slot && root.preview.slot.idx === item.ws.idx)
                root.preview.hold();
            else
                root.preview.show(item, item.ws, true);
            return;
        }
        hoverTimer.slotItem = item;
        hoverTimer.restart();
    }

    function _slotLeft(item) {
        if (hoverTimer.slotItem === item)
            hoverTimer.stop();
        if (root._previewUp)
            root.preview.release();
    }

    function _go(ws) {
        if (root.preview && root.preview.isOpen)
            root.preview.close();
        if (ws.current && ws.isFocused)
            return;
        if (ws.id !== "")
            CompositorService.focusWorkspace(ws.id);
        else
            CompositorService.focusWorkspaceAt(ws.idx);
    }

    // `workspaces peek <n>` (Ipc/WorkspacesIpc.qml): the cell whose ordinal
    // is `n`, previewed with no pointer to follow.
    function peek(n) {
        for (var i = 0; i < root.slots.length; i++) {
            if (root.slots[i].idx === n) {
                var item = slotRepeater.itemAt(i);
                if (!item || !root.preview)
                    return false;
                root.preview.show(item, root.slots[i], false);
                return true;
            }
        }
        return false;
    }

    // `workspaces status`: the cells as this rail resolved them, with each
    // icon's agent state and each cell's settled length, which is how the
    // rig tells them apart without reading pixels. Every `rect` is in the
    // bar window's own coordinates, where the rig parks a real pointer and
    // crops its frames.
    function _rectOf(item) {
        if (!item)
            return { x: 0, y: 0, width: 0, height: 0 };
        var origin = item.mapToItem(null, 0, 0);
        return {
            x: Math.round(origin.x),
            y: Math.round(origin.y),
            width: Math.round(item.width),
            height: Math.round(item.height)
        };
    }

    function status() {
        return root.slots.map(function (ws, i) {
            var item = slotRepeater.itemAt(i);
            return {
                id: ws.id,
                idx: ws.idx,
                label: ws.label,
                active: ws.current,
                focused: ws.isFocused,
                urgent: ws.isUrgent,
                placeholder: ws.placeholder,
                appsShown: item ? item.showsApps : false,
                extent: root._extents[i] || 0,
                rect: root._rectOf(item),
                overflow: ws.overflow,
                icons: ws.windows.map(function (w, at) {
                    return {
                        id: w.id,
                        appId: w.appId,
                        focused: w.isFocused,
                        icon: AppIconService.forWindow(w) !== "",
                        agent: root._agentState(w.id),
                        rect: root._rectOf(item ? item.iconAt(at) : null)
                    };
                })
            };
        });
    }

    function _agentState(windowId) {
        return root._agents && windowId !== "" ? (HerdrService.stateByWindow[windowId] || "") : "";
    }

    // A wheel notch steps one workspace, wrapping. A touchpad reports a
    // notch as many small deltas, so they are summed to a notch's worth
    // first. Under the cells, which hand every notch back (Cell.qml's own
    // onWheel), so it lands here wherever on the row it was scrolled.
    property real _wheelSum: 0

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            if (delta === 0)
                return;
            wheel.accepted = true;
            root._wheelSum += delta;
            if (Math.abs(root._wheelSum) < 120)
                return;
            var next = WorkspacesModel.stepIndex(root.slots.length, root._focusedIndex, root._wheelSum < 0 ? 1 : -1);
            root._wheelSum = 0;
            if (next >= 0)
                root._go(root.slots[next]);
        }
    }

    Item {
        id: strip
        x: root.vertical ? (root.width - strip.width) / 2 : 0
        y: root.vertical ? 0 : (root.height - strip.height) / 2
        // The grid's own size, cells mid-glide included, so the rail's
        // length travels with them and needs no width Behavior of its own.
        width: slotGrid.width
        height: slotGrid.height

        // The focused workspace's pill, under the cells: the fill an `active`
        // cell draws, on the table's own corner. `lead*` and `trail*` chase
        // the same end of the same cell at different speeds; the pill spans
        // the outermost of each pair.
        Box {
            id: pill
            role: "cell"
            box: {
                var composed = {};
                var base = Theme.box("cell", "active");
                for (var key in base)
                    composed[key] = base[key];
                composed.border = null;
                return composed;
            }

            // Focus leaving this output (another monitor took it) is the
            // pill leaving a surface, not travelling: it fades out where it
            // stood and fades back in at whatever cell focus returns to. The
            // travel Behaviors below are disarmed while nothing is drawn, so
            // a re-entry lands at its cell instead of running there from a
            // stale one.
            readonly property bool _here: root._focusedIndex >= 0
            opacity: pill._here ? 1 : 0
            visible: pill.opacity > 0

            Behavior on opacity {
                Anim { kind: "effects" }
            }

            property real targetStart: 0
            property real targetEnd: 0

            function _syncTarget() {
                if (root._focusedIndex < 0 || root._focusedIndex >= root._extents.length)
                    return;
                var start = root._start(root._focusedIndex);
                pill.targetStart = start;
                pill.targetEnd = start + root._extents[root._focusedIndex];
            }

            property real leadStart: pill.targetStart
            property real trailStart: pill.targetStart
            property real leadEnd: pill.targetEnd
            property real trailEnd: pill.targetEnd

            readonly property real _from: Math.min(pill.leadStart, pill.trailStart)
            readonly property real _to: Math.max(pill.leadEnd, pill.trailEnd)

            x: root.vertical ? 0 : pill._from
            y: root.vertical ? pill._from : 0
            width: root.vertical ? strip.width : pill._to - pill._from
            height: root.vertical ? pill._to - pill._from : strip.height

            // Both edges of a pair on `emphasized`, the trailing one over
            // twice the clock (M54 D2, caelestia's ActiveIndicator): the
            // leading edge reaches the new cell while the trailing edge is
            // still leaving the old one. The one place in the shell that
            // spells a duration of its own, because the relationship between
            // the two edges IS the effect and a second token would be a name
            // with one caller.
            Behavior on leadStart {
                enabled: pill.visible && root.animateSize
                Anim { kind: "emphasized" }
            }
            Behavior on leadEnd {
                enabled: pill.visible && root.animateSize
                Anim { kind: "emphasized" }
            }
            Behavior on trailStart {
                enabled: pill.visible && root.animateSize
                Anim { kind: "emphasized"; duration: Theme.motion.emphasized * 2 }
            }
            Behavior on trailEnd {
                enabled: pill.visible && root.animateSize
                Anim { kind: "emphasized"; duration: Theme.motion.emphasized * 2 }
            }
        }

        Grid {
            id: slotGrid
            columns: root.vertical ? 1 : Math.max(1, slotRepeater.count)
            columnSpacing: root._cellGap
            rowSpacing: root._cellGap

            Repeater {
                id: slotRepeater
                // A count rather than the array itself: the model is a fresh
                // array on every focus change, and a Repeater handed one
                // rebuilds every delegate, which would snap every cell's
                // length instead of letting the ones that changed travel.
                model: root.slots.length
                onItemAdded: root._remeasure()
                onItemRemoved: root._remeasure()

                Cell {
                    id: slot
                    required property int index
                    readonly property var ws: root.slots[slot.index] || ({
                        id: "", idx: 0, label: "", current: false, isFocused: false,
                        isUrgent: false, placeholder: true, windows: [], overflow: 0
                    })

                    ghost: root.ghost
                    barEdge: root.barEdge
                    barInk: root.barInk
                    barInkShadow: root.barInkShadow
                    animateSize: root.animateSize

                    interactive: true
                    onClicked: root._go(slot.ws)
                    // The pill is this cell's fill while it is focused, and an
                    // `active` cell takes no wash.
                    hovered: slot.slotHovered && !slot.ws.isFocused
                    panelOpen: !!root.preview && root.preview.isOpen
                        && !!root.preview.slot && root.preview.slot.idx === slot.ws.idx

                    // The ink an `active` cell resolves while the pill is
                    // under this one; otherwise the cell's own, band included.
                    foreground: slot.ws.isFocused
                        ? Theme.color.primaryForeground
                        : slot.bandInk ? slot.barInk : Theme.color.foreground
                    dimForeground: slot.ws.isFocused
                        ? Theme.color.primaryForeground
                        : slot.bandInk ? slot.barInk : Theme.color.mutedForeground

                    readonly property bool slotHovered: slotHover.hovered

                    HoverHandler {
                        id: slotHover
                        parent: slot
                        onHoveredChanged: {
                            if (slotHover.hovered)
                                root._slotEntered(slot);
                            else
                                root._slotLeft(slot);
                        }
                    }

                    readonly property bool occupied: slot.ws.windows.length > 0
                    readonly property bool showsApps: slot.occupied
                        && WorkspacesModel.showsApps(root._showApps, slot.ws.current, slot.slotHovered)
                    readonly property int shownIcons: slot.showsApps ? slot.ws.windows.length : 0
                    readonly property bool showsOverflow: slot.showsApps && slot.ws.overflow > 0

                    function iconAt(at) {
                        return at < iconRepeater.count ? iconRepeater.itemAt(at) : null;
                    }

                    // An agent on this workspace waiting on the user: the
                    // number breathes in `destructive` until it is looked at,
                    // unless it is the one on screen already.
                    readonly property bool waiting: root._agents && !slot.ws.current
                        && slot.ws.windows.some(function (w) { return HerdrService.stateByWindow[w.id] === "blocked"; })

                    // The length the cell settles on, and the length it is
                    // drawn at, gliding there on the arm switch every bar
                    // cell's own width takes.
                    readonly property real targetAlong: slot.vertical ? slot.implicitHeight : slot.implicitWidth
                    onTargetAlongChanged: root._remeasure()

                    property real along: slot.targetAlong
                    Behavior on along {
                        enabled: root.animateSize
                        Anim {}
                    }

                    width: root.vertical ? root.width : slot.along
                    height: root.vertical ? slot.along : root.height
                    clip: slot.along < slot.targetAlong

                    CellRow {
                        spacing: root._iconGap

                        CellLabel {
                            id: label
                            text: slot.ws.label
                            color: slot.ws.isUrgent || slot.waiting
                                ? Theme.color.destructive
                                : (slot.ws.isFocused || slot.ws.current || slot.slotHovered)
                                    ? slot.foreground
                                    : slot.dimForeground

                            Behavior on color {
                                CAnim {}
                            }

                            // One pulse when a workspace turns urgent, not a
                            // loop: the destructive colour is the standing
                            // state, the pulse is the thing that just happened.
                            SequentialAnimation {
                                id: urgentPulse
                                Anim { target: label; property: "opacity"; to: 0.3; kind: "effects" }
                                Anim { target: label; property: "opacity"; to: 1; kind: "effectsSlow" }
                            }

                            // The breathing pulse (Theme.motion.pulseDuration,
                            // DESIGN.md §1's continuous-motion carve-out), for
                            // as long as the agent waits.
                            SequentialAnimation on opacity {
                                running: slot.waiting
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                                NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                            }
                        }

                        Rail {
                            id: icons
                            visible: slot.shownIcons > 0
                            vertical: slot.vertical
                            spacing: root._iconGap
                            glide: false

                            Repeater {
                                id: iconRepeater
                                model: slot.shownIcons

                                Item {
                                    id: iconItem
                                    required property int index
                                    readonly property var win: slot.ws.windows[iconItem.index] || null
                                    readonly property string winId: iconItem.win ? iconItem.win.id : ""
                                    readonly property string source: iconItem.win ? AppIconService.forWindow(iconItem.win) : ""
                                    readonly property string agent: root._agentState(iconItem.winId)
                                    readonly property bool hovered: iconPointer.containsMouse
                                    readonly property bool focusedHere: slot.ws.isFocused && !!iconItem.win && iconItem.win.isFocused
                                    readonly property real size: label.implicitHeight

                                    width: iconItem.size
                                    height: iconItem.size

                                    // On the focused workspace, every window but
                                    // the one holding focus steps back.
                                    property real _dim: slot.ws.isFocused && !iconItem.focusedHere && !iconItem.hovered ? 0.5 : 1
                                    Behavior on _dim {
                                        Anim { kind: "effects" }
                                    }

                                    // Arrives faded up rather than cut in, on
                                    // the arm switch the cell's length takes.
                                    property real _in: root.animateSize ? 0 : 1
                                    Component.onCompleted: iconItem._in = 1
                                    Behavior on _in {
                                        enabled: root.animateSize
                                        Anim { kind: "effects" }
                                    }

                                    Item {
                                        anchors.fill: parent
                                        opacity: iconItem._in * iconItem._dim

                                        Picture {
                                            id: appIcon
                                            anchors.fill: parent
                                            visible: iconItem.source !== "" && appIcon.status !== Image.Error
                                            source: iconItem.source
                                            sourceSize.width: iconItem.size * 2
                                            sourceSize.height: iconItem.size * 2
                                            fillMode: Image.PreserveAspectFit
                                        }

                                        // Nothing in the chain answered: the
                                        // generic window mark, as the switcher
                                        // draws it.
                                        Icon {
                                            anchors.centerIn: parent
                                            visible: !appIcon.visible
                                            name: "app-window"
                                            size: Theme.fontSize.body
                                            color: label.color
                                        }
                                    }

                                    // herdr's word on the agent in this
                                    // window (Services/HerdrService.qml): a
                                    // spinner while it works, a pulsing alert
                                    // while it waits on the user, a check once
                                    // it is done. Nothing at all for idle,
                                    // unknown, or no herdr.
                                    Item {
                                        id: badge
                                        visible: iconItem.agent !== ""
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: -Theme.space.xxs
                                        anchors.topMargin: -Theme.space.xxs
                                        width: root._badgeSize
                                        height: root._badgeSize

                                        // primitive-exempt: the badge's own
                                        // backing disc, which keeps the glyph
                                        // readable over the app icon under it.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.pillRadius(badge.width)
                                            color: Theme.color.background
                                        }

                                        Icon {
                                            anchors.centerIn: parent
                                            width: badge.width
                                            height: badge.height
                                            size: badge.width
                                            name: iconItem.agent === "working"
                                                ? "loader-circle"
                                                : iconItem.agent === "blocked" ? "circle-alert" : "circle-check"
                                            color: iconItem.agent === "blocked"
                                                ? Theme.color.destructive
                                                : iconItem.agent === "done" ? Theme.color.primary : Theme.color.foreground

                                            // A spinner turns on the breathing
                                            // pulse's own clock, and not at all
                                            // under motion.enabled=false.
                                            RotationAnimator on rotation {
                                                running: badge.visible && iconItem.agent === "working" && Theme.motionEnabled
                                                from: 0
                                                to: 360
                                                duration: Theme.motion.pulseDuration
                                                loops: Animation.Infinite
                                            }
                                        }

                                        SequentialAnimation on opacity {
                                            running: badge.visible && iconItem.agent === "blocked"
                                            loops: Animation.Infinite
                                            alwaysRunToEnd: true
                                            NumberAnimation { to: 0.4; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                                            NumberAnimation { to: 1.0; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                                        }
                                    }

                                    MouseArea {
                                        id: iconPointer
                                        anchors.fill: parent
                                        anchors.margins: -root._iconGap / 2
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.preview && root.preview.isOpen)
                                                root.preview.close();
                                            if (iconItem.winId !== "")
                                                CompositorService.focusWindow(iconItem.winId);
                                        }
                                        // No tooltip while the preview is up:
                                        // the card already names every window
                                        // it shows, and the two would stack.
                                        onContainsMouseChanged: {
                                            if (iconPointer.containsMouse && iconItem.winId !== "" && !root._previewUp)
                                                TooltipRegistry.show(iconItem, root._iconTooltip(iconItem.winId, iconItem.agent), root.barEdge);
                                            else
                                                TooltipRegistry.hide(iconItem);
                                        }
                                    }
                                }
                            }

                            // Windows past `workspaces.maxIcons`, counted.
                            Text {
                                visible: slot.showsOverflow
                                text: "+" + slot.ws.overflow
                                color: label.color
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSize.caption
                                font.weight: Theme.weight.medium
                            }
                        }
                    }

                    readonly property bool urgent: slot.ws.isUrgent
                    onUrgentChanged: if (slot.urgent) urgentPulse.restart()
                }
            }
        }
    }

    // The preview opening under a parked pointer takes the tooltip down
    // with it.
    on_PreviewUpChanged: if (root._previewUp) TooltipRegistry.hide(null)

    readonly property var _agentWords: ({
        working: "Agent working",
        blocked: "Agent waiting on you",
        done: "Agent done"
    })

    // The window's title read live (the model carries no titles), with
    // herdr's word on its agent after it.
    function _iconTooltip(windowId, agent) {
        var win = CompositorService.windowById(windowId);
        var title = win ? (win.title || win.appId || "") : "";
        return agent !== "" ? title + " / " + root._agentWords[agent] : title;
    }
}
