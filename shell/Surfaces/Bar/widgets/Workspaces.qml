import QtQuick
import qs.Core
import qs.Components
import qs.Compositor
import qs.Services
import "../../../Bar/workspaces.js" as WorkspacesModel

// Portions from omarchy-spaces (MIT, Copyright 2026 Tornike Gomareli)

// The workspace row, Spaces (DESIGN.md §3 Bar, M74): one chip per workspace
// on this bar's output, each its ordinal (mono) followed by the icons of the
// windows on it, laid out the way omarchy-spaces' own pill delegate is. Which
// chips show, in what order, and which windows each one lists is
// ../../../Bar/workspaces.js's call; the icons come off AppIconService, the
// same chain the switcher's tiles use, and the agent badges off
// HerdrService.
//
// Every occupied chip shows its icons (`workspaces.showApps`, `all` by
// default; `active` and `hover` narrow it). An occupied chip sits on the
// `cell` role's hover wash, the one under the pointer on its press wash, an
// empty one on nothing. On the focused chip the window holding focus sits
// on a plate of the same wash and the rest are dimmed. Resting on another
// occupied chip for the tooltip's own delay opens its preview
// (Surfaces/Panels/WorkspacePreview.qml), live thumbnails of its windows.
//
// The focused chip's own fill is one item that moves rather than a fill
// each chip owns (M48): a switch reads as the fill travelling from the old
// chip to the new one. Its two edges take different clocks (`emphasized`
// for the edge arriving, twice that for the edge leaving), so it stretches
// across the gap and closes up behind itself. Chips differ in length, so
// each end is its own pair of edges chasing the same end of the target
// chip, and whichever of a pair is ahead falls out of min/max rather than
// needing the direction. Both are zeroed by `motion.enabled=false` like
// every other transition, and at zero the fill simply appears on its chip.
//
// On a left or right bar nothing turns: chips stack down the strip, a
// chip's icons stack under its number, and the number stands upright, like
// every other cell's content (Bar/layout.js's labelRotation). The same fill
// runs along the strip's own axis.
Cell {
    id: root

    property string outputName: ""
    // shell.qml's single WorkspacePreview, through Bar.qml.
    property var preview: null

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

    // --- Geometry, after the plugin's delegate: a chip is the bar's cell
    // thickness across, an icon sits on a plate `xs` in from the chip's
    // edges and `xxs` round the icon, and the number is `md` from the
    // chip's start. A bare number is never narrower than the chip is thick,
    // so an empty workspace is a square.
    readonly property real _chipThickness: Theme.space.barCellHeight
    readonly property real _plateSize: root._chipThickness - Theme.space.xs * 2
    readonly property real _iconSize: root._plateSize - Theme.space.xxs * 2
    readonly property real _chipPad: Theme.space.md
    readonly property real _chipGap: Theme.space.xs
    readonly property real _labelGap: Theme.space.sm
    readonly property real _iconGap: Theme.space.xxs
    readonly property real _badgeSize: Theme.fontSize.caption
    // Concentric with the plate `xs` inside it.
    readonly property int _chipRadius: Theme.box("cell").radius
    readonly property int _plateRadius: Math.max(0, root._chipRadius - Theme.space.xs)

    // Each chip's settled length, in order, and where each starts. Read off
    // the chips' own targets rather than their animated extents, so the fill
    // travels to where the chip is going instead of chasing it there.
    property var _extents: []

    function _start(index) {
        var at = 0;
        for (var i = 0; i < index && i < root._extents.length; i++)
            at += root._extents[i] + root._chipGap;
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

    // Which chip the pointer is over. -1 means none.
    property int _hoveredIndex: -1

    // --- Preview (Surfaces/Panels/WorkspacePreview.qml). The pointer opens
    // it after the tooltip's own delay (Components/TooltipGroup.qml, 400ms);
    // once one is up, moving to another chip moves the card with no second
    // wait, the way a tooltip hands off inside its grace. The number and the
    // icons are one target for this: the chip's HoverHandler stays hovered
    // under an icon's own MouseArea.
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
            if (item && item.hovered && root._previews(item.ws))
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

    // `workspaces peek <n>` (Ipc/WorkspacesIpc.qml): the chip whose ordinal
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

    // `workspaces status`: the chips as this cell resolved them, with each
    // icon's agent state and each chip's settled length, which is how the
    // rig tells the chips apart without reading pixels. Every `rect` is in
    // the bar window's own coordinates, where the rig parks a real pointer
    // and crops its frames.
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

    // A wheel notch steps one chip, wrapping. A touchpad reports a notch as
    // many small deltas, so they are summed to a notch's worth first.
    property real _wheelSum: 0

    interactive: true
    acceptedButtons: Qt.NoButton
    // The chips answer the pointer themselves; a wash over the whole row
    // would say the row is one target.
    hovered: false

    onWheeled: wheel => {
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

    // A composed ghost box carrying one wash: the chips and the icon plate
    // are fills a theme already describes (its pointer washes), laid on
    // shapes the cell owns.
    function _washed(color) {
        var composed = {};
        var base = Theme.box("cell", "ghost");
        for (var key in base)
            composed[key] = base[key];
        composed.wash = color;
        return composed;
    }

    Item {
        id: strip
        x: root.vertical ? (parent.width - strip.width) / 2 : 0
        y: root.vertical ? 0 : (parent.height - strip.height) / 2
        // The grid's own size, chips mid-glide included, so the cell's
        // length travels with them and needs no width Behavior of its own.
        width: slotGrid.width
        height: slotGrid.height

        // The focused chip's fill, under the chips. `lead*` and `trail*`
        // chase the same end of the same chip at different speeds; the fill
        // spans the outermost of each pair.
        Box {
            id: pill
            role: "cell"
            // The table's own selected fill, with no border: a raised chip,
            // omarchy-spaces' `subtle` active style, and a fill travelling
            // between chips rather than a box around one.
            box: {
                var composed = {};
                var base = Theme.box("cell", "selected");
                for (var key in base)
                    composed[key] = base[key];
                composed.border = null;
                return composed;
            }
            radius: root._chipRadius

            // Focus leaving this output (another monitor took it) is the
            // fill leaving a surface, not travelling: it fades out where it
            // stood and fades back in at whatever chip focus returns to. The
            // travel Behaviors below are disarmed while nothing is drawn, so
            // a re-entry lands at its chip instead of running there from a
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
            width: root.vertical ? root._chipThickness : pill._to - pill._from
            height: root.vertical ? pill._to - pill._from : root._chipThickness

            // Both edges of a pair on `emphasized`, the trailing one over
            // twice the clock (M54 D2, caelestia's ActiveIndicator): the
            // leading edge reaches the new chip while the trailing edge is
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
            columnSpacing: root._chipGap
            rowSpacing: root._chipGap

            Repeater {
                id: slotRepeater
                // A count rather than the array itself: the model is a fresh
                // array on every focus change, and a Repeater handed one
                // rebuilds every delegate, which would snap every chip's
                // length instead of letting the ones that changed travel.
                model: root.slots.length
                onItemAdded: root._remeasure()
                onItemRemoved: root._remeasure()

                Item {
                    id: slot
                    required property int index
                    readonly property var ws: root.slots[slot.index] || ({
                        id: "", idx: 0, label: "", current: false, isFocused: false,
                        isUrgent: false, placeholder: true, windows: [], overflow: 0
                    })

                    readonly property bool hovered: slotHover.hovered
                    readonly property bool occupied: slot.ws.windows.length > 0
                    readonly property bool showsApps: slot.occupied
                        && WorkspacesModel.showsApps(root._showApps, slot.ws.current, slot.hovered)
                    readonly property int shownIcons: slot.showsApps ? slot.ws.windows.length : 0
                    readonly property bool showsOverflow: slot.showsApps && slot.ws.overflow > 0

                    function iconAt(at) {
                        return at < iconRepeater.count ? iconRepeater.itemAt(at) : null;
                    }

                    // An agent on this workspace waiting on the user: the chip
                    // pulses until it is looked at, unless it is the one on
                    // screen already.
                    readonly property bool waiting: root._agents && !slot.ws.current
                        && slot.ws.windows.some(function (w) { return HerdrService.stateByWindow[w.id] === "blocked"; })

                    readonly property real _labelAlong: root.vertical ? label.implicitHeight : label.implicitWidth
                    readonly property real _iconsAlong: slot.shownIcons > 0
                        ? slot.shownIcons * root._plateSize + (slot.shownIcons - 1) * root._iconGap
                        : 0
                    readonly property real _chipAlong: slot.showsOverflow
                        ? (root.vertical ? chip.implicitHeight : chip.implicitWidth) + root._iconGap
                        : 0
                    readonly property real contentAlong: slot._labelAlong
                        + (slot._iconsAlong > 0 ? root._labelGap + slot._iconsAlong + slot._chipAlong : 0)
                    // The icons' own plates already carry `xs` of air, so the
                    // chip's end past the last one is `xs` rather than the
                    // number's full `md`.
                    readonly property real targetAlong: Math.max(root._chipThickness,
                        slot.contentAlong + root._chipPad + (slot._iconsAlong > 0 ? Theme.space.xs : root._chipPad))
                    onTargetAlongChanged: root._remeasure()

                    // The length the chip is drawn at: its target, gliding
                    // there on the same arm switch every bar cell's own width
                    // takes.
                    property real along: slot.targetAlong
                    Behavior on along {
                        enabled: root.animateSize
                        Anim {}
                    }

                    width: root.vertical ? root._chipThickness : slot.along
                    height: root.vertical ? slot.along : root._chipThickness

                    // The chip's own fill: a quiet wash while it holds
                    // windows, a stronger one under the pointer, nothing on
                    // an empty one at rest. The focused chip leaves it to the
                    // travelling fill under it.
                    Box {
                        anchors.fill: parent
                        role: "cell"
                        radius: root._chipRadius
                        box: root._washed(slot.ws.isFocused
                            ? null
                            : slot.hovered
                                ? (slot.occupied ? Theme.pressFill : Theme.hoverFill)
                                : (slot.occupied ? Theme.hoverFill : null))
                    }

                    // primitive-exempt: an agent waiting, a pulse over the
                    // chip's own shape rather than a bordered box.
                    Rectangle {
                        id: waitGlow
                        anchors.fill: parent
                        radius: root._chipRadius
                        color: Theme.color.destructive
                        visible: slot.waiting
                        opacity: 0.2

                        // The breathing pulse (Theme.motion.pulseDuration,
                        // DESIGN.md §1's continuous-motion carve-out), for as
                        // long as the agent waits.
                        SequentialAnimation on opacity {
                            running: slot.waiting
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                            NumberAnimation { to: 0.2; duration: Theme.motion.pulseDuration; easing.type: Theme.motion.pulseEasing }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._go(slot.ws)
                    }

                    HoverHandler {
                        id: slotHover
                        onHoveredChanged: {
                            if (slotHover.hovered) {
                                root._hoveredIndex = slot.index;
                                root._slotEntered(slot);
                            } else {
                                if (root._hoveredIndex === slot.index)
                                    root._hoveredIndex = -1;
                                root._slotLeft(slot);
                            }
                        }
                    }

                    // Laid out at the settled length and clipped to the drawn
                    // one, so icons are uncovered as the chip opens rather than
                    // squeezed into it.
                    Item {
                        anchors.fill: parent
                        clip: slot.along < slot.targetAlong

                        Grid {
                            id: content
                            columns: root.vertical ? 1 : 2
                            columnSpacing: root._labelGap
                            rowSpacing: root._labelGap
                            horizontalItemAlignment: Grid.AlignHCenter
                            verticalItemAlignment: Grid.AlignVCenter
                            x: root.vertical ? (parent.width - content.width) / 2
                                : (slot._iconsAlong > 0 ? root._chipPad : (slot.targetAlong - slot.contentAlong) / 2)
                            y: root.vertical
                                ? (slot._iconsAlong > 0 ? root._chipPad : (slot.targetAlong - slot.contentAlong) / 2)
                                : (parent.height - content.height) / 2

                            Text {
                                id: label
                                text: slot.ws.label
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSize.body
                                font.weight: slot.ws.isFocused || root.bandInk ? Theme.weight.semibold : Theme.weight.medium
                                horizontalAlignment: Text.AlignHCenter
                                color: slot.ws.isFocused
                                    ? Theme.color.accentForeground
                                    : slot.ws.isUrgent
                                        ? Theme.color.destructive
                                        : (slot.occupied || slot.ws.current) ? root.foreground : root.dimForeground

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
                            }

                            Grid {
                                id: icons
                                visible: slot.shownIcons > 0
                                columns: root.vertical ? 1 : Math.max(1, slot.shownIcons + (slot.showsOverflow ? 1 : 0))
                                columnSpacing: root._iconGap
                                rowSpacing: root._iconGap
                                horizontalItemAlignment: Grid.AlignHCenter
                                verticalItemAlignment: Grid.AlignVCenter

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

                                        width: root._plateSize
                                        height: root._plateSize

                                        // The focused window's plate, and the
                                        // hovered icon's on any chip.
                                        Box {
                                            anchors.fill: parent
                                            role: "cell"
                                            radius: root._plateRadius
                                            box: root._washed(iconItem.focusedHere || iconItem.hovered ? Theme.hoverFill : null)
                                        }

                                        // On the focused chip, every window but
                                        // the one holding focus steps back.
                                        property real _dim: slot.ws.isFocused && !iconItem.focusedHere && !iconItem.hovered ? 0.5 : 1
                                        Behavior on _dim {
                                            Anim { kind: "effects" }
                                        }

                                        // Arrives faded up rather than cut in,
                                        // on the arm switch the chip's length
                                        // takes.
                                        property real _in: root.animateSize ? 0 : 1
                                        Component.onCompleted: iconItem._in = 1
                                        Behavior on _in {
                                            enabled: root.animateSize
                                            Anim { kind: "effects" }
                                        }

                                        Item {
                                            anchors.centerIn: parent
                                            width: root._iconSize
                                            height: root._iconSize
                                            opacity: iconItem._in * iconItem._dim

                                            Picture {
                                                id: appIcon
                                                anchors.fill: parent
                                                visible: iconItem.source !== "" && appIcon.status !== Image.Error
                                                source: iconItem.source
                                                sourceSize.width: root._iconSize * 2
                                                sourceSize.height: root._iconSize * 2
                                                fillMode: Image.PreserveAspectFit
                                            }

                                            // Nothing in the chain answered: the
                                            // generic window mark, as the switcher
                                            // draws it.
                                            Icon {
                                                anchors.centerIn: parent
                                                visible: !appIcon.visible
                                                name: "app-window"
                                                size: root._iconSize
                                                color: label.color
                                            }
                                        }

                                        // herdr's word on the agent in this
                                        // window (Services/HerdrService.qml): a
                                        // spinner while it works, a pulsing
                                        // alert while it waits on the user, a
                                        // check once it is done. Nothing at all
                                        // for idle, unknown, or no herdr.
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
                                                id: badgeGlyph
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
                                    id: chip
                                    visible: slot.showsOverflow
                                    text: "+" + slot.ws.overflow
                                    color: label.color
                                    font.family: Theme.fontFamilyMono
                                    font.pixelSize: Theme.fontSize.caption
                                    font.weight: Theme.weight.medium
                                }
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

    // The window's title read live (the chip model carries no titles), with
    // herdr's word on its agent after it.
    function _iconTooltip(windowId, agent) {
        var win = CompositorService.windowById(windowId);
        var title = win ? (win.title || win.appId || "") : "";
        return agent !== "" ? title + " / " + root._agentWords[agent] : title;
    }
}
