import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Dualsense/model.js" as DualsenseModel

// DualSense panel (M29 Task 4, plan at
// docs/superpowers/plans/2026-08-18-m29-device-panels.md): a sysfs-only
// readout for a Sony DualSense controller, bound directly to
// DualsenseService (Services/DualsenseService.qml). No controls anywhere —
// the owner's host units already own the lightbar/player-LED writes, so
// this panel only ever displays what sysfs reports, and the title band
// carries a dim "READ ONLY" tag so that absence reads as designed rather
// than as a missing feature.
//
// Honest state first: no matching power_supply node at all renders one dim
// "NO CONTROLLER" cell. Past that gate, PanelHero opens on the battery
// percent as its readout (DESIGN.md §2.13 — unlike AirpodsPanel, this
// panel's whole point IS one number) and DualsenseModel.stateLine() as its
// meta; LIGHTBAR and PLAYER LEDS each render only while their own sysfs
// node was actually readable, independent of each other.
Panel {
    id: root

    panelTitle: "DUALSENSE"
    panelWidth: Theme.space.popupWidthNarrow

    titleActions: MetaLabel { text: "READ ONLY" }

    readonly property var _battery: DualsenseService.battery
    readonly property bool _present: DualsenseService.present
    readonly property var _lightbar: DualsenseService.lightbar
    readonly property var _playerLeds: DualsenseService.playerLeds

    onIsOpenChanged: {
        if (root.isOpen) {
            DualsenseService.acquire();
            // Freshen the reading the moment the panel opens rather than
            // waiting up to 30s for the shared timer's next tick —
            // `probe()` itself no-ops while a run is already in flight, so
            // this never doubles up with `acquire()`'s own first-consumer
            // probe.
            DualsenseService.probe();
        } else {
            DualsenseService.release();
        }
    }

    Cell {
        visible: !root._present
        width: parent.width

        MetaLabel { text: "NO CONTROLLER" }
    }

    PanelHero {
        visible: root._present
        width: parent.width
        glyph: "󰊗"
        title: "DualSense"
        meta: DualsenseModel.stateLine(root._battery)
        readout: root._present ? root._battery.percent + "%" : ""
        readoutSize: "displayLarge"
        rail: root._present ? root._battery.percent / 100 : -1
    }

    Cell {
        visible: root._present && root._lightbar !== null
        width: parent.width

        Row {
            spacing: Theme.space.sm

            MetaLabel { text: "LIGHTBAR"; colon: true }

            Rectangle {
                width: Theme.fontSize.body
                height: Theme.fontSize.body
                anchors.verticalCenter: parent.verticalCenter
                radius: 0
                color: root._lightbar || Theme.color.background
                border.width: Theme.borderWidth
                border.color: Theme.color.rule
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root._lightbar || ""
                color: Theme.color.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }
    }

    Cell {
        visible: root._present && root._playerLeds !== null
        width: parent.width

        Row {
            spacing: Theme.space.sm

            MetaLabel { text: "PLAYER LEDS"; colon: true }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.xs

                Repeater {
                    model: 5

                    Text {
                        required property int index
                        text: "●"
                        color: root._playerLeds !== null && index < root._playerLeds
                            ? Theme.color.foreground
                            : Theme.color.foregroundFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }
                }
            }
        }
    }
}
