import QtQuick
import QtTest
import "../shell/Overnight/model.js" as Overnight

TestCase {
    name: "OvernightModel"

    // The g815's own /sys/class/leds, trimmed: the ASUS keyboard backlight
    // lit with no trigger, a LAN LED with no trigger but already dark, the
    // Wi-Fi LED on its radio trigger, and lock keys on theirs.
    readonly property string g815: [
        "asus::kbd_backlight\t[none] kbd-scrolllock kbd-numlock\t3",
        "enp130s0-0::lan\t[none] netdev\t0",
        "phy0-led\tnone [phy0radio] phy0tpt\t1",
        "input12::capslock\tnone [kbd-capslock]\t1",
        "input12::compose\t[none] kbd-capslock\t1",
        "nvidia_0\t[none]\t2",
        ""
    ].join("\n")

    function test_parse_keeps_lit_untriggered_leds() {
        var leds = Overnight.parseLeds(g815);
        compare(leds.length, 2);
        compare(leds[0].name, "asus::kbd_backlight");
        compare(leds[0].brightness, 3);
        compare(leds[1].name, "nvidia_0");
    }

    function test_parse_skips_triggered_dark_and_input_leds() {
        var names = Overnight.parseLeds(g815).map(function (l) { return l.name; });
        verify(names.indexOf("phy0-led") === -1);
        verify(names.indexOf("enp130s0-0::lan") === -1);
        verify(names.indexOf("input12::capslock") === -1);
        verify(names.indexOf("input12::compose") === -1);
    }

    function test_parse_tolerates_empty_and_unreadable() {
        compare(Overnight.parseLeds("").length, 0);
        compare(Overnight.parseLeds(undefined).length, 0);
        compare(Overnight.parseLeds("broken\t[none]\t\n").length, 0);
    }

    function test_restore_args_round_trip() {
        var snap = Overnight.ledSnapshot(Overnight.parseLeds(g815));
        compare(snap["asus::kbd_backlight"], 3);
        compare(Overnight.restoreArgs(snap), ["asus::kbd_backlight", "3", "nvidia_0", "2"]);
    }

    function test_restore_args_drops_zero_and_junk() {
        compare(Overnight.restoreArgs({ a: 0, b: "x", c: 4 }), ["c", "4"]);
        compare(Overnight.restoreArgs(null), []);
    }
}
