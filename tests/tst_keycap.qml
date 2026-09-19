import QtQuick
import QtTest
import qs.Core
import "../shell/Components"
import "../shell/Components/keys.js" as Keys
import "../shell/Menu/hints.js" as Hints
import "../shell/Menu/actions.js" as Actions

// Keycap and Chord: one key per cap, every key spelt one way whatever wrote
// it, arrows as icons, and a chord split into its keys rather than drawn as
// one cap carrying a `+`.
TestCase {
    id: testCase
    name: "Keycap"
    width: 300
    height: 100
    visible: true
    when: windowShown

    Component {
        id: capComponent
        Keycap {}
    }

    Component {
        id: chordComponent
        Chord {}
    }

    function test_names_are_spelt_one_way() {
        compare(Keys.cap("SUPER").text, "Super");
        compare(Keys.cap("ctrl").text, "Ctrl");
        compare(Keys.cap("Control").text, "Ctrl");
        compare(Keys.cap("Escape").text, "Esc");
        compare(Keys.cap("ESC").text, "Esc");
        compare(Keys.cap("Return").text, "Enter");
        compare(Keys.cap("SHIFT").text, "Shift");
        compare(Keys.cap("q").text, "Q");
        compare(Keys.cap("F5").text, "F5");
    }

    function test_arrows_are_icons_not_glyphs() {
        var up = Keys.cap("Up");
        compare(up.text, "");
        compare(up.icon, "arrow-up");
        compare(Keys.cap("left").icon, "arrow-left");
        compare(Keys.cap("Enter").icon, "");
    }

    function test_a_chord_splits_into_its_keys() {
        compare(Keys.split("Super+Alt+Space"), ["Super", "Alt", "Space"]);
        compare(Keys.split("Shift + Enter"), ["Shift", "Enter"]);
        compare(Keys.split(["Up", "Down"]), ["Up", "Down"]);
        compare(Keys.split("Enter"), ["Enter"]);
        compare(Keys.split(""), []);
        compare(Keys.split(null), []);
    }

    // `Ctrl++` is Ctrl and the plus key, not Ctrl and nothing.
    function test_a_plus_key_survives_the_split() {
        compare(Keys.split("Ctrl++"), ["Ctrl", "+"]);
        compare(Keys.split("+"), ["+"]);
    }

    function test_a_cap_is_never_narrower_than_it_is_tall() {
        var cap = createTemporaryObject(capComponent, testCase, { key: "Q" });
        verify(cap !== null);
        compare(cap.implicitHeight, Theme.space.keycapHeight);
        verify(cap.implicitWidth >= cap.implicitHeight);
        var wide = createTemporaryObject(capComponent, testCase, { key: "Space" });
        verify(wide.implicitWidth > cap.implicitWidth);
    }

    function test_a_cap_draws_the_keycap_role() {
        var cap = createTemporaryObject(capComponent, testCase, { key: "Esc" });
        compare(cap.role, "keycap");
        compare(cap.text, "Esc");
    }

    function test_a_chord_draws_one_cap_per_key() {
        var chord = createTemporaryObject(chordComponent, testCase, { keys: "Super+Alt+Space" });
        verify(chord !== null);
        compare(chord.list.length, 3);
        var caps = [];
        for (var i = 0; i < chord.children.length; i++) {
            if (chord.children[i].role === "keycap")
                caps.push(chord.children[i].text);
        }
        compare(caps, ["Super", "Alt", "Space"]);
    }

    // The launcher's route chord is the row's accessory, split for the caps;
    // a count or a prefix is not a chord and draws as text.
    function test_route_chords_reach_the_row_as_keys() {
        compare(Hints.chordKeysFor({ id: "apps", kind: "provider", childIds: [] }),
            ["Super", "Alt", "Space"]);
        compare(Hints.chordKeysFor({ id: "emoji", kind: "provider", childIds: [] }), []);
        compare(Hints.chordKeysFor({ id: "panels", kind: "submenu" }), []);
        compare(Hints.chordKeysFor(null), []);
    }

    // The footer's legend is names, one per cap: no glyph that depends on
    // the mono face, no shouted SHIFT or ESC.
    function test_the_footer_legend_is_key_names() {
        var hints = Actions.hints({ mode: "menu", atRoot: true, discreteGpu: true,
            node: { kind: "app" } });
        var keys = hints.map(function (h) { return h.keys.join("+"); });
        compare(keys, ["Shift+Enter", "Esc"]);
        compare(Actions.primaryAction({ mode: "menu", node: { kind: "app" } }).keys, ["Enter"]);
    }
}
