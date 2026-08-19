import QtQuick
import qs.Core as Core
import qs.Components
import qs.Services
import "../../../Power/model.js" as Power

// The full system monitor, rendered inside the launcher card (M38 Task 7).
// Registered in Menu/appviews.js against the "monitor" route, loaded by
// Menu.qml's app-view Loader. Nothing here knows about the menu beyond
// being sized by it, so this file is also what a second app view copies.
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

    implicitHeight: columns.height

    Component.onCompleted: SystemMonitorService.subscribe()
    Component.onDestruction: SystemMonitorService.unsubscribe()

    // The app-view scroll seam (Menu.qml's key handler): a view that
    // declares `scrollTarget` gets ↑↓/Page/Home/End driving its Flickable,
    // which is what makes the launcher's own MOVE hint true on this route.
    // Declared beside the subscription on purpose: both are this file's
    // whole contract with the menu.
    readonly property Flickable scrollTarget: scroller

    readonly property real _colWidth: Math.round(root.width / 2)

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
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: columns.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // The ledger re-measures on every poll tick (a card appears, an
        // interface goes away), so content can shrink out from under a
        // scrolled-down reader and leave contentY past its own end.
        onContentHeightChanged: scroller.returnToBounds()

        Item {
            id: columns
            width: root.width
            height: Math.max(leftColumn.height, rightColumn.height)

            // Continues the left column's own trailing cell rules (Cell's
            // shared-rule contract) past whichever column ends first, so the
            // two ledgers read as one table rather than two stacks.
            Rectangle {
                x: leftColumn.width - Core.Theme.borderWidth
                width: Core.Theme.borderWidth
                height: columns.height
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
}
