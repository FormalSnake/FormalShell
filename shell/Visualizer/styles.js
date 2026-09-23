.pragma library
.import "model.js" as Model

// The media panel's spectrum styles (M73), drawn by VisualizerCanvas.qml
// into the box twelve spectrum columns occupy (~94x32 at the shipped
// tokens). Every style reads `levels` (VisualizerService.levels, 0..1 per
// cava band) and nothing else: a silent frame draws the style's resting
// state, and anything that moves over time (a falling cap, a particle, a
// scrolling trace) is only ever set moving by a level.
//
// `state` belongs to one renderer and is thrown away when the style
// changes or cava stops, so every buffer here is created lazily on it and
// reused on every later frame. `dt` is 0 on a repaint that is not a new
// frame (a colour change, a resize): a style then redraws what it has
// without advancing or spawning anything.
//
// `ink`: `groove`, `dim`, `content`, `accent` (colours), `mono` (font
// family), `columns`, `gap`, `radius`.
//
// `left` and `right` are the same bands per channel. Only `stereo` reads
// them, and it falls back to `levels` for both when they are missing.

var STYLES = [
    { id: "bars", label: "Bars", description: "Twelve columns filled from the floor, the default." },
    { id: "peaks", label: "Peaks", description: "Thin columns under falling peak caps, Winamp's classic analyser." },
    { id: "led", label: "LED", description: "Segmented LED columns with a lit peak segment, Winamp 2's matrix." },
    { id: "mirror", label: "Mirror", description: "Columns grown both ways from the horizontal centre." },
    { id: "butterfly", label: "Butterfly", description: "Bass in the middle, mirrored out to both edges." },
    { id: "outline", label: "Outline", description: "The column tops alone, joined into one stepped line." },
    { id: "wave", label: "Wave", description: "A filled curve through every band." },
    { id: "dots", label: "Dots", description: "A stippled dot grid, one column per band, lit to its level." },
    { id: "ascii", label: "ASCII", description: "Shade glyphs stacked in the mono font." },
    { id: "matrix", label: "Matrix", description: "Mono glyphs falling down each column as fast as it is loud." },
    { id: "rain", label: "Rain", description: "Droplets falling from each column's top, as many as it is loud." },
    { id: "flame", label: "Flame", description: "Flickering tips and embers rising off the columns." },
    { id: "bubbles", label: "Bubbles", description: "Rings rising off the loudest bands, faster with more energy." },
    { id: "scope", label: "Scope", description: "An oscilloscope trace, synthesised by summing one sine per band." },
    { id: "pulse", label: "Pulse", description: "A disc breathing on the bass, a ring on the mids, flares on the highs." },
    { id: "heartbeat", label: "Heartbeat", description: "An ECG trace that beats on every bass onset." },
    { id: "terrain", label: "Terrain", description: "A scrolling ridge of recent loudness over the bass." },
    { id: "bricks", label: "Bricks", description: "Columns stacked from separate bricks, nothing drawn above the stack." },
    { id: "columns", label: "Columns", description: "Dense one-pixel columns, the bands interpolated between them." },
    { id: "scatter", label: "Scatter", description: "Sparkling dots, denser low down and on the loud bands." },
    { id: "retro", label: "Retro", description: "A synthwave sun over a perspective grid, the spectrum on the horizon." },
    { id: "binary", label: "Binary", description: "Streams of 0s and 1s, faster and busier on the loud bands." },
    { id: "sakura", label: "Sakura", description: "Petals drifting down, more of them and faster with more energy." },
    { id: "firework", label: "Firework", description: "Rockets bursting into falling sparks, one on every bass hit." },
    { id: "firefly", label: "Firefly", description: "Fireflies over a strip of grass, blinking on the highs." },
    { id: "mosaic", label: "Mosaic", description: "A fixed grid of tiles, each lit by its own band past its own threshold." },
    { id: "sand", label: "Sand", description: "Grains poured by each band, piling up until a bass hit drains the bed." },
    { id: "geyser", label: "Geyser", description: "A fountain fed by the bass, a burst shot up on every hit." },
    { id: "stereo", label: "Stereo", description: "Left and right LED meters with a falling peak segment." },
    { id: "redsector", label: "Red Sector", description: "A tumbling wireframe equalizer over a starfield, after the 1989 Amiga demo." },
    { id: "stipple", label: "Stipple", description: "Fine dot columns, shaded by height rather than by level." }
];

function indexOf(id) {
    for (var i = 0; i < STYLES.length; i++) {
        if (STYLES[i].id === id)
            return i;
    }
    return -1;
}

function isKnown(id) {
    return indexOf(id) >= 0;
}

function ids() {
    var out = [];
    for (var i = 0; i < STYLES.length; i++)
        out.push(STYLES[i].id);
    return out;
}

function label(id) {
    var i = indexOf(id);
    return i >= 0 ? STYLES[i].label : STYLES[0].label;
}

// `delta` steps through the cycle order and wraps; an unknown `id` steps
// from bars.
function step(id, delta) {
    var i = Math.max(0, indexOf(id));
    var n = STYLES.length;
    return STYLES[(((i + delta) % n) + n) % n].id;
}

function freshState() {
    return {};
}

// Frames past this are a stall (a hidden window, a suspended session), and
// stepping a whole stall at once would drop every particle and cap at once.
var MAX_DT = 0.1;

function draw(id, ctx, w, h, levels, state, ink, dt, t, left, right) {
    var fn = DRAW.hasOwnProperty(id) ? DRAW[id] : DRAW.bars;
    var frame = (typeof dt === "number" && isFinite(dt) && dt > 0) ? Math.min(dt, MAX_DT) : 0;
    if (!(w > 0) || !(h > 0))
        return;
    var lv = levels || [];
    fn(ctx, w, h, lv, state, ink, frame, t || 0, left || lv, right || lv);
    ctx.globalAlpha = 1;
}

function _buf(state, key, n, fill) {
    var b = state[key];
    if (!b || b.length !== n) {
        b = new Array(n);
        for (var i = 0; i < n; i++)
            b[i] = fill === undefined ? 0 : fill;
        state[key] = b;
    }
    return b;
}

// Peak of each contiguous group, like Model.downsample, written into `out`
// so no frame allocates, and clamped so a malformed level cannot draw
// outside the box.
function _fold(levels, count, out) {
    var len = levels.length;
    var base = Math.floor(len / count);
    var rem = len % count;
    var idx = 0;
    for (var g = 0; g < count; g++) {
        var size = base + (g < rem ? 1 : 0);
        var peak = 0;
        for (var j = 0; j < size; j++) {
            var v = +levels[idx + j];
            if (v > peak)
                peak = v;
        }
        idx += size;
        out[g] = peak > 1 ? 1 : peak;
    }
    return out;
}

function _levels(state, levels, count, key) {
    return _fold(levels, count, _buf(state, key || ("fold" + count), count));
}

function _band(ink, l) {
    return ink[Model.levelColorBand(l)];
}

function _colWidth(w, count, gap) {
    return (w - (count - 1) * gap) / count;
}

function _clamp(v, lo, hi) {
    return v < lo ? lo : v > hi ? hi : v;
}

function _pill(ctx, x, y, cw, ch, r) {
    if (!(ch > 0) || !(cw > 0))
        return;
    var rr = Math.min(r, cw / 2, ch / 2);
    ctx.beginPath();
    ctx.roundedRect(x, y, cw, ch, rr, rr);
    ctx.fill();
}

function _max(a, from, to) {
    var m = 0;
    for (var i = from; i < to; i++) {
        if (a[i] > m)
            m = a[i];
    }
    return m;
}

// The Winamp cap: it rides a rising column, holds at the top, then falls
// under gravity until it lands on the column again.
var CAP_HOLD_SECONDS = 0.3;
var CAP_GRAVITY = 2.6;

function _caps(state, lv, n, dt) {
    var pos = _buf(state, "capPos", n);
    var hold = _buf(state, "capHold", n);
    var vel = _buf(state, "capVel", n);
    for (var i = 0; i < n; i++) {
        var l = lv[i];
        if (l >= pos[i]) {
            pos[i] = l;
            hold[i] = CAP_HOLD_SECONDS;
            vel[i] = 0;
        } else if (hold[i] > 0) {
            hold[i] = Math.max(0, hold[i] - dt);
        } else {
            vel[i] += CAP_GRAVITY * dt;
            pos[i] = Math.max(l, pos[i] - vel[i] * dt);
        }
    }
    return pos;
}

// A fixed pool per style: a spawn with every slot taken is dropped, so a
// loud passage can never grow the work a frame does.
function _pool(state, size) {
    if (!state.pool) {
        state.pool = {
            alive: _buf(state, "pAlive", size, false),
            x: _buf(state, "pX", size), y: _buf(state, "pY", size),
            v: _buf(state, "pV", size), r: _buf(state, "pR", size),
            a: _buf(state, "pA", size), c: _buf(state, "pC", size)
        };
    }
    return state.pool;
}

function _spawnSlot(pool) {
    for (var i = 0; i < pool.alive.length; i++) {
        if (!pool.alive[i])
            return i;
    }
    return -1;
}

// A per-style ring buffer of one value per sample, oldest first on read.
function _history(state, n) {
    if (!state.hist || state.hist.v.length !== n)
        state.hist = { v: _buf(state, "hV", n), w: _buf(state, "hW", n), head: 0, acc: 0 };
    return state.hist;
}

function _push(hist, v, w) {
    hist.v[hist.head] = v;
    hist.w[hist.head] = w;
    hist.head = (hist.head + 1) % hist.v.length;
}

function _floorLine(ctx, w, h, ink) {
    ctx.fillStyle = ink.groove;
    ctx.fillRect(0, h - 1, w, 1);
}

function bars(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var r = Math.min(ink.radius, cw / 2);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        ctx.fillStyle = ink.groove;
        _pill(ctx, x, 0, cw, h, r);
        var l = lv[i];
        if (l > 0) {
            var fh = Math.min(h, Math.max(h * l, r * 2));
            ctx.fillStyle = _band(ink, l);
            _pill(ctx, x, h - fh, cw, fh, r);
        }
    }
}

function peaks(ctx, w, h, levels, state, ink, dt) {
    var n = levels.length > 0 ? Math.min(levels.length, 24) : 24;
    var lv = _levels(state, levels, n);
    var caps = _caps(state, lv, n, dt);
    var cw = _colWidth(w, n, ink.gap);
    var capH = 2;
    var usable = h - capH - 1;
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var l = lv[i];
        if (l > 0) {
            var bh = l * usable;
            ctx.fillStyle = _band(ink, l);
            ctx.fillRect(x, h - bh, cw, bh);
        }
        ctx.fillStyle = caps[i] > 0.02 ? ink.accent : ink.groove;
        ctx.fillRect(x, h - caps[i] * usable - 1 - capH, cw, capH);
    }
}

function led(ctx, w, h, levels, state, ink, dt) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var caps = _caps(state, lv, n, dt);
    var cw = _colWidth(w, n, ink.gap);
    var segH = 2;
    var gapY = 1;
    var segs = Math.max(1, Math.floor((h + gapY) / (segH + gapY)));
    var top = h - (segs * (segH + gapY) - gapY);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var lit = Math.round(lv[i] * segs);
        var cap = Math.round(caps[i] * segs) - 1;
        for (var k = 0; k < segs; k++) {
            var y = h - (k + 1) * segH - k * gapY;
            if (y < top)
                break;
            if (k < lit)
                ctx.fillStyle = _band(ink, (k + 1) / segs);
            else if (k === cap)
                ctx.fillStyle = ink.accent;
            else
                ctx.fillStyle = ink.groove;
            ctx.fillRect(x, y, cw, segH);
        }
    }
}

function mirror(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var r = Math.min(ink.radius, cw / 2);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        ctx.fillStyle = ink.groove;
        _pill(ctx, x, 0, cw, h, r);
        var l = lv[i];
        if (l > 0) {
            var fh = Math.min(h, Math.max(h * l, r * 2));
            ctx.fillStyle = _band(ink, l);
            _pill(ctx, x, (h - fh) / 2, cw, fh, r);
        }
    }
}

function butterfly(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var half = Math.ceil(n / 2);
    var lv = _levels(state, levels, half);
    var cw = _colWidth(w, n, ink.gap);
    var r = Math.min(ink.radius, cw / 2);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var band = i < n / 2 ? Math.floor(n / 2) - 1 - i : i - Math.floor(n / 2);
        var l = lv[_clamp(band, 0, half - 1)];
        ctx.fillStyle = ink.groove;
        _pill(ctx, x, 0, cw, h, r);
        if (l > 0) {
            var fh = Math.min(h, Math.max(h * l, r * 2));
            ctx.fillStyle = _band(ink, l);
            _pill(ctx, x, (h - fh) / 2, cw, fh, r);
        }
    }
}

function outline(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var lw = 1;
    var capH = 2;
    ctx.strokeStyle = ink.dim;
    ctx.lineWidth = lw;
    ctx.beginPath();
    for (var i = 0; i < n; i++) {
        var x0 = i * (cw + ink.gap);
        var y = _clamp(h - lv[i] * h, capH / 2, h - capH / 2);
        var left = i === 0 ? 0 : x0 - ink.gap / 2;
        var right = i === n - 1 ? w : x0 + cw + ink.gap / 2;
        if (i === 0)
            ctx.moveTo(left, y);
        else
            ctx.lineTo(left, y);
        ctx.lineTo(right, y);
    }
    ctx.stroke();
    for (var j = 0; j < n; j++) {
        var x = j * (cw + ink.gap);
        var l = lv[j];
        ctx.fillStyle = l > 0 ? _band(ink, l) : ink.groove;
        ctx.fillRect(x, _clamp(h - l * h, 0, h - capH), cw, capH);
    }
}

function wave(ctx, w, h, levels, state, ink) {
    var n = levels.length > 1 ? Math.min(levels.length, 24) : 24;
    var lv = _levels(state, levels, n);
    var lw = 1.5;
    var peak = _max(lv, 0, n);
    ctx.beginPath();
    ctx.moveTo(0, h);
    var px = 0;
    var py = _clamp(h - lv[0] * h, lw / 2, h - lw / 2);
    ctx.lineTo(px, py);
    for (var i = 1; i < n; i++) {
        var x = i / (n - 1) * w;
        var y = _clamp(h - lv[i] * h, lw / 2, h - lw / 2);
        ctx.quadraticCurveTo(px, py, (px + x) / 2, (py + y) / 2);
        px = x;
        py = y;
    }
    ctx.lineTo(px, py);
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.globalAlpha = 0.3;
    ctx.fillStyle = peak > 0 ? _band(ink, peak) : ink.groove;
    ctx.fill();
    ctx.globalAlpha = 1;

    ctx.beginPath();
    px = 0;
    py = _clamp(h - lv[0] * h, lw / 2, h - lw / 2);
    ctx.moveTo(px, py);
    for (var j = 1; j < n; j++) {
        var x2 = j / (n - 1) * w;
        var y2 = _clamp(h - lv[j] * h, lw / 2, h - lw / 2);
        ctx.quadraticCurveTo(px, py, (px + x2) / 2, (py + y2) / 2);
        px = x2;
        py = y2;
    }
    ctx.lineTo(px, py);
    ctx.lineWidth = lw;
    ctx.strokeStyle = peak > 0 ? ink.content : ink.dim;
    ctx.stroke();
}

function dots(ctx, w, h, levels, state, ink) {
    var size = 2;
    var pitch = 4;
    var cols = Math.max(1, Math.floor((w + pitch - size) / pitch));
    var rows = Math.max(1, Math.floor((h + pitch - size) / pitch));
    var lv = _levels(state, levels, cols);
    var ox = (w - ((cols - 1) * pitch + size)) / 2;
    var oy = (h - ((rows - 1) * pitch + size)) / 2;
    for (var c = 0; c < cols; c++) {
        var l = lv[c];
        var lit = Math.round(l * rows);
        var colour = _band(ink, l);
        for (var k = 0; k < rows; k++) {
            ctx.fillStyle = k < lit ? colour : ink.groove;
            ctx.fillRect(ox + c * pitch, oy + (rows - 1 - k) * pitch, size, size);
        }
    }
}

// Light, medium and dark shade, then the full block.
var SHADES = ["░", "▒", "▓", "█"];

function ascii(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var rows = 4;
    var rowH = h / rows;
    ctx.font = Math.floor(rowH) + "px " + ink.mono;
    ctx.textBaseline = "middle";
    ctx.textAlign = "center";
    for (var i = 0; i < n; i++) {
        var cx = i * (cw + ink.gap) + cw / 2;
        var l = lv[i];
        var fill = l * rows;
        var colour = _band(ink, l);
        for (var k = 0; k < rows; k++) {
            var part = _clamp(fill - k, 0, 1);
            var glyph;
            if (part <= 0) {
                if (k > 0)
                    break;
                ctx.fillStyle = ink.groove;
                glyph = SHADES[0];
            } else {
                ctx.fillStyle = colour;
                glyph = SHADES[Math.min(3, Math.ceil(part * 4) - 1)];
            }
            ctx.fillText(glyph, cx, h - (k + 0.5) * rowH);
        }
    }
}

var MATRIX_GLYPHS = "0123456789:=+<>";
var MATRIX_TRAIL = 3;
// Full level crosses the box's 32px in about a third of a second.
var MATRIX_SPEED = 90;

function matrix(ctx, w, h, levels, state, ink, dt) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var rowH = 8;
    var rows = Math.max(1, Math.floor(h / rowH));
    var span = rows + MATRIX_TRAIL;
    var head = state.heads;
    if (!head) {
        head = _buf(state, "heads", n);
        for (var s = 0; s < n; s++)
            head[s] = (s * 5) % span;
    }
    ctx.font = rowH + "px " + ink.mono;
    ctx.textBaseline = "middle";
    ctx.textAlign = "center";
    var oy = (h - rows * rowH) / 2;
    for (var i = 0; i < n; i++) {
        var l = lv[i];
        head[i] = (head[i] + l * MATRIX_SPEED / rowH * dt) % span;
        var hr = Math.floor(head[i]);
        var cx = i * (cw + ink.gap) + cw / 2;
        for (var k = 0; k <= MATRIX_TRAIL; k++) {
            var row = hr - k;
            if (row < 0 || row >= rows)
                continue;
            if (l <= 0) {
                ctx.fillStyle = ink.groove;
                ctx.globalAlpha = 1;
            } else if (k === 0) {
                ctx.fillStyle = l >= Model.LEVEL_ACCENT_FROM ? ink.accent : ink.content;
                ctx.globalAlpha = 1;
            } else {
                ctx.fillStyle = ink.dim;
                ctx.globalAlpha = 1 - k / (MATRIX_TRAIL + 1);
            }
            var g = (i * 7 + (hr - k) * 13 + Math.floor(head[i] / span) * 3) % MATRIX_GLYPHS.length;
            ctx.fillText(MATRIX_GLYPHS.charAt(g < 0 ? g + MATRIX_GLYPHS.length : g), cx, oy + row * rowH + rowH / 2);
        }
    }
    ctx.globalAlpha = 1;
}

var RAIN_POOL = 40;
var RAIN_RATE = 9;

function rain(ctx, w, h, levels, state, ink, dt) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var r = Math.min(ink.radius, cw / 2);
    var pool = _pool(state, RAIN_POOL);
    var acc = _buf(state, "spawnAcc", n);
    var dropW = Math.min(2, cw);
    var dropH = 3;
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var l = lv[i];
        ctx.fillStyle = ink.groove;
        _pill(ctx, x, 0, cw, h, r);
        if (l > 0) {
            var fh = Math.min(h, Math.max(h * l, r * 2));
            ctx.globalAlpha = 0.45;
            ctx.fillStyle = ink.dim;
            _pill(ctx, x, h - fh, cw, fh, r);
            ctx.globalAlpha = 1;
        }
        acc[i] += l * RAIN_RATE * dt;
        while (acc[i] >= 1) {
            acc[i] -= 1;
            var slot = _spawnSlot(pool);
            if (slot < 0)
                continue;
            pool.alive[slot] = true;
            pool.x[slot] = x + (cw - dropW) / 2;
            pool.y[slot] = _clamp(h - l * h, 0, h - dropH);
            pool.v[slot] = 24 + l * 40;
            pool.c[slot] = l;
        }
    }
    for (var p = 0; p < RAIN_POOL; p++) {
        if (!pool.alive[p])
            continue;
        pool.y[p] += pool.v[p] * dt;
        if (pool.y[p] + dropH > h) {
            pool.alive[p] = false;
            continue;
        }
        ctx.fillStyle = pool.c[p] >= Model.LEVEL_ACCENT_FROM ? ink.accent : ink.content;
        ctx.fillRect(pool.x[p], pool.y[p], dropW, dropH);
    }
}

var FLAME_POOL = 36;
var FLAME_RATE = 10;
var EMBER_LIFE = 0.45;

function flame(ctx, w, h, levels, state, ink, dt) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var r = Math.min(ink.radius, cw / 2);
    var pool = _pool(state, FLAME_POOL);
    var acc = _buf(state, "spawnAcc", n);
    var flick = _buf(state, "flick", n);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var l = lv[i];
        if (dt > 0)
            flick[i] = (Math.random() * 2 - 1) * 0.12 * l;
        var fh = l > 0 ? _clamp(h * l * (1 + flick[i]), r * 2, h) : 0;
        if (fh > 0) {
            var tip = Math.min(fh, Math.max(3, fh * 0.35));
            ctx.fillStyle = ink.dim;
            _pill(ctx, x, h - fh, cw, fh, r);
            ctx.fillStyle = l >= Model.LEVEL_DIM_BELOW ? ink.accent : ink.content;
            _pill(ctx, x, h - fh, cw, tip, r);
        }
        acc[i] += l * l * FLAME_RATE * dt;
        while (acc[i] >= 1) {
            acc[i] -= 1;
            var slot = _spawnSlot(pool);
            if (slot < 0)
                continue;
            pool.alive[slot] = true;
            pool.x[slot] = x + Math.random() * (cw - 1);
            pool.y[slot] = _clamp(h - fh - 2, 0, h - 2);
            pool.v[slot] = 18 + l * 30;
            pool.a[slot] = EMBER_LIFE;
        }
    }
    _floorLine(ctx, w, h, ink);
    ctx.fillStyle = ink.accent;
    for (var p = 0; p < FLAME_POOL; p++) {
        if (!pool.alive[p])
            continue;
        pool.y[p] -= pool.v[p] * dt;
        pool.a[p] -= dt;
        if (pool.a[p] <= 0 || pool.y[p] < 0) {
            pool.alive[p] = false;
            continue;
        }
        ctx.globalAlpha = pool.a[p] / EMBER_LIFE;
        ctx.fillRect(pool.x[p], pool.y[p], 1, 2);
    }
    ctx.globalAlpha = 1;
}

var BUBBLE_POOL = 20;
var BUBBLE_RATE = 16;

function bubbles(ctx, w, h, levels, state, ink, dt) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var pool = _pool(state, BUBBLE_POOL);
    var total = 0;
    for (var i = 0; i < n; i++)
        total += lv[i];
    var energy = total / n;
    state.acc = (state.acc || 0) + energy * BUBBLE_RATE * dt;
    while (state.acc >= 1) {
        state.acc -= 1;
        var slot = _spawnSlot(pool);
        if (slot < 0 || total <= 0)
            continue;
        // A column picked in proportion to its own level, so the rings
        // rise off the bands that are actually loud.
        var pick = Math.random() * total;
        var col = 0;
        while (col < n - 1 && pick > lv[col]) {
            pick -= lv[col];
            col++;
        }
        var rad = 1.5 + lv[col] * 2.5;
        pool.alive[slot] = true;
        pool.r[slot] = rad;
        pool.x[slot] = _clamp(col * (cw + ink.gap) + cw / 2 + (Math.random() - 0.5) * 2 * (cw + ink.gap), rad + 0.5, w - rad - 0.5);
        pool.y[slot] = h - rad - 1;
        pool.v[slot] = 10 + energy * 36;
        pool.c[slot] = lv[col];
        pool.a[slot] = Math.random() * 6.28;
    }
    _floorLine(ctx, w, h, ink);
    ctx.lineWidth = 1;
    for (var p = 0; p < BUBBLE_POOL; p++) {
        if (!pool.alive[p])
            continue;
        pool.y[p] -= pool.v[p] * dt;
        var rr = pool.r[p];
        if (pool.y[p] - rr < 0.5) {
            pool.alive[p] = false;
            continue;
        }
        var bx = _clamp(pool.x[p] + Math.sin(pool.y[p] * 0.35 + pool.a[p]), rr + 0.5, w - rr - 0.5);
        ctx.globalAlpha = _clamp(pool.y[p] / h + 0.25, 0.25, 1);
        ctx.strokeStyle = pool.c[p] >= Model.LEVEL_ACCENT_FROM ? ink.accent : ink.content;
        ctx.beginPath();
        ctx.arc(bx, pool.y[p], rr, 0, Math.PI * 2);
        ctx.stroke();
    }
    ctx.globalAlpha = 1;
}

var SCOPE_BANDS = 8;
var SCOPE_POINTS = 48;

function scope(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, SCOPE_BANDS);
    var phase = _buf(state, "phase", SCOPE_BANDS);
    var sum = 0;
    var amp = 0;
    for (var k = 0; k < SCOPE_BANDS; k++) {
        phase[k] = (phase[k] + dt * (k + 1) * 3.1) % (Math.PI * 2);
        sum += lv[k];
        if (lv[k] > amp)
            amp = lv[k];
    }
    var mid = h / 2;
    var lw = 1.5;
    var reach = mid - lw;
    ctx.fillStyle = ink.groove;
    ctx.fillRect(0, Math.floor(mid), w, 1);
    ctx.beginPath();
    for (var i = 0; i <= SCOPE_POINTS; i++) {
        var x = i / SCOPE_POINTS * w;
        var s = 0;
        if (sum > 0) {
            for (var b = 0; b < SCOPE_BANDS; b++)
                s += lv[b] * Math.sin((b + 1) * 2 * Math.PI * (i / SCOPE_POINTS) * 1.5 + phase[b]);
            s = s / sum * amp;
        }
        var y = _clamp(mid - s * reach, lw / 2, h - lw / 2);
        if (i === 0)
            ctx.moveTo(x, y);
        else
            ctx.lineTo(x, y);
    }
    ctx.lineWidth = lw;
    ctx.strokeStyle = amp > 0 ? _band(ink, Math.max(amp, Model.LEVEL_DIM_BELOW)) : ink.dim;
    ctx.stroke();
}

function pulse(ctx, w, h, levels, state, ink) {
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 3);
    var mids = _max(lv, 3, 8);
    var highs = _max(lv, 8, 12);
    var cx = w / 2;
    var cy = h / 2;
    var ringMax = cy - 1;
    var disc = 2.5 + bass * (ringMax - 6.5);
    var ring = Math.min(ringMax, disc + 2 + mids * 4);

    var reach = highs * (cx - ring - 2);
    if (reach > 0.5) {
        ctx.fillStyle = ink.dim;
        ctx.fillRect(cx - ring - 1 - reach, Math.floor(cy), reach, 1);
        ctx.fillRect(cx + ring + 1, Math.floor(cy), reach, 1);
    }
    ctx.lineWidth = 1;
    ctx.strokeStyle = mids > 0 ? _band(ink, Math.max(mids, Model.LEVEL_DIM_BELOW)) : ink.groove;
    ctx.beginPath();
    ctx.arc(cx, cy, ring, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = bass > 0 ? _band(ink, Math.max(bass, Model.LEVEL_DIM_BELOW)) : ink.groove;
    ctx.beginPath();
    ctx.arc(cx, cy, disc, 0, Math.PI * 2);
    ctx.fill();
}

// A beat is a rise in the bass over its own recent average, with a
// refractory window so one kick draws one complex.
var BEAT_RISE = 0.12;
var BEAT_FLOOR = 0.3;
var BEAT_REFRACTORY = 0.25;
var BEAT_SECONDS = 0.2;
var ECG_SPEED = 40;

// Q dip, R spike, S dip, back to the line, over BEAT_SECONDS.
function _ecg(u) {
    if (u < 0.15)
        return -0.2 * (u / 0.15);
    if (u < 0.35)
        return -0.2 + 1.2 * ((u - 0.15) / 0.2);
    if (u < 0.55)
        return 1 - 1.4 * ((u - 0.35) / 0.2);
    if (u < 1)
        return -0.4 * (1 - (u - 0.55) / 0.45);
    return 0;
}

function heartbeat(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 2);
    var n = Math.max(2, Math.ceil(w));
    var hist = _history(state, n);
    if (dt > 0) {
        state.avg = (state.avg || 0) + (bass - (state.avg || 0)) * (1 - Math.exp(-dt / 0.3));
        state.since = (state.since === undefined ? BEAT_REFRACTORY : state.since) + dt;
        if (bass > BEAT_FLOOR && bass - state.avg > BEAT_RISE && state.since >= BEAT_REFRACTORY) {
            state.since = 0;
            state.beat = 0;
            state.beatAmp = bass;
        }
        hist.acc += dt * ECG_SPEED;
        while (hist.acc >= 1) {
            hist.acc -= 1;
            var v = 0;
            if (state.beat !== undefined && state.beat < BEAT_SECONDS) {
                v = _ecg(state.beat / BEAT_SECONDS) * state.beatAmp;
                state.beat += 1 / ECG_SPEED;
            }
            _push(hist, v, bass);
        }
    }
    var mid = Math.round(h * 0.6) + 0.5;
    var lw = 1.5;
    ctx.fillStyle = ink.groove;
    ctx.fillRect(0, mid - 0.5, w, 1);
    // Older samples in `dim`, the newest stretch in `content`, so the trace
    // reads as moving leftward even when it is flat.
    var split = Math.floor(n * 0.6);
    for (var pass = 0; pass < 2; pass++) {
        ctx.beginPath();
        var from = pass === 0 ? 0 : split;
        var to = pass === 0 ? split : n - 1;
        for (var i = from; i <= to; i++) {
            var sample = hist.v[(hist.head + i) % n];
            var y = _clamp(mid - (sample >= 0 ? sample * (mid - lw) : sample * (h - mid - lw)), lw / 2, h - lw / 2);
            var x = i / (n - 1) * w;
            if (i === from)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.lineWidth = lw;
        ctx.strokeStyle = pass === 0 ? ink.dim : ink.content;
        ctx.stroke();
    }
}

var TERRAIN_STEP = 2;
var TERRAIN_SPEED = 24;

function terrain(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var n = Math.max(2, Math.floor(w / TERRAIN_STEP) + 1);
    var hist = _history(state, n);
    if (dt > 0) {
        var sq = 0;
        for (var i = 0; i < 12; i++)
            sq += lv[i] * lv[i];
        var loud = Math.sqrt(sq / 12);
        var bass = _max(lv, 0, 3);
        hist.acc += dt * TERRAIN_SPEED / TERRAIN_STEP;
        while (hist.acc >= 1) {
            hist.acc -= 1;
            _push(hist, loud, bass);
        }
    }
    var lw = 1.5;
    for (var layer = 0; layer < 2; layer++) {
        var key = layer === 0 ? hist.w : hist.v;
        ctx.beginPath();
        ctx.moveTo(0, h);
        for (var j = 0; j < n; j++) {
            var y = _clamp(h - key[(hist.head + j) % n] * (h - lw), lw / 2, h);
            ctx.lineTo(Math.min(w, j * TERRAIN_STEP), y);
        }
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.globalAlpha = layer === 0 ? 1 : 0.35;
        ctx.fillStyle = layer === 0 ? ink.groove : ink.dim;
        ctx.fill();
    }
    ctx.globalAlpha = 1;
    ctx.beginPath();
    for (var k = 0; k < n; k++) {
        var yy = _clamp(h - hist.v[(hist.head + k) % n] * (h - lw), lw / 2, h - lw / 2);
        if (k === 0)
            ctx.moveTo(0, yy);
        else
            ctx.lineTo(Math.min(w, k * TERRAIN_STEP), yy);
    }
    ctx.lineWidth = lw;
    ctx.strokeStyle = ink.content;
    ctx.stroke();
}

// Deterministic 0..1 per integer triple, for layouts that must not change
// from one frame to the next (a tile's band, a star's place, a bit).
function _hash(a, b, c) {
    var x = (Math.imul(a | 0, 374761393) + Math.imul(b | 0, 668265263) + Math.imul(c | 0, 1440662683)) | 0;
    x = Math.imul(x ^ (x >>> 13), 1274126177);
    x ^= x >>> 16;
    return (x >>> 0) / 4294967296;
}

// Nearest band for each of `count` slots, for styles with more slots than
// cava has bands, where `_fold` would leave the extra slots empty.
function _spread(state, levels, count, key) {
    var src = _levels(state, levels, Model.BAR_COUNT, "fold" + Model.BAR_COUNT);
    var out = _buf(state, key || ("spread" + count), count);
    for (var i = 0; i < count; i++)
        out[i] = src[Math.min(Model.BAR_COUNT - 1, Math.floor(i * Model.BAR_COUNT / count))];
    return out;
}

function _mean(a, from, to) {
    var s = 0;
    for (var i = from; i < to; i++)
        s += a[i];
    return to > from ? s / (to - from) : 0;
}

// The heartbeat's onset test, on its own keys so a style can read it for
// any band.
function _onset(state, v, dt) {
    if (!(dt > 0))
        return false;
    state.onAvg = (state.onAvg || 0) + (v - (state.onAvg || 0)) * (1 - Math.exp(-dt / 0.3));
    state.onSince = (state.onSince === undefined ? BEAT_REFRACTORY : state.onSince) + dt;
    if (v > BEAT_FLOOR && v - state.onAvg > BEAT_RISE && state.onSince >= BEAT_REFRACTORY) {
        state.onSince = 0;
        return true;
    }
    return false;
}

function bricks(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var brickH = 3;
    var gapY = 2;
    var rows = Math.max(1, Math.floor((h + gapY) / (brickH + gapY)));
    var r = Math.min(1, cw / 2);
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap);
        var l = lv[i];
        var lit = l > 0 ? Math.ceil(l * rows) : 0;
        if (lit === 0) {
            ctx.fillStyle = ink.groove;
            _pill(ctx, x, h - brickH, cw, brickH, r);
            continue;
        }
        ctx.fillStyle = _band(ink, l);
        for (var k = 0; k < lit; k++)
            _pill(ctx, x, h - (k + 1) * brickH - k * gapY, cw, brickH, r);
    }
}

function columns(ctx, w, h, levels, state, ink) {
    var pitch = 2;
    var count = Math.max(2, Math.floor((w + 1) / pitch));
    var src = _levels(state, levels, Model.BAR_COUNT, "fold" + Model.BAR_COUNT);
    // Whole pixels, or a 1px column straddles two and the gaps blur shut.
    var ox = Math.floor((w - ((count - 1) * pitch + 1)) / 2);
    for (var c = 0; c < count; c++) {
        var pos = c / (count - 1) * (Model.BAR_COUNT - 1);
        var i0 = Math.floor(pos);
        var i1 = Math.min(Model.BAR_COUNT - 1, i0 + 1);
        var l = src[i0] + (src[i1] - src[i0]) * (pos - i0);
        var bh = l * h;
        var x = ox + c * pitch;
        if (bh < 1) {
            ctx.fillStyle = ink.groove;
            ctx.fillRect(x, h - 1, 1, 1);
        } else {
            ctx.fillStyle = _band(ink, l);
            ctx.fillRect(x, h - bh, 1, bh);
        }
    }
}

var SCATTER_HZ = 20;

function scatter(ctx, w, h, levels, state, ink, dt) {
    var size = 2;
    var pitch = 3;
    var cols = Math.max(1, Math.floor((w + pitch - size) / pitch));
    var rows = Math.max(1, Math.floor((h - 2 + pitch - size) / pitch));
    var lv = _spread(state, levels, cols);
    state.acc = (state.acc || 0) + dt * SCATTER_HZ;
    if (state.acc >= 1) {
        state.tick = ((state.tick || 0) + Math.floor(state.acc)) % 100000;
        state.acc -= Math.floor(state.acc);
    }
    var tick = state.tick || 0;
    var ox = (w - ((cols - 1) * pitch + size)) / 2;
    _floorLine(ctx, w, h, ink);
    for (var c = 0; c < cols; c++) {
        var l = lv[c];
        if (l <= 0)
            continue;
        ctx.fillStyle = _band(ink, l);
        for (var k = 0; k < rows; k++) {
            // k counts up from the floor: grains settle low.
            var weight = 1 - 0.5 * k / Math.max(1, rows - 1);
            if (_hash(c, k, tick) < l * l * weight)
                ctx.fillRect(ox + c * pitch, h - 2 - size - k * pitch, size, size);
        }
    }
}

var RETRO_GRID_SPEED = 0.9;

function retro(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 3);
    var energy = _mean(lv, 0, 12);
    var horizon = Math.max(3, Math.round(h * 0.5));
    var cx = w / 2;

    var sunR = Math.min(horizon - 1, horizon * 0.7 + bass * 3);
    ctx.fillStyle = ink.dim;
    for (var d = 1; d <= sunR; d++) {
        // Stripes cut through the lower half, thinning toward the horizon.
        if (d < sunR * 0.55 && Math.floor(d / 2) % 2 === 1)
            continue;
        var half = Math.sqrt(sunR * sunR - (d - 0.5) * (d - 0.5));
        ctx.fillRect(cx - half, horizon - d, half * 2, 1);
    }

    var floorH = h - horizon - 1;
    ctx.strokeStyle = ink.dim;
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.6;
    ctx.beginPath();
    var spokes = 10;
    for (var i = 0; i <= spokes; i++) {
        var bx = i / spokes * w;
        ctx.moveTo(cx + (bx - cx) * 0.08, horizon + 0.5);
        ctx.lineTo(_clamp(bx, 0.5, w - 0.5), h - 0.5);
    }
    state.scroll = ((state.scroll || 0) + energy * RETRO_GRID_SPEED * dt) % 1;
    var lines = 4;
    for (var j = 0; j < lines; j++) {
        var z = (j + state.scroll) / lines;
        // On a pixel centre, or the 1px stroke smears over two rows.
        var y = Math.floor(horizon + 2 + z * z * (floorH - 2)) + 0.5;
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.fillStyle = ink.dim;
    ctx.fillRect(0, horizon, w, 1);

    // The spectrum rides the horizon, bass in the middle.
    var n = 12;
    var peak = _max(lv, 0, n);
    ctx.beginPath();
    for (var p = 0; p <= 2 * n; p++) {
        var band = Math.abs(p - n);
        var l = lv[Math.min(n - 1, band)];
        var px = p / (2 * n) * w;
        var py = _clamp(horizon - 1 - l * (horizon - 2) * 0.7, 0.75, horizon - 0.75);
        if (p === 0)
            ctx.moveTo(px, py);
        else
            ctx.lineTo(px, py);
    }
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = peak > 0 ? _band(ink, Math.max(peak, Model.LEVEL_DIM_BELOW)) : ink.dim;
    ctx.stroke();
}

// Rows per second at full level.
var BINARY_SPEED = 12;

function binary(ctx, w, h, levels, state, ink, dt) {
    var rowH = 8;
    var charW = 6;
    var rows = Math.max(1, Math.floor(h / rowH));
    var cols = Math.max(1, Math.floor(w / charW));
    var lv = _levels(state, levels, cols);
    var off = _buf(state, "binOff", cols);
    var ox = (w - cols * charW) / 2 + charW / 2;
    var oy = (h - rows * rowH) / 2 + rowH / 2;
    ctx.font = rowH + "px " + ink.mono;
    ctx.textBaseline = "middle";
    ctx.textAlign = "center";
    for (var c = 0; c < cols; c++) {
        var l = lv[c];
        off[c] = (off[c] + l * BINARY_SPEED * dt) % 100000;
        var scroll = Math.floor(off[c]);
        for (var r = 0; r < rows; r++) {
            var one = _hash(c, r - scroll, 3) < 0.15 + 0.6 * l;
            if (one && l >= Model.LEVEL_DIM_BELOW)
                ctx.fillStyle = _band(ink, l);
            else if (one)
                ctx.fillStyle = ink.dim;
            else
                ctx.fillStyle = ink.groove;
            ctx.fillText(one ? "1" : "0", ox + c * charW, oy + r * rowH);
        }
    }
}

var SAKURA_PETALS = 16;

function sakura(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var energy = _mean(lv, 0, 12);
    state.drift = ((state.drift || 0) + energy * dt) % 10000;
    var drift = state.drift;
    var shown = 6 + energy * (SAKURA_PETALS - 6);
    var wrap = h + 8;
    for (var i = 0; i < SAKURA_PETALS; i++) {
        var alpha = _clamp(shown - i, 0, 1);
        if (alpha <= 0)
            continue;
        var near = _hash(i, 3, 0) > 0.55;
        var size = near ? 2.4 + _hash(i, 4, 0) * 0.8 : 1.4 + _hash(i, 4, 0) * 0.5;
        // Distant petals fall faster, as in cliamp's reference.
        var speed = near ? 16 : 26;
        var y = (_hash(i, 2, 0) * wrap + drift * speed) % wrap - 4;
        if (y < 0 || y > h)
            continue;
        var phase = _hash(i, 5, 0) * 6.283;
        var x = _hash(i, 1, 0) * w + Math.sin(drift * 2.5 + phase) * 3;
        var a = drift * 3 + phase;
        var ux = Math.cos(a) * size * 1.4;
        var uy = Math.sin(a) * size * 1.4;
        var vx = -Math.sin(a) * size * 1.6;
        var vy = Math.cos(a) * size * 1.6;
        ctx.globalAlpha = alpha;
        ctx.fillStyle = near ? ink.accent : ink.dim;
        ctx.beginPath();
        ctx.moveTo(_clamp(x + ux, 0, w), _clamp(y + uy, 0, h));
        ctx.quadraticCurveTo(_clamp(x + vx, 0, w), _clamp(y + vy, 0, h), _clamp(x - ux, 0, w), _clamp(y - uy, 0, h));
        ctx.quadraticCurveTo(_clamp(x - vx, 0, w), _clamp(y - vy, 0, h), _clamp(x + ux, 0, w), _clamp(y + uy, 0, h));
        ctx.fill();
    }
    ctx.globalAlpha = 1;
}

var FIREWORK_ROCKETS = 5;
var FIREWORK_SPARKS = 72;
var FIREWORK_RATE = 3;
var SPARK_LIFE = 0.9;
var SPARK_GRAVITY = 30;

function _launch(state, w, h, l) {
    var alive = state.rkAlive;
    for (var i = 0; i < FIREWORK_ROCKETS; i++) {
        if (alive[i])
            continue;
        alive[i] = true;
        state.rkX[i] = 8 + Math.random() * Math.max(0, w - 16);
        state.rkY[i] = h - 1;
        state.rkTop[i] = h * (0.2 + Math.random() * 0.3);
        state.rkL[i] = l;
        return;
    }
}

function firework(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 3);
    var energy = _mean(lv, 0, 12);
    var peak = _max(lv, 0, 12);
    _buf(state, "rkAlive", FIREWORK_ROCKETS, false);
    _buf(state, "rkX", FIREWORK_ROCKETS);
    _buf(state, "rkY", FIREWORK_ROCKETS);
    _buf(state, "rkTop", FIREWORK_ROCKETS);
    _buf(state, "rkL", FIREWORK_ROCKETS);
    var pool = _pool(state, FIREWORK_SPARKS);
    state.acc = (state.acc || 0) + energy * FIREWORK_RATE * dt;
    if (_onset(state, bass, dt))
        state.acc += 1;
    while (state.acc >= 1) {
        state.acc -= 1;
        _launch(state, w, h, peak);
    }
    _floorLine(ctx, w, h, ink);
    ctx.fillStyle = ink.dim;
    for (var i = 0; i < FIREWORK_ROCKETS; i++) {
        if (!state.rkAlive[i])
            continue;
        state.rkY[i] -= 60 * dt;
        if (state.rkY[i] <= state.rkTop[i]) {
            state.rkAlive[i] = false;
            var l = state.rkL[i];
            var count = 10 + Math.round(l * 10);
            var speed = 14 + l * 22;
            for (var k = 0; k < count; k++) {
                var slot = _spawnSlot(pool);
                if (slot < 0)
                    break;
                var ang = k / count * Math.PI * 2;
                var sp = speed * (0.6 + Math.random() * 0.4);
                pool.alive[slot] = true;
                pool.x[slot] = state.rkX[i];
                pool.y[slot] = state.rkTop[i];
                pool.v[slot] = Math.cos(ang) * sp;
                pool.r[slot] = Math.sin(ang) * sp;
                pool.a[slot] = SPARK_LIFE;
                pool.c[slot] = l;
            }
            continue;
        }
        ctx.fillRect(state.rkX[i], _clamp(state.rkY[i], 0, h - 3), 1, 3);
    }
    for (var p = 0; p < FIREWORK_SPARKS; p++) {
        if (!pool.alive[p])
            continue;
        pool.r[p] += SPARK_GRAVITY * dt;
        pool.x[p] += pool.v[p] * dt;
        pool.y[p] += pool.r[p] * dt;
        pool.a[p] -= dt;
        if (pool.a[p] <= 0 || pool.x[p] < 0 || pool.x[p] > w - 1.5 || pool.y[p] < 0 || pool.y[p] > h - 2.5) {
            pool.alive[p] = false;
            continue;
        }
        ctx.globalAlpha = _clamp(pool.a[p] / SPARK_LIFE * 1.4, 0, 1);
        ctx.fillStyle = pool.c[p] >= Model.LEVEL_ACCENT_FROM ? ink.accent : ink.content;
        ctx.fillRect(pool.x[p], pool.y[p], 1.5, 1.5);
    }
    ctx.globalAlpha = 1;
}

var FIREFLIES = 12;

function firefly(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var bass = _mean(lv, 0, 4);
    var high = _mean(lv, 8, 12);
    var energy = _mean(lv, 0, 12);
    state.clock = ((state.clock || 0) + energy * 1.5 * dt) % 100000;
    var t = state.clock;

    ctx.fillStyle = ink.groove;
    ctx.beginPath();
    ctx.moveTo(0, h);
    for (var gx = 0; gx <= w; gx += 2) {
        var gh = 2.5 + 1.2 * Math.sin(gx * 0.41) + 0.8 * Math.sin(gx * 0.17 + 2.3);
        ctx.lineTo(gx, h - gh);
    }
    ctx.lineTo(w, h);
    ctx.closePath();
    ctx.fill();

    var halo = 2.5;
    for (var i = 0; i < FIREFLIES; i++) {
        var fx = 0.6 + _hash(i, 1, 9) * 0.5;
        var fy = 0.9 + _hash(i, 2, 9) * 0.5;
        var phx = _hash(i, 3, 9) * 6.283;
        var phy = _hash(i, 4, 9) * 6.283;
        var x = w / 2 + Math.cos(t * fx + phx) * (w / 2 - 4) + bass * 3 * Math.sin(t * 0.7 + phx);
        var y = (h - 6) * 0.5 + Math.sin(t * fy + phy) * (h - 8) * 0.4;
        x = _clamp(x, halo, w - halo);
        y = _clamp(y, halo, h - 5);
        var glow = 0.5 + 0.5 * Math.sin(t * 3 + i * 1.31);
        if (glow + high * 0.6 > 0.8) {
            ctx.globalAlpha = 0.3;
            ctx.fillStyle = ink.accent;
            ctx.beginPath();
            ctx.arc(x, y, halo, 0, Math.PI * 2);
            ctx.fill();
            ctx.globalAlpha = 1;
            ctx.fillStyle = high >= Model.LEVEL_DIM_BELOW ? ink.accent : ink.content;
            ctx.fillRect(x - 1, y - 1, 2, 2);
        } else {
            ctx.fillStyle = ink.dim;
            ctx.fillRect(x - 0.5, y - 0.5, 1, 1);
        }
    }
}

var MOSAIC_DECAY = 0.25;

function mosaic(ctx, w, h, levels, state, ink, dt) {
    var tileW = 5;
    var tileH = 4;
    var gap = 1;
    var cols = Math.max(1, Math.floor((w + gap) / (tileW + gap)));
    var rows = Math.max(1, Math.floor((h + gap) / (tileH + gap)));
    var n = cols * rows;
    var src = _levels(state, levels, Model.BAR_COUNT, "fold" + Model.BAR_COUNT);
    var value = _buf(state, "tileV", n);
    var decay = Math.exp(-dt / MOSAIC_DECAY);
    var ox = (w - (cols * (tileW + gap) - gap)) / 2;
    var oy = (h - (rows * (tileH + gap) - gap)) / 2;
    for (var k = 0; k < n; k++) {
        var c = k % cols;
        var r = Math.floor(k / cols);
        var band = Math.floor(_hash(c, r, 1) * Model.BAR_COUNT);
        var threshold = 0.25 + _hash(c, r, 2) * 0.65;
        var l = src[band];
        if (dt > 0) {
            value[k] *= decay;
            if (l > threshold)
                value[k] = Math.max(value[k], 0.4 + 0.6 * (l - threshold) / (1 - threshold));
        }
        var v = value[k];
        var x = ox + c * (tileW + gap);
        var y = oy + r * (tileH + gap);
        if (v < 0.05) {
            ctx.fillStyle = ink.groove;
        } else {
            ctx.fillStyle = _band(ink, v);
            ctx.globalAlpha = 0.4 + 0.6 * v;
        }
        _pill(ctx, x, y, tileW, tileH, 1);
        ctx.globalAlpha = 1;
    }
}

var SAND_HZ = 40;
// Past this share of the bed a bass hit drains it, and past the second it
// drains on its own, so a passage with no clear hits cannot fill it solid.
var SAND_DRAIN_ON_HIT = 0.35;
var SAND_DRAIN_ALWAYS = 0.55;
var SAND_DRAIN_TO = 0.15;

function sand(ctx, w, h, levels, state, ink, dt) {
    var cell = 2;
    var cols = Math.max(1, Math.floor(w / cell));
    var rows = Math.max(2, Math.floor(h / cell));
    var grid = _buf(state, "sand", cols * rows);
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 3);
    if (_onset(state, bass, dt) && state.grains > cols * rows * SAND_DRAIN_ON_HIT)
        state.draining = true;
    state.acc = (state.acc || 0) + dt * SAND_HZ;
    var steps = 0;
    while (state.acc >= 1 && steps < 4) {
        state.acc -= 1;
        steps++;
        for (var b = 0; b < 12; b++) {
            var l = lv[b];
            if (l <= 0 || Math.random() >= l * l * 0.6)
                continue;
            var col = _clamp(Math.round((b + 0.5) * cols / 12 + (Math.random() - 0.5) * 2), 0, cols - 1);
            if (grid[col] === 0)
                grid[col] = l >= Model.LEVEL_ACCENT_FROM ? 3 : l >= Model.LEVEL_DIM_BELOW ? 2 : 1;
        }
        if (state.draining) {
            for (var d = 0; d < cols; d++)
                grid[(rows - 1) * cols + d] = 0;
        }
        var flip = steps % 2 === 0;
        for (var r = rows - 2; r >= 0; r--) {
            for (var cc = 0; cc < cols; cc++) {
                var c = flip ? cols - 1 - cc : cc;
                var at = r * cols + c;
                var g = grid[at];
                if (g === 0)
                    continue;
                var below = at + cols;
                var to = -1;
                if (grid[below] === 0) {
                    to = below;
                } else {
                    var first = Math.random() < 0.5 ? -1 : 1;
                    if (c + first >= 0 && c + first < cols && grid[below + first] === 0)
                        to = below + first;
                    else if (c - first >= 0 && c - first < cols && grid[below - first] === 0)
                        to = below - first;
                }
                if (to >= 0) {
                    grid[to] = g;
                    grid[at] = 0;
                }
            }
        }
    }
    if (steps > 0) {
        var count = 0;
        for (var q = 0; q < grid.length; q++) {
            if (grid[q] !== 0)
                count++;
        }
        state.grains = count;
        if (count > cols * rows * SAND_DRAIN_ALWAYS)
            state.draining = true;
        else if (count <= cols * rows * SAND_DRAIN_TO)
            state.draining = false;
    }
    _floorLine(ctx, w, h, ink);
    var oy = h - rows * cell;
    var ox = (w - cols * cell) / 2;
    for (var row = 0; row < rows; row++) {
        var x = 0;
        while (x < cols) {
            var v = grid[row * cols + x];
            if (v === 0) {
                x++;
                continue;
            }
            var start = x;
            while (x < cols && grid[row * cols + x] === v)
                x++;
            ctx.fillStyle = v === 3 ? ink.accent : v === 2 ? ink.content : ink.dim;
            ctx.fillRect(ox + start * cell, oy + row * cell, (x - start) * cell, cell);
        }
    }
}

var GEYSER_POOL = 90;
var GEYSER_GRAVITY = 120;

function _jet(pool, x, y, vx, vy, l) {
    var slot = _spawnSlot(pool);
    if (slot < 0)
        return;
    pool.alive[slot] = true;
    pool.x[slot] = x;
    pool.y[slot] = y;
    pool.v[slot] = vx;
    pool.r[slot] = vy;
    pool.c[slot] = l;
}

function geyser(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, 12);
    var bass = _max(lv, 0, 3);
    var mid = _mean(lv, 3, 8);
    var high = _mean(lv, 8, 12);
    var steady = bass * 0.85 + mid * 0.25 + high * 0.08;
    var pool = _pool(state, GEYSER_POOL);
    var jx = w / 2;
    var floorY = h - 2;
    state.acc = (state.acc || 0) + steady * 60 * dt;
    while (state.acc >= 1) {
        state.acc -= 1;
        _jet(pool, jx + (Math.random() - 0.5) * 3, floorY, (Math.random() - 0.5) * 12, -(30 + steady * 50) * (0.8 + Math.random() * 0.2), bass);
    }
    if (_onset(state, bass, dt)) {
        for (var b = 0; b < 20; b++)
            _jet(pool, jx + (Math.random() - 0.5) * 4, floorY, (Math.random() - 0.5) * 36, -(60 + bass * 30) * (0.7 + Math.random() * 0.3), 1);
    }
    _floorLine(ctx, w, h, ink);
    ctx.fillStyle = ink.groove;
    ctx.fillRect(jx - 3, h - 2, 6, 1);
    for (var p = 0; p < GEYSER_POOL; p++) {
        if (!pool.alive[p])
            continue;
        pool.r[p] += GEYSER_GRAVITY * dt;
        pool.x[p] += pool.v[p] * dt;
        pool.y[p] += pool.r[p] * dt;
        if (pool.y[p] > floorY || pool.x[p] < 0 || pool.x[p] > w - 1.5) {
            pool.alive[p] = false;
            continue;
        }
        ctx.fillStyle = _band(ink, pool.c[p]);
        ctx.fillRect(pool.x[p], Math.max(0, pool.y[p]), 1.5, 1.5);
    }
}

function _loudness(a) {
    var sq = 0;
    for (var i = 0; i < a.length; i++)
        sq += a[i] * a[i];
    return a.length > 0 ? Math.sqrt(sq / a.length) : 0;
}

function stereo(ctx, w, h, levels, state, ink, dt, t, left, right) {
    var lvL = _levels(state, left, Model.BAR_COUNT, "foldL");
    var lvR = _levels(state, right, Model.BAR_COUNT, "foldR");
    var meter = _buf(state, "meter", 2);
    meter[0] = _loudness(lvL);
    meter[1] = _loudness(lvR);
    var caps = _caps(state, meter, 2, dt);
    var labelW = 9;
    var segW = 3;
    var gapX = 1;
    var segs = Math.max(1, Math.floor((w - labelW + gapX) / (segW + gapX)));
    var x0 = w - (segs * (segW + gapX) - gapX);
    var meterH = Math.max(1, Math.floor((h - 2) / 2) - 2);
    ctx.font = "8px " + ink.mono;
    ctx.textBaseline = "middle";
    ctx.textAlign = "left";
    for (var ch = 0; ch < 2; ch++) {
        var y = ch === 0 ? h / 2 - 1 - meterH : h / 2 + 1;
        ctx.fillStyle = ink.dim;
        ctx.fillText(ch === 0 ? "L" : "R", 0, y + meterH / 2);
        var lit = Math.round(meter[ch] * segs);
        var cap = Math.round(caps[ch] * segs) - 1;
        for (var k = 0; k < segs; k++) {
            if (k < lit)
                ctx.fillStyle = _band(ink, (k + 1) / segs);
            else if (k === cap)
                ctx.fillStyle = ink.accent;
            else
                ctx.fillStyle = ink.groove;
            ctx.fillRect(x0 + k * (segW + gapX), y, segW, meterH);
        }
    }
}

var RS_BARS = 5;
var RS_STARS = 28;
var RS_DISTANCE = 7;
var RS_SPACING = 1;
var RS_HALF = 0.3;
var RS_MAX_HEIGHT = 2;
var RS_MIN_HEIGHT = 0.15;
// Corner signs, then faces as corner indices with their outward normal.
var RS_CORNERS = [[-1, 0, -1], [1, 0, -1], [1, 0, 1], [-1, 0, 1], [-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]];
var RS_FACES = [
    { v: [0, 1, 2, 3], n: [0, -1, 0] }, { v: [4, 5, 6, 7], n: [0, 1, 0] },
    { v: [0, 1, 5, 4], n: [0, 0, -1] }, { v: [3, 2, 6, 7], n: [0, 0, 1] },
    { v: [0, 3, 7, 4], n: [-1, 0, 0] }, { v: [1, 2, 6, 5], n: [1, 0, 0] }
];

function _rot(state, x, y, z, out, k) {
    var cy = state.rsCy;
    var sy = state.rsSy;
    var cp = state.rsCp;
    var sp = state.rsSp;
    var x1 = x * cy + z * sy;
    var z1 = -x * sy + z * cy;
    out[k] = x1;
    out[k + 1] = y * cp - z1 * sp;
    out[k + 2] = y * sp + z1 * cp;
}

function redsector(ctx, w, h, levels, state, ink, dt) {
    var lv = _levels(state, levels, RS_BARS * 2);
    var energy = _mean(lv, 0, RS_BARS * 2);
    state.yaw = ((state.yaw === undefined ? 0.6 : state.yaw) + energy * 1.2 * dt) % (Math.PI * 2);
    state.tumble = ((state.tumble || 0) + energy * 0.7 * dt) % (Math.PI * 2);
    state.stars = ((state.stars || 0) + energy * 14 * dt) % 100000;
    // Negative pitch tips the top toward the camera, so the caps show.
    var pitch = -0.35 - Math.sin(state.tumble) * 0.2;
    state.rsCy = Math.cos(state.yaw);
    state.rsSy = Math.sin(state.yaw);
    state.rsCp = Math.cos(pitch);
    state.rsSp = Math.sin(pitch);

    for (var s = 0; s < RS_STARS; s++) {
        var depth = 0.3 + 0.7 * _hash(s, 2, 7);
        var sx = ((_hash(s, 0, 7) * w - state.stars * depth) % w + w) % w;
        var sy = _hash(s, 1, 7) * (h - 1);
        ctx.globalAlpha = 0.3 + 0.5 * depth;
        ctx.fillStyle = ink.dim;
        ctx.fillRect(Math.min(sx, w - 1), sy, 1, 1);
    }
    ctx.globalAlpha = 1;

    // The fit is taken at full height for the current pose, so the object
    // only grows or shrinks as it turns, never as the bars move.
    var pts = _buf(state, "rsPts", RS_BARS * 8 * 3);
    var cxs = (RS_BARS - 1) / 2;
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (var b = 0; b < RS_BARS; b++) {
        for (var c = 0; c < 8; c++) {
            var k = (b * 8 + c) * 3;
            var sg = RS_CORNERS[c];
            _rot(state, (b - cxs) * RS_SPACING + sg[0] * RS_HALF, sg[1] * RS_MAX_HEIGHT - RS_MAX_HEIGHT / 2, sg[2] * RS_HALF, pts, k);
            var zf = 1 / (pts[k + 2] + RS_DISTANCE);
            minX = Math.min(minX, pts[k] * zf);
            maxX = Math.max(maxX, pts[k] * zf);
            minY = Math.min(minY, -pts[k + 1] * zf);
            maxY = Math.max(maxY, -pts[k + 1] * zf);
        }
    }
    var f = Math.min((w - 2) / Math.max(1e-6, maxX - minX), (h - 2) / Math.max(1e-6, maxY - minY));
    var ox = w / 2 - (minX + maxX) / 2 * f;
    var oy = h / 2 - (minY + maxY) / 2 * f;

    ctx.lineWidth = 1;
    for (var bar = 0; bar < RS_BARS; bar++) {
        var l = Math.max(lv[bar * 2], lv[bar * 2 + 1]);
        var bh = RS_MIN_HEIGHT + l * (RS_MAX_HEIGHT - RS_MIN_HEIGHT);
        for (var c2 = 0; c2 < 8; c2++) {
            var k2 = (bar * 8 + c2) * 3;
            var sg2 = RS_CORNERS[c2];
            _rot(state, (bar - cxs) * RS_SPACING + sg2[0] * RS_HALF, sg2[1] * bh - RS_MAX_HEIGHT / 2, sg2[2] * RS_HALF, pts, k2);
        }
        ctx.strokeStyle = l > 0 ? _band(ink, Math.max(l, Model.LEVEL_DIM_BELOW)) : ink.dim;
        ctx.beginPath();
        for (var fi = 0; fi < RS_FACES.length; fi++) {
            var face = RS_FACES[fi];
            var nx = face.n[0], ny = face.n[1], nz = face.n[2];
            var nrx = nx * state.rsCy + nz * state.rsSy;
            var nrz1 = -nx * state.rsSy + nz * state.rsCy;
            var nry = ny * state.rsCp - nrz1 * state.rsSp;
            var nrz = ny * state.rsSp + nrz1 * state.rsCp;
            var v0 = (bar * 8 + face.v[0]) * 3;
            // The camera sits at z = -RS_DISTANCE looking down +z.
            if (nrx * pts[v0] + nry * pts[v0 + 1] + nrz * (pts[v0 + 2] + RS_DISTANCE) >= 0)
                continue;
            for (var e = 0; e <= 4; e++) {
                var vk = (bar * 8 + face.v[e % 4]) * 3;
                var zf2 = 1 / (pts[vk + 2] + RS_DISTANCE);
                var px = _clamp(ox + pts[vk] * zf2 * f, 0.5, w - 0.5);
                var py = _clamp(oy - pts[vk + 1] * zf2 * f, 0.5, h - 0.5);
                if (e === 0)
                    ctx.moveTo(px, py);
                else
                    ctx.lineTo(px, py);
            }
        }
        ctx.stroke();
    }
}

function stipple(ctx, w, h, levels, state, ink) {
    var n = ink.columns;
    var lv = _levels(state, levels, n);
    var cw = _colWidth(w, n, ink.gap);
    var pitch = 2;
    var dotsX = Math.max(1, Math.floor((cw + 1) / pitch));
    var rows = Math.max(1, Math.floor((h + 1) / pitch));
    var inset = (cw - ((dotsX - 1) * pitch + 1)) / 2;
    for (var i = 0; i < n; i++) {
        var x = i * (cw + ink.gap) + inset;
        var lit = Math.round(lv[i] * rows);
        for (var k = 0; k < Math.max(1, lit); k++) {
            ctx.fillStyle = lit === 0 ? ink.groove : _band(ink, (k + 1) / rows);
            var y = h - 1 - k * pitch;
            for (var d = 0; d < dotsX; d++)
                ctx.fillRect(Math.round(x + d * pitch), y, 1, 1);
        }
    }
}

var DRAW = {
    bars: bars, peaks: peaks, led: led, mirror: mirror, butterfly: butterfly,
    outline: outline, wave: wave, dots: dots, ascii: ascii, matrix: matrix,
    rain: rain, flame: flame, bubbles: bubbles, scope: scope, pulse: pulse,
    heartbeat: heartbeat, terrain: terrain, bricks: bricks, columns: columns,
    scatter: scatter, retro: retro, binary: binary, sakura: sakura,
    firework: firework, firefly: firefly, mosaic: mosaic, sand: sand,
    geyser: geyser, stereo: stereo, redsector: redsector, stipple: stipple
};
