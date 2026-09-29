import QtQuick
import QtTest
import "../shell/Menu/actions.js" as Actions
import "../shell/Menu/providers.js" as Providers

TestCase {
    name: "MenuDevices"

    function test_id_part_round_trips_and_has_no_dot() {
        var keys = ["a.b", "a:b", "a b", "ü", "plain"];
        for (var i = 0; i < keys.length; i++) {
            var part = Providers.idPart(keys[i]);
            compare(part.indexOf("."), -1);
            compare(decodeURIComponent(part), keys[i]);
        }
    }

    function _labels(ctx) {
        return Actions.hints(ctx).map(function (h) { return h.label; });
    }

    function test_alternate_hint_shows_its_label() {
        verify(_labels({ mode: "menu", alternateLabel: "Forget" }).indexOf("Forget") >= 0);
    }

    function test_alternate_hint_absent_without_a_label() {
        compare(_labels({ mode: "menu", alternateLabel: "" }).indexOf("Forget"), -1);
        compare(Actions.hints({ mode: "menu", atRoot: true }).length, 1);
    }

    function test_alternate_hint_absent_while_confirming() {
        compare(_labels({ mode: "menu", alternateLabel: "Forget", confirming: true }).indexOf("Forget"), -1);
    }

    function test_alternate_hint_absent_in_input_mode() {
        compare(_labels({ mode: "input", alternateLabel: "Forget" }), ["Cancel"]);
    }
}
