.pragma library

// Pure matrix-rain state stepping (DESIGN.md's "themed terminal-text-effect
// animation", spec §10, M7 Task 5): every function is a deterministic
// function of (column, row, frame) — no Date.now(), no randomness — so
// Screensaver.qml stays a thin per-frame render layer over this and the
// whole animation is genuinely testable frame by frame.

// Plain ASCII so it renders identically in any monospace font, regardless
// of the font's own glyph coverage — no dependency on Nerd Font codepoints
// for a purely decorative effect.
var CHARSET = "01ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*<>/\\|+-=";

// How many rows a glyph stays lit behind a column's head before decaying to
// fully off — the visible "trail" length.
var TRAIL_LENGTH = 12;

// Deterministic per-column fall speed (rows per frame): a small spread so
// columns drift out of phase with each other instead of marching in
// lockstep down the screen.
function columnSpeed(column) {
    return 1 + (column % 5);
}

// Deterministic per-column start offset so every column's head begins at a
// different point in its cycle rather than all starting in sync.
function columnOffset(column) {
    return (column * 13) % 97;
}

// The row a column's head (its brightest glyph) occupies at a given frame.
// Cycles modulo (rowCount + TRAIL_LENGTH) and is shifted down by
// TRAIL_LENGTH so the head's trail fully drains off the top of the screen
// before that same head reappears at the top — the returned value goes
// negative during that drain, which is fine: brightnessAt() below simply
// reads it as "no visible row is that far behind yet".
function headRow(column, frame, rowCount) {
    var cycle = rowCount + TRAIL_LENGTH;
    var pos = (columnOffset(column) + frame * columnSpeed(column)) % cycle;
    return pos - TRAIL_LENGTH;
}

// Deterministic glyph selection: a function of column, row AND frame (not
// row alone) so a glyph visibly changes as the trail passes over it,
// instead of the same static character just scrolling past.
function glyphAt(column, row, frame) {
    var index = Math.abs((column * 31 + row * 7 + frame * 3) % CHARSET.length);
    return CHARSET.charAt(index);
}

// Brightness (0..1) of the glyph at `row` in `column` at `frame`: 1 at the
// head itself, decaying linearly over the TRAIL_LENGTH rows behind it, and
// 0 (resting — nothing drawn) everywhere else, whether that's still ahead
// of the head or already further behind than the trail reaches.
function brightnessAt(column, row, frame, rowCount) {
    var head = headRow(column, frame, rowCount);
    var behind = head - row;
    if (behind < 0 || behind > TRAIL_LENGTH) return 0;
    return 1 - behind / TRAIL_LENGTH;
}

// One column's full per-frame state: glyph + brightness for every row.
function columnState(column, frame, rowCount) {
    var rows = [];
    for (var row = 0; row < rowCount; row++) {
        rows.push({
            char: glyphAt(column, row, frame),
            brightness: brightnessAt(column, row, frame, rowCount)
        });
    }
    return rows;
}

// The full grid for one frame: columnCount arrays of rowCount cells each —
// Screensaver.qml's Canvas renders this directly, no further math on its
// side.
function frameState(columnCount, rowCount, frame) {
    var columns = [];
    for (var c = 0; c < columnCount; c++)
        columns.push(columnState(c, frame, rowCount));
    return columns;
}
