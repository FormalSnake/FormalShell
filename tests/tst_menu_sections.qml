import QtQuick
import QtTest
import "../shell/Menu/model.js" as Model

// The launcher's group headings and field prompts (M48 D6). The shipped
// tree is read from disk for the last case, which is the one that would go
// quietly wrong: a section is only one block while the entries declaring it
// are still contiguous in default-menu.jsonc, and nothing about a reordered
// file looks broken until the frame shows two SUGGESTIONS headings. Reading
// a file outside the test's own directory needs QML_XHR_ALLOW_FILE_READ=1,
// set by the qmltestrunner invocations in justfile and flake.nix's qml-tests
// derivation.
TestCase {
    name: "MenuSections"

    property string defaultMenu: ""

    function initTestCase() {
        var done = false;
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) done = true;
        };
        xhr.open("GET", Qt.resolvedUrl("../shell/Menu/default-menu.jsonc"));
        xhr.send();
        tryVerify(function () { return done; }, 5000);
        defaultMenu = xhr.responseText;
    }

    function test_section_and_prompt_survive_build() {
        var tree = Model.buildTree({
            "apps": { provider: "apps", section: "Suggestions", prompt: "Search apps" },
            "plain": { label: "Plain" }
        }, {});
        compare(tree.nodes["apps"].section, "Suggestions");
        compare(tree.nodes["apps"].prompt, "Search apps");
        verify(tree.nodes["plain"].section === undefined);
        verify(tree.nodes["plain"].prompt === undefined);
    }

    // A user overlay wins per key here like everywhere else, which is what
    // makes regrouping the root a one-line menu.jsonc edit.
    function test_user_overlay_moves_a_row_between_groups() {
        var tree = Model.buildTree(
            { "apps": { provider: "apps", section: "Suggestions" } },
            { "apps": { section: "Mine" } });
        compare(tree.nodes["apps"].section, "Mine");
    }

    function test_declared_section_wins_at_the_root() {
        var rows = [
            { id: "apps", section: "Suggestions" },
            { id: "emoji", section: "Suggestions" },
            { id: "tray" }
        ];
        var sections = Model.sectionsFor(rows, { mode: "menu", level: null });
        compare(sections, ["Suggestions", "Suggestions", "Commands"]);
        compare(Model.sectionNames(sections), ["Suggestions", "Commands"]);
    }

    // Inside a level the rows are that level's, so it names them, and the
    // frecency head of a provider that marks one leads under Recent.
    function test_level_names_its_own_rows() {
        var rows = [
            { id: "apps.a", recent: true },
            { id: "apps.b", recent: true },
            { id: "apps.c" },
            { id: "apps.d" }
        ];
        var sections = Model.sectionsFor(rows, { mode: "menu", level: "apps", levelLabel: "Apps" });
        compare(sections, ["Recent", "Recent", "Apps", "Apps"]);
        compare(Model.sectionNames(sections), ["Recent", "Apps"]);
    }

    // A ranked list is not a level's children: a row's own declared section
    // would cut the results into a heading per row, in score order.
    function test_a_query_names_its_results() {
        var rows = [
            { id: "emoji", section: "Suggestions" },
            { id: "apps.a", recent: true },
            { id: "tray" }
        ];
        var sections = Model.sectionsFor(rows, { mode: "menu", searching: true, level: null });
        compare(sections, ["Results", "Results", "Results"]);
    }

    // The breadcrumb chip above the list already says "Clipboard", so a
    // CLIPBOARD heading under it separates nothing.
    function test_a_single_group_level_draws_no_heading() {
        var rows = [{ id: "clipboard.a" }, { id: "clipboard.b" }];
        var sections = Model.sectionsFor(rows, {
            mode: "menu", level: "clipboard", levelLabel: "Clipboard"
        });
        compare(sections, ["", ""]);
        compare(Model.sectionNames(sections), []);
    }

    // A grid draws no headings, so it must not claim any either: `menu
    // status` is the only place a heading is observable from the rig.
    function test_a_grid_has_no_headings() {
        var rows = [{ id: "emoji.a" }, { id: "emoji.b" }];
        var sections = Model.sectionsFor(rows, {
            mode: "menu", grid: true, level: "emoji", levelLabel: "Emoji"
        });
        compare(sections, ["", ""]);
        compare(Model.sectionNames(sections), []);
    }

    function test_dmenu_modes_name_themselves() {
        var rows = [{ id: "select.0" }, { id: "select.1" }];
        compare(Model.sectionsFor(rows, { mode: "select" }), ["Options", "Options"]);
        compare(Model.sectionsFor([], { mode: "input" }), []);
        compare(Model.sectionNames(["", ""]), []);
    }

    function test_prompt_is_the_nodes_own_or_its_label() {
        compare(Model.promptFor({ label: "Emoji", prompt: "Search emoji" }), "Search emoji");
        compare(Model.promptFor({ label: "Toggles" }), "Search Toggles");
        compare(Model.promptFor(null), "");
    }

    // The shipped root: one Suggestions block, then everything else, with no
    // heading appearing twice.
    function test_shipped_root_is_two_contiguous_groups() {
        var tree = Model.buildTree(Model.parseJsonc(defaultMenu), {});
        var rows = Model.visibleChildren(tree.nodes, null, {});
        verify(rows.length > 8);
        var sections = Model.sectionsFor(rows, { mode: "menu", level: null });
        compare(Model.sectionNames(sections), ["Suggestions", "Commands"]);
        var seen = [];
        for (var i = 0; i < sections.length; i++) {
            if (i > 0 && sections[i] === sections[i - 1])
                continue;
            verify(seen.indexOf(sections[i]) < 0,
                "section " + sections[i] + " is declared in two blocks");
            seen.push(sections[i]);
        }
        compare(sections[0], "Suggestions");
        compare(sections[sections.length - 1], "Commands");
    }
}
