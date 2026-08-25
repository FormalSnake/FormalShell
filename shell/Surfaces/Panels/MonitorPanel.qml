import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Compact system-monitor panel (M38 Task 6, plan at
// docs/superpowers/plans/2026-08-19-m38-launcher-everything-and-gpu.md):
// CPU, MEM, and a one-line-per-card GPU summary: the glance this bar cell
// opens under it. This is deliberately NOT the full monitor: every metric
// here also lives in the launcher's "monitor" route (Menu/appviews.js,
// Surfaces/Menu/views/MonitorView.qml: per-core bars, swap, load, uptime,
// temps, network, disk, full GPU detail), and the last row below is the
// hinge between the two, closing this panel and summoning that route.
//
// SystemMonitorService only polls while subscribed (its own header); this
// panel joins in onIsOpenChanged rather than on instantiation, so an
// unopened panel costs nothing beyond the bar cell's own subscription (if
// the cell is placed at all). GpuService rides that same tick passively
// (its own Connections to SystemMonitorService.tick), so no separate GPU
// subscription is needed here.
//
// Every value can be null on the first tick after a subscribe (cpuDelta/
// netDelta both need a previous sample): `_pct` renders that as an em
// dash, never a fabricated 0%.
Panel {
    id: root

    property var menu: null

    panelTitle: "MONITOR"
    panelWidth: Theme.space.popupWidthDefault

    onIsOpenChanged: {
        if (root.isOpen)
            SystemMonitorService.subscribe();
        else
            SystemMonitorService.unsubscribe();
    }

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

    readonly property var _mem: SystemMonitorService.mem

    Cell {
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                MetaLabel {
                    width: parent.width - cpuValue.width - parent.spacing
                    text: "CPU"
                    colon: true
                }

                Text {
                    id: cpuValue
                    text: root._pct(SystemMonitorService.cpu.aggregate)
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }

            DitherFill {
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * root._fill(SystemMonitorService.cpu.aggregate)
                    height: parent.height
                    color: Theme.color.primary
                }
            }
        }
    }

    Cell {
        width: parent.width

        Column {
            width: parent.width
            spacing: Theme.space.xxs

            Row {
                width: parent.width
                spacing: Theme.space.sm

                MetaLabel {
                    width: parent.width - memValue.width - parent.spacing
                    text: "MEM"
                    colon: true
                }

                Text {
                    id: memValue
                    text: root._pct(root._mem.available ? root._mem.usedFraction : null)
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }
            }

            DitherFill {
                width: parent.width
                height: Theme.space.trackThickness

                Rectangle {
                    width: parent.width * root._fill(root._mem.available ? root._mem.usedFraction : null)
                    height: parent.height
                    color: Theme.color.primary
                }
            }
        }
    }

    Cell {
        width: parent.width

        MetaLabel { text: "GPU"; colon: true }
    }

    // No card in /sys/class/drm at all (the mac VM, a headless server) is a
    // normal state to name, not a gap to fill with a plausible-looking row.
    Cell {
        width: parent.width
        visible: GpuService.cards.length === 0

        MetaLabel { text: "NO GPU" }
    }

    Repeater {
        model: GpuService.cards

        delegate: Cell {
            id: gpuCell
            required property var modelData
            width: parent.width

            Row {
                width: parent.width
                spacing: Theme.space.sm

                Text {
                    width: parent.width - gpuStatus.width - parent.spacing
                    text: gpuCell.modelData.name
                    color: gpuCell.modelData.metrics.available ? Theme.color.foreground : Theme.color.mutedForeground
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                // i915/xe expose no unprivileged utilisation counter, and
                // nvidia-smi may not be on PATH, both are a normal state,
                // never a fabricated percent.
                MetaLabel {
                    id: gpuStatus
                    text: gpuCell.modelData.metrics.available ? root._pct(gpuCell.modelData.metrics.busy) : "NO METRICS"
                    color: gpuCell.modelData.metrics.available ? Theme.color.foreground : Theme.color.mutedForeground
                }
            }
        }
    }

    // Which screen the shell treats as the main one
    // (`display.outputPriority`, MainOutputService). It sits under the GPU
    // rows because that is what it qualifies on a hybrid machine: the card
    // above driving the screen named here. "—" when there is no output at
    // all, never a placeholder connector.
    Cell {
        width: parent.width

        Row {
            width: parent.width
            spacing: Theme.space.sm

            MetaLabel {
                width: parent.width - mainOutputValue.width - parent.spacing
                text: "MAIN DISPLAY"
                colon: true
                elide: Text.ElideRight
            }

            Text {
                id: mainOutputValue
                text: MainOutputService.mainOutput !== "" ? MainOutputService.mainOutput : "—"
                color: Theme.color.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }
    }

    // The hinge to the full view (Menu/appviews.js's "monitor" route),
    // which carries the process table too: closing first so the launcher
    // opens into a clean surface rather than stacking on top of an
    // already-open popout.
    Cell {
        id: openFullCell
        width: parent.width
        interactive: true

        ActionLabel {
            text: "OPEN SYSTEM MONITOR"
            color: openFullCell.foreground
        }

        onClicked: {
            root.close();
            if (root.menu)
                root.menu.open("monitor");
        }
    }
}
