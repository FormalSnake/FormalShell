import QtQuick
import qs.Core as Core
import qs.Components
import qs.Services
import "../../../Menu/actions.js" as Actions
import "../../../Monitor/procs.js" as Procs
import "../../../Power/model.js" as Power

// The full system monitor, rendered inside the launcher card (M38 Task 7).
// Registered in Menu/appviews.js against the "monitor" route, loaded by
// Menu.qml's app-view Loader. Nothing here knows about the menu beyond
// being sized by it, so this file is also what a second app view copies.
//
// btop's layout, and for btop's reason: the machine's stats above, the
// process table below taking whatever room is left, one surface. The table
// shipped as a route of its own for one day (M39's "processes") and was
// folded back in here (owner, 2026-08-19: "I never wanted a separate
// processes list"). Two routes made the search field on THIS one inert,
// which is the state a text cursor sitting in an empty field promises the
// opposite of; there is one place to look at the machine now, and typing in
// it filters the table.
//
// So this view uses all four of Menu/appviews.js's seams: `query` filters
// the table, `scrollTarget` is the table, `viewKey` claims the keys a row
// cursor needs before the menu's own handler sees them, and `viewActions`
// replaces the row list's verbs with the ones that are true here.
//
// Two ledger columns behind one shared vertical rule, in DESIGN.md's cell
// grammar: uppercase MetaLabel section headers with a trailing colon, one
// Cell per row, DitherFill tracks with a flat accent fill for every
// fraction, and radius 0 throughout. The rule between the columns is drawn
// explicitly because the left column's own trailing cell rules stop at its
// last row, and a ledger column that ends short would otherwise leave the
// divider hanging.
//
// Which sections land in which column is packed per machine rather than
// nailed down (see _splitIndex): a headless VM with one GPU-less card and
// four interfaces and a hybrid laptop with two cards do not balance at the
// same place, and the fixed split left a third of the left column empty
// while the right one overflowed.
//
// SystemMonitorService is subscribed on completion and released on
// destruction, which is the whole reason that service refcounts: the menu
// unloads this view the moment the route is left or the launcher closes, so
// a closed launcher leaves nothing polling /proc.
//
// Anything the first tick cannot know renders as a dash, never a zero:
// every delta (CPU busy, per-core busy, network rates) needs two samples,
// and nvidia-smi emits a literal [N/A] for fan speed on laptop GPUs. A 0%
// there would read as a measurement rather than the absence of one.
//
// Casing rule for the whole file: every string this view WRITES is an
// uppercase meta label (CPU, OUTPUTS:, NO GPU), and every string it is
// HANDED renders verbatim. `eDP-2` uppercased is `EDP-2`, which names
// nothing the kernel or the compositor would answer to, and `/nix/store`
// uppercased is a path that does not exist. Same division Tooltip.qml's
// `verbatim` already draws for foreign strings.
Item {
    id: root

    // What the card wants before Menu.qml caps it (_rowsAreaHeight takes
    // the smaller of this and its cap): the whole ledger plus a row per
    // process, which on any real machine is far past the cap and therefore
    // asks for the tallest card the launcher will draw. That is the point —
    // the table is the reason this route is a view rather than a row list.
    // Measured arithmetically off the row count rather than read back off
    // `list.contentHeight`, which would close a loop through the height the
    // list is then given.
    implicitHeight: statsColumns.height + procChrome.height
        + (root._rows.length === 0 ? emptyCell.height : root._rows.length * root._rowHeight)

    Component.onCompleted: {
        SystemMonitorService.subscribe();
        ProcessService.subscribe();
    }
    Component.onDestruction: {
        SystemMonitorService.unsubscribe();
        ProcessService.unsubscribe();
    }

    // The app-view scroll seam (Menu.qml's key handler). It names the
    // process table rather than the ledger above it: the table is the part
    // with more content than room, and it is what the cursor lives in.
    readonly property Flickable scrollTarget: list

    // Bound by Menu.qml to the live search text.
    property string query: ""

    property string sortMode: "cpu"

    // Which process the cursor is on, held as a pid rather than an index:
    // the table re-sorts on every poll and a row that gained a percent
    // point moves under an index-based cursor, so an index would arm a
    // confirm on one process and fire it at another.
    property int cursorPid: 0

    // The armed action, or "" when nothing is. Cleared by anything that
    // changes what the cursor is pointing at.
    property string confirmAction: ""
    property int confirmPid: 0

    readonly property var _rows: Procs.sortRows(Procs.filterRows(ProcessService.rows, root.query), root.sortMode)
    readonly property int _cursorIndex: {
        for (var i = 0; i < root._rows.length; i++) {
            if (root._rows[i].pid === root.cursorPid)
                return i;
        }
        return root._rows.length > 0 ? 0 : -1;
    }
    readonly property var _cursorRow: root._cursorIndex >= 0 ? root._rows[root._cursorIndex] : null

    // Retyping the filter is a new decision about what to act on, so it
    // disarms too. A cursor move disarms in _moveCursor; a process that
    // exits from under an armed confirm needs nothing, since _press re-arms
    // whenever the pid under the cursor is not the pid that was armed.
    onQueryChanged: root._disarm()

    readonly property real _colWidth: Math.round(root.width / 2)

    // How the two halves split the card, in the order the answers matter.
    // Neither half is allowed to hold room the other needs: the table takes
    // what its rows actually come to, the ledger takes what is left up to
    // its own full height, and when both want more than there is they meet
    // at btop's half-and-half. That last clause is the normal case (400
    // processes), and the first is what keeps a filter that narrows to one
    // row from leaving half a card of nothing under it.
    readonly property real _tableWanted: root._rows.length === 0
        ? emptyCell.height
        : root._rows.length * root._rowHeight
    readonly property real _statsHeight: Math.max(0, Math.min(statsColumns.height,
        Math.max(root.height - procChrome.height - root._tableWanted, Math.round(root.height * 0.5))))

    // --- Formatting ------------------------------------------------------
    //
    // Null in, dash out, everywhere: these are the only place the view
    // decides what an unmeasured value looks like.

    function _pct(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return "—";
        return Math.round(fraction * 100) + "%";
    }

    function _fill(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return 0;
        return Math.max(0, Math.min(1, fraction));
    }

    function _bytes(value) {
        if (value === null || value === undefined || !isFinite(value))
            return "—";
        var units = ["B", "K", "M", "G", "T"];
        var scaled = value;
        var i = 0;
        while (scaled >= 1024 && i < units.length - 1) {
            scaled /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(scaled) : scaled.toFixed(1)) + units[i];
    }

    function _rate(bytesPerSec) {
        if (bytesPerSec === null || bytesPerSec === undefined || !isFinite(bytesPerSec))
            return "—";
        return root._bytes(bytesPerSec) + "/S";
    }

    function _degrees(celsius) {
        if (celsius === null || celsius === undefined || !isFinite(celsius))
            return "—";
        return Math.round(celsius) + "°";
    }

    function _watts(value) {
        if (value === null || value === undefined || !isFinite(value))
            return "—";
        return value.toFixed(1) + "W";
    }

    // "cpu7" -> "7". The aggregate line never reaches here (cpuDelta drops
    // it from `cores`), so there is no bare "cpu" case to fall back on.
    function _coreLabel(label) {
        return String(label).replace(/^cpu/, "");
    }

    // hwmon rows in the order parseTemps emitted them, folded into one
    // group per chip so a 12-sensor coretemp reads as one block instead of
    // twelve unrelated rows. hasOwnProperty because a chip name is kernel
    // data, not something this file gets to assume is not "constructor".
    function _groupTemps(rows) {
        var groups = [];
        var byChip = {};
        for (var i = 0; i < rows.length; i++) {
            var chip = rows[i].chip;
            if (!Object.prototype.hasOwnProperty.call(byChip, chip)) {
                byChip[chip] = { chip: chip, rows: [] };
                groups.push(byChip[chip]);
            }
            byChip[chip].rows.push(rows[i]);
        }
        return groups;
    }

    readonly property var _tempGroups: root._groupTemps(SystemMonitorService.temps.rows || [])

    // Interfaces carrying traffic first, everything else after in the order
    // the kernel listed them. Two buckets rather than a sort by rate: two
    // busy interfaces would otherwise trade places every poll tick as their
    // rates crossed. Nothing is filtered: an idle interface is a true fact
    // about the machine (the rig's three mac80211_hwsim radios are real
    // radios), so it moves down rather than away.
    function _orderNet(rows) {
        var busy = [];
        var idle = [];
        for (var i = 0; i < rows.length; i++) {
            var rate = (Number(rows[i].rxBytesPerSec) || 0) + (Number(rows[i].txBytesPerSec) || 0);
            (rate > 0 ? busy : idle).push(rows[i]);
        }
        return busy.concat(idle);
    }

    readonly property var _netRows: root._orderNet(SystemMonitorService.net.rows || [])

    // Gutter for the per-core index, wide enough for the highest one in the
    // set so every bar in the grid starts at the same x. One caption pixel
    // size per digit is comfortably wider than a mono digit's advance, and
    // it tracks the font instead of pinning a literal.
    readonly property real _coreLabelWidth: Core.Theme.fontSize.caption
        * String(Math.max(0, SystemMonitorService.cpu.cores.length - 1)).length

    readonly property var _mem: SystemMonitorService.mem
    readonly property bool _hasSwap: root._mem.available === true && root._mem.swapTotalBytes > 0
    readonly property real _swapFraction: root._hasSwap
        ? (root._mem.swapTotalBytes - root._mem.swapFreeBytes) / root._mem.swapTotalBytes
        : 0

    // --- Shared row shapes ------------------------------------------------

    // A label/value line: uppercase meta on the left, the value hard right.
    // The value takes whatever width it needs and the label absorbs the
    // rest, so a long mount point elides rather than pushing its own number
    // off the cell. An Item rather than a Row because the two run at
    // different font sizes (caption meta, body value) and a Row would top
    // align them; these are centered against each other.
    component StatLine: Item {
        id: statLine

        property string label: ""
        property string value: ""
        property color valueColor: Core.Theme.color.foreground
        // The label is a kernel identifier rather than wording this file
        // chose (see the casing rule in the header): keeps the meta band's
        // ink, size and tracking, drops the forced uppercase.
        property bool identifier: false

        implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)

        MetaLabel {
            id: statLabel
            anchors.left: parent.left
            anchors.right: statValue.left
            anchors.rightMargin: Core.Theme.space.sm
            anchors.verticalCenter: parent.verticalCenter
            text: statLine.label
            colon: true
            elide: Text.ElideRight
            font.capitalization: statLine.identifier ? Font.MixedCase : Font.AllUppercase
        }

        Text {
            id: statValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: statLine.value
            color: statLine.valueColor
            font.family: Core.Theme.fontFamily
            font.pixelSize: Core.Theme.fontSize.body
        }
    }

    // The one track idiom in the shell (DESIGN.md §2 item 8): a dithered
    // remainder under a flat accent fill, no thumb, no gauge.
    component StatBar: DitherFill {
        id: statBar

        property real fraction: 0

        height: Core.Theme.space.trackThickness

        Rectangle {
            width: statBar.width * statBar.fraction
            height: statBar.height
            color: Core.Theme.color.accent
        }
    }

    component SectionHeader: Cell {
        id: sectionHeader

        property string label: ""

        MetaLabel {
            text: sectionHeader.label
            colon: true
        }
    }

    // --- Column packing --------------------------------------------------
    //
    // Which column a section lands in is decided from the SHAPE of its data
    // (how many cards, sensors, interfaces, mounts), never from measured
    // geometry and never from how wide a value happens to render. That is
    // what makes it stable: a number growing a digit cannot move a section
    // across, only a row appearing or leaving can.
    //
    // The decision is a single cut through a fixed section order rather than
    // a bin-pack, so the ledger still reads top to bottom down the left
    // column and on down the right one, exactly as the old hardcoded split
    // did. It is one integer, and only a row count can change it.
    readonly property var _sectionOrder: ["cpu", "memory", "system", "gpu", "temps", "network", "disk"]

    // Height in ledger lines. A cell's own padding is worth about a line, so
    // every cell pays for one; the units cancel in the comparison below, so
    // approximate is all this has to be.
    function _cellWeight(lines) {
        return lines + 1;
    }

    function _sectionWeight(id) {
        var i;
        var total = root._cellWeight(1);
        if (id === "cpu") {
            total += root._cellWeight(2);
            var cores = SystemMonitorService.cpu.cores.length;
            if (cores > 0)
                total += root._cellWeight(Math.ceil(cores / 2));
            return total;
        }
        if (id === "memory")
            return total + root._cellWeight(2) + root._cellWeight(root._hasSwap ? 2 : 1);
        if (id === "system")
            return total + root._cellWeight(3);
        if (id === "gpu") {
            var cards = GpuService.cards;
            if (cards.length === 0)
                return total + root._cellWeight(1);
            for (i = 0; i < cards.length; i++) {
                total += root._cellWeight(3);
                total += root._cellWeight(1 + Math.max(1, cards[i].outputs.length));
                total += root._cellWeight(cards[i].metrics.available ? 7 : 1);
            }
            return total;
        }
        if (id === "temps") {
            var groups = root._tempGroups;
            if (groups.length === 0)
                return total + root._cellWeight(1);
            for (i = 0; i < groups.length; i++)
                total += root._cellWeight(1 + groups[i].rows.length);
            return total;
        }
        if (id === "network") {
            if (root._netRows.length === 0)
                return total + root._cellWeight(1);
            return total + root._netRows.length * root._cellWeight(3);
        }
        if (id === "disk") {
            var mounts = SystemMonitorService.disk.rows;
            if (mounts.length === 0)
                return total + root._cellWeight(1);
            return total + mounts.length * root._cellWeight(2);
        }
        return total;
    }

    // The cut leaving the two columns closest in height. A tie keeps the
    // earlier cut rather than whichever the loop saw last, so the same data
    // always packs the same way.
    readonly property int _splitIndex: {
        var order = root._sectionOrder;
        var weights = [];
        var total = 0;
        for (var i = 0; i < order.length; i++) {
            weights.push(root._sectionWeight(order[i]));
            total += weights[i];
        }
        var best = 1;
        var bestGap = Infinity;
        var left = 0;
        for (var k = 1; k < order.length; k++) {
            left += weights[k - 1];
            var gap = Math.abs(total - left * 2);
            if (gap < bestGap) {
                bestGap = gap;
                best = k;
            }
        }
        return best;
    }

    readonly property var _leftSections: root._sectionOrder.slice(0, root._splitIndex)
    readonly property var _rightSections: root._sectionOrder.slice(root._splitIndex)

    function _sectionComponent(id) {
        switch (id) {
        case "cpu": return cpuSection;
        case "memory": return memorySection;
        case "system": return systemSection;
        case "gpu": return gpuSection;
        case "temps": return tempsSection;
        case "network": return networkSection;
        case "disk": return diskSection;
        }
        return null;
    }

    // --- Sections -------------------------------------------------------
    //
    // Each section is a Component rather than markup nailed into one of the
    // two columns, because which column it lands in is decided from the
    // data's own shape (_splitIndex above). Every one is otherwise the same
    // markup it was when it sat inline: a header cell, then its rows.

    Component {
        id: cpuSection

        Column {
            id: cpuColumn

            SectionHeader {
                width: parent.width
                label: "CPU"
            }

            Cell {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Core.Theme.space.xxs

                    StatLine {
                        width: parent.width
                        label: "TOTAL"
                        value: root._pct(SystemMonitorService.cpu.aggregate)
                    }

                    StatBar {
                        width: parent.width
                        fraction: root._fill(SystemMonitorService.cpu.aggregate)
                    }
                }
            }

            // Per-core bars two abreast: a 24-core machine is twelve
            // rows here and one row per core would be taller than the
            // whole card. Absent entirely on the first tick, when
            // cpuDelta has no previous sample and `cores` is empty.
            Cell {
                width: parent.width
                visible: SystemMonitorService.cpu.cores.length > 0

                Grid {
                    id: coreGrid
                    width: parent.width
                    columns: 2
                    columnSpacing: Core.Theme.space.lg
                    rowSpacing: Core.Theme.space.xxs

                    Repeater {
                        model: SystemMonitorService.cpu.cores

                        delegate: Item {
                            id: coreEntry
                            required property var modelData

                            width: (coreGrid.width - coreGrid.columnSpacing) / 2
                            height: coreLabel.implicitHeight

                            MetaLabel {
                                id: coreLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: root._coreLabelWidth
                                text: root._coreLabel(coreEntry.modelData.label)
                                horizontalAlignment: Text.AlignRight
                            }

                            StatBar {
                                anchors.left: coreLabel.right
                                anchors.leftMargin: Core.Theme.space.sm
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                fraction: root._fill(coreEntry.modelData.fraction)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: memorySection

        Column {
            id: memoryColumn

            SectionHeader {
                width: parent.width
                label: "MEMORY"
            }

            Cell {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Core.Theme.space.xxs

                    StatLine {
                        width: parent.width
                        label: "RAM"
                        value: root._mem.available
                            ? root._bytes(root._mem.totalBytes - root._mem.availableBytes) + " / " + root._bytes(root._mem.totalBytes)
                            : "—"
                    }

                    StatBar {
                        width: parent.width
                        fraction: root._fill(root._mem.available ? root._mem.usedFraction : null)
                    }
                }
            }

            Cell {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Core.Theme.space.xxs

                    // A swapless machine has nothing to measure, so the
                    // row says so rather than drawing an empty 0% track.
                    MetaLabel {
                        visible: !root._hasSwap
                        text: "NO SWAP"
                    }

                    StatLine {
                        width: parent.width
                        visible: root._hasSwap
                        label: "SWAP"
                        value: root._hasSwap
                            ? root._bytes(root._mem.swapTotalBytes - root._mem.swapFreeBytes) + " / " + root._bytes(root._mem.swapTotalBytes)
                            : "—"
                    }

                    StatBar {
                        width: parent.width
                        visible: root._hasSwap
                        fraction: root._fill(root._swapFraction)
                    }
                }
            }
        }
    }

    Component {
        id: systemSection

        Column {
            id: systemColumn

            SectionHeader {
                width: parent.width
                label: "SYSTEM"
            }

            Cell {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Core.Theme.space.xxs

                    StatLine {
                        width: parent.width
                        label: "LOAD"
                        value: SystemMonitorService.load.available
                            ? SystemMonitorService.load.load1.toFixed(2) + " " + SystemMonitorService.load.load5.toFixed(2) + " " + SystemMonitorService.load.load15.toFixed(2)
                            : "—"
                    }

                    StatLine {
                        width: parent.width
                        label: "PROCS"
                        value: SystemMonitorService.load.available
                            ? SystemMonitorService.load.runningProcs + " / " + SystemMonitorService.load.totalProcs
                            : "—"
                    }

                    StatLine {
                        width: parent.width
                        label: "UPTIME"
                        // Power/model.js's formatDuration, not a second
                        // copy of the same "1D 3H" arithmetic: it is a
                        // pure formatter that happens to live beside the
                        // battery's own remaining-time readout.
                        value: SystemMonitorService.uptime.available
                            ? Power.formatDuration(SystemMonitorService.uptime.uptimeSeconds)
                            : "—"
                    }
                }
            }
        }
    }

    Component {
        id: gpuSection

        Column {
            id: gpuColumn

            SectionHeader {
                width: parent.width
                label: "GPU"
            }

            // No card in /sys/class/drm at all (the mac VM, a headless
            // server) is a normal state with a name, not a gap to fill
            // with a plausible-looking row.
            Cell {
                width: parent.width
                visible: GpuService.cards.length === 0

                MetaLabel { text: "NO GPU" }
            }

            Repeater {
                model: GpuService.cards

                delegate: Column {
                    id: cardBlock
                    required property var modelData

                    width: gpuColumn.width

                    Cell {
                        width: parent.width

                        Column {
                            width: parent.width
                            spacing: Core.Theme.space.xxs

                            Row {
                                width: parent.width
                                spacing: Core.Theme.space.sm

                                Text {
                                    id: cardName
                                    width: Math.max(0, parent.width - cardKind.width - parent.spacing)
                                    text: cardBlock.modelData.name
                                    color: Core.Theme.color.foreground
                                    elide: Text.ElideRight
                                    font.family: Core.Theme.fontFamily
                                    font.pixelSize: Core.Theme.fontSize.body
                                }

                                // boot_vga decides this, never the card
                                // number: the owner's g815 enumerates
                                // its dGPU as card0.
                                MetaLabel {
                                    id: cardKind
                                    text: cardBlock.modelData.discrete ? "DISCRETE" : "INTEGRATED"
                                }
                            }

                            StatLine {
                                width: parent.width
                                label: "DRIVER"
                                value: cardBlock.modelData.driver
                            }

                            StatLine {
                                width: parent.width
                                label: "PCI"
                                value: cardBlock.modelData.pci
                            }
                        }
                    }

                    Cell {
                        width: parent.width

                        Column {
                            width: parent.width
                            spacing: Core.Theme.space.xxs

                            MetaLabel {
                                text: "OUTPUTS"
                                colon: true
                            }

                            MetaLabel {
                                visible: cardBlock.modelData.outputs.length === 0
                                text: "NONE"
                            }

                            Repeater {
                                model: cardBlock.modelData.outputs

                                // A connected connector is the one thing
                                // on this block worth reading at a
                                // glance, so it carries full-strength
                                // ink and the rest stay dim. The one
                                // `display.outputPriority` resolves to
                                // says so too (MainOutputService): on a
                                // hybrid machine that names which card
                                // is driving the main screen, which is
                                // the reason to read this block at all.
                                delegate: StatLine {
                                    id: outputLine
                                    required property var modelData
                                    readonly property bool isMain: MainOutputService.isMain(outputLine.modelData.name)

                                    width: parent.width
                                    identifier: true
                                    label: outputLine.modelData.name
                                    value: outputLine.modelData.connected
                                        ? (outputLine.isMain ? "MAIN / CONNECTED" : "CONNECTED")
                                        : "DISCONNECTED"
                                    valueColor: outputLine.modelData.connected
                                        ? Core.Theme.color.foreground
                                        : Core.Theme.color.foregroundDim
                                }
                            }
                        }
                    }

                    Cell {
                        width: parent.width

                        Column {
                            width: parent.width
                            spacing: Core.Theme.space.xxs

                            // i915/xe expose no unprivileged utilisation
                            // counter, and nvidia-smi may not be
                            // installed at all. Both say so here rather
                            // than rendering an invented 0%.
                            MetaLabel {
                                visible: !cardBlock.modelData.metrics.available
                                text: "NO METRICS"
                            }

                            StatLine {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                label: "BUSY"
                                value: root._pct(cardBlock.modelData.metrics.busy)
                            }

                            StatBar {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                fraction: root._fill(cardBlock.modelData.metrics.busy)
                            }

                            StatLine {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                label: "VRAM"
                                value: root._bytes(cardBlock.modelData.metrics.vramUsed) + " / " + root._bytes(cardBlock.modelData.metrics.vramTotal)
                            }

                            StatBar {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                fraction: root._fill(cardBlock.modelData.metrics.vramTotal > 0
                                    ? cardBlock.modelData.metrics.vramUsed / cardBlock.modelData.metrics.vramTotal
                                    : null)
                            }

                            StatLine {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                label: "TEMP"
                                value: root._degrees(cardBlock.modelData.metrics.tempC)
                            }

                            StatLine {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                label: "POWER"
                                value: root._watts(cardBlock.modelData.metrics.powerW)
                            }

                            StatLine {
                                width: parent.width
                                visible: cardBlock.modelData.metrics.available
                                label: "FAN"
                                value: root._pct(cardBlock.modelData.metrics.fanPercent === null
                                    ? null
                                    : cardBlock.modelData.metrics.fanPercent / 100)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: tempsSection

        Column {
            id: tempsColumn

            SectionHeader {
                width: parent.width
                label: "TEMPS"
            }

            Cell {
                width: parent.width
                visible: root._tempGroups.length === 0

                MetaLabel { text: "NO SENSORS" }
            }

            Repeater {
                model: root._tempGroups

                delegate: Cell {
                    id: tempGroup
                    required property var modelData

                    width: tempsColumn.width

                    Column {
                        width: parent.width
                        spacing: Core.Theme.space.xxs

                        MetaLabel {
                            text: tempGroup.modelData.chip
                            colon: true
                            font.capitalization: Font.MixedCase
                        }

                        Repeater {
                            model: tempGroup.modelData.rows

                            delegate: StatLine {
                                id: tempLine
                                required property var modelData

                                width: parent.width
                                identifier: true
                                label: tempLine.modelData.label
                                value: root._degrees(tempLine.modelData.celsius)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: networkSection

        Column {
            id: networkColumn

            SectionHeader {
                width: parent.width
                label: "NETWORK"
            }

            // Two different empty states. No interface at all beyond
            // loopback is one; a machine with interfaces whose rates
            // are not measurable yet is the other, since netDelta has
            // no previous sample to subtract on the first tick and a
            // rate nobody measured is not 0 B/S.
            Cell {
                width: parent.width
                visible: root._netRows.length === 0

                MetaLabel {
                    text: SystemMonitorService.net.available ? "NO TRAFFIC YET" : "NO INTERFACES"
                }
            }

            Repeater {
                model: root._netRows

                delegate: Cell {
                    id: netRow
                    required property var modelData

                    width: networkColumn.width

                    Column {
                        width: parent.width
                        spacing: Core.Theme.space.xxs

                        Text {
                            width: parent.width
                            text: netRow.modelData.iface
                            color: Core.Theme.color.foreground
                            elide: Text.ElideRight
                            font.family: Core.Theme.fontFamily
                            font.pixelSize: Core.Theme.fontSize.body
                        }

                        StatLine {
                            width: parent.width
                            label: "RX"
                            value: root._rate(netRow.modelData.rxBytesPerSec)
                        }

                        StatLine {
                            width: parent.width
                            label: "TX"
                            value: root._rate(netRow.modelData.txBytesPerSec)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: diskSection

        Column {
            id: diskColumn

            SectionHeader {
                width: parent.width
                label: "DISK"
            }

            Cell {
                width: parent.width
                visible: SystemMonitorService.disk.rows.length === 0

                MetaLabel { text: "NO MOUNTS" }
            }

            Repeater {
                model: SystemMonitorService.disk.rows

                delegate: Cell {
                    id: diskRow
                    required property var modelData

                    width: diskColumn.width

                    Column {
                        width: parent.width
                        spacing: Core.Theme.space.xxs

                        StatLine {
                            width: parent.width
                            identifier: true
                            label: diskRow.modelData.mount
                            value: root._bytes(diskRow.modelData.used) + " / " + root._bytes(diskRow.modelData.size)
                        }

                        StatBar {
                            width: parent.width
                            fraction: root._fill(diskRow.modelData.fraction)
                        }
                    }
                }
            }
        }
    }

    Flickable {
        id: statsPane
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root._statsHeight
        contentWidth: width
        contentHeight: statsColumns.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // The ledger re-measures on every poll tick (a card appears, an
        // interface goes away), so content can shrink out from under a
        // scrolled-down reader and leave contentY past its own end.
        onContentHeightChanged: statsPane.returnToBounds()

        Item {
            id: statsColumns
            width: root.width
            height: Math.max(leftColumn.height, rightColumn.height)

            // Continues the left column's own trailing cell rules (Cell's
            // shared-rule contract) past whichever column ends first, so the
            // two ledgers read as one table rather than two stacks.
            Rectangle {
                x: leftColumn.width - Core.Theme.borderWidth
                width: Core.Theme.borderWidth
                height: statsColumns.height
                color: Core.Theme.color.rule
            }

            Column {
                id: leftColumn
                anchors.top: parent.top
                anchors.left: parent.left
                width: root._colWidth

                Repeater {
                    model: root._leftSections

                    delegate: Loader {
                        required property var modelData

                        // The Loader owns the section's width: it has an
                        // explicit one, so it resizes what it loads, and the
                        // section Column carries no width binding of its own
                        // for the two not to fight over the same property.
                        width: leftColumn.width
                        sourceComponent: root._sectionComponent(modelData)
                    }
                }
            }

            Column {
                id: rightColumn
                anchors.top: parent.top
                anchors.left: leftColumn.right
                anchors.right: parent.right

                Repeater {
                    model: root._rightSections

                    delegate: Loader {
                        required property var modelData

                        width: rightColumn.width
                        sourceComponent: root._sectionComponent(modelData)
                    }
                }
            }
        }
    }

    // --- Process table ----------------------------------------------------
    //
    // One line per process, in mek.gallery's ruled-row grammar: fixed
    // gutters for the numbers (tabular by construction, since the whole
    // shell is monospace), the argv absorbing whatever is left, and the
    // cursor row as a full fg/bg inversion. The columns are the four facts
    // a decision needs (which process, whose command line, what it costs),
    // and nothing else fits on a line that has to stay scannable.
    //
    // Destructive by design, so every action is two presses: the first arms
    // it and the row goes full-bleed urgent under a CONFIRM verb, the second
    // sends the signal. Moving the cursor, retyping the filter or leaving
    // the route disarms it. The confirm is not a modal and never steals a
    // key: it is the same arm-then-Enter idiom the launcher's own confirm
    // rows already use (Menu.qml's _confirmPendingId).

    function _disarm() {
        root.confirmAction = "";
        root.confirmPid = 0;
    }

    function _moveCursor(delta) {
        if (root._rows.length === 0)
            return;
        var next = Math.max(0, Math.min(root._rows.length - 1, root._cursorIndex + delta));
        root.cursorPid = root._rows[next].pid;
        root._disarm();
        list.positionViewAtIndex(next, ListView.Contain);
    }

    // A process's share of one CPU carries a decimal the ledger's own
    // whole-machine percentages do not: the difference between 0.4% and
    // 4.0% is the difference between idle and busy on a 24-thread box, and
    // rounding both to 0% and 4% throws away the only thing the sort is
    // ordering by. Same null-in-dash-out rule as _pct above.
    function _procPct(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return "—";
        return (fraction * 100).toFixed(1) + "%";
    }

    // Column gutters measured off the font rather than pinned as literals,
    // so a retheme that changes fontBaseSize keeps the columns aligned.
    TextMetrics {
        id: metrics
        font.family: Core.Theme.fontFamily
        font.pixelSize: Core.Theme.fontSize.body
        text: "0"
    }
    readonly property real _digit: metrics.advanceWidth
    // 7 digits covers /proc/sys/kernel/pid_max at its 4194304 ceiling.
    readonly property real _pidWidth: root._digit * 7
    readonly property real _nameWidth: root._digit * 20
    readonly property real _cpuWidth: root._digit * 6
    readonly property real _memWidth: root._digit * 7
    readonly property real _rowHeight: metrics.height + Core.Theme.space.controlPaddingY * 2 + Core.Theme.borderWidth

    // The verb a press would take right now, in the action bar's own shape.
    // Everything the footer says about this route is derived here, so the
    // bar can never promise a key the handler below does not answer.
    readonly property var viewActions: {
        var hints = [
            { key: "↑↓", label: "Move" },
            { key: "^⏎", label: "Kill" },
            { key: "^R", label: "Restart" },
            { key: Actions.KEY_ESC, label: root.confirmAction !== "" ? "Cancel" : "Back" }
        ];
        if (!root._cursorRow)
            return { primary: null, hints: hints };
        var name = root._cursorRow.name;
        if (root.confirmAction !== "")
            return { primary: { key: Actions.KEY_ENTER, label: "Confirm " + root.confirmAction + " " + name }, hints: hints };
        return { primary: { key: Actions.KEY_ENTER, label: "Terminate " + name }, hints: hints };
    }

    // One press of the primary: arm the action, or run the armed one. The
    // pointer path (the action bar's own click) and the rig's `menu
    // activate` both land here too, so there is exactly one place that
    // decides what Enter means on this route.
    function _press(action) {
        var row = root._cursorRow;
        if (!row)
            return false;
        if (root.confirmAction === "" || root.confirmPid !== row.pid || root.confirmAction !== action) {
            root.confirmAction = action;
            root.confirmPid = row.pid;
            return true;
        }
        root._disarm();
        if (action === "RESTART")
            ProcessService.restartPid(row.pid);
        else
            ProcessService.signalPid(row.pid, action);
        return true;
    }

    // The rig's stand-in for Enter (Menu.qml's `activate`, MenuIpc's own
    // `menu activate <index>`): index < 0 means "wherever the cursor already
    // is", which is what the action bar's click passes.
    function viewActivate(index) {
        if (index >= 0 && index < root._rows.length)
            root.cursorPid = root._rows[index].pid;
        return root._press(root.confirmAction !== "" ? root.confirmAction : "TERM");
    }

    // Keys claimed ahead of Menu.qml's own handler. Everything not listed
    // falls through untouched, which is what keeps Escape popping the level,
    // backspace popping on an empty field, and every printable character
    // going to the search field where the filter lives.
    function viewKey(key, modifiers) {
        var ctrl = (modifiers & Qt.ControlModifier) !== 0;
        switch (key) {
        case Qt.Key_Up:
            root._moveCursor(-1);
            return true;
        case Qt.Key_Down:
            root._moveCursor(1);
            return true;
        case Qt.Key_PageUp:
            root._moveCursor(-Math.max(1, Math.floor(list.height / root._rowHeight) - 1));
            return true;
        case Qt.Key_PageDown:
            root._moveCursor(Math.max(1, Math.floor(list.height / root._rowHeight) - 1));
            return true;
        case Qt.Key_Home:
            root._moveCursor(-root._rows.length);
            return true;
        case Qt.Key_End:
            root._moveCursor(root._rows.length);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            return root._press(ctrl ? "KILL" : (root.confirmAction !== "" ? root.confirmAction : "TERM"));
        case Qt.Key_R:
            if (!ctrl)
                return false;
            return root._press("RESTART");
        case Qt.Key_S:
            if (!ctrl)
                return false;
            root.sortMode = Procs.nextSort(root.sortMode);
            return true;
        case Qt.Key_Escape:
            // Only when something is armed: cancelling the confirm is what
            // the footer promises there, and every other Escape still pops
            // the route.
            if (root.confirmAction === "") {
                return false;
            }
            root._disarm();
            return true;
        }
        return false;
    }

    // The table's own two header rows, measured as one block so the list
    // below can be told how much room is left in whole rows.
    Column {
        id: procChrome
        anchors.top: statsPane.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        // The seam, drawn only when the ledger above is genuinely taller
        // than the room it got. Its last visible cell is then cut partway
        // through, and a cut with no line under it reads as a broken frame
        // rather than as "wheel up for the rest"; a ledger that fits ends
        // on its own cell's bottom rule (Cell's shared-rule contract) and a
        // second line here would double it.
        Rectangle {
            width: parent.width
            height: statsColumns.height > statsPane.height ? Core.Theme.borderWidth : 0
            color: Core.Theme.color.rule
        }

        Cell {
            id: header
            width: parent.width

            Item {
                width: parent.width
                implicitHeight: headerLabel.implicitHeight

                MetaLabel {
                    id: headerLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._rows.length === ProcessService.rows.length
                        ? "PROCESSES / " + root._rows.length
                        : "PROCESSES / " + root._rows.length + " OF " + ProcessService.rows.length
                    colon: true
                }

                // The last action's own answer, verbatim: a kill that failed
                // on permissions says so in the kernel's words rather than
                // this file's guess at what went wrong.
                Text {
                    anchors.left: headerLabel.right
                    anchors.leftMargin: Core.Theme.space.lg
                    anchors.right: sortLabel.left
                    anchors.rightMargin: Core.Theme.space.lg
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ProcessService.lastResult !== null
                    text: ProcessService.lastResult
                        ? ProcessService.lastResult.pid + " " + ProcessService.lastResult.action + ": " + ProcessService.lastResult.message
                        : ""
                    color: (ProcessService.lastResult && ProcessService.lastResult.ok)
                        ? Core.Theme.color.foregroundDim
                        : Core.Theme.color.urgent
                    elide: Text.ElideRight
                    font.family: Core.Theme.fontFamily
                    font.pixelSize: Core.Theme.fontSize.caption
                }

                MetaLabel {
                    id: sortLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SORT ↓" + root.sortMode + " ^S"
                }
            }
        }

        // Column labels, and the other way to sort: a click on one takes
        // that column, which is the only thing on this route the pointer can
        // do that the keyboard cannot say faster.
        Cell {
            id: columnHeader
            width: parent.width
            interactive: true
            onClicked: mouse => {
                var x = mouse.x;
                if (x < root._pidWidth)
                    root.sortMode = "pid";
                else if (x < root._pidWidth + Core.Theme.space.lg + root._nameWidth)
                    root.sortMode = "name";
                else if (x > columnHeader.width - root._memWidth - Core.Theme.space.lg * 2)
                    root.sortMode = "mem";
                else if (x > columnHeader.width - root._memWidth - root._cpuWidth - Core.Theme.space.lg * 3)
                    root.sortMode = "cpu";
            }

            Item {
                width: parent.width
                implicitHeight: pidHeader.implicitHeight

                MetaLabel {
                    id: pidHeader
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._pidWidth
                    horizontalAlignment: Text.AlignRight
                    text: "PID"
                    color: root.sortMode === "pid" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
                }

                MetaLabel {
                    id: nameHeader
                    anchors.left: pidHeader.right
                    anchors.leftMargin: Core.Theme.space.lg
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._nameWidth
                    text: "PROCESS"
                    color: root.sortMode === "name" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
                }

                MetaLabel {
                    anchors.left: nameHeader.right
                    anchors.leftMargin: Core.Theme.space.lg
                    anchors.right: cpuHeader.left
                    anchors.rightMargin: Core.Theme.space.lg
                    anchors.verticalCenter: parent.verticalCenter
                    text: "COMMAND"
                    elide: Text.ElideRight
                }

                MetaLabel {
                    id: cpuHeader
                    anchors.right: memHeader.left
                    anchors.rightMargin: Core.Theme.space.lg
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._cpuWidth
                    horizontalAlignment: Text.AlignRight
                    text: "CPU"
                    color: root.sortMode === "cpu" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
                }

                MetaLabel {
                    id: memHeader
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root._memWidth
                    horizontalAlignment: Text.AlignRight
                    text: "MEM"
                    color: root.sortMode === "mem" ? Core.Theme.color.foreground : Core.Theme.color.foregroundDim
                }
            }
        }
    }

    // A ListView rather than a Column in a Flickable (the ledger's shape
    // above): this table renders every process on the machine, and a
    // delegate per row for 400 of them costs more to build than the whole
    // launcher. ListView is itself a Flickable, so the scroll seam is
    // unchanged.
    ListView {
        id: list
        anchors.top: procChrome.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        // A whole number of rows, never the leftover space: the card's own
        // height cap (Menu.qml's _maxTotalHeight) lands wherever it lands,
        // and a list anchored to the bottom of it draws its last row cut in
        // half, which reads as a broken frame rather than as more content
        // below.
        height: Math.max(0, Math.floor((root.height - statsPane.height - procChrome.height) / root._rowHeight) * root._rowHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root._rows

        delegate: Cell {
            id: procRow
            required property int index
            required property var modelData

            width: list.width
            height: root._rowHeight
            interactive: true
            selected: procRow.index === root._cursorIndex
            urgent: root.confirmAction !== "" && root.confirmPid === procRow.modelData.pid

            onClicked: {
                root.cursorPid = procRow.modelData.pid;
                root._disarm();
            }

            Text {
                id: pidText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root._pidWidth
                horizontalAlignment: Text.AlignRight
                text: procRow.modelData.pid
                color: procRow.dimForeground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            Text {
                id: nameText
                anchors.left: pidText.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._nameWidth
                elide: Text.ElideRight
                text: procRow.modelData.name
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            // A kernel thread has no argv at all, which is a fact about the
            // process rather than a gap in the reading, so the column says
            // which of the two it is.
            Text {
                anchors.left: nameText.right
                anchors.leftMargin: Core.Theme.space.lg
                anchors.right: cpuText.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: procRow.modelData.kernel ? "KERNEL" : procRow.modelData.cmd
                color: procRow.dimForeground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
                font.capitalization: procRow.modelData.kernel ? Font.AllUppercase : Font.MixedCase
            }

            Text {
                id: cpuText
                anchors.right: memText.left
                anchors.rightMargin: Core.Theme.space.lg
                anchors.verticalCenter: parent.verticalCenter
                width: root._cpuWidth
                horizontalAlignment: Text.AlignRight
                text: root._procPct(procRow.modelData.cpuFraction)
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }

            Text {
                id: memText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root._memWidth
                horizontalAlignment: Text.AlignRight
                text: root._bytes(procRow.modelData.memBytes)
                color: procRow.foreground
                font.family: Core.Theme.fontFamily
                font.pixelSize: Core.Theme.fontSize.body
            }
        }
    }

    // Nothing to show is two different facts, and they need two different
    // answers: the collector has not landed a sample yet, or it has and the
    // filter matched none of it. A sibling of the list rather than a child,
    // which would scroll with its content.
    Cell {
        id: emptyCell
        anchors.top: list.top
        width: list.width
        visible: root._rows.length === 0

        MetaLabel {
            text: ProcessService.available ? "NO MATCH" : "NO SAMPLE YET"
        }
    }
}
