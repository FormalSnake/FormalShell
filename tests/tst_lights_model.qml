import QtQuick
import QtTest
import "../shell/Lights/model.js" as Lights
import "../shell/Menu/model.js" as Model
import "../shell/Menu/providers.js" as Providers
import "../shell/Menu/toggles.js" as Toggles

TestCase {
    name: "LightsModel"

    // What LightsService's probe prints on the g815 (asusd 6.x, busctl's
    // text form), static Flexoki blue at full brightness.
    readonly property string g815: [
        "MODE=u 0",
        "DATA=(uu(yyy)(yyy)ss) 0 0 67 133 190 0 0 0 \"Med\" \"Right\"",
        "BRIGHT=u 3",
        "MODES=au 12 0 1 2 3 4 5 6 7 8 10 11 12",
        ""
    ].join("\n")

    function test_parse_probe() {
        var p = Lights.parseProbe(g815);
        compare(p.mode, 0);
        compare(p.colour, "4385be");
        compare(p.speed, "med");
        compare(p.brightness, 3);
        compare(p.modes.length, 12);
        compare(Lights.effectForMode(p.mode).id, "static");
    }

    function test_parse_probe_tolerates_empty_fields() {
        var p = Lights.parseProbe("MODE=\nDATA=\nBRIGHT=\nMODES=\n");
        compare(p.mode, -1);
        compare(p.colour, "");
        compare(p.brightness, -1);
        compare(p.modes.length, 0);
        compare(Lights.parseProbe(undefined).mode, -1);
    }

    function test_supported_follows_the_chassis() {
        compare(Lights.supported([0, 1, 10]).map(function (e) { return e.id; }).join(","), "static,breathe,pulse");
        // No report at all offers the whole table rather than an empty menu.
        compare(Lights.supported([]).length, Lights.EFFECTS.length);
    }

    function test_normalize_hex() {
        compare(Lights.normalizeHex("#FF8800"), "ff8800");
        compare(Lights.normalizeHex(" ff8800 "), "ff8800");
        compare(Lights.normalizeHex("f80"), "");
        compare(Lights.normalizeHex("orange"), "");
        compare(Lights.normalizeHex(null), "");
    }

    function test_effect_args_match_asusctl_usage() {
        compare(Lights.effectArgs("static", "ff8800", "med").join(" "), "asusctl aura effect static --colour ff8800");
        compare(Lights.effectArgs("breathe", "ff8800", "high").join(" "),
            "asusctl aura effect breathe --colour ff8800 --colour2 ff8800 --speed high");
        compare(Lights.effectArgs("rainbow-wave", "", "low").join(" "),
            "asusctl aura effect rainbow-wave --speed low --direction right");
        compare(Lights.effectArgs("rain", "ff8800", "bogus").join(" "), "asusctl aura effect rain --speed med");
        compare(Lights.effectArgs("comet", "nope", "med").join(" "), "asusctl aura effect comet --colour ffffff");
        compare(Lights.effectArgs("disco", "ff8800", "med"), null);
    }

    function test_brightness_args() {
        compare(Lights.brightnessArgs(0).join(" "), "asusctl leds set off");
        compare(Lights.brightnessArgs(3).join(" "), "asusctl leds set high");
        compare(Lights.brightnessArgs(4), null);
        compare(Lights.brightnessArgs(-1), null);
    }

    function test_route_absent_without_a_keyboard() {
        compare(Object.keys(Providers.lightsEntries(false, [])).length, 0);
    }

    function test_route_rows_are_live_in_process_choices() {
        var effects = Lights.supported([0, 1]).map(function (e) { return { id: e.id, label: e.label }; });
        var tree = Model.buildTree(Providers.lightsEntries(true, effects), {});
        var root = tree.nodes["lights"];
        verify(root);
        compare(root.childIds.join(","), "lights.power,lights.effect,lights.color,lights.source,lights.speed,lights.brightness");
        compare(tree.nodes["lights.effect"].childIds.length, 2);
        var ids = Object.keys(tree.nodes).filter(function (id) {
            return tree.nodes[id].kind === "action";
        });
        verify(ids.length > 10);
        ids.forEach(function (id) {
            var node = tree.nodes[id];
            compare(node.action.indexOf("@ipc:lights."), 0, id);
            if (id === "lights.color.hex")
                return;
            compare(node.keepOpen, true, id);
            var path = Toggles.statePath(node.checked).split("=")[0];
            verify(Toggles.isKnownPath(path) || Toggles.isKnownEnumPath(path), id);
        });
        var snap = Toggles.snapshot({ "lights.effect": "breathe", "lights.speed": "high" });
        compare(Toggles.checkedFor(tree.nodes["lights.effect.breathe"], snap, {}), true);
        compare(Toggles.checkedFor(tree.nodes["lights.effect.static"], snap, {}), false);
        compare(Toggles.checkedFor(tree.nodes["lights.speed.high"], snap, {}), true);
    }
}
