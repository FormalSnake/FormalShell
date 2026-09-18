import QtQuick
import Quickshell
import qs.Core
import "../../Notifications/model.js" as Model
import "../../Notifications/icon.js" as NotificationIcon

// One notification, and since M60 T4 the facade over two shapes rather than
// one of them: a consumer hands in the entry and wires the three signals,
// and which shape it gets is the live theme's `notification` habit and never
// a theme name. `row` (NotificationRow.qml) is the shadcn toast card as
// built, `bubble` (NotificationBubble.qml) is elementary's notification
// bubble. Nothing a consumer touches moved.
//
// What stays here is the contract and the derived data both shapes read: the
// entry's sanitized body, its relative time, the actions worth drawing, the
// picture its icon slot resolves to, and the box role and state urgency and
// `flat` decide between them. A recipe draws those and reaches for nothing
// else, which is what keeps the two from drifting apart over what a
// notification IS.
//
// Purely presentational either way: Toasts.qml and Center.qml own fetching
// the entry from NotificationService and wiring the three signals below to
// its verbs.
Item {
    id: root

    required property var entry
    property double now: Date.now()

    // Both are Center.qml's, both paint nothing in either shape: its rows
    // still spell the pre-shadcn hover inversion and pending marker this
    // way, and M44 Task 2 rewrites them along with the rest of that surface.
    property bool invertOnHover: false
    property bool pending: false

    // Set by the notification centre, never by the toast stack.
    property bool flat: false

    // A corner of the consumer's own choosing, -1 for the table's (Box's own
    // contract): the concentric rule is geometry, so it belongs to whoever
    // knows the padding around this card.
    property int radius: -1

    readonly property bool hovered: recipe.item ? recipe.item.hovered : false

    signal dismiss
    signal bodyClicked
    signal actionInvoked(string key)

    readonly property bool critical: root.entry.urgency === 2

    // The `notification` box rather than a panel's `card`: a toast has
    // nothing blurred behind it, so its fill is opaque. A flat card paints
    // neither fill nor border, except the one urgency asked for (Cell.qml's
    // ghost state, same rule): critical is a `destructive` border and icon,
    // so the border has to survive the flattening.
    //
    // Read by the recipes and by Toasts.qml's peek shell, which paints the
    // same box at a narrower width with nothing in it.
    readonly property string role: "notification"
    readonly property string state: root.flat
        ? (root.critical ? "flatCritical" : "flat")
        : (root.critical ? "critical" : "rest")

    readonly property var buttonActions: Model.buttonActions(root.entry)

    // sanitizeBody/styledBody live once in model.js and are applied here at
    // the shared-component boundary, so both Toasts.qml's popups and
    // Center.qml's rows get the Chromium URL-prefix strip and the newline ->
    // <br/> conversion for free (M15 origin: "GH notifs are ugly").
    readonly property string styledBody: Model.styledBody(root.entry.body, root.entry.appName, root.entry.appIcon)
    readonly property string relTime: Model.relTime(root.now, root.entry.arrivedAt)

    // `count` only exists on a row that came through Model.groupEntries; both
    // surfaces render every row that way, but an entry handed in directly
    // carries no such key and `undefined > 1` is false, so no default is
    // needed.
    readonly property string meta: root.entry.count > 1
        ? root.relTime + "  x" + root.entry.count
        : root.relTime

    // The image, the app icon, the sender's desktop entry, then nothing
    // (M48 D4). The order and the path/url/themed-name branching live in
    // icon.js; this is only the wiring of the two lookups it needs. Both are
    // check-resolved, so a name no icon theme carries answers "" and each
    // shape's bell takes over, rather than the icon provider's own
    // missing-texture pixmap rendering as a healthy Image.
    readonly property string iconSource: NotificationIcon.resolve(root.entry, {
        themed: function (name) { return Quickshell.iconPath(name, true); },
        entry: function (desktopId, appName) {
            return (desktopId.length > 0 ? DesktopEntries.byId(desktopId) : null)
                ?? (appName.length > 0 ? DesktopEntries.heuristicLookup(appName) : null);
        }
    })

    readonly property bool _bubble: Theme.habit.notification === "bubble"

    implicitWidth: recipe.implicitWidth
    implicitHeight: recipe.implicitHeight

    Component {
        id: rowRecipe

        NotificationRow {
            owner: root
            radius: root.radius
            onDismiss: root.dismiss()
            onBodyClicked: root.bodyClicked()
            onActionInvoked: key => root.actionInvoked(key)
        }
    }

    Component {
        id: bubbleRecipe

        NotificationBubble {
            owner: root
            radius: root.radius
            onDismiss: root.dismiss()
            onBodyClicked: root.bodyClicked()
            onActionInvoked: key => root.actionInvoked(key)
        }
    }

    Loader {
        id: recipe
        anchors.fill: parent
        sourceComponent: root._bubble ? bubbleRecipe : rowRecipe
    }
}
