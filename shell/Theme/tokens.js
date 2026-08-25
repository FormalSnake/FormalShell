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
// scale step), same scaling rule as SPACING_BASE. shadcn redesign
// (2026-08-25): `controlHeight`, `barCellHeight`, `barMargin`,
// `controlPaddingX`/`Y`, `rowGap`, `iconGap`, `panelPadding` and
// `sectionGap` take the spec's own values, decoupling `controlPaddingX`/`Y`
// from the bare `lg`/`sm` scale steps they used to mirror exactly. Older
// keys not named in the spec (`controlGap`, `inputPaddingY`,
// `popupRowHeight`, `rowPaddingX`, `labelGap`, `panelGap`) keep their
// existing values: surfaces still reading them move to the new semantic
// keys on their own retrofit milestone (M45 prunes what nothing reads any
// more). `trackThickness` is the one flat-fill-track idiom (OSD,
// volume/brightness/life-progress sliders), a single token so every track
// site renders the same thickness instead of each surface picking its own
// literal. `popupWidth{Narrow,Default,Wide,Menu,MenuSplit,MenuApp}` are the
// six snap points every floating card's width picks from. `MenuSplit`
// (1.5x `Menu`) is the menu's own split-pane step, for the
// clipboard/share-history route's left-half list plus right-half preview,
// which needs more than one column of rows can hold. `MenuApp` is one step
// past it, for a menu route rendering a whole app view (Menu/appviews.js):
// two ledger columns of labelled numbers, both carrying their own values,
// where the split route's right half is a single preview that can take
// whatever room is left over.
var SEMANTIC_SPACING_BASE = {
    controlGap: 8, controlPaddingX: 12, controlPaddingY: 6, inputPaddingY: 7,
    controlHeight: 32, barCellHeight: 28, barMargin: 6,
    popupRowHeight: 28, rowGap: 4, iconGap: 8, rowPaddingX: 12,
    labelGap: 4, panelGap: 14, panelPadding: 12, sectionGap: 16,
    trackThickness: 6,
    popupWidthNarrow: 320, popupWidthDefault: 380, popupWidthWide: 480, popupWidthMenu: 560,
    popupWidthMenuSplit: 840, popupWidthMenuApp: 900
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

// shadcn font-weight tokens (spec "Type"). Flat, not scaled: a weight is a
// font axis value, not a size.
var WEIGHTS = { normal: 400, medium: 500, semibold: 600 };

// Radius tokens (spec "Radius"): sm/md/lg/xl step off the settings-driven
// base by fixed 2-4px offsets, floored at 2 so a base pinned near 0 never
// produces a negative or invisible radius.
function radiusTokens(base) {
    var b = typeof base === "number" ? base : 0;
    return {
        sm: Math.max(2, b - 4),
        md: Math.max(2, b - 2),
        lg: Math.max(2, b),
        xl: Math.max(2, b + 4)
    };
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
// elide instead of scrolling at 0px/s.
var MOTION_BASE = { fast: 100, standard: 130, slide: 4, reveal: 400, marqueePxPerSec: 30, marqueeHoldMs: 2000 };

function motionTokens(enabled) {
    return {
        fast: enabled ? MOTION_BASE.fast : 0,
        standard: enabled ? MOTION_BASE.standard : 0,
        slide: MOTION_BASE.slide,
        reveal: enabled ? MOTION_BASE.reveal : 0,
        marqueePxPerSec: MOTION_BASE.marqueePxPerSec,
        marqueeHoldMs: MOTION_BASE.marqueeHoldMs
    };
}
