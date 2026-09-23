import QtQuick
import QtTest
import "../shell/Visualizer/styles.js" as Styles
import "../shell/Visualizer/model.js" as Model

TestCase {
    name: "VisualizerStyles"

    readonly property real boxW: 94
    readonly property real boxH: 32
    readonly property var ink: ({
            groove: "#111111", dim: "#555555", content: "#eeeeee", accent: "#ff8800",
            mono: "monospace", columns: 12, gap: 2, radius: 4
        })

    // Records every coordinate a style hands the context. Only the calls
    // listed here exist, so a style reaching for anything else throws.
    function mockContext() {
        var points = [];
        function pt(x, y, what) {
            points.push({ x: x, y: y, what: what });
        }
        return {
            points: points,
            fillStyle: "", strokeStyle: "", lineWidth: 1, globalAlpha: 1,
            font: "", textBaseline: "", textAlign: "",
            beginPath: function () {},
            closePath: function () {},
            fill: function () {},
            stroke: function () {},
            moveTo: function (x, y) { pt(x, y, "moveTo"); },
            lineTo: function (x, y) { pt(x, y, "lineTo"); },
            quadraticCurveTo: function (cx, cy, x, y) { pt(cx, cy, "quadCtl"); pt(x, y, "quadTo"); },
            fills: [],
            fillRect: function (x, y, w, h) {
                this.fills.push(this.fillStyle);
                pt(x, y, "fillRect");
                pt(x + w, y + h, "fillRect end");
            },
            roundedRect: function (x, y, w, h) { pt(x, y, "roundedRect"); pt(x + w, y + h, "roundedRect end"); },
            arc: function (x, y, r) { pt(x - r, y - r, "arc"); pt(x + r, y + r, "arc end"); },
            fillText: function (text, x, y) {
                if (typeof text !== "string" || text.length === 0)
                    throw new Error("fillText without a glyph");
                pt(x, y, "fillText");
            }
        };
    }

    function frame(value) {
        var out = [];
        for (var i = 0; i < Model.BAR_COUNT; i++)
            out.push(typeof value === "function" ? value(i) : value);
        return out;
    }

    function checkInside(id, label, ctx) {
        var eps = 0.001;
        for (var i = 0; i < ctx.points.length; i++) {
            var p = ctx.points[i];
            verify(isFinite(p.x) && isFinite(p.y), id + " " + label + ": non-finite " + p.what + " " + p.x + "," + p.y);
            verify(p.x >= -eps && p.x <= boxW + eps && p.y >= -eps && p.y <= boxH + eps,
                id + " " + label + ": " + p.what + " outside the box at " + p.x + "," + p.y);
        }
        compare(ctx.globalAlpha, 1, id + " " + label + " leaves globalAlpha at 1");
    }

    function test_ids_are_unique_and_start_with_bars() {
        var ids = Styles.ids();
        compare(ids[0], "bars");
        verify(ids.length >= 31);
        var seen = {};
        for (var i = 0; i < ids.length; i++) {
            verify(!seen[ids[i]], "duplicate id " + ids[i]);
            seen[ids[i]] = true;
            verify(Styles.STYLES[i].label.length > 0);
            verify(Styles.STYLES[i].description.length > 0);
        }
    }

    function test_step_wraps_both_ways() {
        var ids = Styles.ids();
        compare(Styles.step("bars", 1), ids[1]);
        compare(Styles.step("bars", -1), ids[ids.length - 1]);
        compare(Styles.step(ids[ids.length - 1], 1), "bars");
        compare(Styles.step("nope", 1), ids[1]);
    }

    function test_unknown_id_is_not_known() {
        verify(!Styles.isKnown("nope"));
        verify(Styles.isKnown("peaks"));
    }

    function test_every_style_stays_inside_the_box() {
        var inputs = [
            { label: "silence", levels: frame(0) },
            { label: "flat loud", levels: frame(1) },
            { label: "ramp", levels: frame(function (i) { return i / (Model.BAR_COUNT - 1); }) },
            { label: "garbage", levels: frame(function (i) { return i % 3 === 0 ? NaN : i % 3 === 1 ? 3 : -1; }) }
        ];
        var steps = [0, 0.016, 0.016, 0.05, 0.5, 0.016];
        var ids = Styles.ids();
        for (var s = 0; s < ids.length; s++) {
            for (var k = 0; k < inputs.length; k++) {
                var state = Styles.freshState();
                var t = 0;
                // Several frames loud, then the input under test, so falling
                // caps and live particles are exercised on the way down too.
                for (var warm = 0; warm < 20; warm++) {
                    var wctx = mockContext();
                    t += 0.016;
                    Styles.draw(ids[s], wctx, boxW, boxH, frame(1), state, ink, 0.016, t);
                    checkInside(ids[s], "warm-up", wctx);
                }
                for (var j = 0; j < steps.length; j++) {
                    var ctx = mockContext();
                    t += steps[j];
                    Styles.draw(ids[s], ctx, boxW, boxH, inputs[k].levels, state, ink, steps[j], t);
                    checkInside(ids[s], inputs[k].label, ctx);
                }
            }
        }
    }

    function test_silence_from_a_fresh_state_draws_something_still() {
        var ids = Styles.ids();
        for (var s = 0; s < ids.length; s++) {
            var state = Styles.freshState();
            var a = mockContext();
            Styles.draw(ids[s], a, boxW, boxH, frame(0), state, ink, 0.016, 0);
            var b = mockContext();
            Styles.draw(ids[s], b, boxW, boxH, frame(0), state, ink, 0.016, 0.016);
            verify(a.points.length > 0, ids[s] + " draws a resting state");
            compare(JSON.stringify(b.points), JSON.stringify(a.points), ids[s] + " does not move in silence");
        }
    }

    // An id with no drawing function would fall back to bars unnoticed.
    function test_every_id_has_its_own_drawing() {
        var ids = Styles.ids();
        for (var i = 0; i < ids.length; i++)
            verify(Styles.DRAW.hasOwnProperty(ids[i]), ids[i] + " has no entry in DRAW");
    }

    function test_stereo_draws_each_channel_on_its_own() {
        var loud = frame(0.9);
        var quiet = frame(0.1);
        var a = mockContext();
        Styles.draw("stereo", a, boxW, boxH, loud, Styles.freshState(), ink, 0.016, 0, loud, quiet);
        var b = mockContext();
        Styles.draw("stereo", b, boxW, boxH, loud, Styles.freshState(), ink, 0.016, 0, quiet, loud);
        var c = mockContext();
        Styles.draw("stereo", c, boxW, boxH, loud, Styles.freshState(), ink, 0.016, 0);
        checkInside("stereo", "split", a);
        verify(JSON.stringify(a.fills) !== JSON.stringify(b.fills), "swapping the channels changes the meters");
        verify(JSON.stringify(a.fills) !== JSON.stringify(c.fills), "a missing channel pair falls back to the mix");
    }

    function test_unknown_style_draws_bars() {
        var a = mockContext();
        Styles.draw("nope", a, boxW, boxH, frame(0.5), Styles.freshState(), ink, 0, 0);
        var b = mockContext();
        Styles.draw("bars", b, boxW, boxH, frame(0.5), Styles.freshState(), ink, 0, 0);
        compare(JSON.stringify(a.points), JSON.stringify(b.points));
    }
}
