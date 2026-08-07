import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Corner-mark ornament regression guard (shell/Components/CornerMarks.qml,
// DESIGN.md §2 item 7): four foregroundFaint squares, xs-sized, centered on
// a card's four corners. Theme comes from tests/stubs/qs/Core (same
// palette.js/tokens.js values the real singleton derives its own from).
TestCase {
    id: testCase
    name: "CornerMarks"
    width: 400
    height: 400
    visible: true
    when: windowShown

    Component {
        id: cardComponent

        Item {
            id: card
            width: 180
            height: 120

            readonly property Item probeMarks: marks

            CornerMarks { id: marks }
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    // Repeater's delegates are reparented onto its own parent (CornerMarks'
    // root Item), so `marks.children` holds them directly — filtered by
    // `color`, the one property that tells a mark Rectangle apart from the
    // Repeater sitting alongside it in the same child list.
    function _markAt(marks, cx, cy) {
        for (var i = 0; i < marks.children.length; i++) {
            var m = marks.children[i];
            if (m.color === undefined)
                continue;
            var mcx = m.x + m.width / 2;
            var mcy = m.y + m.height / 2;
            if (Math.abs(mcx - cx) < 0.5 && Math.abs(mcy - cy) < 0.5)
                return m;
        }
        return null;
    }

    function test_four_marks_sit_centered_on_each_corner() {
        var card = createTemporaryObject(cardComponent, testCase);
        verify(card);
        settle(card);

        var marks = card.probeMarks;
        verify(_markAt(marks, 0, 0));
        verify(_markAt(marks, card.width, 0));
        verify(_markAt(marks, 0, card.height));
        verify(_markAt(marks, card.width, card.height));
    }

    function test_marks_are_xs_sized_and_foreground_faint() {
        var card = createTemporaryObject(cardComponent, testCase);
        verify(card);
        settle(card);

        // space.xs is 3 at the stub's default scale (fontBaseSize 13).
        var mark = _markAt(card.probeMarks, 0, 0);
        verify(mark);
        compare(mark.width, 3);
        compare(mark.height, 3);
        verify(Qt.colorEqual(mark.color, Theme.color.foregroundFaint));
    }

    function test_marks_track_a_resized_card() {
        var card = createTemporaryObject(cardComponent, testCase);
        verify(card);
        settle(card);

        card.width = 240;
        card.height = 150;
        settle(card);

        verify(_markAt(card.probeMarks, card.width, card.height));
    }
}
