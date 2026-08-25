import QtQuick
import QtTest
import "../shell/Components"

// KeyCatcher's dispatch table (spec "Keyboard model"): every key fires
// exactly one signal, and `blocked` fires none so the focused inline editor
// sees the keystroke instead.
//
// The QML TestCase key helpers deliver to whatever holds active focus in the
// test's own window, so each case focuses the catcher first.
TestCase {
    id: testCase
    name: "KeyCatcher"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: catcherComponent

        KeyCatcher {
            property int moves: 0
            property int dx: 0
            property int dy: 0
            property int activates: 0
            property int closes: 0
            property int deletes: 0
            property int tabs: 0
            property int direction: 0
            property int typed: 0
            property string lastText: ""

            readonly property int total: moves + activates + closes + deletes + tabs + typed

            onMoveRequested: (x, y) => {
                moves++;
                dx = x;
                dy = y;
            }
            onActivateRequested: activates++
            onCloseRequested: closes++
            onDeleteRequested: deletes++
            onTabRequested: d => {
                tabs++;
                direction = d;
            }
            onTextKey: t => {
                typed++;
                lastText = t;
            }
        }
    }

    function makeCatcher(props) {
        var catcher = createTemporaryObject(catcherComponent, testCase, props);
        verify(catcher);
        catcher.forceActiveFocus();
        verify(catcher.activeFocus);
        return catcher;
    }

    function test_escape_closes() {
        var catcher = makeCatcher({});
        keyClick(Qt.Key_Escape);
        compare(catcher.closes, 1);
        compare(catcher.total, 1);
    }

    function test_tab_and_backtab_carry_a_direction() {
        var forward = makeCatcher({});
        keyClick(Qt.Key_Tab);
        compare(forward.tabs, 1);
        compare(forward.direction, 1);
        compare(forward.total, 1);

        var back = makeCatcher({});
        keyClick(Qt.Key_Backtab);
        compare(back.tabs, 1);
        compare(back.direction, -1);
        compare(back.total, 1);
    }

    function test_arrows_move_data() {
        return [
            { tag: "down", key: Qt.Key_Down, dx: 0, dy: 1 },
            { tag: "up", key: Qt.Key_Up, dx: 0, dy: -1 },
            { tag: "right", key: Qt.Key_Right, dx: 1, dy: 0 },
            { tag: "left", key: Qt.Key_Left, dx: -1, dy: 0 }
        ];
    }

    function test_arrows_move(data) {
        var catcher = makeCatcher({});
        keyClick(data.key);
        compare(catcher.moves, 1);
        compare(catcher.dx, data.dx);
        compare(catcher.dy, data.dy);
        compare(catcher.total, 1);
    }

    function test_hjkl_move_data() {
        return [
            { tag: "j", key: "j", dx: 0, dy: 1 },
            { tag: "k", key: "k", dx: 0, dy: -1 },
            { tag: "l", key: "l", dx: 1, dy: 0 },
            { tag: "h", key: "h", dx: -1, dy: 0 }
        ];
    }

    function test_hjkl_move(data) {
        var catcher = makeCatcher({});
        keyClick(data.key);
        compare(catcher.moves, 1);
        compare(catcher.dx, data.dx);
        compare(catcher.dy, data.dy);
        // A movement key is never also a printable one.
        compare(catcher.typed, 0);
        compare(catcher.total, 1);
    }

    function test_activate_keys_data() {
        return [
            { tag: "return", key: Qt.Key_Return },
            { tag: "enter", key: Qt.Key_Enter },
            { tag: "space", key: Qt.Key_Space }
        ];
    }

    // Space carries a printable text of its own, so it has to be caught as a
    // key or it reaches textKey as " ".
    function test_activate_keys(data) {
        var catcher = makeCatcher({});
        keyClick(data.key);
        compare(catcher.activates, 1);
        compare(catcher.typed, 0);
        compare(catcher.total, 1);
    }

    function test_x_deletes() {
        var catcher = makeCatcher({});
        keyClick("x");
        compare(catcher.deletes, 1);
        compare(catcher.typed, 0);
        compare(catcher.total, 1);
    }

    function test_a_printable_goes_to_textKey() {
        var catcher = makeCatcher({});
        keyClick("a");
        compare(catcher.typed, 1);
        compare(catcher.lastText, "a");
        compare(catcher.total, 1);
    }

    function test_blocked_fires_nothing() {
        var catcher = makeCatcher({ blocked: true });
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        keyClick("j");
        keyClick("x");
        keyClick("a");
        compare(catcher.total, 0);
    }
}
