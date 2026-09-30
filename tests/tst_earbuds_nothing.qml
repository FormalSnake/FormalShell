import QtQuick
import QtTest
import "../shell/Earbuds/nothing.js" as Nothing
import "../shell/Earbuds/model.js" as Model

TestCase {
    name: "EarbudsNothing"

    // Fixtures follow nothingctl v0.1.0's own serialisation: the state line
    // is src/protocol/state.rs:178-192 (`Snapshot`, camelCase, serde_json
    // field order) filled the way snapshot() at :194-220 fills it for the
    // B175 table in src/protocol/model.rs:134-193; `ack` and `error` are
    // src/session.rs:193-196, `disconnected` src/main.rs:177, and a `list
    // --json` row src/transport/mod.rs:17-22. `eq.custom` is an f32 array,
    // which serde_json prints with a fractional part.

    property string b175: "{\"type\":\"state\",\"address\":\"AA:BB:CC:DD:EE:FF\",\"name\":\"CMF Headphone Pro\",\"model\":{\"base\":\"B175\",\"name\":\"CMF Headphone Pro\",\"kind\":\"headphone\"},\"firmware\":\"1.0.1.52\",\"battery\":[{\"id\":\"single\",\"level\":80,\"charging\":false}],\"anc\":{\"mode\":\"high\",\"available\":[\"off\",\"transparency\",\"high\",\"mid\",\"low\",\"adaptive\"]},\"eq\":{\"preset\":\"rock\",\"available\":[\"rock\",\"electronic\",\"pop\",\"vocals\",\"classical\",\"custom\"],\"custom\":null},\"lowLatency\":false,\"spatial\":{\"mode\":\"off\",\"available\":[\"off\",\"concert\",\"theatre\"]}}"

    property string b175Custom: "{\"type\":\"state\",\"address\":\"aa:bb:cc:dd:ee:ff\",\"name\":\"\",\"model\":{\"base\":\"B175\",\"name\":\"CMF Headphone Pro\",\"kind\":\"headphone\"},\"firmware\":\"1.0.1.52\",\"battery\":[{\"id\":\"single\",\"level\":35,\"charging\":true}],\"anc\":{\"mode\":\"adaptive\",\"available\":[\"off\",\"transparency\",\"high\",\"mid\",\"low\",\"adaptive\"]},\"eq\":{\"preset\":\"custom\",\"available\":[\"rock\",\"electronic\",\"pop\",\"vocals\",\"classical\",\"custom\"],\"custom\":[3.0,0.0,-2.0]},\"lowLatency\":true,\"spatial\":{\"mode\":\"theatre\",\"available\":[\"off\",\"concert\",\"theatre\"]}}"

    // Right after connect, before any reply: every value null, the model's
    // lists still present.
    property string b175Early: "{\"type\":\"state\",\"address\":\"AA:BB:CC:DD:EE:FF\",\"name\":\"CMF Headphone Pro\",\"model\":{\"base\":\"B175\",\"name\":\"CMF Headphone Pro\",\"kind\":\"headphone\"},\"firmware\":null,\"battery\":[],\"anc\":{\"mode\":null,\"available\":[\"off\",\"transparency\",\"high\",\"mid\",\"low\",\"adaptive\"]},\"eq\":{\"preset\":\"dirac\",\"available\":[\"rock\",\"electronic\",\"pop\",\"vocals\",\"classical\",\"custom\"],\"custom\":null},\"lowLatency\":null,\"spatial\":{\"mode\":null,\"available\":[\"off\",\"concert\",\"theatre\"]}}"

    function state(line) {
        return Nothing.parseLine(line).state;
    }

    function keys(list, field) {
        return list.map(function (x) { return x[field]; }).join(",");
    }

    function test_parse_line_types() {
        var s = Nothing.parseLine(b175);
        compare(s.type, "state");
        compare(s.state.address, "AA:BB:CC:DD:EE:FF");
        compare(s.state.model.base, "B175");
        compare(Nothing.parseLine("{\"cmd\":\"anc high\",\"type\":\"ack\"}").cmd, "anc high");
        compare(Nothing.parseLine("{\"message\":\"write failed: broken pipe\",\"type\":\"error\"}").message, "write failed: broken pipe");
        compare(Nothing.parseLine("{\"type\":\"disconnected\"}").type, "disconnected");
    }

    // nothingctl v0.1.1's refusal line, src/main.rs `unsupported_line`.
    function test_unsupported_model_line() {
        var e = Nothing.parseLine("{\"type\":\"error\",\"code\":\"unsupported-model\",\"modelId\":\"ABCDEF\",\"message\":\"model id ABCDEF on AA:BB:CC:DD:EE:FF is not supported (supported: B175 CMF Headphone Pro); nothing was sent\"}");
        compare(e.type, "error");
        compare(e.code, Nothing.UNSUPPORTED);
        compare(e.modelId, "ABCDEF");
        compare(Nothing.parseLine("{\"type\":\"error\",\"code\":\"unsupported-model\",\"modelId\":null,\"message\":\"x\"}").modelId, null);
        compare(Nothing.parseLine("{\"type\":\"error\",\"message\":\"write failed\"}").code, "");
        compare(Nothing.UNSUPPORTED_EXIT, 3);
    }

    function test_rearm_needs_a_disconnect_then_a_connect() {
        var a = "AA:BB:CC:DD:EE:FF";
        var marks = {};
        marks[a] = { seenDown: false };
        marks = Nothing.rearm(marks, [a]);
        compare(marks[a].seenDown, false);
        marks = Nothing.rearm(marks, []);
        compare(marks[a].seenDown, true);
        marks = Nothing.rearm(marks, []);
        compare(marks[a].seenDown, true);
        marks = Nothing.rearm(marks, [a]);
        compare(marks[a], undefined);
    }

    function test_custom_bands_read_in_db() {
        var bass = Model.control(Nothing.normalise(state(b175Custom), ""), "eq-bass");
        compare(bass.unit, "db");
        compare(Model.rangeText(bass), "+3\u00a0dB");
        compare(Model.rangeFraction(bass), 0.75);
    }

    function test_parse_line_garbage() {
        compare(Nothing.parseLine(""), null);
        compare(Nothing.parseLine("error: no Nothing device is connected"), null);
        compare(Nothing.parseLine("{\"type\":\"state\""), null);
        compare(Nothing.parseLine("[1,2]"), null);
        compare(Nothing.parseLine("null"), null);
        compare(Nothing.parseLine("{\"type\":\"reboot\"}"), null);
        compare(Nothing.parseLine("{\"type\":\"state\",\"address\":\"; rm -rf\",\"model\":{\"base\":\"B175\"}}"), null);
        compare(Nothing.parseLine("{\"type\":\"state\",\"address\":\"AA:BB:CC:DD:EE:FF\"}"), null);
    }

    function test_list() {
        var l = Nothing.parseList("[{\"address\":\"AA:BB:CC:DD:EE:FF\",\"name\":\"CMF Headphone Pro\",\"connected\":true},{\"address\":\"11:22:33:44:55:66\",\"name\":\"Ear (2)\",\"connected\":false},{\"address\":\"-d x\",\"name\":\"x\",\"connected\":true}]");
        compare(l.length, 2);
        compare(l[0].connected, true);
        compare(l[1].connected, false);
        compare(Nothing.parseList("error: cannot reach BlueZ").length, 0);
        compare(Nothing.watchArgv("AA:BB:CC:DD:EE:FF").join(" "), "nothingctl watch -d AA:BB:CC:DD:EE:FF");
        compare(Nothing.watchArgv("AA:BB --dry-run").length, 0);
    }

    function test_normalise_b175() {
        var dev = Nothing.normalise(state(b175), "");
        compare(dev.key, "nothing:AA:BB:CC:DD:EE:FF");
        compare(dev.backend, "nothing");
        compare(dev.kind, "headphone");
        compare(dev.name, "CMF Headphone Pro");
        compare(dev.batteries.length, 1);
        compare(dev.batteries[0].id, "single");
        compare(dev.batteries[0].level, 80);
        compare(Model.worstLevel(dev), 80);
        compare(keys(dev.controls, "key"), "anc,eq,spatial,low-latency");
        var anc = Model.control(dev, "anc");
        compare(keys(anc.options, "value"), "off,transparency,high,mid,low,adaptive");
        compare(anc.value, "high");
        compare(Model.control(dev, "eq").value, "rock");
        compare(keys(Model.control(dev, "eq").options, "label"), "Rock,Electronic,Pop,Vocals,Classical,Custom");
        compare(Model.control(dev, "spatial").value, "off");
        compare(Model.control(dev, "low-latency").value, false);
        compare(dev.stateLine, "High noise cancellation");
    }

    function test_normalise_custom_eq_bands() {
        var dev = Nothing.normalise(state(b175Custom), "");
        compare(dev.address, "AA:BB:CC:DD:EE:FF");
        compare(dev.name, "CMF Headphone Pro");
        compare(keys(dev.controls, "key"), "anc,eq,eq-bass,eq-mid,eq-treble,spatial,low-latency");
        var bass = Model.control(dev, "eq-bass");
        compare(bass.kind, "range");
        compare(bass.value, 3);
        compare(bass.min, -6);
        compare(bass.max, 6);
        compare(Model.control(dev, "eq-treble").value, -2);
        compare(dev.batteries[0].charging, true);
        compare(dev.stateLine, "Adaptive");
        compare(Nothing.normalise(state(b175Custom), Nothing.FAILED).stateLine, Nothing.FAILED);
    }

    function test_normalise_before_replies() {
        var dev = Nothing.normalise(state(b175Early), "");
        compare(dev.batteries.length, 0);
        compare(Model.control(dev, "anc").value, null);
        // dirac is decoded but not offered, so no option is selected.
        compare(Model.control(dev, "eq").value, null);
        compare(Model.control(dev, "low-latency"), null);
        compare(dev.stateLine, "");
    }

    function test_unknown_model_has_no_custom_bands() {
        var s = state(b175Custom);
        s.model.base = "B999";
        compare(Model.control(Nothing.normalise(s, ""), "eq-bass"), null);
        compare(Nothing.command("eq-bass", 1, s), "");
    }

    function test_commands() {
        var s = state(b175);
        compare(Nothing.command("anc", "transparency", s), "anc transparency");
        compare(Nothing.command("eq", "classical", s), "eq classical");
        compare(Nothing.command("spatial", "concert", s), "spatial concert");
        compare(Nothing.command("low-latency", true, s), "low-latency on");
        compare(Nothing.command("low-latency", false, s), "low-latency off");
        var c = state(b175Custom);
        compare(Nothing.command("eq-mid", 4, c), "eq-custom 3 4 -2");
        compare(Nothing.command("eq-bass", -6, c), "eq-custom -6 0 -2");
    }

    function test_command_refusals() {
        var s = state(b175);
        compare(Nothing.command("anc", "high", null), "");
        compare(Nothing.command("rename", "x", s), "");
        compare(Nothing.command("firmware", "update", s), "");
        compare(Nothing.command("eq-custom", "1 1 1", s), "");
        compare(Nothing.command("anc", "loud", s), "");
        compare(Nothing.command("eq", "dirac", s), "");
        compare(Nothing.command("spatial", "on", s), "");
        compare(Nothing.command("low-latency", "on", s), "");
        compare(Nothing.command("anc", "high\nset -d 11:22:33:44:55:66 anc off", s), "");
        compare(Nothing.command("anc", "high ", s), "");
        compare(Nothing.command("anc", ["high"], s), "");
        compare(Nothing.command("eq", "rock\n", s), "");
        // Custom bands only exist while the custom preset is on.
        compare(Nothing.command("eq-bass", 2, s), "");
        var c = state(b175Custom);
        compare(Nothing.command("eq-bass", 7, c), "");
        compare(Nothing.command("eq-bass", 1.5, c), "");
        compare(Nothing.command("eq-bass", "2", c), "");
        compare(Nothing.command("eq-bass", "2\nanc off", c), "");
    }

    function test_injected_available_list_is_not_trusted() {
        var s = state(b175);
        s.anc.available.push("high\nspatial off");
        compare(Nothing.command("anc", "high\nspatial off", s), "");
        var raw = JSON.parse(b175);
        raw.anc.available.push("off anc high");
        var parsed = Nothing.parseLine(JSON.stringify(raw)).state;
        compare(parsed.anc.available.indexOf("off anc high"), -1);
    }
}
