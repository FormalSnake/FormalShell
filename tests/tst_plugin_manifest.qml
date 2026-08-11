import QtQuick
import QtTest
import "../shell/Plugins/manifest.js" as Manifest

TestCase {
    name: "PluginManifest"

    readonly property string dir: "/home/u/.config/formalshell/plugins"

    // Rebuilds exactly what SCAN_SCRIPT prints: boundary, plugin dir, then
    // the manifest bytes, once per plugin.
    function scan(records) {
        var out = "";
        for (var i = 0; i < records.length; i++)
            out += Manifest.RECORD_BOUNDARY + "\n" + dir + "/" + records[i].id + "\n" + records[i].text + "\n";
        return out;
    }

    function one(id, manifest) {
        return scan([{ id: id, text: JSON.stringify(manifest) }]);
    }

    function barManifest() {
        return { apiVersion: 1, id: "diskwatch", kind: "bar", entry: "DiskWatch.qml" };
    }

    function test_empty_scan_output_is_zero_plugins_zero_warnings() {
        var r = Manifest.resolve("", []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 0);
        var u = Manifest.resolve(undefined, undefined);
        compare(u.plugins.length, 0);
        compare(u.warnings.length, 0);
    }

    function test_scanCommand_argv_shape() {
        var argv = Manifest.scanCommand(dir);
        compare(argv.length, 6);
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        compare(argv[2], Manifest.SCAN_SCRIPT);
        compare(argv[3], "sh");
        compare(argv[4], dir);
        compare(argv[5], Manifest.RECORD_BOUNDARY);
        // The directory only ever arrives as $1: nothing caller-supplied is
        // interpolated into the script text.
        verify(Manifest.SCAN_SCRIPT.indexOf(dir) < 0);
    }

    function test_splitScan_recovers_dir_and_body_per_record() {
        var text = scan([
            { id: "alpha", text: "{\"a\":1}" },
            // Boundary-adjacent text inside the payload must not split it.
            { id: "beta", text: "{\"note\":\"#--formalshell-plugin-boundary\"}" }
        ]);
        var records = Manifest.splitScan(text);
        compare(records.length, 2);
        compare(records[0].id, "alpha");
        compare(records[0].dir, dir + "/alpha");
        compare(JSON.parse(records[0].text).a, 1);
        compare(records[1].id, "beta");
        compare(JSON.parse(records[1].text).note, "#--formalshell-plugin-boundary");
    }

    function test_valid_bar_manifest_defaults() {
        var r = Manifest.resolve(one("diskwatch", barManifest()), []);
        compare(r.warnings.length, 0);
        compare(r.plugins.length, 1);
        var p = r.plugins[0];
        compare(p.id, "diskwatch");
        compare(p.kind, "bar");
        compare(p.name, "diskwatch");
        compare(p.region, "right");
        compare(p.keepLoaded, null);
        compare(p.width, null);
        compare(r.byId["diskwatch"], p);
    }

    function test_valid_panel_manifest_defaults() {
        var r = Manifest.resolve(one("notes", { apiVersion: 1, id: "notes", kind: "panel", entry: "Notes.qml" }), []);
        compare(r.warnings.length, 0);
        var p = r.plugins[0];
        compare(p.keepLoaded, false);
        compare(p.width, "default");
        compare(p.region, null);
    }

    function test_unparsable_json_drops_plugin_with_one_warning() {
        var r = Manifest.resolve(scan([{ id: "broken", text: "{ not json" }]), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("plugins/broken:") === 0);
        verify(r.warnings[0].indexOf("not valid JSON") >= 0);
    }

    function test_json_array_drops_plugin_with_one_warning() {
        var r = Manifest.resolve(scan([{ id: "listy", text: "[]" }]), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("must be a JSON object") >= 0);
    }

    function test_missing_required_key_drops_plugin_with_one_warning() {
        var keys = ["apiVersion", "id", "kind", "entry"];
        for (var i = 0; i < keys.length; i++) {
            var m = barManifest();
            delete m[keys[i]];
            var r = Manifest.resolve(one("diskwatch", m), []);
            compare(r.plugins.length, 0);
            compare(r.warnings.length, 1);
            verify(r.warnings[0].indexOf("missing required key \"" + keys[i] + "\"") >= 0);
        }
    }

    function test_wrong_api_version_drops_plugin_with_one_warning() {
        var m = barManifest();
        m.apiVersion = 2;
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("apiVersion 2 is not supported") >= 0);
    }

    function test_id_must_equal_directory_name() {
        var m = barManifest();
        m.id = "somethingelse";
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("does not match its directory name") >= 0);
    }

    function test_id_with_illegal_characters_drops_plugin() {
        var r = Manifest.resolve(one("Disk Watch", { apiVersion: 1, id: "Disk Watch", kind: "bar", entry: "D.qml" }), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("lowercase letters, digits and dashes") >= 0);
    }

    function test_unknown_kind_drops_plugin_with_one_warning() {
        var m = barManifest();
        m.kind = "shellscript";
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("unknown kind \"shellscript\"") >= 0);
    }

    function test_entry_escaping_plugin_dir_is_rejected() {
        var bad = ["/etc/passwd", "../Other.qml", "sub/../../Other.qml", "..", ""];
        for (var i = 0; i < bad.length; i++) {
            var m = barManifest();
            m.entry = bad[i];
            var r = Manifest.resolve(one("diskwatch", m), []);
            compare(r.plugins.length, 0);
            compare(r.warnings.length, 1);
            verify(r.warnings[0].indexOf("must be a path inside the plugin directory") >= 0);
        }
    }

    function test_entry_with_dots_in_a_filename_is_accepted() {
        var m = barManifest();
        m.entry = "widgets/Disk..Watch.qml";
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.warnings.length, 0);
        compare(r.plugins.length, 1);
    }

    function test_wrong_kind_key_is_dropped_to_default_but_plugin_survives() {
        var cases = [
            { id: "svc", manifest: { apiVersion: 1, id: "svc", kind: "service", entry: "S.qml", region: "left" }, key: "region" },
            { id: "diskwatch", manifest: { apiVersion: 1, id: "diskwatch", kind: "bar", entry: "D.qml", keepLoaded: true }, key: "keepLoaded" },
            { id: "over", manifest: { apiVersion: 1, id: "over", kind: "overlay", entry: "O.qml", width: "wide" }, key: "width" }
        ];
        for (var i = 0; i < cases.length; i++) {
            var r = Manifest.resolve(one(cases[i].id, cases[i].manifest), []);
            compare(r.plugins.length, 1);
            compare(r.warnings.length, 1);
            verify(r.warnings[0].indexOf("\"" + cases[i].key + "\" is not a valid key for kind") >= 0);
        }
        // The offending key never leaks into the resolved shape.
        var svc = Manifest.resolve(one("svc", cases[0].manifest), []).plugins[0];
        compare(svc.region, null);
        var bar = Manifest.resolve(one("diskwatch", cases[1].manifest), []).plugins[0];
        compare(bar.keepLoaded, null);
        var over = Manifest.resolve(one("over", cases[2].manifest), []).plugins[0];
        compare(over.width, null);
    }

    function test_illegal_enum_value_falls_back_with_warning() {
        var m = barManifest();
        m.region = "middle";
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 1);
        compare(r.plugins[0].region, "right");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("unknown region \"middle\"") >= 0);

        var w = Manifest.resolve(one("notes", { apiVersion: 1, id: "notes", kind: "panel", entry: "N.qml", width: "huge" }), []);
        compare(w.plugins.length, 1);
        compare(w.plugins[0].width, "default");
        compare(w.warnings.length, 1);
        verify(w.warnings[0].indexOf("unknown width \"huge\"") >= 0);
    }

    function test_unknown_manifest_key_warns_but_keeps_plugin() {
        var m = barManifest();
        m.enabled = false;
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 1);
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("unknown manifest key \"enabled\"") >= 0);
    }

    function test_name_defaults_to_id_and_a_non_string_warns() {
        var m = barManifest();
        m.name = 7;
        var r = Manifest.resolve(one("diskwatch", m), []);
        compare(r.plugins.length, 1);
        compare(r.plugins[0].name, "diskwatch");
        compare(r.warnings.length, 1);
        verify(r.warnings[0].indexOf("\"name\" must be a non-empty string") >= 0);
    }

    function test_disabled_ids_are_excluded_without_warning() {
        var text = scan([
            { id: "alpha", text: JSON.stringify({ apiVersion: 1, id: "alpha", kind: "bar", entry: "A.qml" }) },
            { id: "beta", text: JSON.stringify({ apiVersion: 1, id: "beta", kind: "bar", entry: "B.qml" }) }
        ]);
        var r = Manifest.resolve(text, ["beta"]);
        compare(r.plugins.length, 1);
        compare(r.plugins[0].id, "alpha");
        verify(r.byId["beta"] === undefined);
        compare(r.warnings.length, 0);
    }

    function test_disabled_id_with_a_broken_manifest_never_warns() {
        var r = Manifest.resolve(scan([{ id: "broken", text: "{ not json" }]), ["broken"]);
        compare(r.plugins.length, 0);
        compare(r.warnings.length, 0);
    }

    function test_entryUrl_is_file_scheme_joined_to_dir() {
        var p = Manifest.resolve(one("diskwatch", barManifest()), []).plugins[0];
        compare(p.entryUrl, "file://" + dir + "/diskwatch/DiskWatch.qml");
        compare(Manifest.entryUrl(p), p.entryUrl);
    }

    function test_surfaceKey_carries_the_plugin_prefix() {
        var p = Manifest.resolve(one("diskwatch", barManifest()), []).plugins[0];
        compare(Manifest.surfaceKey(p), "plugin:diskwatch");
        compare(Manifest.PLUGIN_PREFIX, "plugin:");
    }

    function test_plugins_are_id_sorted() {
        var text = scan([
            { id: "zulu", text: JSON.stringify({ apiVersion: 1, id: "zulu", kind: "bar", entry: "Z.qml" }) },
            { id: "alpha", text: JSON.stringify({ apiVersion: 1, id: "alpha", kind: "bar", entry: "A.qml" }) }
        ]);
        var r = Manifest.resolve(text, []);
        compare(r.plugins.map(function (p) { return p.id; }).join(","), "alpha,zulu");
    }

    function test_selectors_partition_by_kind() {
        var text = scan([
            { id: "b", text: JSON.stringify({ apiVersion: 1, id: "b", kind: "bar", entry: "B.qml" }) },
            { id: "p", text: JSON.stringify({ apiVersion: 1, id: "p", kind: "panel", entry: "P.qml" }) },
            { id: "o", text: JSON.stringify({ apiVersion: 1, id: "o", kind: "overlay", entry: "O.qml" }) },
            { id: "s", text: JSON.stringify({ apiVersion: 1, id: "s", kind: "service", entry: "S.qml" }) }
        ]);
        var all = Manifest.resolve(text, []).plugins;
        compare(all.length, 4);
        compare(Manifest.barPlugins(all).length, 1);
        compare(Manifest.surfacePlugins(all).length, 2);
        compare(Manifest.servicePlugins(all).length, 1);
        compare(Manifest.barPlugins(all).length + Manifest.surfacePlugins(all).length + Manifest.servicePlugins(all).length, all.length);
        compare(Manifest.barPlugins(undefined).length, 0);
    }

    function test_one_broken_plugin_never_drops_its_neighbours() {
        var text = scan([
            { id: "alpha", text: JSON.stringify({ apiVersion: 1, id: "alpha", kind: "bar", entry: "A.qml" }) },
            { id: "broken", text: "{ not json" },
            { id: "zulu", text: JSON.stringify({ apiVersion: 1, id: "zulu", kind: "bar", entry: "Z.qml" }) }
        ]);
        var r = Manifest.resolve(text, []);
        compare(r.plugins.map(function (p) { return p.id; }).join(","), "alpha,zulu");
        compare(r.warnings.length, 1);
    }
}
