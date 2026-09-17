import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Card is a Box with the `card` role (M59 T5), which puts two things at
// risk that no other test covers: a consumer's children have to land in the
// padded slot rather than in Box's own default slot, which is a mask and is
// never drawn, and the frame has to keep painting the role a surface asks
// for. The notification card and the capture picker both ride on that.
TestCase {
    id: testCase
    name: "Card"
    width: 400
    height: 300
    visible: true
    when: windowShown

    Component {
        id: cardComponent

        Card {
            id: card
            readonly property Item probeBody: body

            Rectangle {
                id: body
                width: 120
                height: 40
            }
        }
    }

    function make(props) {
        var card = createTemporaryObject(cardComponent, testCase, props);
        verify(card);
        waitForRendering(card);
        return card;
    }

    // The slot, and with it the measurement every panel's implicit size is.
    // Box's silhouette is a mask and is never drawn, so content that landed
    // there would measure right and paint nothing: the parent walk is what
    // says it is the drawn slot.
    function test_the_content_lands_in_the_padded_slot() {
        var card = make({});
        compare(card.probeBody.parent, card.contentItem);
        compare(card.contentItem.parent, card);
        verify(card.contentItem.visible);
        compare(card.contentItem.anchors.margins, card.padding);
        compare(card.implicitWidth, 120 + card.padding * 2);
        compare(card.implicitHeight, 40 + card.padding * 2);
    }

    // The frame, off the table: translucent by default, and opaque for a
    // surface on a namespace the compositor does not blur.
    function test_the_frame_paints_the_card_role() {
        var rest = make({});
        verify(Qt.colorEqual(rest.box.fill, Qt.alpha(Theme.color.card, Theme.surfaceOpacity)));
        compare(rest.box.radius, Theme.radiusXl);
        compare(rest.box.border.width, Theme.borderWidth);

        var opaque = make({ state: "opaque" });
        verify(Qt.colorEqual(opaque.box.fill, Theme.color.card));
        compare(opaque.box.radius, Theme.radiusXl);
    }
}
