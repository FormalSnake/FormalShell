import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Dualsense/model.js" as DualsenseModel

// DualSense panel (DESIGN.md §3 "Panel", spec "Panels"): a sysfs-only
// readout for a Sony DualSense controller, bound to DualsenseService. No
// controls anywhere, because the owner's host units already own the
// lightbar and player-LED writes, so this panel only ever displays what
// sysfs reports; the header carries a READ ONLY chip so that absence reads
// as designed rather than as a missing feature.
//
// Honest state first: no matching power_supply node at all renders one dim
// NO CONTROLLER row. Past that gate the hero carries the battery percent as
// its oversized readout (unlike AirPods, this panel's whole subject IS one
// number) with DualsenseModel.stateLine() as its meta and the charge level
// as its rail. LIGHTBAR and PLAYER LEDS each render only while their own
// sysfs node was actually readable, independent of each other.
//
// Keyboard (spec "Keyboard model"): the cursor walks the readout rows and
// nothing more. There is deliberately no cursorActivated handler, since
// nothing here is actionable, the same shape MonitorPanel's metric rows
// take; Escape closes and the ring says which row the eye is on.
Panel {
    id: root

    panelIcon: "gamepad-2"
    panelTitle: "DualSense"
    panelWidth: Theme.space.popupWidthDefault

    // A chip, not a control: this panel writes nothing, and the header is
    // where that has to be said before the rows are read.
    titleActions: [
        Cell {
            chip: true
            radius: Theme.radiusSm

            SectionLabel { text: "READ ONLY" }
        }
    ]

    readonly property var _battery: DualsenseService.battery
    readonly property bool _present: DualsenseService.present
    readonly property var _lightbar: DualsenseService.lightbar
    readonly property var _playerLeds: DualsenseService.playerLeds

    readonly property var _rows: {
        var out = [];
        if (!root._present)
            return out;
        out.push("battery");
        if (root._lightbar !== null)
            out.push("lightbar");
        if (root._playerLeds !== null)
            out.push("leds");
        return out;
    }

    function _rowIndex(key) {
        return root._rows.indexOf(key);
    }

    function _pointAt(index) {
        if (index < 0)
            return;
        root.cursorActive = true;
        root.cursorIndex = index;
    }

    cursorCount: root._rows.length

    onIsOpenChanged: {
        if (root.isOpen) {
            root.cursorIndex = 0;
            root.cursorSection = 0;
            DualsenseService.acquire();
            // Freshen the reading the moment the panel opens rather than
            // waiting up to 30s for the shared timer's next tick.
            // `probe()` no-ops while a run is already in flight, so this
            // never doubles up with `acquire()`'s own first-consumer probe.
            DualsenseService.probe();
        } else {
            DualsenseService.release();
        }
    }

    Cell {
        visible: !root._present
        width: parent.width

        SectionLabel { text: "NO CONTROLLER" }
    }

    PanelHero {
        id: batteryHero
        visible: root._present
        width: parent.width
        title: "DualSense"
        meta: DualsenseModel.stateLine(root._battery)
        readout: root._present ? root._battery.percent + "%" : ""
        readoutSize: "displayLarge"
        rail: root._present ? root._battery.percent / 100 : -1
        cursor: root.cursorActive && root.cursorIndex === 0
        interactive: true
        acceptedButtons: Qt.NoButton
        onContainsPointerChanged: if (batteryHero.containsPointer) root._pointAt(0)

        leading: Component {
            Icon {
                name: "gamepad-2"
                size: Theme.fontSize.heading
                color: batteryHero.foreground
            }
        }
    }

    Column {
        width: parent.width
        visible: root._present && root._lightbar !== null
        spacing: Theme.space.rowGap

        SectionLabel { text: "LIGHTBAR" }

        Cell {
            id: lightbarCell
            width: parent.width
            cursor: root.cursorActive && root.cursorIndex === root._rowIndex("lightbar")
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (lightbarCell.containsPointer) root._pointAt(root._rowIndex("lightbar"))

            Item {
                width: parent.width
                height: Math.max(lightbarSwatch.height, lightbarValue.implicitHeight)

                // primitive-exempt: the lightbar's own colour, drawn as a swatch. The
                // fill IS the value here, so no primitive can own it.
                Rectangle {
                    id: lightbarSwatch
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.fontSize.body
                    height: Theme.fontSize.body
                    radius: Theme.radiusSm
                    color: root._lightbar || Theme.color.background
                    border.width: Theme.borderWidth
                    border.color: Theme.color.border
                }

                // A hex triplet is an identifier, so it takes the mono face
                // (spec "Type").
                Text {
                    id: lightbarValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._lightbar || ""
                    color: lightbarCell.foreground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._present && root._playerLeds !== null
        spacing: Theme.space.rowGap

        SectionLabel { text: "PLAYER LEDS" }

        Cell {
            id: ledsCell
            width: parent.width
            cursor: root.cursorActive && root.cursorIndex === root._rowIndex("leds")
            interactive: true
            acceptedButtons: Qt.NoButton
            onContainsPointerChanged: if (ledsCell.containsPointer) root._pointAt(root._rowIndex("leds"))

            Item {
                width: parent.width
                height: Math.max(ledsRow.height, ledsValue.implicitHeight)

                // The pips a real DualSense always exposes all five of
                // (DESIGN.md §3's own dot idiom): lit ones carry `primary`,
                // the rest stay muted.
                Row {
                    id: ledsRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.sm

                    Repeater {
                        model: 5

                        // primitive-exempt: one of five player-LED pips, a hardware readout
                        // drawn at the size the LEDs are. An indicator, not a surface.
                        Rectangle {
                            required property int index
                            width: Theme.space.md
                            height: Theme.space.md
                            radius: width / 2
                            color: root._playerLeds !== null && index < root._playerLeds
                                ? Theme.color.primary
                                : Theme.color.mutedForeground
                        }
                    }
                }

                Text {
                    id: ledsValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._playerLeds !== null ? root._playerLeds + " / 5" : ""
                    color: ledsCell.foreground
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }
            }
        }
    }
}
