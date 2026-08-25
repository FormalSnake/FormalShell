import QtQuick
import qs.Core
import qs.Components

// One row of the unified menu — a Cell carrying an optional icon glyph, the
// label (or a "CONFIRM <label>?" swap while a confirm-gated action awaits its
// second Enter), and a trailing indicator: "▸" for anything that descends
// (submenu/link/provider), "✓" when the node's `checked` condition resolved
// true (either a shell command's exit code or a live "@state:" read;
// Menu.qml decides which), or a full-bleed accent tag when the node
// carries `meta` (the CALC
// result row). Menu.qml owns cursor/condition state; this row only paints it
// and reports intent back via signals.
Cell {
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

    selected: root.current
    accent: root.confirming

    // Clipboard image entries (M14 Task 6) ride a taller row: the thumbnail
    // is twice the height a plain text row's content would be.
    readonly property bool _isImage: (root.node.thumbSource || "") !== ""
    readonly property real _bodyHeight: label.implicitHeight
    readonly property real _thumbHeight: root._bodyHeight * 2

    // Label width cap (M30): the split-pane clipboard route's rowsView is
    // roughly half the plain menu's width, narrow enough that a 60-char
    // preview label (providers.js's previewLabel truncation) can run past
    // the trailing indicator's reserved gutter — every route gets the cap,
    // since a row this narrow is possible anywhere the tree gets deep
    // enough to rank a long label. `_leadWidth` sums whichever leading
    // slots are actually showing; `_trailReserve` mirrors whichever
    // trailing element (the meta tag or the ▸/✓ indicator, the two never
    // show together) reserves its own room past `content`'s padding.
    //
    // The label (band 1) has priority over the dim desc (band 2): desc is
    // provider-supplied context, not the row's own identity, and unlike
    // the label it has no universal length cap upstream (keybind rows'
    // `describeAction` joins action+argv uncapped). So `_labelMaxWidth`
    // reserves only lead/trail, never desc. Desc gets whatever room the
    // label's actual rendered width leaves behind, computed below as
    // `_descMaxWidth` off `label.width` once the label itself has settled.
    readonly property real _leadWidth: (root._isImage ? root._thumbHeight * 3 + Theme.space.labelGap : 0)
        + ((root.node.iconSource || "") !== "" ? label.implicitHeight + Theme.space.labelGap : 0)
        + (root.node.icon !== "" ? iconGlyph.implicitWidth + Theme.space.labelGap : 0)
    readonly property real _trailReserve: (root.node.meta || "") !== ""
        ? Theme.space.controlPaddingX + Theme.borderWidth + metaTagBg.width
        : ((!root.confirming && (root.checkedState || root.isBranch))
            ? Theme.space.controlPaddingX + Theme.borderWidth + trailingIndicator.implicitWidth
            : 0)
    readonly property real _labelMaxWidth: Math.max(0, root.width - Theme.space.controlPaddingX * 2 - Theme.borderWidth
        - root._leadWidth - root._trailReserve)
    readonly property real _descMaxWidth: (root.node.desc || "") !== ""
        ? Math.max(0, root._labelMaxWidth - label.width - Theme.space.labelGap)
        : 0

    width: ListView.view ? ListView.view.width : implicitWidth
    height: (root._isImage ? root._thumbHeight : root._bodyHeight) + Theme.space.controlPaddingY * 2 + Theme.borderWidth

    Row {
        id: contentRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.labelGap

        // Row has no per-item vertical-alignment property (verified against
        // the pinned Qt qtdeclarative plugins.qmltypes: QQuickRow exposes
        // only layoutDirection) — every child centers itself against the
        // row's own auto-computed height (the tallest child, the thumbnail
        // when one's present) via an explicit `y`, rather than the default
        // top alignment.

        // Clipboard image thumbnail (M14 Task 6): a plain file:// Image at
        // twice the body row height, width capped so a wide capture doesn't
        // stretch the row, PreserveAspectFit letterboxes rather than
        // cropping, radius 0, no border — shares the ledger rule contract
        // like every other row, it's just taller.
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
        // at the glyph cell's size, radius 0, no border — DESIGN.md's one
        // sanctioned image-icon exception. `iconSource` is already
        // check-resolved by the provider, so a failed lookup is "" and the
        // slot simply doesn't render (never a missing-texture box).
        Image {
            y: (contentRow.height - height) / 2
            visible: (root.node.iconSource || "") !== ""
            source: root.node.iconSource || ""
            width: label.implicitHeight
            height: label.implicitHeight
            sourceSize.width: label.implicitHeight
            sourceSize.height: label.implicitHeight
            fillMode: Image.PreserveAspectFit
        }

        Text {
            id: iconGlyph
            y: (contentRow.height - height) / 2
            visible: root.node.icon !== ""
            text: root.node.icon
            color: root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        Text {
            id: label
            y: (contentRow.height - height) / 2
            // Capped to whatever room this row actually has (`_labelMaxWidth`
            // above) and elided rather than left to overflow past the
            // trailing indicator or get an ungraceful mid-character cut from
            // the list's own clip — a no-op everywhere the label already
            // fits, since `Math.min` only ever narrows it.
            width: Math.min(label.implicitWidth, root._labelMaxWidth)
            elide: Text.ElideRight
            text: root.confirming ? ("CONFIRM " + root.node.label + "?") : root.node.label
            // `dim: true` marks a non-activatable honest-empty row (the nix
            // provider's NO NIX): `dimForeground` reads as `mutedForeground`
            // at rest but promotes to the cursor row's own primaryForeground
            // ink when this row is current (Cell.qml's inversion default is
            // primary since M18 Task 2, so a bare `mutedForeground` here
            // would sit unreadably on the primary fill).
            color: root.node.dim === true ? root.dimForeground : root.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }

        // Dimmed trailing description (nix search rows, clipboard image
        // captured-at, keybind chords). Most providers pre-truncate, but
        // `describeAction`'s joined action+argv carries no such cap, so
        // this band gets the same width-cap-and-elide treatment as the
        // label rather than trusting every producer to bound it upstream.
        // `dimForeground` over a bare `mutedForeground` for the same reason
        // as the label above: this text sits on the cursor row's primary
        // fill too.
        Text {
            id: descText
            y: (contentRow.height - height) / 2
            visible: (root.node.desc || "") !== ""
            width: Math.min(descText.implicitWidth, root._descMaxWidth)
            elide: Text.ElideRight
            text: root.node.desc || ""
            color: root.dimForeground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }
    }

    Text {
        id: trailingIndicator
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.controlPaddingX + Theme.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.confirming && (root.checkedState || root.isBranch)
        text: root.checkedState ? "✓" : "▸"
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize.body
    }

    // DESIGN.md §2.4: primary reads as a full-bleed fill with
    // primaryForeground text, never a tinted label, independent of the
    // row's own cursor inversion.
    Rectangle {
        id: metaTagBg
        visible: (root.node.meta || "") !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.controlPaddingX + Theme.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        width: metaTag.implicitWidth + Theme.space.sm * 2
        height: metaTag.implicitHeight + Theme.space.xxs * 2
        color: Theme.color.primary

        MetaLabel {
            id: metaTag
            anchors.centerIn: parent
            text: root.node.meta || ""
            color: Theme.color.primaryForeground
        }
    }

    interactive: true
    // Qt re-delivers a hover move to whichever row slid under a parked
    // pointer, so this fires on every filter keystroke and every scroll
    // with the pointer untouched — hence the gate on the other end.
    onPointerMoved: (x, y) => root.hoverMoved(root, x, y)
    onClicked: root.activate()
}
