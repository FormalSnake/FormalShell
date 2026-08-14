import QtQuick
import Quickshell.Services.SystemTray
import qs.Core
import qs.Components
import qs.Services

// The tray's bucket manager (DESIGN.md §Panels, M23 Task 3): macOS
// Bartender's "which icons live on the bar" sheet, read through this shell's
// ledger grammar: one row per registered StatusNotifierItem, each carrying
// the item's own name and the two verbs that move it between pinned, drawer
// and hidden.
//
// Built on Components/Panel, the shell's one popout mechanism, rather than a
// surface of its own: it inherits the bordered radius-0 card, the anchoring
// under the cell that opened it, the Escape and click-outside dismissal, the
// multi-output DismissTwins catchers and PanelRegistry's mutual exclusion
// with every other popout, none of which is worth rebuilding for one more
// card. It is declared inside Tray.qml rather than shell.qml (where every
// other Panel instance lives) because Tray.qml is the only file the tray
// owns on the bar; see that file's own gate for how one instance per screen
// still yields exactly one open popup.
//
// Rows use the panel ledger's pointer feedback, not a keyboard cursor: this
// task does not make bar cells keyboard-navigable, and the IPC routes
// (`tray pin|unpin|hide|show`) are the non-pointer path. The two action
// cells carry no second state treatment either, because the verb already
// says which bucket the item is in: UNPIN can only appear on a pinned item
// and SHOW only on a hidden one (DESIGN.md §2.4's no-double-treatment rule).
Panel {
    id: root

    panelTitle: "TRAY / MANAGE"
    // Wider than the default popout: every row carries a foreign process's
    // own title plus two action cells, and the title is the part that would
    // otherwise elide down to nothing.
    panelWidth: Theme.space.popupWidthWide

    readonly property int _count: SystemTray.items.values.length

    Cell {
        width: parent.width

        // Sentence-cased body text, deliberately not a MetaLabel: this
        // explains the surface rather than naming a piece of content, so
        // DESIGN.md §2.3's uppercase meta convention does not apply to it.
        Text {
            width: parent.width
            text: "Pinned icons stay on the bar. Hidden icons never show."
            color: Theme.color.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.bodySmall
            wrapMode: Text.WordWrap
        }
    }

    Cell {
        visible: root._count === 0
        width: parent.width

        MetaLabel { text: "NO ITEMS" }
    }

    // Bound to the live ObjectModel, not a `.values` snapshot, for the same
    // reason Tray.qml's own Repeater is: Quickshell re-notifies `.values` far
    // more often than the item set changes, and a plain-array model treats
    // every new array as a full reset that would drop the pointer's place in
    // the list mid-click.
    Repeater {
        model: SystemTray.items

        delegate: Cell {
            id: itemRow
            required property var modelData
            width: parent.width

            readonly property string _id: itemRow.modelData.id
            readonly property string _bucket: TrayService.bucketOf(itemRow._id)

            hovered: nameHover.containsMouse || pinHover.containsMouse || hideHover.containsMouse

            Item {
                width: parent.width
                // Measured off the cells rather than actionsRow: a Row drops
                // a hidden child from its own height, which would leave a
                // locked row shorter than the rest and break the ledger's
                // uniform row height.
                height: Math.max(nameText.implicitHeight, pinCell.height, hideCell.height, lockedCell.height)

                Text {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: actionsRow.left
                    anchors.rightMargin: Theme.space.sm
                    anchors.verticalCenter: parent.verticalCenter
                    // The item's own words, in the SNI's own order of
                    // preference, and never uppercased: another process's
                    // title is content, not a caption naming content (the
                    // same reasoning Tooltip.qml's `verbatim` flag carries).
                    text: itemRow.modelData.title || itemRow.modelData.id
                    color: itemRow.foreground
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                }

                Row {
                    id: actionsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.sm

                    Cell {
                        id: pinCell
                        visible: !TrayService.bucketsLocked
                        width: implicitWidth
                        height: implicitHeight
                        hovered: pinHover.containsMouse

                        MetaLabel {
                            // Band-1 ink, not MetaLabel's own dim default:
                            // these two verbs ARE the row's content, the same
                            // call BluetoothPanel's per-row action cells make
                            // (DESIGN.md §1.4).
                            text: itemRow._bucket === "pinned" ? "UNPIN" : "PIN"
                            color: pinCell.foreground
                        }

                        MouseArea {
                            id: pinHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TrayService.togglePin(itemRow._id)
                        }
                    }

                    Cell {
                        id: hideCell
                        visible: !TrayService.bucketsLocked
                        width: implicitWidth
                        height: implicitHeight
                        hovered: hideHover.containsMouse

                        MetaLabel {
                            text: itemRow._bucket === "hidden" ? "SHOW" : "HIDE"
                            color: hideCell.foreground
                        }

                        MouseArea {
                            id: hideHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: TrayService.toggleHide(itemRow._id)
                        }
                    }

                    // settings.json declares the buckets, and the shell never
                    // writes settings.json, so the row says where the answer
                    // lives instead of offering buttons whose every click
                    // would be dropped by TrayService.
                    Cell {
                        id: lockedCell
                        visible: TrayService.bucketsLocked
                        width: implicitWidth
                        height: implicitHeight

                        MetaLabel {
                            text: "SET IN SETTINGS"
                            color: lockedCell.dimForeground
                        }
                    }
                }

                MouseArea {
                    id: nameHover
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: actionsRow.left
                    hoverEnabled: true
                }
            }
        }
    }
}
