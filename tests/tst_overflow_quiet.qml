import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// The chevron's second bar and the tray's are built fresh on every open
// (BarOverflow.qml, TrayOverflow.qml), so their cells measure themselves for
// the first time while the card is arriving. With the layout rule armed
// (M53 D2) that made every open two movements at once: the card entering,
// and every cell inside it growing into a slot the rail was still sliding
// its neighbours along (owner, 2026-09-09: "every time there's an animation
// moving the icons and text, which is annoying").
//
// The gate that fixes it is Panel's `settledOpen`, read here as the two
// halves that have to hold together: the flag itself, over the real
// `Presence`, and what a slot carrying Bar.qml's own presence Behavior does
// on either side of it. Both are built out of the primitives rather than out
// of a Panel, which cannot be instantiated headless, so what this pins is
// the arithmetic each surface spells.
TestCase {
    id: testCase
    name: "OverflowQuiet"
    width: 400
    height: 200
    visible: true
    when: windowShown

    // Panel.qml's own gate: the card is up and standing still.
    Component {
        id: cardComponent

        Item {
            id: card
            property bool isOpen: false
            readonly property bool settledOpen: card.isOpen && presence.settled
            readonly property Presence probe: presence

            Presence {
                id: presence
                open: card.isOpen
                edge: "top"
            }
        }
    }

    // Bar.qml's region delegate, cut down to the two terms this is about:
    // one presence driver behind both the slot's extent and the item's
    // opacity, on a Behavior armed from outside.
    Component {
        id: slotComponent

        Item {
            id: slot
            property bool armed: false
            property bool present: false
            property real progress: slot.present ? 1 : 0

            Behavior on progress {
                enabled: slot.armed
                NumberAnimation { duration: Theme.motion.surface }
            }

            width: 40 * slot.progress
            height: 28
        }
    }

    function test_the_gate_is_shut_for_the_length_of_the_entrance() {
        var card = createTemporaryObject(cardComponent, testCase);
        verify(card);
        compare(card.settledOpen, false);
        card.isOpen = true;
        // The instant the card opens: Presence has started its enter, so the
        // gate must not read true on the same tick, or a rail would arm
        // itself for the frame the cells first measure in.
        compare(card.settledOpen, false);
        tryCompare(card, "settledOpen", true, 1000);
    }

    function test_the_gate_shuts_again_on_close() {
        var card = createTemporaryObject(cardComponent, testCase, { isOpen: true });
        verify(card);
        tryCompare(card, "settledOpen", true, 1000);
        card.isOpen = false;
        // Both terms drop it, and it stays down through the exit, so the
        // next open is as quiet as the first.
        compare(card.settledOpen, false);
        tryCompare(card.probe, "shown", false, 1000);
        compare(card.settledOpen, false);
    }

    // The claim the owner made: a cell that turns on while the card is
    // arriving is simply there, at its full extent, in the frame it turned
    // on in.
    function test_a_slot_lands_at_full_extent_while_the_gate_is_shut() {
        var slot = createTemporaryObject(slotComponent, testCase, { armed: false });
        verify(slot);
        compare(slot.width, 0);
        slot.present = true;
        compare(slot.progress, 1);
        compare(slot.width, 40);
    }

    // And the other half: once the card is open, a cell arriving late still
    // opens its slot rather than appearing in it.
    function test_a_slot_travels_once_the_gate_is_open() {
        var slot = createTemporaryObject(slotComponent, testCase, { armed: true });
        verify(slot);
        compare(slot.width, 0);
        slot.present = true;
        verify(slot.progress < 1);
        tryCompare(slot, "width", 40, 1000);
    }
}
