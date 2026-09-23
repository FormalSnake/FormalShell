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
    { id: "terrain", label: "Terrain", description: "A scrolling ridge of recent loudness over the bass." }
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

function draw(id, ctx, w, h, levels, state, ink, dt, t) {
    var fn = DRAW.hasOwnProperty(id) ? DRAW[id] : DRAW.bars;
    var frame = (typeof dt === "number" && isFinite(dt) && dt > 0) ? Math.min(dt, MAX_DT) : 0;
    if (!(w > 0) || !(h > 0))
        return;
    fn(ctx, w, h, levels || [], state, ink, frame, t || 0);
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

var DRAW = {
    bars: bars, peaks: peaks, led: led, mirror: mirror, butterfly: butterfly,
    outline: outline, wave: wave, dots: dots, ascii: ascii, matrix: matrix,
    rain: rain, flame: flame, bubbles: bubbles, scope: scope, pulse: pulse,
    heartbeat: heartbeat, terrain: terrain
};
