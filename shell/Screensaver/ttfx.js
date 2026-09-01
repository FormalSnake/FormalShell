.pragma library

// ttfx (github.com/omacom-io/ttfx, MIT) drives the screensaver's banner
// animation, the same engine omarchy's own screensaver runs, invoked with
// the same shape of arguments (bin/omarchy-screensaver: centered canvas,
// centered text, a random effect, no gradient overrides, so every effect
// paints in its own upstream colors).
//
// Spec addendum, same standing as the `panel` IPC target: §10 says the
// effect is "drawn in QML with the shell's mono font and palette, no
// spawned terminal windows". No terminal window is spawned here and the
// glyphs are still drawn by the shell's own Canvas in the shell's own mono
// font; what moved out of QML is the *frame math*, from effect.js's five
// hand-written effects to ttfx's 37. effect.js stays as the engine for an
// install with no ttfx on PATH, so the pure-QML/JS guarantee still holds
// with nothing installed alongside the shell.
//
// Everything here is a pure function of its arguments, the argv the
// surface spawns and the parse of what comes back, so the wire protocol
// is unit tested rather than only observed in a smoke run.

// `ttfx --help`, ttfx 0.3.0, in its own listed order.
var EFFECT_NAMES = [
    "beams", "binarypath", "blackhole", "bouncyballs", "bubbles", "burn",
    "colorshift", "crumble", "decrypt", "errorcorrect", "expand", "fireworks",
    "highlight", "laseretch", "matrix", "middleout", "orbittingvolley",
    "overflow", "pour", "print", "rain", "randomsequence", "rings",
    "scattered", "slice", "slide", "smoke", "spotlights", "spray", "swarm",
    "sweep", "synthgrid", "thunderstorm", "unstable", "vhstape", "waves",
    "wipe"
];

// The two effects ttfx's own README calls out as gated on wall-clock time
// rather than frame count. Under normal pacing they behave like any other
// effect; at --frame-rate 0 (the deterministic pin path below) they emit as
// many frames as the machine can produce inside that fixed duration, which
// is not reproducible across hosts, so they are never recorded frame by
// frame.
var TIMED_EFFECTS = ["matrix", "thunderstorm"];

// A pinned (frame-stepped) run re-generates the effect from scratch and
// counts frames until it reaches the requested one, so a single pathological
// run can't stream unbounded output into the shell. 600 frames is ~10s of
// animation at 60fps, past the end of every effect that isn't wall-clock
// gated, at this surface's canvas size.
var PIN_FRAME_CAP = 600;

function isKnownEffect(name) {
    return EFFECT_NAMES.indexOf(name) >= 0;
}

function isTimedEffect(name) {
    return TIMED_EFFECTS.indexOf(name) >= 0;
}

// Same contract effect.js's own rerollEffectName has, over ttfx's pool: a
// known (pinned) name replays itself, anything else, "random", the default,
// or an unrecognised name, picks from every effect except the immediately
// previous one, so consecutive cycles never repeat.
function rerollEffectName(requested, previousEffect, seed) {
    if (isKnownEffect(requested))
        return requested;
    var pool = [];
    for (var i = 0; i < EFFECT_NAMES.length; i++) {
        if (EFFECT_NAMES[i] !== previousEffect)
            pool.push(EFFECT_NAMES[i]);
    }
    return pool[Math.abs(seed) % pool.length];
}

// ---- wire protocol -------------------------------------------------------
// ttfx writes one full canvas repaint per frame to stdout: `rows` lines of
// `columns` cells, separated by \n, with truecolor SGR runs inside them.
// Between two frames it emits restore-cursor, save-cursor, cursor-up-rows,
// which is the only byte sequence that can't occur inside a frame, so it is
// what Quickshell's SplitParser splits on. (Verified against ttfx 0.3.0's
// real output, not assumed: the complete escape vocabulary it emits is
// ESC7, ESC8, ESC[<rows>A, ESC[0m, ESC[38;2;R;G;Bm and the ESC[?25l/h
// cursor-visibility pair. No background colors, no cursor addressing.)
function frameDelimiter(rows) {
    return "\u001b8\u001b7\u001b[" + rows + "A";
}

// The ttfx flags for one run. Deliberately omarchy's own set
// (bin/omarchy-screensaver) apart from the three things a pipe forces:
//
//   --ignore-terminal-dimensions   there is no tty on the other end of this
//     pipe, so without it ttfx measures nothing and silently falls back to
//     80x24 no matter what --canvas-width/height say (confirmed against the
//     binary, omarchy doesn't need it because it really is inside a
//     terminal, and passes --canvas-width 0 to mean "measure it").
//   --terminal-background-color    ttfx blends against it; the caller
//     passes the same black omarchy's screensaver terminal is pinned to,
//     which is what every upstream effect gradient is authored against.
//   --seed                         a pinned/recorded run has to replay
//     identically; a live run gets the activation's own seed so successive
//     cycles of the same effect don't animate identically.
//
// No gradient overrides, exactly like omarchy: each effect brings its own
// upstream colors, which is where the per-cycle color change comes from.
function args(opts) {
    return [
        "-i", opts.bannerPath,
        "--canvas-width", String(opts.columns),
        "--canvas-height", String(opts.rows),
        "--anchor-canvas", "c",
        "--anchor-text", "c",
        "--ignore-terminal-dimensions",
        "--frame-rate", String(opts.frameRate),
        "--terminal-background-color", normalizeColor(opts.background),
        "--seed", String(Math.abs(opts.seed) % 2147483647),
        opts.effect
    ];
}

// QML stringifies an opaque color as #rrggbb but a translucent one as
// #aarrggbb, which ttfx rejects outright (exit 2, no frames at all). The
// background this surface paints is opaque today; dropping the alpha here
// means a theme that ever stops being opaque degrades to the wrong blend
// rather than to no screensaver.
function normalizeColor(value) {
    var text = String(value || "");
    if (/^#[0-9a-fA-F]{8}$/.test(text))
        return "#" + text.slice(3);
    return /^#[0-9a-fA-F]{6}$/.test(text) ? text : "#000000";
}

// Wrapped in the same `command -v` guard VisualizerService uses for cava:
// defense in depth against ttfx vanishing from PATH between the shell's
// startup probe and a real activation, and the reason a missing binary
// surfaces as exit 127 rather than a Process error with no exit code.
function command(opts) {
    return ["sh", "-c", 'command -v ttfx >/dev/null 2>&1 || exit 127; exec ttfx "$@"', "sh"].concat(args(opts));
}

// ---- frame parsing -------------------------------------------------------
// One frame's text -> rows of { col, color, text } runs, where color is ""
// for ttfx's default foreground (an SGR reset) and "#rrggbb" otherwise.
// Runs, not cells: consecutive characters sharing a color are one fillText
// call in the surface's Canvas, which is what keeps a dense effect (beams
// colors every cell it touches) inside a frame budget.
function parseFrame(text) {
    var rows = [];
    var runs = [];
    var run = null;
    var col = 0;
    var color = "";
    var i = 0;

    function flush() {
        if (run !== null && run.text.length > 0)
            runs.push(run);
        run = null;
    }

    while (i < text.length) {
        var ch = text.charAt(i);
        if (ch === "\u001b") {
            var esc = _readEscape(text, i);
            i = esc.next;
            if (esc.color !== null) {
                flush();
                color = esc.color;
            }
            continue;
        }
        if (ch === "\n") {
            flush();
            rows.push(runs);
            runs = [];
            col = 0;
            i++;
            continue;
        }
        if (ch === "\r") {
            i++;
            continue;
        }
        if (run === null)
            run = { col: col, color: color, text: "" };
        run.text += ch;
        col++;
        i++;
    }
    flush();
    rows.push(runs);
    return rows;
}

// Returns { next, color }: the index just past the escape sequence, and the
// color it selects, null when the sequence doesn't change the color (a
// cursor move, the show/hide-cursor pair, an SGR this doesn't model).
function _readEscape(text, start) {
    if (text.charAt(start + 1) !== "[")
        return { next: start + 2, color: null }; // ESC7 / ESC8 and friends
    var i = start + 2;
    while (i < text.length && "0123456789;?".indexOf(text.charAt(i)) >= 0)
        i++;
    var final = text.charAt(i);
    var params = text.slice(start + 2, i);
    var next = i + 1;
    if (final !== "m")
        return { next: next, color: null };
    if (params === "" || params === "0" || params === "39")
        return { next: next, color: "" };
    var parts = params.split(";");
    if (parts.length === 5 && parts[0] === "38" && parts[1] === "2")
        return { next: next, color: _hex(parts[2], parts[3], parts[4]) };
    return { next: next, color: null };
}

function _hex(r, g, b) {
    return "#" + _byte(r) + _byte(g) + _byte(b);
}

function _byte(value) {
    var n = Math.max(0, Math.min(255, parseInt(value, 10) || 0));
    return (n < 16 ? "0" : "") + n.toString(16);
}

// Flattens a parsed frame back to plain per-row strings, the shape tests
// assert content against, and the only thing that needs a run's `col` to be
// honoured rather than assumed contiguous.
function rowsToText(rows) {
    var out = [];
    for (var r = 0; r < rows.length; r++) {
        var line = "";
        var runs = rows[r];
        for (var i = 0; i < runs.length; i++) {
            while (line.length < runs[i].col)
                line += " ";
            line += runs[i].text;
        }
        out.push(line);
    }
    return out;
}
