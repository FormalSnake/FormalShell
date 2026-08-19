import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar cell for the system monitor (M38 Task 6, plan at
// docs/superpowers/plans/2026-08-19-m38-launcher-everything-and-gpu.md): a
// gauge glyph plus CPU/MEM percent, GPU percent appended only when some card
// on this machine actually reports one: MonitorPanel is the compact glance
// this cell opens, the launcher's "monitor" route (Menu/appviews.js) is the
// full one. Glyph codepoint verified against the pinned
// nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via fonttools ttx, not
// memory: md-gauge U+F029A, the same one panels.monitor uses in
// Menu/providers.js's PANEL_NAMES.
//
// SystemMonitorService only polls while something has subscribed
// (SystemMonitorService.qml's own header), so this cell only exists to
// spawn a collector for as long as "monitor" is actually placed in
// bar.layout, same acquire/release-on-instantiation idiom
// AirpodsWidget/DualsenseWidget already use for their own services.
//
// Every number here can be null on the very first tick (cpuDelta/memory
// both need a previous sample, sysinfo.js's own contract): that renders as
// an em dash, never a fabricated 0% or a gap that would reflow the bar's
// other cells as the cell's width settles.
Cell {
    id: root

    property var panel: null

    readonly property bool _panelOpen: root.panel ? root.panel.isOpen : false

    readonly property var _cpu: SystemMonitorService.cpu
    readonly property var _mem: SystemMonitorService.mem

    // First card whose driver actually reports a busy fraction (amdgpu,
    // or nvidia with nvidia-smi on PATH): i915/xe and a card with no
    // nvidia-smi both carry metrics.available:false, and this cell just
    // omits the GPU segment entirely rather than printing a fabricated
    // percent for them.
    function _busyCard() {
        var cards = GpuService.cards;
        for (var i = 0; i < cards.length; i++) {
            var m = cards[i].metrics;
            if (m && m.available && m.busy !== null && m.busy !== undefined)
                return cards[i];
        }
        return null;
    }

    readonly property var _gpuCard: root._busyCard()

    function _pct(fraction) {
        if (fraction === null || fraction === undefined || !isFinite(fraction))
            return "—";
        return Math.round(fraction * 100) + "%";
    }

    // Label-off by default (M23's precedent, reversed for this cell the way
    // DisplayWidget.qml's own showLabel already is): the value text below is
    // always-on content, not something this flag gates: `showLabel` opts in
    // an extra "MONITOR" caption for a host where the glyph plus numbers
    // alone could read ambiguously next to other percent-bearing cells.
    readonly property bool _showLabel: Config.get("bar.widgets.monitor.showLabel", false)

    standalone: true
    tooltipText: "MONITOR / CPU " + root._pct(root._cpu.aggregate) + " / MEM " + root._pct(root._mem.available ? root._mem.usedFraction : null)
        + (root._gpuCard ? " / GPU " + root._pct(root._gpuCard.metrics.busy) : "")

    Component.onCompleted: SystemMonitorService.subscribe()
    Component.onDestruction: SystemMonitorService.unsubscribe()

    // The value text resizes as its digits tick: glide the width instead
    // of shoving the bar's other widgets instantly (DESIGN.md §4, M16 Task
    // 2's contract, extended to every numeric bar cell by M26 Task 7).
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.xxs

        // Fixed-width slot (M26 Task 7), matching this cell's siblings even
        // though this glyph itself never swaps.
        Item {
            id: glyphSlot
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space.huge
            height: glyphText.implicitHeight

            Text {
                id: glyphText
                anchors.centerIn: parent
                text: "󰊚"
                color: root.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }

        MetaLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: "C" + root._pct(root._cpu.aggregate) + " M" + root._pct(root._mem.available ? root._mem.usedFraction : null)
                + (root._gpuCard ? " G" + root._pct(root._gpuCard.metrics.busy) : "")
            color: root.dimForeground
        }

        MetaLabel {
            visible: root._showLabel
            anchors.verticalCenter: parent.verticalCenter
            text: "MONITOR"
            color: root.dimForeground
        }
    }

    PanelOpenDot {
        visible: root._panelOpen
        inverted: root.invertedNow
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    interactive: true
    onClicked: {
        if (root.panel)
            root.panel.toggleFrom(root);
    }
}
