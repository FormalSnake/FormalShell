.pragma library

// Omarchy-derived token math (DESIGN.md §1): pure functions only, no theme
// object touches this file. `Theme.qml` wires these against the live
// matugen palette (`palette.js`'s color roles); tests exercise the maths
// here directly, against `.pragma library` precedent elsewhere in the repo
// (menu/search.js, screensaver/effect.js, …).

// --- 1.3 scale roots -------------------------------------------------

// fontScale is fontBaseSize/13 — 13 is the shell's long-standing body size,
// so the default base size produces fontScale 1.0 and every multiplier
// below reduces to the exact px values already shipping.
var FONT_MULTIPLIERS = {
    caption: 0.833, bodySmall: 0.917, body: 1.0, subtitle: 1.083,
    title: 1.167, heading: 1.333, display: 2.0, displayLarge: 2.333
};

function fontScale(baseSize) {
    return baseSize / 13;
}

// Every font token as `fontBaseSize * multiplier`, rounded — retheming the
// one `baseSize` number rescales every token proportionally.
function fontTokens(baseSize) {
    var out = { baseSize: baseSize };
    for (var key in FONT_MULTIPLIERS)
        out[key] = Math.round(baseSize * FONT_MULTIPLIERS[key]);
    return out;
}

// Base px per token at spacingScale 1.0.
var SPACING_BASE = {
    xxs: 2, xs: 3, sm: 4, md: 6, lg: 8, xl: 10, xxl: 12, xxxl: 14, huge: 18
};

// Semantic spacing tokens (a control's own padding/height, not a bare
// scale step) — same scaling rule as SPACING_BASE. `trackThickness` is the
// one flat-fill-track idiom (OSD, volume/brightness/life-progress sliders)
// — a single token so every track site renders the same thickness instead
// of each surface picking its own literal. `controlPaddingX`/`Y` match
// `lg`/`sm` exactly (2026-08-07 spacing-consistency pass) — Cell.qml's
// implicit sizing routes through these now instead of the bare scale
// steps, so the two numbers can't drift apart independently again.
// `popupWidth{Narrow,Default,Wide,Menu}` are the four snap points every
// floating card's width now picks from (DESIGN.md §1.3's popup width
// scale) instead of each surface choosing its own literal.
var SEMANTIC_SPACING_BASE = {
    controlGap: 8, controlPaddingX: 8, controlPaddingY: 4, inputPaddingY: 7,
    controlHeight: 28, popupRowHeight: 28, rowGap: 8, rowPaddingX: 12,
    labelGap: 4, panelGap: 14, panelPadding: 18, popupPadding: 14,
    trackThickness: 6,
    popupWidthNarrow: 280, popupWidthDefault: 320, popupWidthWide: 400, popupWidthMenu: 560
};

function spacingTokens(scale) {
    var out = {};
    for (var key in SPACING_BASE)
        out[key] = Math.round(SPACING_BASE[key] * scale);
    for (var semanticKey in SEMANTIC_SPACING_BASE)
        out[semanticKey] = Math.round(SEMANTIC_SPACING_BASE[semanticKey] * scale);
    return out;
}

// DESIGN.md §2.3's uppercase meta-row tracking, the wider variant the
// lock/greeter date label uses, and `display`'s own wide tracking for the
// lock clock's oversized digits — a font metric, so it scales with
// fontScale (not spacingScale) to stay proportional to the text it tracks.
var LETTER_SPACING_BASE = { meta: 1, wide: 2, display: 6 };

function letterSpacingTokens(scale) {
    var out = {};
    for (var key in LETTER_SPACING_BASE)
        out[key] = Math.round(LETTER_SPACING_BASE[key] * scale);
    return out;
}

// --- §4 motion tokens ---------------------------------------------------

// The owner's brief verbatim: "fast and subtle, it should just look
// better". `fast` paces hover fills, `standard` paces surface enter/exit —
// both inside DESIGN.md §4's 90-140ms band. `slide` is the enter/exit
// translate distance (§4's 4-8px). `reveal` paces the two full-screen
// fades: the wallpaper crossfade (§4's third named carve-out, beside the
// pulse and the screensaver) and the screensaver's own enter/exit
// (§4 rule 6, owner's call 2026-08-12) — deliberately outside the
// 90-140ms band since a full-screen swap reads better slower than a
// control hover. `enabled: false`
// (the motion.enabled settings key) short-circuits `fast`/`standard`/
// `reveal` to 0 while leaving `slide` intact: a zero-duration animation
// still lands on the same end state, so disabling motion never moves a
// single pixel of chrome.
//
// `marqueePxPerSec`/`marqueeHoldMs` pace the now-playing bar cell's
// overflow scroll (owner-requested, M16 Task 11) — a constant scroll rate,
// not a duration, so `enabled` doesn't zero them the way it zeroes
// fast/standard/reveal; the caller (NowPlaying.qml) gates the whole
// animation on `Theme.motionEnabled` directly and falls back to today's
// elide instead of scrolling at 0px/s. `rotatePeriod` paces the power
// panel's charging/discharging phrase rotation the same way — a fixed
// cadence the caller (PowerPanel.qml) also gates on `Theme.motionEnabled`
// itself, not a value this function zeroes.
var MOTION_BASE = { fast: 100, standard: 130, slide: 6, reveal: 400, marqueePxPerSec: 30, marqueeHoldMs: 2000, rotatePeriod: 3000 };

function motionTokens(enabled) {
    return {
        fast: enabled ? MOTION_BASE.fast : 0,
        standard: enabled ? MOTION_BASE.standard : 0,
        slide: MOTION_BASE.slide,
        reveal: enabled ? MOTION_BASE.reveal : 0,
        marqueePxPerSec: MOTION_BASE.marqueePxPerSec,
        marqueeHoldMs: MOTION_BASE.marqueeHoldMs,
        rotatePeriod: MOTION_BASE.rotatePeriod
    };
}

// --- 1.1 four interactive states --------------------------------------

// fillAlpha/borderWidth per state, independent of color — the caller
// resolves fill color separately (a palette role or raw hex) and pairs it
// with this appearance. Border color/alpha is no longer part of this
// table (2026-08-07 revision, DESIGN.md §1.1/§1.4): a bordered state's
// border always draws the `rule` token at alpha 1.0, resolved by the
// caller (`Theme.stateStyle()`), not stored per-state here. `focus` is a
// deliberate alias of `hover-cursor` (DESIGN.md: "defaults to mirroring
// hover-cursor"); `pressed` is a transient mouse-down overlay, never a
// persistent state.
var STATE_APPEARANCE = {
    "normal": { fillAlpha: 0.04, borderWidth: 2 },
    "hover-cursor": { fillAlpha: 0.08, borderWidth: 2 },
    "selected": { fillAlpha: 0.18, borderWidth: 0 },
    "pressed": { fillAlpha: 0.22, borderWidth: 2 }
};
STATE_APPEARANCE["focus"] = STATE_APPEARANCE["hover-cursor"];

function stateAppearance(name) {
    return STATE_APPEARANCE[name] || STATE_APPEARANCE["normal"];
}

// Paint-priority resolution (DESIGN.md §1.1): pressed > focus (only when
// the control is real-focusable) > hover-cursor > selected > normal.
// `flags`: { pressed, focused, focusable, hovered, selected }.
function resolveState(flags) {
    var f = flags || {};
    if (f.pressed) return "pressed";
    if (f.focused && f.focusable) return "focus";
    if (f.hovered) return "hover-cursor";
    if (f.selected) return "selected";
    return "normal";
}

// --- 1.2 border specs --------------------------------------------------

// A border spec carries color, per-side widths, and an optional gradient —
// never a bare scalar width. `widths` may be a partial object; missing
// sides fall back to `defaultWidth` (all four sides uniform is the common
// case a renderer picks the cheap flat-Rectangle path for).
function borderSpec(color, widths, defaultWidth, gradient) {
    var w = widths || {};
    var d = defaultWidth === undefined ? 0 : defaultWidth;
    return {
        color: color,
        widths: {
            top: w.top !== undefined ? w.top : d,
            right: w.right !== undefined ? w.right : d,
            bottom: w.bottom !== undefined ? w.bottom : d,
            left: w.left !== undefined ? w.left : d
        },
        gradient: gradient || { colors: [], angle: 45, enabled: false }
    };
}

function uniformBorderSpec(color, width) {
    return borderSpec(color, { top: width, right: width, bottom: width, left: width }, width);
}

// True when a renderer can use the cheap flat-Rectangle-with-border path:
// no gradient, and all four sides agree.
function isUniformBorder(spec) {
    var w = spec.widths;
    return !spec.gradient.enabled && w.top === w.right && w.right === w.bottom && w.bottom === w.left;
}

// --- selection inversion (§1.1 ASCII-OS override) ----------------------

// { bg, fg } for the selection-inversion pair (DESIGN.md §2.2, 2026-08-07
// revision): always accent-carried — `role` picks `"accent"` (default) or
// `"urgent"` for an urgent-carrying row. The old photo-negative
// foreground/background pair is retired shell-wide, not kept as an option.
function invertedPair(colors, role) {
    return role === "urgent"
        ? { bg: colors.urgent, fg: colors.onUrgent }
        : { bg: colors.accent, fg: colors.onAccent };
}
