import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor

// The shared per-widget popout (DESIGN.md §Panels, spec §2, M6 Task 1): one
// ledger table anchored under the bar cell that opened it — header meta row
// (panelTitle) then whatever rows the instantiating panel (AudioPanel, and
// later network/bluetooth/power/calendar/weather) supplies via its default
// content slot. Same top-layer / OnDemand-keyboard structure as
// Center.qml/Osd.qml, but — unlike either — needs "closes on click-outside"
// too. Quickshell's PopupWindow gives that for free via grabFocus, but its
// xdg_popup grab needs a real pointer/key serial, which panel.open(name)
// (PanelIpc, headless verification) never has. So this stays a plain
// PanelWindow like every other surface: a transparent, exclusiveZone:-1
// layer spanning the whole screen, with a backdrop MouseArea that closes on
// any click landing outside the visible frame (the frame's own nested
// MouseArea eats its clicks first, per Qt Quick's normal nested-MouseArea
// priority, so nothing inside it ever falls through).
PanelWindow {
    id: root

    property bool isOpen: false
    property string panelTitle: ""
    property int panelWidth: 320
    // Screen-relative x of the bar cell that opened this panel, computed by
    // the caller within ITS OWN window (see AudioWidget.qml) — Wayland gives
    // clients no cross-window global coordinates, so a raw Item reference
    // mapped here would be meaningless. -1 means "no cell, opened via IPC",
    // which falls back to the bar's right region, where every M6 widget
    // cell lives.
    property real anchorX: -1
    default property alias content: contentColumn.data

    readonly property int _barHeight: 32

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    readonly property real _frameX: {
        if (!root._screen) return 0;
        var x = root.anchorX >= 0 ? root.anchorX : (root._screen.width - root.panelWidth - Theme.spacing.md);
        return Math.max(0, Math.min(x, root._screen.width - root.panelWidth));
    }

    readonly property real _maxContentHeight: root._screen ? root._screen.height * 0.6 : 400
    readonly property real _frameHeight: Theme.borderWidth + titleCell.height + Math.min(contentColumn.implicitHeight, root._maxContentHeight)

    function open(x) {
        root.anchorX = x !== undefined ? x : -1;
        root.isOpen = true;
        Qt.callLater(function () { backdrop.forceActiveFocus(); });
    }

    function close() {
        root.isOpen = false;
    }

    function toggle(x) {
        if (root.isOpen) root.close();
        else root.open(x);
    }

    screen: root._screen
    visible: root.isOpen
    color: "transparent"

    WlrLayershell.namespace: "formalshell:panel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        onClicked: root.close()

        Item {
            id: frame
            x: root._frameX
            y: root._barHeight
            width: root.panelWidth
            height: root._frameHeight

            // Swallows clicks anywhere inside the frame (including padding
            // between rows) before they ever reach the backdrop above —
            // ordinary nested-MouseArea priority, no manual event plumbing.
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                id: topRule
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.borderWidth
                color: Theme.color.rule
            }

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: Theme.borderWidth
                color: Theme.color.rule
            }

            Cell {
                id: titleCell
                anchors.top: topRule.bottom
                anchors.left: parent.left
                anchors.leftMargin: Theme.borderWidth
                width: frame.width - Theme.borderWidth

                MetaLabel { text: root.panelTitle }
            }

            Flickable {
                anchors.top: titleCell.bottom
                anchors.left: parent.left
                anchors.leftMargin: Theme.borderWidth
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                contentWidth: width
                contentHeight: contentColumn.implicitHeight

                Column {
                    id: contentColumn
                    width: parent.width
                }
            }
        }
    }
}
