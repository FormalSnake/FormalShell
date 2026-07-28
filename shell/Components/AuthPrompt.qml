import QtQuick
import qs.Core

// The lock screen's and greeter's shared centre block (DESIGN.md §Lock/
// greeter, M8b Task 6). The owner's complaint about the old surface was
// literal: "an oversized mono clock, a thin-underlined input, three loose
// stacked items" floating independently on the backdrop. The fix here is
// not a restyle of those three items in place — it's ONE alignment spine:
// a single bordered plate (the same omarchy-card idiom Panel.qml/Menu.qml
// already use for every other floating surface) holding the clock, the
// date, a dividing rule, and the password/username field, all centred on
// the plate's own width rather than coincidentally centred on the screen.
// The clock and the field converge on nearly the same rendered width (see
// `_fieldWidth` vs the clock's own `implicitWidth` below) so the plate's
// outer edge reads as one designed column, not an arbitrary wide box
// around whichever line happens to be longest.
//
// Both LockSurface.qml (blurred wallpaper backdrop) and greeter.qml (flat
// background, no wallpaper) instantiate this unchanged — the backdrop is
// each caller's own concern, this component only ever draws the plate and
// everything inside it.
Item {
    id: root

    property date now: new Date()
    // Meta label shown above the field: the caller's own idle-state text
    // ("PASSWORD", "USER", a greetd prompt message). Overridden below by
    // `errorState`/`checking` so both callers get identical CHECKING…/error
    // presentation without duplicating that logic on each side.
    property string label: "PASSWORD"
    property bool errorState: false
    property bool checking: false
    // false = plain visible text (greeter's username step); true = `●`
    // masking with shrink-to-fit letter-spacing (every password entry).
    property bool masked: true
    property bool fingerprintEnrolled: false
    property bool inputEnabled: true
    // Non-empty replaces the whole field body with this message (greeter's
    // "no greetd socket" honest-unavailable state) instead of a dead input.
    property string unavailableText: ""

    property alias text: input.text

    signal accepted(string value)
    // Fired on every key reaching the field, alongside (never instead of)
    // TextInput's own normal handling — the lock screen's idle-wake signal
    // rides on this; the greeter simply has nothing listening.
    signal activity()

    function forceInputFocus() {
        input.forceActiveFocus();
    }

    // Omarchy reference: a single 381x67 field with a 3px outline, scaled
    // proportionally off the same fontBaseSize/fontScale root as every
    // other token (DESIGN.md §1.3) rather than frozen as a literal.
    readonly property real _fieldWidth: Math.round(381 * Theme.fontScale)
    readonly property real _fieldHeight: Math.round(67 * Theme.fontScale)
    readonly property real _glyphReserve: root.fingerprintEnrolled
        ? Math.round(Theme.fontSize.title + Theme.space.md)
        : 0

    // DESIGN.md §1.2: a border is a spec (color + widths), not a bare
    // scalar — this is that vocabulary's first real consumer. The field's
    // outline is deliberately its own uniform 3px spec (not `Theme.borderWidth`,
    // which stays the plate's own 2px framing below), the "field gains real
    // mass" bullet made literal: it reads as thicker, more load-bearing than
    // the frame around it.
    readonly property var _fieldBorder: Theme.uniformBorderSpec(
        root.errorState ? "urgent" : "foreground",
        Math.round(3 * Theme.fontScale))

    readonly property string _displayLabel: root.checking ? "CHECKING…" : root.label

    implicitWidth: Math.max(_fieldWidth, clockText.implicitWidth, dateLabel.implicitWidth) + Theme.space.huge * 2
    implicitHeight: plateColumn.implicitHeight + Theme.space.huge * 2
    width: implicitWidth
    height: implicitHeight

    // The plate: one bordered rectangle, radius 0, opaque fill — reads as a
    // designed panel against the blurred wallpaper (or the greeter's flat
    // background) instead of bare text floating on it.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.color.background
        border.width: Theme.borderWidth
        border.color: Theme.color.rule
    }

    Column {
        id: plateColumn
        anchors.centerIn: parent
        width: root.width - Theme.space.huge * 2
        spacing: Theme.space.lg

        Text {
            id: clockText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "hh:mm")
            color: Theme.color.foreground
            font.family: Theme.font.family
            // Typographic ambition (Task 6 bullet 2): the display slot at a
            // genuinely large multiple of the scale root, deliberate
            // letter-spacing so it reads as set type rather than a raw
            // clock widget, tabular figures for free (any monospace font,
            // by construction — DESIGN.md §2.5).
            font.pixelSize: Math.round(Theme.fontSize.displayLarge * 4)
            font.letterSpacing: Theme.space.md
        }

        MetaLabel {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font.pixelSize: Theme.fontSize.subtitle
            font.letterSpacing: 2
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root._fieldWidth
            height: Theme.borderWidth
            color: Theme.color.rule
        }

        Item {
            id: fieldBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: root._fieldWidth
            height: root._fieldHeight

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: "transparent"
                border.width: root._fieldBorder.widths.top
                border.color: root._fieldBorder.color
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Theme.space.xxl * 2
                spacing: Theme.space.xs
                visible: root.unavailableText === ""

                // Only shown for a state worth calling out (error/checking)
                // — round-1 screenshot review found "PASSWORD" here and
                // "ENTER PASSWORD" as the placeholder right below it reading
                // as the exact duplicated-copy kind of "average" the brief
                // was about. Idle state relies on the placeholder alone.
                MetaLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.errorState || root.checking
                    text: root._displayLabel
                    color: root.errorState ? Theme.color.urgent : Theme.color.foregroundDim
                    font.italic: root.errorState
                }

                // Collapses entirely while checking (Column skips invisible
                // children) rather than leaving an empty gap under
                // "CHECKING…" where the input/placeholder used to be.
                Item {
                    id: inputRow
                    width: parent.width
                    height: input.implicitHeight
                    visible: !root.checking

                    MetaLabel {
                        anchors.centerIn: parent
                        visible: input.text.length === 0
                        text: root.masked ? "Enter Password" : "Enter Username"
                        font.pixelSize: Theme.fontSize.body
                    }

                    // FontMetrics measured at zero letter-spacing on purpose
                    // — feeding `input.font` back in here (its letterSpacing
                    // included) would make the shrink-to-fit measurement
                    // depend on its own previous output.
                    FontMetrics {
                        id: dotMetrics
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                    }

                    TextInput {
                        id: input
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: root._glyphReserve
                        anchors.rightMargin: root._glyphReserve
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.checking
                        horizontalAlignment: TextInput.AlignHCenter
                        color: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.body
                        echoMode: root.masked ? TextInput.Password : TextInput.Normal
                        passwordCharacter: "●"
                        enabled: root.inputEnabled && !root.checking
                        focus: true
                        selectByMouse: true
                        // Cursor only shows once there's real content — an
                        // empty, centred cursor otherwise lands squarely
                        // inside the centred placeholder, printing as a
                        // stray bar through the middle of a word (round-1
                        // screenshot). Not a plain `cursorVisible: text.length
                        // > 0` binding: QQuickTextInput's own C++
                        // focusInEvent() calls setCursorVisible(true)
                        // directly the moment focus lands (forceActiveFocus()
                        // in LockSurface/greeter's onVisibleChanged), which
                        // silently breaks any declarative binding on this
                        // property — reproduced directly, an ordinary binding
                        // stuck permanently true from the first screenshot
                        // onward. Re-asserting imperatively after that
                        // internal override (and after every text change) is
                        // what actually sticks.
                        onActiveFocusChanged: {
                            if (activeFocus)
                                Qt.callLater(function () { input.cursorVisible = input.text.length > 0; });
                        }
                        onTextChanged: input.cursorVisible = input.text.length > 0

                        // Shrink-to-fit dot spacing: as more dots need to
                        // fit the fixed field width, letter-spacing narrows
                        // (down to slight overlap) rather than letting the
                        // run clip silently past the field's edge.
                        font.letterSpacing: (root.masked && text.length > 1)
                            ? Math.max(-2, Math.min(6, (width - dotMetrics.advanceWidth("●".repeat(text.length))) / (text.length - 1)))
                            : 0

                        Keys.onPressed: event => {
                            root.activity();
                            if (event.key === Qt.Key_Escape) {
                                input.text = "";
                                event.accepted = true;
                            } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                                input.text = "";
                                event.accepted = true;
                            }
                        }

                        onAccepted: {
                            var value = input.text;
                            input.text = "";
                            root.accepted(value);
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.fingerprintEnrolled
                        text: "󰈷"
                        color: Theme.color.foregroundDim
                        font.family: Theme.font.family
                        font.pixelSize: Theme.fontSize.title
                    }
                }
            }

            MetaLabel {
                anchors.centerIn: parent
                width: parent.width - Theme.space.xxl * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.unavailableText !== ""
                text: root.unavailableText
                font.pixelSize: Theme.fontSize.caption
            }
        }
    }
}
