import QtQuick
import QtTest

// The blur half of docs/examples/hyprland/formalshell.conf, read out of the
// file the package actually ships rather than out of a copy of the same
// strings. DESIGN.md pairs the two properties: a surface either paints
// `Theme.surface(card)` and takes a blur layerrule, or it is opaque and takes
// none. The polkit card sat on the wrong side of that for a while, drawn at
// surfaceOpacity with nothing blurred behind it, which reads as a rendering
// fault rather than as depth. Nothing in the smoke rig can catch that (it
// disables compositor blur outright so a frame shows what the shell itself
// draws), so this is where the pairing is pinned.
//
// Reading a file outside the test's own directory needs
// QML_XHR_ALLOW_FILE_READ=1, set by the qmltestrunner invocations in
// justfile and flake.nix's qml-tests derivation.
TestCase {
    name: "HyprlandLayerrules"

    property string conf: ""

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../docs/examples/hyprland/formalshell.conf"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        conf = xhr.responseText;
    }

    // Hyprland 0.56 takes layer rules as a named block, so this walks brace
    // depth rather than matching one line: `namespace`, `blur` and
    // `ignore_alpha` sit at three different depths inside one rule.
    function _rules() {
        var out = [];
        var current = null;
        var depth = 0;
        var lines = conf.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/#.*$/, "").trim();
            if (line === "")
                continue;
            if (line.indexOf("layerrule") === 0 && current === null) {
                current = { namespace: "", blur: "", ignoreAlpha: "", noAnim: "" };
                depth = 0;
            }
            if (current === null)
                continue;
            var m = line.match(/^(namespace|blur|ignore_alpha|no_anim)\s*=\s*(.+)$/);
            if (m) {
                if (m[1] === "namespace") current.namespace = m[2].trim();
                else if (m[1] === "blur") current.blur = m[2].trim();
                else if (m[1] === "no_anim") current.noAnim = m[2].trim();
                else current.ignoreAlpha = m[2].trim();
            }
            depth += (line.match(/{/g) || []).length;
            depth -= (line.match(/}/g) || []).length;
            if (depth <= 0) {
                out.push(current);
                current = null;
            }
        }
        return out;
    }

    function _byNamespace(ns) {
        var rules = _rules();
        for (var i = 0; i < rules.length; i++) {
            if (rules[i].namespace === ns)
                return rules[i];
        }
        return null;
    }

    function test_translucent_surfaces_all_blur() {
        // Every namespace whose surface paints `Theme.surface(card)` or
        // `Theme.surface(popover)`. Adding one to the shell without adding it
        // here is the regression: it ships translucent over an unblurred
        // desktop.
        var translucent = [
            "formalshell:bar",
            "formalshell:panel",
            "formalshell:menu",
            "formalshell:notifications-center",
            "formalshell:tooltip",
            "formalshell:polkit"
        ];
        for (var i = 0; i < translucent.length; i++) {
            var rule = _byNamespace(translucent[i]);
            verify(rule !== null, translucent[i] + " has no layerrule at all");
            compare(rule.blur, "$blur", translucent[i] + " does not take the theme's blur");
        }
    }

    // $blur is what ThemeEngine writes into formalshell-chrome.conf, so the
    // retro preset turning blur off has to reach every one of these. A rule
    // hardcoding `true` would keep blurring under a preset that asked for
    // none.
    function test_no_rule_hardcodes_blur() {
        var rules = _rules();
        for (var i = 0; i < rules.length; i++) {
            if (rules[i].blur !== "")
                compare(rules[i].blur, "$blur", rules[i].namespace + " hardcodes its blur");
        }
    }

    // ignore_alpha is what keeps the bar strip's empty band between the cells
    // clear: a blurred layer without it blurs the gaps too.
    function test_every_blurred_rule_sets_ignore_alpha() {
        var rules = _rules();
        for (var i = 0; i < rules.length; i++) {
            if (rules[i].blur === "")
                continue;
            verify(rules[i].ignoreAlpha !== "",
                rules[i].namespace + " blurs without an ignore_alpha");
        }
    }

    // The other side of the pairing: a surface DESIGN.md calls opaque takes
    // no blur. Toasts and the OSD paint `Theme.color.card` flat.
    function test_opaque_surfaces_do_not_blur() {
        var opaque = ["formalshell:notifications", "formalshell:osd"];
        for (var i = 0; i < opaque.length; i++) {
            var rule = _byNamespace(opaque[i]);
            verify(rule !== null, opaque[i] + " has no layerrule at all");
            compare(rule.blur, "", opaque[i] + " blurs behind an opaque surface");
        }
    }

    // The shell animates its own surfaces, so a compositor animation on the
    // layer runs a second one over the top of it.
    function test_every_rule_disables_the_compositor_animation() {
        var rules = _rules();
        verify(rules.length >= 8, "only " + rules.length + " layerrules parsed");
        for (var i = 0; i < rules.length; i++)
            compare(rules[i].noAnim, "true", rules[i].namespace + " takes a compositor animation");
    }
}
