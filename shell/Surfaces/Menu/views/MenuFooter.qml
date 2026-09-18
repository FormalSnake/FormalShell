import QtQuick
import qs.Core as Core
import ".." as MenuParts

// The footer band (spec "Launcher"): the action bar's hint line (what
// Enter does to the row under the cursor, plus the keys that always apply,
// Menu/actions.js owns the wording) plus the app view's own overflow hint
// at its right end, where the hint line cannot reach it. In the footer
// rather than over the view because a hint sitting on the content it
// announces hides the rows the reader is reaching for.
Item {
    id: root

    property var primary: null
    property var hints: []
    property string scrollHint: ""

    signal primaryActivated

    height: actionBar.height

    // Clicking the primary verb is the pointer acting, exactly like
    // clicking the row itself: same path, same gate re-arm. Menu.qml
    // decides what that click does (an app view's own primary, or the row
    // list's cursor row), this just relays the click.
    MenuParts.MenuActionBar {
        id: actionBar
        anchors.left: parent.left
        anchors.right: parent.right
        primary: root.primary
        hints: root.hints
        onPrimaryActivated: root.primaryActivated()
    }

    Text {
        anchors.right: actionBar.right
        anchors.verticalCenter: actionBar.verticalCenter
        visible: root.scrollHint !== ""
        text: root.scrollHint
        color: Core.Theme.color.mutedForeground
        font.family: Core.Theme.fontFamilySans
        font.pixelSize: Core.Theme.fontSize.caption
        font.capitalization: Font.AllLowercase
    }
}
