import QtQuick
import qs.Core
import qs.Components
import qs.Services
import "../../Menu/icons.js" as MenuIcons
import "../../Theme/icons/distro.js" as Distro
import "../../Menu/hints.js" as MenuHints

// One launcher row (M72 T4), Raycast's: an icon, the title, a muted
// subtitle after it, and a right-aligned muted accessory naming what the
// row is or carrying its value (Menu/hints.js's accessoryFor). Drawn on a
// ghost `Cell`, so what a row looks like at rest, under the pointer, as the
// cursor and armed for a confirm is the `cell` role's answer in every
// theme's table: `ghost` at rest, `selected` for the cursor, `destructive`
// for a confirm waiting on its second Enter. The cursor's fill itself is the
// view's, one of it travelling under every row (the view carries
// `ownsSelectionFill`), and the row keeps the selected ink.
//
// A row that opens a group carries that group's heading (`section`) above
// itself: a `SectionLabel` and space, never a rule. The heading rides the
// row rather than living in the list because the keyed row model carries
// ids alone, and because a heading that is part of its first row can never
// be scrolled apart from it.
//
// Menu.qml owns cursor/condition/section state; this row only paints it and
// reports intent back via signals.
Item {
    id: root

    required property var modelData
    required property int index
    readonly property var node: modelData

    property bool current: false
    // Whether the pointer's hover counts right now (PointerMoveGate's
    // `live`): Qt reports a row sliding under a parked pointer as hovered,
    // and that row must not light up.
    property bool hoverLive: true
    property bool checkedState: false
    property bool confirming: false

    // The heading this row opens, "" for a row that continues the group
    // above it. `sectionFirst` drops the gap above the list's first heading,
    // which the view's own top inset already holds.
    property string section: ""
    property bool sectionFirst: false

    signal activate
    // Carries the raw pointer sample rather than "the pointer is here now":
    // whether it counts as a real move is PointerMoveGate's call, and only
    // Menu.qml holds the gate (one gate for the whole list, not one per row).
    signal hoverMoved(var source, real x, real y)

    // Clipboard image entries (M14 Task 6) ride a taller row: the thumbnail
    // is twice the height a plain text row's content would be.
    readonly property bool _isImage: (root.node.thumbSource || "") !== ""
    readonly property real _bodyHeight: label.implicitHeight
    readonly property real _thumbHeight: root._bodyHeight * 2
    // A capture that is only emoji (providers.js) is a picture, drawn at the
    // emoji grid's floor. At the body size a colour emoji fills about the
    // body font's cap height, smaller than the words on the rows around it.
    readonly property bool _isEmoji: root.node.emojiOnly === true

    // The route's named icon, else the logo a distro route draws from the
    // font that carries it, else the named fallback for what the row is
    // (Menu/icons.js). A row with no icon of any kind (a clipboard entry, a
    // keybind, a select option) keeps no icon slot at all.
    readonly property string _iconName: MenuIcons.iconFor(root.node)
    readonly property string _logoGlyph: {
        const key = MenuIcons.logoFor(root.node);
        return key !== "" ? (Distro.LOGOS[key] || "") : "";
    }
    readonly property bool _hasPicture: (root.node.iconSource || "") !== ""
    readonly property string _drawnIcon: root._iconName !== ""
        ? root._iconName
        : (root._logoGlyph === "" && !root._hasPicture && (root.node.icon || "") !== ""
            ? MenuIcons.fallbackFor(root.node)
            : "")
    readonly property real _iconSize: Theme.fontSize.body

    readonly property string _accessory: MenuHints.accessoryFor(root.node)
    readonly property var _chordKeys: MenuHints.chordKeysFor(root.node)
    // A kind name is a word and takes the sans face; a value, a chord, a
    // prefix or a count takes the mono one (spec "Type").
    readonly property bool _accessoryWord: (root.node.meta || "") === ""
        && (root.node.kind === "app" || root.node.kind === "action")

    readonly property real _rowHeight: root._isImage
        ? root._thumbHeight + Theme.space.controlPaddingY * 2
        : (root._isEmoji ? root._bodyHeight + Theme.space.controlPaddingY * 2 : Theme.space.controlHeight)
    readonly property real _headerBand: root.section === ""
        ? 0
        : (root.sectionFirst ? 0 : Theme.space.sectionGap) + sectionHeading.implicitHeight + Theme.space.rowGap

    width: ListView.view ? ListView.view.width : implicitWidth
    height: root._headerBand + root._rowHeight

    SectionLabel {
        id: sectionHeading
        anchors.bottom: cell.top
        anchors.bottomMargin: Theme.space.rowGap
        anchors.left: parent.left
        leftPadding: Theme.space.controlPaddingX
        visible: root.section !== ""
        text: root.section
    }

    Cell {
        id: cell
        y: root._headerBand
        width: root.width
        height: root._rowHeight
        ghost: true
        selected: root.current
        destructive: root.confirming
        hovered: cell.containsPointer && root.hoverLive
        interactive: true
        onClicked: root.activate()
        onPointerMoved: (x, y) => root.hoverMoved(cell, x, y)

        // Sized off the row rather than the cell's own implicit size, which
        // is what this measures into.
        Item {
            id: content
            width: root.width - Theme.space.controlPaddingX * 2
            height: root._isImage ? root._thumbHeight : root._bodyHeight

            Row {
                id: lead
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.iconGap

                // Clipboard image thumbnail (M14 Task 6), `fit` from
                // ThumbnailService's cache when there is one: the slot is
                // 3:1 and letterboxes, and a centre crop of a screenshot
                // throws away the part that says which screenshot it is.
                // True colour under `theme.dither` (M49 D3), since this row
                // exists to pick one capture out of the ledger.
                Image {
                    id: rowThumb
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._isImage
                    readonly property string cachedUrl: root._isImage
                        ? ThumbnailService.urlFor(root.node.thumbSource, "fit")
                        : ""
                    source: rowThumb.cachedUrl !== ""
                        ? rowThumb.cachedUrl
                        : (root._isImage ? "file://" + root.node.thumbSource : "")
                    height: root._thumbHeight
                    width: root._thumbHeight * 3
                    fillMode: Image.PreserveAspectFit
                    // Themed icons stay on the main thread, see Picture.qml.
                    asynchronous: String(source).indexOf("image://icon/") !== 0
                    cache: false
                    sourceSize.width: root._thumbHeight * 3
                    sourceSize.height: root._thumbHeight
                }

                // An app's own themed icon, already check-resolved by the
                // provider, so a failed lookup is "" and draws nothing.
                Picture {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._hasPicture
                    source: root.node.iconSource || ""
                    width: root._bodyHeight
                    height: root._bodyHeight
                    sourceSize.width: root._bodyHeight
                    sourceSize.height: root._bodyHeight
                    fillMode: Image.PreserveAspectFit
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._drawnIcon !== ""
                    name: root._drawnIcon !== "" ? root._drawnIcon : "circle-help"
                    size: root._iconSize
                    color: cell.foreground
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._logoGlyph !== ""
                    width: root._iconSize
                    horizontalAlignment: Text.AlignHCenter
                    text: root._logoGlyph
                    color: cell.foreground
                    font.family: Distro.FAMILY
                    font.pixelSize: root._iconSize
                }

                Text {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(label.implicitWidth, root._labelMaxWidth)
                    elide: Text.ElideRight
                    text: root.confirming ? ("Confirm " + root.node.label + "?") : root.node.label
                    // Row labels carry provider data verbatim, and a
                    // clipboard capture of copied markup trips AutoText's
                    // rich-text heuristic: the tags would be parsed away and
                    // the document's own font would resize the row.
                    textFormat: Text.PlainText
                    color: root.node.dim === true ? cell.dimForeground : cell.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: root._isEmoji ? Theme.fontSize.display : Theme.fontSize.body
                    font.weight: Theme.weight.medium
                }

                // The subtitle (nix descriptions, a capture's time, a
                // keybind's action). `describeAction` joins action and argv
                // uncapped, so this is capped to what the title leaves.
                Text {
                    id: subtitle
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.node.desc || "") !== ""
                    width: Math.min(subtitle.implicitWidth, root._subtitleMaxWidth)
                    elide: Text.ElideRight
                    text: root.node.desc || ""
                    textFormat: Text.PlainText
                    color: cell.dimForeground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.bodySmall
                }
            }

            Row {
                id: trail
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space.iconGap

                Chord {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._chordKeys.length > 0
                    keys: root._chordKeys
                }

                Text {
                    id: accessory
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root._accessory !== "" && root._chordKeys.length === 0
                    text: root._accessory
                    color: cell.dimForeground
                    font.family: root._accessoryWord ? Theme.fontFamilySans : Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSize.caption
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.checkedState && !root.confirming
                    name: "check"
                    size: root._iconSize
                    color: cell.foreground
                }
            }
        }
    }

    // The title outranks the subtitle: the subtitle is context a provider
    // hands over, the title is the row. So the title's cap reserves the
    // leading slot and the trailing one and nothing else, and the subtitle
    // takes whatever the title's drawn width leaves.
    readonly property real _leadWidth: (root._isImage ? rowThumb.width + Theme.space.iconGap : 0)
        + (root._hasPicture ? root._bodyHeight + Theme.space.iconGap : 0)
        + (root._drawnIcon !== "" || root._logoGlyph !== "" ? root._iconSize + Theme.space.iconGap : 0)
    readonly property real _trailWidth: trail.width > 0 ? trail.width + Theme.space.controlPaddingX : 0
    readonly property real _labelMaxWidth: Math.max(0, content.width - root._leadWidth - root._trailWidth)
    readonly property real _subtitleMaxWidth: Math.max(0, root._labelMaxWidth - label.width - Theme.space.iconGap)
}
