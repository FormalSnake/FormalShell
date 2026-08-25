import QtQuick

// The one key dispatcher every keyboard-driven surface wraps its content in
// (spec "Keyboard model"): Escape closes, Tab and Shift+Tab move between
// sections, arrows and hjkl move the cursor, Enter and Space activate, `x`
// deletes, and any other printable character goes to `textKey` so a surface
// can type-to-filter without binding keys of its own.
//
// `blocked` hands the keyboard to an inline editor: nothing fires and the
// event goes unaccepted, so the focused field sees it.
Item {
    id: root

    signal moveRequested(int dx, int dy)
    signal activateRequested()
    signal closeRequested()
    signal deleteRequested()
    signal tabRequested(int direction)
    signal textKey(string text)

    property bool blocked: false

    focus: true
    Keys.priority: Keys.BeforeItem

    Keys.onPressed: event => root.handle(event)

    // Public so a surface that owns the keyboard elsewhere can order this
    // dispatch against its own handling: Panel.qml's backdrop holds focus
    // and calls this only after its `keyPressed` consumers have passed on
    // the event.
    function handle(event) {
        if (root.blocked)
            return;

        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested();
            event.accepted = true;
            return;
        case Qt.Key_Tab:
            root.tabRequested(1);
            event.accepted = true;
            return;
        case Qt.Key_Backtab:
            root.tabRequested(-1);
            event.accepted = true;
            return;
        case Qt.Key_Down:
            root.moveRequested(0, 1);
            event.accepted = true;
            return;
        case Qt.Key_Up:
            root.moveRequested(0, -1);
            event.accepted = true;
            return;
        case Qt.Key_Right:
            root.moveRequested(1, 0);
            event.accepted = true;
            return;
        case Qt.Key_Left:
            root.moveRequested(-1, 0);
            event.accepted = true;
            return;
        // Space carries a printable text of its own, so it has to be caught
        // here or it reaches textKey as " ".
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.activateRequested();
            event.accepted = true;
            return;
        }

        var text = event.text;
        if (text.length !== 1 || text.charCodeAt(0) < 0x20)
            return;

        switch (text) {
        case "j":
            root.moveRequested(0, 1);
            break;
        case "k":
            root.moveRequested(0, -1);
            break;
        case "l":
            root.moveRequested(1, 0);
            break;
        case "h":
            root.moveRequested(-1, 0);
            break;
        case "x":
            root.deleteRequested();
            break;
        default:
            root.textKey(text);
            break;
        }
        event.accepted = true;
    }
}
