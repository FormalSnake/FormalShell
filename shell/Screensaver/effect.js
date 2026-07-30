.pragma library

// Pure banner-effect state stepping (DESIGN.md's screensaver exception,
// M8b Task 7): every function below is a deterministic function of
// (column, row, frame, banner) — no Date.now(), no Math.random() — so
// Screensaver.qml stays a thin per-frame render layer over this and the
// whole animation is genuinely testable frame by frame. The banner itself
// (branding/screensaver.txt by default) is the entire subject: nothing is
// ever drawn outside its own width/height grid, in any effect.

// Plain ASCII so scramble/noise glyphs render identically in any monospace
// font, regardless of the font's own glyph coverage.
var NOISE_CHARSET = "01ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*<>/\\|+=";

var EFFECT_NAMES = ["decrypt", "rain", "expand", "slide", "scatter"];

// ---- banner parsing ------------------------------------------------------

// Splits raw banner text into an equal-width grid of rows: trims one
// trailing newline and space-pads every row to the widest row's length, so
// every effect can address (col, row) without its own bounds-checking.
function parseBanner(text) {
    var raw = (text || "").replace(/\n$/, "").split("\n");
    var width = 0;
    for (var i = 0; i < raw.length; i++)
        width = Math.max(width, raw[i].length);
    var rows = [];
    for (var r = 0; r < raw.length; r++) {
        var row = raw[r];
        while (row.length < width) row += " ";
        rows.push(row);
    }
    if (rows.length === 0) rows.push("");
    return { width: width, height: rows.length, rows: rows };
}

function targetChar(banner, col, row) {
    if (row < 0 || row >= banner.height || col < 0 || col >= banner.width)
        return " ";
    return banner.rows[row].charAt(col);
}

// Deterministic per-cell pseudo-random integer in [0, mod) — every effect's
// apparent "randomness" (stagger timing, arrival order) is really just this
// hash, so a whole activation is a pure function of frame: reproducible by
// tests, and identical in shape on every real activation too (only the
// chosen effect name varies run to run, never the math within it).
function hash(col, row, salt, mod) {
    var h = Math.abs((col * 374761393 + row * 668265263 + salt * 2246822519) % 1000003);
    return h % mod;
}

// ---- decrypt: static noise resolving to the banner, no direction --------
// Every non-space cell flickers through the noise charset until its own
// (hashed, scattered) reveal frame, then holds its target character
// forever. No motion, no directionality — a "hacker terminal" resolve.

var DECRYPT_SPAN = 40; // every cell's revealAt is < this, so it bounds convergence

function decryptCell(col, row, frame, banner) {
    var target = targetChar(banner, col, row);
    if (target === " ") return { char: " ", opacity: 0 };
    var revealAt = hash(col, row, 11, DECRYPT_SPAN);
    if (frame >= revealAt) return { char: target, opacity: 1 };
    var noiseIndex = Math.abs((col * 13 + row * 29 + frame * 5) % NOISE_CHARSET.length);
    return { char: NOISE_CHARSET.charAt(noiseIndex), opacity: 0.85 };
}

// ---- rain: falling trail that locks each cell once it passes over -------
// The restructured matrix rain (M7's original effect): a per-column head
// falls monotonically (no wrap — unlike a decorative loop, this one must
// actually finish) leaving a short fading trail; once the head passes a
// row for the first time that cell locks to its target character for good.

var RAIN_TRAIL = 3;

// Frames-per-row (not rows-per-frame): the banner is only a handful of
// rows tall, so a head moving a whole row every frame would settle almost
// instantly — these keep a column's fall visible for a couple of seconds
// instead of one.
function rainColumnPeriod(col) { return 6 + (col % 5); }
function rainColumnStartDelay(col) { return (col * 13) % 24; }

function rainCell(col, row, frame, banner) {
    var target = targetChar(banner, col, row);
    if (target === " ") return { char: " ", opacity: 0 };
    var elapsed = frame - rainColumnStartDelay(col);
    if (elapsed < 0) return { char: " ", opacity: 0 };
    var head = elapsed / rainColumnPeriod(col);
    if (head >= row) return { char: target, opacity: 1 };
    var behind = row - head;
    if (behind <= RAIN_TRAIL) {
        var noiseIndex = Math.abs((col * 3 + row * 5 + frame * 7) % NOISE_CHARSET.length);
        return { char: NOISE_CHARSET.charAt(noiseIndex), opacity: 1 - behind / (RAIN_TRAIL + 1) };
    }
    return { char: " ", opacity: 0 };
}

function rainConvergenceFrame(banner) {
    var worst = 0;
    for (var col = 0; col < banner.width; col++) {
        var needed = rainColumnStartDelay(col) + rainColumnPeriod(col) * (banner.height - 1);
        worst = Math.max(worst, needed);
    }
    return Math.ceil(worst) + RAIN_TRAIL + 2;
}

// ---- expand: reveal opens outward from the centre -----------------------
// No noise stage at all: a cell is either not-yet-open (blank) or open
// (its target character) — the open region is a diamond growing outward
// from the banner's centre, doubling row-distance to compensate for
// glyphs being visually taller than they are wide.

var EXPAND_SPEED = 2;

function _expandDistance(col, row, banner) {
    var cx = (banner.width - 1) / 2;
    var cy = (banner.height - 1) / 2;
    return Math.max(Math.abs(col - cx), Math.abs(row - cy) * 2);
}

function expandCell(col, row, frame, banner) {
    var target = targetChar(banner, col, row);
    if (target === " ") return { char: " ", opacity: 0 };
    var revealAt = Math.ceil(_expandDistance(col, row, banner)) * EXPAND_SPEED;
    if (frame >= revealAt) return { char: target, opacity: 1 };
    return { char: " ", opacity: 0 };
}

function expandConvergenceFrame(banner) {
    var maxDist = 0;
    for (var row = 0; row < banner.height; row++)
        for (var col = 0; col < banner.width; col++)
            maxDist = Math.max(maxDist, _expandDistance(col, row, banner));
    return Math.ceil(maxDist) * EXPAND_SPEED + 1;
}

// ---- slide: rows wipe in from alternating edges --------------------------
// Each row is its own curtain: even rows sweep open left-to-right, odd rows
// right-to-left, each column revealing in turn as the sweep passes it.
// Rows are themselves staggered so the whole banner assembles in a visible
// zigzag rather than all rows finishing at once.

var SLIDE_ROW_STAGGER = 6;
var SLIDE_STEP = 1;

function slideCell(col, row, frame, banner) {
    var target = targetChar(banner, col, row);
    if (target === " ") return { char: " ", opacity: 0 };
    var fromLeft = (row % 2) === 0;
    var sweepPos = fromLeft ? col : (banner.width - 1 - col);
    var revealAt = row * SLIDE_ROW_STAGGER + sweepPos * SLIDE_STEP;
    if (frame >= revealAt) return { char: target, opacity: 1 };
    return { char: " ", opacity: 0 };
}

function slideConvergenceFrame(banner) {
    return (banner.height - 1) * SLIDE_ROW_STAGGER + (banner.width - 1) * SLIDE_STEP + 1;
}

// ---- scatter: individual glyphs pop in at scattered moments --------------
// Unlike decrypt's dense, constantly-changing noise, scatter's canvas is
// mostly blank: each cell independently and abruptly "lands" at its own
// hashed arrival frame, fading in over a short final approach rather than
// flickering through unrelated glyphs first — a sparse, unordered
// materialize instead of a scramble-and-resolve.

var SCATTER_SPAN = 50;
var SCATTER_APPROACH = 4;

function scatterCell(col, row, frame, banner) {
    var target = targetChar(banner, col, row);
    if (target === " ") return { char: " ", opacity: 0 };
    var arriveAt = hash(col, row, 29, SCATTER_SPAN);
    if (frame >= arriveAt) return { char: target, opacity: 1 };
    var untilArrival = arriveAt - frame;
    if (untilArrival <= SCATTER_APPROACH)
        return { char: target, opacity: 0.2 + 0.2 * (SCATTER_APPROACH - untilArrival) };
    return { char: " ", opacity: 0 };
}

// ---- registry -------------------------------------------------------------

var _CELL_FNS = {
    decrypt: decryptCell,
    rain: rainCell,
    expand: expandCell,
    slide: slideCell,
    scatter: scatterCell
};

function isKnownEffect(name) {
    return EFFECT_NAMES.indexOf(name) >= 0;
}

// "random" or any unrecognised name deterministically falls back to a
// pick keyed on `seed` (the caller supplies a fresh seed per activation —
// see Screensaver.qml — so a long idle session still cycles variants).
function resolveEffectName(requested, seed) {
    if (isKnownEffect(requested)) return requested;
    return EFFECT_NAMES[Math.abs(seed) % EFFECT_NAMES.length];
}

// The number of frames after which `name` is guaranteed fully converged
// (every non-space cell showing its target character) for the given
// banner — used by tests, and available to callers that want to know when
// an activation has "settled".
function convergenceFrame(name, banner) {
    switch (name) {
    case "decrypt": return DECRYPT_SPAN;
    case "rain": return rainConvergenceFrame(banner);
    case "expand": return expandConvergenceFrame(banner);
    case "slide": return slideConvergenceFrame(banner);
    case "scatter": return SCATTER_SPAN;
    default: return convergenceFrame(resolveEffectName(name, 0), banner);
    }
}

// The full per-frame grid for `name`: banner.height arrays of banner.width
// { char, opacity } cells — Screensaver.qml's Canvas renders this directly
// at a fixed on-screen offset, no further per-effect logic on its side.
function frameState(name, frame, banner) {
    var fn = _CELL_FNS[name] || _CELL_FNS[resolveEffectName(name, 0)];
    var rows = [];
    for (var row = 0; row < banner.height; row++) {
        var cols = [];
        for (var col = 0; col < banner.width; col++)
            cols.push(fn(col, row, frame, banner));
        rows.push(cols);
    }
    return rows;
}

// ---- continuous cycling (M13b Task 5) ------------------------------------
// After an effect converges the controller holds the finished banner for
// screensaver.holdSeconds, then rerolls and animates again, indefinitely.
// Both helpers are pure so the reroll contract — a pinned effect replays
// itself, "random" never repeats the immediately previous effect — is unit
// tested rather than only observed in a smoke run.

// How many auto-timer ticks the converged banner holds before the reroll.
// Never less than one full frame, so holdSeconds: 0 still yields a rendered
// converged banner instead of an instant reroll mid-paint.
function holdFrames(holdSeconds, tickMs) {
    return Math.max(1, Math.ceil((holdSeconds * 1000) / tickMs));
}

// The next cycle's effect. A known (pinned) name replays itself — the fresh
// activation seed only resets the frame counter. "random" (or any unknown
// name, same fallback as resolveEffectName) picks from every effect except
// the immediately previous one, so consecutive cycles never repeat while
// more than one effect exists.
function rerollEffectName(requested, previousEffect, seed) {
    if (isKnownEffect(requested)) return requested;
    var pool = [];
    for (var i = 0; i < EFFECT_NAMES.length; i++) {
        if (EFFECT_NAMES[i] !== previousEffect)
            pool.push(EFFECT_NAMES[i]);
    }
    return pool[Math.abs(seed) % pool.length];
}

// ---- frame-pin resolution (ScreensaverIpc's `frame(n)`, M11 Task 1) ------
// Pure decision logic behind Screensaver.qml's deterministic frame pin: which
// counter actually renders, whether the free-running per-surface Timer
// should tick, and what the pin resolves to across an active/inactive
// transition. Kept here rather than inline in QML so the contract — a stale
// pin never survives deactivation — is directly testable instead of only
// exercised by a manual smoke run.

// -1 means "not pinned" — the free-running counter renders.
function resolveRenderFrame(pinnedFrame, autoFrame) {
    return pinnedFrame >= 0 ? pinnedFrame : autoFrame;
}

// The free-run Timer only ticks while nothing is pinned.
function autoTimerShouldRun(visible, pinnedFrame) {
    return visible && pinnedFrame < 0;
}

// Any deactivation releases a stale pin so the very next activation always
// free-runs from frame 0 rather than replaying whatever a previous headless
// recorder left it parked on.
function nextPinnedFrame(active, pinnedFrame) {
    return active ? pinnedFrame : -1;
}
