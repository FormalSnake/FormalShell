import QtQuick
import QtTest
import qs.Core
import "../shell/Surfaces/Notifications"
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/pantheon.js" as Pantheon

// NotificationCard as the facade over its two shapes (M60 T4): the contract
// a consumer binds to has to mean the same thing under either habit, and the
// bubble has two claims of its own that no other surface makes.
//
// The habit is driven by swapping the live table, which is how the shell
// picks a recipe: no test here names a preset, and nothing reaches into a
// recipe for anything a consumer cannot read off the card. The close button
// is found by the icon it carries rather than by walking a path down to it,
// so the layout inside the bubble is free to move.
TestCase {
    id: testCase
    name: "NotificationCard"
    width: 500
    height: 400
    visible: true
    when: windowShown

    readonly property double arrivedAt: 1758000000000

    // One notification with a body long enough to have somewhere to wrap and
    // no icon anywhere, so both shapes fall back to their own bell (the icon
    // stubs answer nothing, the same as a session with no icon theme).
    readonly property var entry: ({
        id: "1", appName: "Signal", appIcon: "", desktopEntry: "",
        summary: "A summary", urgency: 1, actions: [], image: "", local: false,
        body: "A body with enough words in it to have to wrap somewhere before it runs out of card",
        arrivedAt: testCase.arrivedAt, seenAt: null, expiresAt: null, memberIds: ["1"]
    })

    Component {
        id: cardComponent

        NotificationCard {
            entry: testCase.entry
            now: testCase.arrivedAt
        }
    }

    property var _originalStyle

    function init() {
        testCase._originalStyle = Theme.style;
    }

    function cleanup() {
        Theme.style = testCase._originalStyle;
    }

    function cardOn(table, props) {
        Theme.style = table;
        var card = createTemporaryObject(cardComponent, testCase, props);
        verify(card);
        waitForRendering(card);
        return card;
    }

    // A `Button` carrying one named icon, wherever it ended up: `variant` is
    // what tells a button from anything else that happens to have a `name`.
    function iconButton(item, wanted) {
        if (item.variant !== undefined && item.name !== undefined && item.name === wanted)
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = testCase.iconButton(item.children[i], wanted);
            if (hit)
                return hit;
        }
        return null;
    }

    function textNamed(item, wanted) {
        if (item.text !== undefined && item.wrapMode !== undefined && item.text === wanted)
            return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = testCase.textNamed(item.children[i], wanted);
            if (hit)
                return hit;
        }
        return null;
    }

    // --- the contract -----------------------------------------------------

    function test_the_derived_data_is_the_facades_under_both_habits() {
        var tables = [Metamorphosis.STYLE, Pantheon.STYLE];
        for (var i = 0; i < tables.length; i++) {
            var card = testCase.cardOn(tables[i]);
            compare(card.role, "notification");
            compare(card.state, "rest");
            compare(card.critical, false);
            compare(card.relTime, "now");
            compare(card.meta, "now");
            compare(card.iconSource, "");
            verify(card.styledBody.length > 0);
            verify(card.implicitHeight > 0);
            compare(card.hovered, false);
        }
    }

    // Urgency and `flat` name the box between them, and critical keeps its
    // rim through the flattening: that rim is what urgency asked for.
    function test_urgency_and_flat_name_the_box() {
        var tables = [Metamorphosis.STYLE, Pantheon.STYLE];
        for (var i = 0; i < tables.length; i++) {
            Theme.style = tables[i];
            compare(testCase.cardOn(tables[i], { flat: true }).state, "flat");
            var crit = testCase.cardOn(tables[i], { entry: testCase.criticalEntry });
            compare(crit.critical, true);
            compare(crit.state, "critical");
            compare(testCase.cardOn(tables[i], {
                entry: testCase.criticalEntry, flat: true
            }).state, "flatCritical");
        }
    }

    readonly property var criticalEntry: {
        var out = {};
        for (var key in testCase.entry)
            out[key] = testCase.entry[key];
        out.urgency = 2;
        return out;
    }

    // --- the two shapes ---------------------------------------------------

    // Each shape states its own width, and the card takes it: the row is on
    // the shell's own narrow snap point, the bubble on elementary's
    // transcribed 332.
    function test_each_shape_states_its_own_width() {
        compare(testCase.cardOn(Metamorphosis.STYLE).implicitWidth,
            Theme.space.popupWidthNarrow);
        compare(testCase.cardOn(Pantheon.STYLE).implicitWidth,
            Theme.space.popupWidthBubble);
        compare(Theme.space.popupWidthBubble, 332);
    }

    // elementary's `max-width-chars` on the body, in the unit that survives a
    // font change: the advance of 33 digits at the body's own size, and
    // narrower than the column it sits in, or the measure is doing nothing.
    function test_the_bubbles_body_wraps_at_elementarys_character_measure() {
        var card = testCase.cardOn(Pantheon.STYLE);
        var body = testCase.textNamed(card, card.styledBody);
        verify(body);
        metrics.font.family = Theme.fontFamilySans;
        metrics.font.pixelSize = Theme.fontSize.bodySmall;
        compare(body.width, Math.ceil(metrics.advanceWidth("0") * 33));
        verify(body.width < card.implicitWidth - Theme.space.panelPadding * 2);
    }

    FontMetrics {
        id: metrics
    }

    // The row's close button is always there; the bubble's is not there until
    // the pointer is, and it cannot be clicked while it is not.
    function test_the_bubbles_close_button_waits_for_the_pointer() {
        var row = testCase.cardOn(Metamorphosis.STYLE);
        var rowClose = testCase.iconButton(row, "x");
        verify(rowClose);
        compare(rowClose.visible, true);

        var card = testCase.cardOn(Pantheon.STYLE);
        var close = testCase.iconButton(card, "x");
        verify(close);
        compare(close.visible, false);
        compare(close.enabled, false);

        mouseMove(card, card.width / 2, card.height / 2);
        tryCompare(card, "hovered", true);
        tryCompare(close, "opacity", 1);
        compare(close.visible, true);
        compare(close.enabled, true);

        // Off the card again, and it goes back to nothing.
        mouseMove(testCase, testCase.width - 1, testCase.height - 1);
        tryCompare(card, "hovered", false);
        tryCompare(close, "opacity", 0);
        compare(close.visible, false);
    }

    // The clocks the stack reads off the table (Surfaces/Notifications/
    // Toasts.qml): the bubble's own 400ms unfold and its 200ms restack with
    // a stagger window, against the families the metamorphosis names.
    function test_the_arrival_and_restack_clocks_come_off_the_table() {
        Theme.style = Pantheon.STYLE;
        compare(Theme.motion.arrive, 400);
        compare(Theme.motion.restack, 200);
        compare(Theme.motion.restackStagger, 150);
        compare(Theme.motion.curves.restack, Theme.motion.curves.emphasizedDecel);

        Theme.style = Metamorphosis.STYLE;
        compare(Theme.motion.arrive, Theme.motion.spatial);
        compare(Theme.motion.restack, Theme.motion.spatial);
        compare(Theme.motion.restackStagger, 0);
        compare(Theme.motion.curves.arrive, Theme.motion.curves.emphasizedDecel);
    }
}
