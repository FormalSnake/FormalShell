import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Compact system-monitor panel (DESIGN.md §3 "Panel", spec "Panels"): CPU,
// memory and one row per GPU card, each a section label over a `display`
// mono figure and a `Track`, then the screen `display.outputPriority`
// resolves to, then the hinge into the launcher's full `monitor` route
// (Menu/appviews.js), which carries the per-core bars, swap, load, uptime,
// temps, network, disk, full GPU detail and the process table.
//
// SystemMonitorService only polls while subscribed (its own header); this
// panel joins in onIsOpenChanged rather than on instantiation, so an
// unopened panel costs nothing beyond the bar cell's own subscription (if
// the cell is placed at all). GpuService rides that same tick passively (its
// own Connections to SystemMonitorService.tick), so no separate GPU
// subscription is needed here.
//
// Honest states, never a fabricated number: every value can be null on the
// first tick after a subscribe (cpuDelta and netDelta both need a previous
// sample) and renders as `--`; a machine with no card in /sys/class/drm at
// all is one muted `NO GPU` row; a card whose driver exposes no unprivileged
// utilisation counter (i915/xe, or nvidia with no nvidia-smi on PATH) is
// `NO METRICS` with no track under it.
//
// Keyboard (spec "Keyboard model"): the cursor walks the readout rows, Tab
// reaches the footer button and Enter opens the full view there.
Panel {
    id: root

    property var menu: null

    panelIcon: "activity"
    panelTitle: "Monitor"
    panelWidth: Theme.space.popupWidthWide

    readonly property var _mem: SystemMonitorService.mem

    function _pct(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return "--";
        return Math.round(fraction * 100) + "%";
    }

    function _fill(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return -1;
        return Math.max(0, Math.min(1, fraction));
    }

    // One descriptor per metric row: the section label above it, the mono
    // figure, the track fraction (-1 draws no track) and the honest state
    // that stands in for a figure nobody can measure.
    readonly property var _metrics: {
        var out = [];
        var cpu = SystemMonitorService.cpu.aggregate;
        out.push({ label: "CPU", figure: root._pct(cpu), fill: root._fill(cpu), state: "" });

        var memFraction = root._mem.available ? root._mem.usedFraction : null;
        out.push({ label: "MEMORY", figure: root._pct(memFraction), fill: root._fill(memFraction), state: "" });

        var cards = GpuService.cards;
        if (cards.length === 0) {
            out.push({ label: "GPU", figure: "", fill: -1, state: "NO GPU" });
        } else {
            for (var i = 0; i < cards.length; i++) {
                var m = cards[i].metrics;
                var measured = m && m.available && m.busy !== null && m.busy !== undefined;
                out.push({
                    label: "GPU " + cards[i].name,
                    figure: measured ? root._pct(m.busy) : "",
                    fill: measured ? root._fill(m.busy) : -1,
                    state: measured ? "" : "NO METRICS"
                });
            }
        }
        return out;
    }

    // The metric rows plus the main-display row under them.
    cursorCount: root._metrics.length + 1
    // 0 is the readout list, 1 is the footer's open button.
    sectionCount: 2

    onCursorActivated: {
        if (root.cursorSection !== 1)
            return;
        root._openFullView();
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            SystemMonitorService.subscribe();
            root.cursorIndex = 0;
            root.cursorSection = 0;
        } else {
            SystemMonitorService.unsubscribe();
        }
    }

    // Closing first so the launcher opens into a clean surface rather than
    // stacking on top of an already-open popout.
    function _openFullView() {
        root.close();
        if (root.menu)
            root.menu.open("monitor");
    }

    function _pointAt(index) {
        root.cursorActive = true;
        root.cursorSection = 0;
        root.cursorIndex = index;
    }

    Repeater {
        model: root._metrics

        delegate: Column {
            id: metricBlock
            required property int index
            required property var modelData

            width: parent.width
            spacing: Theme.space.rowGap

            SectionLabel { leftPadding: Theme.space.controlPaddingX; text: metricBlock.modelData.label }

            Cell {
                id: metricCell
                width: parent.width
                ghost: true
                cursor: root.cursorActive && root.cursorSection === 0 && root.cursorIndex === metricBlock.index
                interactive: true
                acceptedButtons: Qt.NoButton
                onContainsPointerChanged: if (metricCell.containsPointer) root._pointAt(metricBlock.index)

                Column {
                    width: parent.width
                    spacing: Theme.space.xxs

                    // A figure and a state never co-occur: `state` is what
                    // stands in for a figure nobody can measure.
                    Row {
                        width: parent.width
                        spacing: Theme.space.iconGap

                        Text {
                            visible: metricBlock.modelData.figure !== ""
                            text: metricBlock.modelData.figure
                            color: metricCell.foreground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.display
                            font.weight: Theme.weight.semibold
                        }

                        SectionLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: metricBlock.modelData.state !== ""
                            text: metricBlock.modelData.state
                            color: metricCell.dimForeground
                        }
                    }

                    Track {
                        width: parent.width
                        visible: metricBlock.modelData.fill >= 0
                        value: metricBlock.modelData.fill
                    }
                }
            }
        }
    }

    // Which screen the shell treats as the main one
    // (`display.outputPriority`, MainOutputService). It sits under the GPU
    // rows because that is what it qualifies on a hybrid machine: the card
    // above driving the screen named here.
    Column {
        width: parent.width
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "MAIN DISPLAY" }

        Cell {
            id: mainOutputCell
            width: parent.width
            ghost: true
            cursor: root.cursorActive && root.cursorSection === 0 && root.cursorIndex === root._metrics.length
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (mainOutputCell.containsPointer) root._pointAt(root._metrics.length)

            Item {
                width: parent.width
                height: mainOutputValue.implicitHeight

                // A connector name is an identifier, so it takes the mono
                // face at the ordinary row size rather than the oversized
                // readout the metrics above carry.
                Text {
                    id: mainOutputValue
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: MainOutputService.mainOutput !== "" ? MainOutputService.mainOutput : "--"
                    color: mainOutputCell.foreground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }
            }
        }
    }

    Item {
        width: parent.width
        height: openFullButton.height

        Button {
            id: openFullButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            variant: "ghost"
            icon: "external-link"
            text: "Open monitor"
            cursor: root.cursorActive && root.cursorSection === 1
            onClicked: root._openFullView()
        }
    }
}
