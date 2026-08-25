import QtQuick
import qs.Core

// The lock screen's and the greeter's shared centre block (DESIGN.md §3
// "Lock, greeter", spec "Lock and greeter", M45 D2): a centred column, no
// plate. The clock at `displayLarge` x3 in mono semibold, the date as a
// SectionLabel, and one `Input` a `popupWidthNarrow` wide carrying the ring
// while focused and the destructive border plus its caption while `errorText`
// is set.
//
// The backdrop is each caller's own concern: LockSurface draws the wallpaper
// under a scrim, greeter.qml a flat background. This component only ever
// draws the column.
Item {
    id: root

    property date now: new Date()
    // The section label above the field: the greeter's live greetd prompt
    // message. The lock screen leaves it empty and relies on the
    // placeholder, which says the same thing once.
    property string label: ""
    property bool showLabel: root.label !== ""
    // Non-empty puts the field in its error state: destructive border plus
    // this text as the caption under it.
    property string errorText: ""
    readonly property bool errorState: root.errorText !== ""
    property bool checking: false
    // false = plain visible text (the greeter's username step); true = the
    // password masking every password entry takes.
    property bool masked: true
    property bool fingerprintEnrolled: false
    property bool inputEnabled: true
    // Non-empty replaces the field with this message (the greeter's "no
    // greetd socket" honest-unavailable state) instead of a dead input.
    property string unavailableText: ""

    property alias text: input.text

    signal accepted(string value)
    // Fired on every key reaching the field, alongside (never instead of)
    // the field's own handling. The lock screen's idle-wake rides on this;
    // the greeter has nothing listening.
    signal activity()

    function forceInputFocus() {
        input.forceFocus();
    }

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // Escape and Ctrl+U clear the field. Handled here rather than inside
    // `Input`, whose other callers sit in panels where Escape is the
    // KeyCatcher's close key; neither is consumed by the field itself, so
    // both reach this ancestor.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) {
            input.text = "";
            event.accepted = true;
        }
    }

    // Focus comes back the moment a conversation ends: the field is disabled
    // while one is in flight, and a disabled item drops active focus.
    onCheckingChanged: {
        if (!root.checking)
            Qt.callLater(function () { input.forceFocus(); });
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: Theme.space.lg

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "hh:mm")
            color: Theme.color.foreground
            font.family: Theme.fontFamilyMono
            font.pixelSize: Math.round(Theme.fontSize.displayLarge * 3)
            font.weight: Theme.weight.semibold
        }

        SectionLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
        }

        SectionLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showLabel && root.unavailableText === ""
            text: root.label
        }

        Input {
            id: input
            width: Theme.space.popupWidthNarrow
            visible: root.unavailableText === ""
            enabled: root.inputEnabled && !root.checking
            placeholder: root.masked ? "Password" : "Username"
            echoMode: root.masked ? TextInput.Password : TextInput.Normal
            error: root.errorState
            errorText: root.errorText
            onAccepted: {
                const value = input.text;
                input.text = "";
                root.accepted(value);
            }
            onActivity: root.activity()
        }

        // The reader is a parallel PAM flow with no field of its own, so the
        // hint is the icon alone: present only once `lock.fingerprintPamService`
        // names a service, absent entirely otherwise.
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.fingerprintEnrolled && root.unavailableText === ""
            name: "fingerprint"
            size: Theme.fontSize.title
            color: Theme.color.mutedForeground
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.space.popupWidthNarrow
            visible: root.unavailableText !== ""
            text: root.unavailableText
            color: Theme.color.mutedForeground
            font.family: Theme.fontFamilySans
            font.pixelSize: Theme.fontSize.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
