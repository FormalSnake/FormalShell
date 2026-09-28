import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Notifications/model.js" as Model
import "../../Iphone/model.js" as IphoneModel

// iPhone panel (M75 Task 3, DESIGN.md §3 "Panel"): the popout behind
// IphoneWidget's bar cell, bound to IphoneService. Honest states first: no
// bridge binary on PATH, a bridge that cannot reach ancs4linux's observer
// (the system daemon `services.formalshell.iphone.enable` turns on), and a
// running daemon with no phone bonded, which offers Pair with the code the
// phone shows once advertising starts. Past those the hero is the phone
// itself, the Focus line is worded as an inference (ANCS carries no Focus
// state of its own, only the `silent` flag a Focus intercept sets on
// whatever it holds back), and Recent lists the mirrored notifications with
// their phone-side actions and a local dismiss synced back to the phone.
//
// Below Recent, a Now playing section (M75 Task 4): the phone's own AMS
// now-playing, a compact title/artist/transport peek driven straight off
// IphoneService (never through MediaService's active-source pick, so this
// card always reaches the phone), honest about AMS having nothing to report
// yet. MediaPanel picks the phone up as an ordinary `iphone` row in its own
// source menu with no wiring here at all.
//
// Keyboard (spec "Keyboard model"): the cursor walks Recent keyed by
// notification id (BluetoothPanel's idiom), so a row arriving or leaving
// mid-session never slides the highlight onto a different notification.
// Enter fires the row's positive action (the phone's own label, "Answer" or
// "Reply", decides what it does), `x` dismisses it on both ends, and Tab
// reaches the now-playing transport and the footer's Pair button, which
// never both show at once (the footer only appears with no phone connected,
// and now-playing only with one).
Panel {
    id: root

    panelIcon: "smartphone"
    panelTitle: "iPhone"
    panelWidth: Theme.space.popupWidthDefault

    readonly property bool _notInstalled: !IphoneService.installed
    readonly property bool _daemonDown: IphoneService.installed && !IphoneService.available
    readonly property bool _noPhone: IphoneService.available && !IphoneService.connected
    readonly property bool _connected: IphoneService.connected
    readonly property bool _pairing: IphoneService.advertising || IphoneService.pairingCode !== ""
    readonly property bool _showFooter: root._noPhone

    // The now-playing card (M75 Task 4): a row only once AMS has actually
    // reported a track, same gate MediaService.qml's `_iphoneRows` uses, so
    // this and the footer's Pair button never both need a section (a phone
    // that is `_noPhone` has nothing connected to play anything).
    readonly property bool _nowPlaying: root._connected && IphoneService.mediaAvailable && IphoneService.mediaTitle !== ""
    readonly property var _nowPlayingOptions: [
        { icon: "skip-back", value: "prev" },
        { icon: IphoneService.mediaPlayback === "playing" ? "pause" : "play", value: "toggle" },
        { icon: "skip-forward", value: "next" }
    ]

    readonly property var _entries: IphoneService.recent
    readonly property var _rowModel: root._entries.map(function (entry, i) {
        return { entry: entry, idx: i, ruled: i > 0 };
    })

    // Relative timestamps recompute off this timer alone, never off a
    // notification's own arrival tick (Center.qml's same constraint).
    property double _now: Date.now()
    Timer {
        interval: 30000
        running: root.isOpen
        repeat: true
        onTriggered: root._now = Date.now()
    }

    // 0 is Recent; the now-playing card and the footer's Pair button never
    // coexist (see `_nowPlaying`'s comment), so whichever is showing takes
    // section 1 and `_footerSection`/`_nowPlayingSection` are never both >= 0.
    readonly property int _nowPlayingSection: root._nowPlaying ? 1 : -1
    readonly property int _footerSection: root._showFooter ? 1 : -1

    cursorCount: root.cursorSection === 0 ? root._entries.length
        : root.cursorSection === root._nowPlayingSection ? root._nowPlayingOptions.length : 1
    sectionCount: 1 + (root._nowPlaying ? 1 : 0) + (root._showFooter ? 1 : 0)

    function _idAt(index) {
        var e = root._entries[index];
        return e ? e.id : -1;
    }

    function _indexForId(id) {
        for (var i = 0; i < root._entries.length; i++)
            if (root._entries[i].id === id)
                return i;
        return -1;
    }

    property int _cursorId: -1

    onCursorIndexChanged: {
        if (root.cursorSection === 0)
            root._cursorId = root._idAt(root.cursorIndex);
    }

    onCursorSectionChanged: {
        root.cursorIndex = 0;
        if (root.cursorSection === 0)
            root._cursorId = root._idAt(0);
    }

    on_EntriesChanged: {
        var index = root._indexForId(root._cursorId);
        if (index >= 0 && index !== root.cursorIndex)
            root.cursorIndex = index;
    }

    // The footer and the now-playing card each come and go on their own
    // (pairing state, AMS reporting a track); a cursor stranded on either
    // when it stops rendering falls back to Recent.
    on_ShowFooterChanged: {
        if (root._showFooter || root.cursorSection === 0)
            return;
        root.cursorSection = 0;
        root.cursorIndex = 0;
        root._cursorId = root._idAt(0);
    }

    on_NowPlayingChanged: {
        if (root._nowPlaying || root.cursorSection === 0)
            return;
        root.cursorSection = 0;
        root.cursorIndex = 0;
        root._cursorId = root._idAt(0);
    }

    function _pointAt(section, index) {
        root.cursorActive = true;
        root.cursorSection = section;
        root.cursorIndex = index;
    }

    function _pressNowPlaying(index) {
        var opt = root._nowPlayingOptions[index];
        if (opt)
            IphoneService.mediaCommand(opt.value);
    }

    onCursorActivated: index => {
        if (root.cursorSection === root._nowPlayingSection) {
            root._pressNowPlaying(index);
            return;
        }
        if (root.cursorSection === root._footerSection) {
            IphoneService.pair();
            return;
        }
        var e = root._entries[index];
        if (e && e.positiveAction !== "")
            IphoneService.invoke(e.id, true);
    }

    onCursorDeleted: index => {
        if (root.cursorSection !== 0)
            return;
        var e = root._entries[index];
        if (e)
            IphoneService.dismiss(e.id);
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root.cursorIndex = 0;
            root.cursorSection = 0;
            root._cursorId = root._idAt(0);
            IphoneService.markRead();
        } else {
            root._cursorId = -1;
        }
    }

    titleActions: [
        IconButton {
            name: "trash"
            tooltipText: "Clear all"
            visible: root._entries.length > 0
            onClicked: IphoneService.clear()
        }
    ]

    SectionLabel {
        visible: root._notInstalled
        leftPadding: Theme.space.controlPaddingX
        text: "No bridge on PATH"
    }

    Column {
        visible: root._daemonDown
        width: parent.width
        spacing: Theme.space.xxs

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "Bridge not running"
        }

        Text {
            width: parent.width
            leftPadding: Theme.space.controlPaddingX
            text: "Enable services.formalshell.iphone.enable and rebuild"
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            wrapMode: Text.WordWrap
        }
    }

    Text {
        visible: IphoneService.lastError !== "" && !root._notInstalled && !root._daemonDown
        width: parent.width
        leftPadding: Theme.space.controlPaddingX
        text: IphoneService.lastError
        color: Theme.color.destructive
        font.family: Theme.fontFamilySans
        font.pixelSize: Theme.fontSize.bodySmall
        wrapMode: Text.WordWrap
    }

    PanelHero {
        id: deviceHero
        visible: root._connected
        width: parent.width
        title: IphoneService.deviceName !== "" ? IphoneService.deviceName : "iPhone"
        meta: "Connected"
        readout: IphoneService.batteryAvailable ? Math.round(IphoneService.battery * 100) + "%" : ""
        rail: IphoneService.batteryAvailable ? IphoneService.battery : -1

        leading: Component {
            Icon {
                name: "smartphone"
                size: Theme.fontSize.heading
                color: deviceHero.foreground
            }
        }
    }

    PanelHero {
        id: pairHero
        visible: root._noPhone
        width: parent.width
        title: "No phone paired"
        meta: root._pairing ? "Advertising for pairing" : "Not paired"
        readout: IphoneService.pairingCode
        readoutSize: "displayLarge"

        leading: Component {
            Icon {
                name: "smartphone"
                size: Theme.fontSize.heading
                color: pairHero.foreground
            }
        }
    }

    // Worded as an inference (IphoneService.inFocus header comment): no BLE
    // accessory can read the phone's actual Focus state, only ANCS's
    // `silent` flag on what a Focus intercept held back.
    Item {
        id: focusRow
        visible: root._connected && IphoneService.inFocus
        width: parent.width
        height: Math.max(focusIcon.height, focusText.implicitHeight)

        Icon {
            id: focusIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            name: "moon"
            size: Theme.fontSize.body
            color: Theme.color.mutedForeground
        }

        Text {
            id: focusText
            anchors.left: focusIcon.right
            anchors.leftMargin: Theme.space.iconGap
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Focus likely on, so notifications are held back"
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            wrapMode: Text.WordWrap
        }
    }

    // One notification row: a ghost Cell carrying its own stack (sender
    // line, title, body, an action row), so DESIGN.md §1's ladder rung 4
    // applies and a Separator runs between rows rather than space alone.
    Component {
        id: notifRow

        Cell {
            id: rowCell
            required property var modelData
            width: parent.width
            ghost: true

            readonly property var _entry: rowCell.modelData.entry
            readonly property string _summary: rowCell._entry.title !== "" ? rowCell._entry.title
                : (IphoneModel.categoryLabel(rowCell._entry.category) || rowCell._entry.appName)
            readonly property string _body: rowCell._entry.subtitle !== ""
                ? rowCell._entry.subtitle + "\n" + rowCell._entry.body : rowCell._entry.body
            readonly property string _time: rowCell._entry.ts > 0 ? Model.relTime(root._now, rowCell._entry.ts) : ""

            cursor: root.cursorActive && root.cursorSection === 0 && root._cursorId === rowCell._entry.id

            interactive: true
            onContainsPointerChanged: if (rowCell.containsPointer) {
                root.cursorActive = true;
                root.cursorSection = 0;
                root.cursorIndex = rowCell.modelData.idx;
            }

            Column {
                width: parent.width
                spacing: Theme.space.xxs

                Separator {
                    visible: rowCell.modelData.ruled
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: Math.max(rowIcon.height, closeButton.implicitHeight)

                    Row {
                        anchors.left: parent.left
                        anchors.right: closeButton.left
                        anchors.rightMargin: Theme.space.iconGap
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.iconGap

                        Icon {
                            id: rowIcon
                            anchors.verticalCenter: parent.verticalCenter
                            name: IphoneModel.appIcon(rowCell._entry.bundleId, rowCell._entry.category)
                            size: Theme.fontSize.body
                            color: rowCell.dimForeground
                        }

                        SectionLabel {
                            anchors.verticalCenter: parent.verticalCenter
                            text: rowCell._entry.appName
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: rowCell._time !== ""
                            text: rowCell._time
                            color: Theme.color.mutedForeground
                            font.family: Theme.fontFamilyMono
                            font.pixelSize: Theme.fontSize.caption
                        }
                    }

                    IconButton {
                        id: closeButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        onClicked: IphoneService.dismiss(rowCell._entry.id)
                    }
                }

                Text {
                    width: parent.width
                    text: rowCell._summary
                    color: rowCell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    font.weight: Theme.weight.medium
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }

                Text {
                    visible: rowCell._body.trim().length > 0
                    width: parent.width
                    text: rowCell._body
                    color: rowCell.dimForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.bodySmall
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }

                Item {
                    visible: rowCell._entry.positiveAction !== "" || rowCell._entry.negativeAction !== ""
                    width: parent.width
                    height: actionRow.implicitHeight + Theme.space.rowGap

                    Row {
                        id: actionRow
                        anchors.bottom: parent.bottom
                        spacing: Theme.space.sm

                        Button {
                            visible: rowCell._entry.positiveAction !== ""
                            variant: "outline"
                            text: rowCell._entry.positiveAction
                            onClicked: IphoneService.invoke(rowCell._entry.id, true)
                        }

                        Button {
                            visible: rowCell._entry.negativeAction !== ""
                            variant: "outline"
                            text: rowCell._entry.negativeAction
                            onClicked: IphoneService.invoke(rowCell._entry.id, false)
                        }
                    }
                }
            }
        }
    }

    Column {
        width: parent.width
        visible: root._connected || root._noPhone
        spacing: Theme.space.rowGap

        SectionLabel {
            leftPadding: Theme.space.controlPaddingX
            text: "Recent"
            count: root._entries.length
        }

        SectionLabel {
            visible: root._entries.length === 0
            leftPadding: Theme.space.controlPaddingX
            text: "None"
        }

        Column {
            width: parent.width
            spacing: 0

            Repeater {
                model: root._rowModel
                delegate: notifRow
            }
        }
    }

    // The phone's now-playing (M75 Task 4): title, artist and the three
    // transport buttons AMS always answers to, driven straight off
    // IphoneService rather than through MediaService's active-source pick,
    // so this card controls the phone whatever the media panel currently
    // has selected. The full experience (progress, volume, the source menu
    // picking the phone up as any other row) is MediaPanel's, for free,
    // once `players` carries the `iphone` row.
    Column {
        width: parent.width
        visible: root._connected
        spacing: Theme.space.rowGap

        SectionLabel { leftPadding: Theme.space.controlPaddingX; text: "Now playing" }

        SectionLabel {
            visible: !root._nowPlaying
            leftPadding: Theme.space.controlPaddingX
            text: "Not available yet"
        }

        Column {
            visible: root._nowPlaying
            width: parent.width
            spacing: Theme.space.xxs

            Text {
                width: parent.width
                leftPadding: Theme.space.controlPaddingX
                rightPadding: Theme.space.controlPaddingX
                text: IphoneService.mediaTitle
                color: Theme.color.foreground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: IphoneService.mediaArtist !== ""
                leftPadding: Theme.space.controlPaddingX
                rightPadding: Theme.space.controlPaddingX
                text: IphoneService.mediaArtist
                color: Theme.color.mutedForeground
                font.family: Theme.fontFamilySans
                font.pixelSize: Theme.fontSize.bodySmall
                elide: Text.ElideRight
            }

            ButtonGroup {
                id: nowPlayingGroup
                anchors.left: parent.left
                anchors.leftMargin: Theme.space.controlPaddingX
                height: Theme.space.controlHeight
                exclusive: false
                options: root._nowPlayingOptions
                cursorIndex: root.cursorIndex
                cursor: root.cursorActive && root.cursorSection === root._nowPlayingSection
                onPressed: index => root._pressNowPlaying(index)
                onHovered: (index, isHovered) => { if (isHovered) root._pointAt(root._nowPlayingSection, index); }
            }
        }
    }

    // The footer acts on the panel rather than sitting in the list above it,
    // so the seam runs the full width of the surface.
    Separator {
        visible: root._showFooter
        width: parent.width
    }

    Item {
        width: parent.width
        visible: root._showFooter
        height: pairButton.height

        Button {
            id: pairButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            variant: "outline"
            icon: "smartphone"
            text: root._pairing ? "Pairing" : "Pair"
            enabled: !root._pairing
            cursor: root.cursorActive && root.cursorSection === root._footerSection
            onClicked: IphoneService.pair()
        }
    }
}
