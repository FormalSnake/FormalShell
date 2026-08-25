import QtQuick
import qs.Core
import qs.Components
import "../../Menu/icons.js" as MenuIcons

// One row of the command palette (M43 D2): a borderless, square-cornered
// item carrying a named `Icon` (or an app's own themed image), the label in
// sans, a muted detail, and a trailing indicator. The cursor row and a
// hovered row both paint `accent` with `accentForeground` ink; the list has
// no rules between rows and no ring, since the cursor is the only focus a
// modal surface has.
//
// Not a `Cell`: every Cell draws a 1px border, and the launcher's list is
// the one place in the shell that has none.
//
// Menu.qml owns cursor/condition state; this row only paints it and reports
// intent back via signals.
Item {
    id: root

    required property var modelData
    required property int index
    readonly property var node: modelData

    property bool current: false
    property bool checkedState: false
    property bool confirming: false

    signal activate
    // Carries the raw pointer sample rather than "the pointer is here now":
    // whether it counts as a real move is PointerMoveGate's call, and only
    // Menu.qml holds the gate (one gate for the whole list, not one per row).
    signal hoverMoved(var source, real x, real y)

    readonly property bool isBranch: node.kind === "submenu" || node.kind === "link" || node.kind === "provider"

    // Clipboard image entries (M14 Task 6) ride a taller row: the thumbnail
    // is twice the height a plain text row's content would be.
    readonly property bool _isImage: (root.node.thumbSource || "") !== ""
    readonly property real _bodyHeight: label.implicitHeight
    readonly property real _thumbHeight: root._bodyHeight * 2

    // The route's Lucide name, or "" for a row whose icon is its own data
    // (a user menu.jsonc route, an emoji, a provider row with a bare glyph).
    readonly property string _iconName: MenuIcons.iconFor(root.node)
    readonly property real _iconSize: Theme.fontSize.body

    readonly property bool _hovered: pointer.containsMouse
    readonly property bool _filled: root.current || root._hovered
    readonly property bool _hasTrailIcon: !root.confirming && (root.checkedState || root.isBranch)

    // A confirm-gated row states itself in `destructive` ink rather than a
    // full-bleed fill (DESIGN.md §5).
    readonly property color foreground: root.confirming
        ? Theme.color.destructive
        : (root._filled ? Theme.color.accentForeground : Theme.color.foreground)
    readonly property color dimForeground: root._filled
        ? Theme.color.accentForeground
        : Theme.color.mutedForeground

    // Label width cap (M30): the split-pane clipboard route's rowsView is
    // roughly half the plain menu's width, narrow enough that a 60-char
    // preview label (providers.js's previewLabel truncation) can run past
    // the trailing indicator's reserved gutter. Every route gets the cap,
    // since a row this narrow is possible anywhere the tree gets deep
    // enough to rank a long label. `_leadWidth` sums whichever leading
    // slots are actually showing; `_trailReserve` mirrors whichever
    // trailing element (the meta value or the check/chevron, the two never
    // show together) reserves its own room.
    //
    // The label (band 1) has priority over the dim desc (band 2): desc is
    // provider-supplied context, not the row's own identity, and unlike
    // the label it has no universal length cap upstream (keybind rows'
    // `describeAction` joins action+argv uncapped). So `_labelMaxWidth`
    // reserves only lead/trail, never desc. Desc gets whatever room the
    // label's actual rendered width leaves behind.
    readonly property real _leadWidth: (root._isImage ? root._thumbHeight * 3 + Theme.space.iconGap : 0)
        + ((root.node.iconSource || "") !== "" ? root._bodyHeight + Theme.space.iconGap : 0)
        + (root._iconName !== ""
            ? root._iconSize + Theme.space.iconGap
            : (root.node.icon !== "" ? dataGlyph.implicitWidth + Theme.space.iconGap : 0))
    readonly property real _trailReserve: (root.node.meta || "") !== ""
        ? Theme.space.controlPaddingX + metaValue.implicitWidth
        : (root._hasTrailIcon ? Theme.space.controlPaddingX + root._iconSize : 0)
    readonly property real _labelMaxWidth: Math.max(0, root.width - Theme.space.controlPaddingX * 2
        - root._leadWidth - root._trailReserve)
    readonly property real _descMaxWidth: (root.node.desc || "") !== ""
        ? Math.max(0, root._labelMaxWidth - label.width - Theme.space.iconGap)
        : 0

    width: ListView.view ? ListView.view.width : implicitWidth
    height: root._isImage
        ? root._thumbHeight + Theme.space.controlPaddingY * 2
        : Theme.space.controlHeight

    // The cursor snaps (DESIGN.md §1 "List cursors jump"); only the hover
    // fill below fades.
    Rectangle {
        anchors.fill: parent
        visible: root.current
        color: Theme.color.accent
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.accent
        opacity: (root._hovered && !root.current) ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.fast; easing.type: Theme.motion.easing }
        }
    }

    // Declared ahead of the content so the text draws over it. Qt
    // re-delivers a hover move to whichever row slid under a parked
    // pointer, so `onPositionChanged` fires on every filter keystroke and
    // every scroll with the pointer untouched, hence the gate on the other
    // end.
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
        onPositionChanged: event => root.hoverMoved(root, event.x, event.y)
    }

    Row {
        id: contentRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.iconGap

        // Row has no per-item vertical-alignment property (verified against
        // the pinned Qt qtdeclarative plugins.qmltypes: QQuickRow exposes
        // only layoutDirection), so every child centers itself against the
        // row's own auto-computed height (the tallest child, the thumbnail
        // when one's present) via an explicit `y`.

        // Clipboard image thumbnail (M14 Task 6): a plain file:// Image at
        // twice the body row height, width capped so a wide capture doesn't
        // stretch the row, PreserveAspectFit letterboxes rather than
        // cropping.
        Image {
            y: (contentRow.height - height) / 2
            visible: root._isImage
            source: root._isImage ? "file://" + root.node.thumbSource : ""
            height: root._thumbHeight
            width: root._thumbHeight * 3
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            // Decode capped at the rendered thumb size (M16 Task 12): a
            // multi-MB screenshot capture otherwise decodes at full
            // resolution for a row-height slot.
            sourceSize.width: root._thumbHeight * 3
            sourceSize.height: root._thumbHeight
        }

        // Image variant of the icon slot (app rows): a themed desktop icon
        // at the glyph cell's size, the spec's one sanctioned image-icon
        // exception. `iconSource` is already check-resolved by the provider,
        // so a failed lookup is "" and the slot simply doesn't render (never
        // a missing-texture box).
        Image {
            y: (contentRow.height - height) / 2
            visible: (root.node.iconSource || "") !== ""
            source: root.node.iconSource || ""
            width: root._bodyHeight
            height: root._bodyHeight
            sourceSize.width: root._bodyHeight
            sourceSize.height: root._bodyHeight
            fillMode: Image.PreserveAspectFit
        }

        Icon {
            y: (contentRow.height - height) / 2
            visible: root._iconName !== ""
            name: root._iconName !== "" ? root._iconName : "circle-help"
            size: root._iconSize
            color: root.foreground
        }

        // The fallback for a row whose icon is its own data: the glyph
        // itself, in the mono font that carries it.
        Text {
            id: dataGlyph
            y: (contentRow.height - height) / 2
            visible: root._iconName === "" && root.node.icon !== ""
            text: root.node.icon
            color: root.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: root._iconSize
        }

        Text {
            id: label
            y: (contentRow.height - height) / 2
            // Capped to whatever room this row actually has
            // (`_labelMaxWidth` above) and elided rather than left to
            // overflow past the trailing indicator or get an ungraceful
            // mid-character cut from the list's own clip. A no-op everywhere
            // the label already fits, since `Math.min` only ever narrows it.
            width: Math.min(label.implicitWidth, root._labelMaxWidth)
            elide: Text.ElideRight
            text: root.confirming ? ("Confirm " + root.node.label + "?") : root.node.label
            // `dim: true` marks a non-activatable honest-empty row (the nix
            // provider's NO NIX): it reads muted at rest and promotes to the
            // cursor row's own ink on a filled row, where a bare
            // `mutedForeground` would sit unreadably.
            color: root.node.dim === true ? root.dimForeground : root.foreground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.body
            font.weight: Theme.weight.medium
        }

        // Dimmed trailing description (nix search rows, clipboard image
        // captured-at, keybind chords). Most providers pre-truncate, but
        // `describeAction`'s joined action+argv carries no such cap, so
        // this band gets the same width-cap-and-elide treatment as the
        // label rather than trusting every producer to bound it upstream.
        Text {
            id: descText
            y: (contentRow.height - height) / 2
            visible: (root.node.desc || "") !== ""
            width: Math.min(descText.implicitWidth, root._descMaxWidth)
            elide: Text.ElideRight
            text: root.node.desc || ""
            color: root.dimForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        visible: root._hasTrailIcon
        name: root.checkedState ? "check" : "chevron-right"
        size: root._iconSize
        color: root.checkedState ? root.foreground : root.dimForeground
    }

    // The row's own value (the CALC result). A value, so mono.
    Text {
        id: metaValue
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        visible: (root.node.meta || "") !== ""
        text: root.node.meta || ""
        color: root.foreground
        font.family: Theme.fontFamilyMono
        font.pixelSize: Theme.fontSize.body
    }
}
