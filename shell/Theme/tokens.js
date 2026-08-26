.pragma library

// Omarchy-derived token math (DESIGN.md §1): pure functions only, no theme
// object touches this file. `Theme.qml` wires these against the live
// matugen palette (`palette.js`'s color roles); tests exercise the maths
// here directly, against `.pragma library` precedent elsewhere in the repo
// (menu/search.js, screensaver/effect.js, …).

// --- 1.3 scale roots -------------------------------------------------

// fontScale is fontBaseSize/13, 13 is the shell's long-standing body size,
// so the default base size produces fontScale 1.0 and every multiplier
// below reduces to the exact px values already shipping.
var FONT_MULTIPLIERS = {
    caption: 0.833, bodySmall: 0.917, body: 1.0, subtitle: 1.083,
    title: 1.167, heading: 1.333, display: 2.0, displayLarge: 2.333
};

function fontScale(baseSize) {
    return baseSize / 13;
}

// Every font token as `fontBaseSize * multiplier`, rounded, retheming the
// one `baseSize` number rescales every token proportionally.
function fontTokens(baseSize) {
    var out = { baseSize: baseSize };
    for (var key in FONT_MULTIPLIERS)
        out[key] = Math.round(baseSize * FONT_MULTIPLIERS[key]);
    return out;
}

// Base px per token at spacingScale 1.0.
var SPACING_BASE = {
    xxs: 2, xs: 3, sm: 4, md: 6, lg: 8, xl: 10, xxl: 12, huge: 18
};

// Semantic spacing tokens (a control's own padding/height, not a bare
// scale step), same scaling rule as SPACING_BASE. shadcn redesign
// (2026-08-25): `controlHeight`, `barCellHeight`, `barMargin`,
// `controlPaddingX`/`Y`, `rowGap`, `iconGap`, `panelPadding` and
// `sectionGap` take the spec's own values, decoupling `controlPaddingX`/`Y`
// from the bare `lg`/`sm` scale steps they used to mirror exactly. Older
// keys not named in the spec (`controlGap`, `popupRowHeight`) keep their
// existing values while surfaces still read them. `panelGap` (14) is gone:
// one padding rule (DESIGN.md §1) leaves every floating surface sitting
// `panelPadding` off the edge it hangs from, so a fourth number had nothing
// left to describe.
// `screenPadding` (M48 D3) is the one distance every floating surface keeps
// from a screen edge it hangs from: panels sit `barMargin` under the bar and
// `screenPadding` in from the side, the notification centre takes it on
// three edges, toasts and the OSD take it from theirs, and every surface's
// height is capped at the screen minus the bar and these paddings so its
// content scrolls instead of running off the display. Separate from
// `panelPadding`, which is a card's own inset: one describes the gap outside
// a surface, the other the gap inside it, and they only happen to share a
// value today.
// `trackThickness` is the one flat-fill-track idiom (OSD,
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
    controlGap: 8, controlPaddingX: 12, controlPaddingY: 6,
    controlHeight: 32, barCellHeight: 28, barMargin: 6,
    popupRowHeight: 28, rowGap: 4, iconGap: 8,
    panelPadding: 12, sectionGap: 16, screenPadding: 12,
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
// lock clock's oversized digits, a font metric, so it scales with
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

// Holds a settings-supplied number inside a range. Anything that is not a
// finite number resolves to `fallback` rather than to `min`, which for an
// alpha would mean a surface nobody can see. Same shape as
// HotCorners/corners.js's own `_clampedNumber`, minus the rounding and the
// warning, since a fraction is not an integer and Theme has no warning
// channel.
function clamp(value, min, max, fallback) {
    if (value === undefined || value === null)
        return fallback;
    var n = Number(value);
    if (!isFinite(n))
        return fallback;
    return Math.max(min, Math.min(max, n));
}

// Radius tokens (spec "Radius"): sm/md/lg/xl step off the settings-driven
// base by fixed 2-4px offsets, floored at 2 so a base pinned near 0 never
// produces a negative or invisible radius. A base of 0 is not "near 0": it
// is the retro preset (M49 D2) asking for square corners, so it returns
// zeros and the floor only applies once the base is positive. Anything that
// is not a number reads as 0 and squares the same way.
function radiusTokens(base) {
    var b = typeof base === "number" ? base : 0;
    if (!(b > 0))
        return { sm: 0, md: 0, lg: 0, xl: 0 };
    return {
        sm: Math.max(2, b - 4),
        md: Math.max(2, b - 2),
        lg: Math.max(2, b),
        xl: Math.max(2, b + 4)
    };
}

// --- Interaction states -------------------------------------------------

// What hover and press paint on a surface the compositor blurs behind.
// `accent` is the right colour on an opaque shadcn page, but every surface
// here is drawn at `surfaceOpacity`, so what the pointer actually lands on
// is the card colour mixed with whatever the wallpaper left behind it. An
// opaque `accent` chip on top of that lands at a delta the wallpaper
// decides: a bright wallpaper lifts the surface past `accent` and the hover
// reads as a dark patch, and a wallpaper close to `card` leaves no delta to
// see at all, which is what made the bar's hover all but invisible. A wash
// of the surface's own ink stacks on top of whatever resolved there
// instead, so the lift keeps its size and its direction over every
// wallpaper. That is what `accent` already is on an opaque page: zinc's
// `#27272a` is `card` under white at 0.07, `#f4f4f5` is `card` under black
// at 0.043. `hover` takes a larger step than either, since a bar cell sits
// on `card` rather than on `background` and has that much less room between
// the two to read against; `press` is the same wash one step further on.
//
// `filledHover`/`filledPress` are shadcn's `hover:bg-primary/90` for a
// control that already carries a colour: the fill blended toward
// `background` and left opaque. Dropping the fill's own opacity instead is
// what shadcn's `/90` means on an opaque page and something else here, a
// primary button on a translucent panel goes see-through and the wallpaper
// reads straight through its label.
var STATE_ALPHA = {
    dark: { hover: 0.1, press: 0.16, filledHover: 0.1, filledPress: 0.18 },
    light: { hover: 0.06, press: 0.1, filledHover: 0.1, filledPress: 0.18 }
};

function stateAlpha(mode) {
    return mode === "light" ? STATE_ALPHA.light : STATE_ALPHA.dark;
}

// --- §4 motion tokens ---------------------------------------------------

// The owner's brief verbatim: "fast and subtle, it should just look
// better". `fast` paces hover fills, `standard` paces surface enter/exit,
// both inside DESIGN.md §4's 90-140ms band. `slide` is the enter/exit
// translate distance (§4's 4-8px). `reveal` paces the two full-screen
// fades: the wallpaper crossfade (§4's third named carve-out, beside the
// pulse and the screensaver) and the screensaver's own enter/exit
// (§4 rule 6, owner's call 2026-08-12), deliberately outside the
// 90-140ms band since a full-screen swap reads better slower than a
// control hover. `enabled: false`
// (the motion.enabled settings key) short-circuits `fast`/`standard`/
// `reveal` to 0 while leaving `slide` intact: a zero-duration animation
// still lands on the same end state, so disabling motion never moves a
// single pixel of chrome.
//
// `marqueePxPerSec`/`marqueeHoldMs` pace the now-playing bar cell's
// overflow scroll (owner-requested, M16 Task 11), a constant scroll rate,
// not a duration, so `enabled` doesn't zero them the way it zeroes
// fast/standard/reveal; the caller (NowPlaying.qml) gates the whole
// animation on `Theme.motionEnabled` directly and falls back to today's
// elide instead of scrolling at 0px/s.
// `emphasized` (250) is the one duration longer than the 90-140ms control
// band that still paces chrome rather than a full screen: the bar's
// workspace indicator, where a single pill slides and stretches between dot
// slots and needs the travel to be readable as one movement. `standard`
// makes the same slide read as a jump.
var MOTION_BASE = { fast: 100, standard: 130, emphasized: 250, slide: 4, reveal: 400, marqueePxPerSec: 30, marqueeHoldMs: 2000 };

function motionTokens(enabled) {
    return {
        fast: enabled ? MOTION_BASE.fast : 0,
        standard: enabled ? MOTION_BASE.standard : 0,
        emphasized: enabled ? MOTION_BASE.emphasized : 0,
        slide: MOTION_BASE.slide,
        reveal: enabled ? MOTION_BASE.reveal : 0,
        marqueePxPerSec: MOTION_BASE.marqueePxPerSec,
        marqueeHoldMs: MOTION_BASE.marqueeHoldMs
    };
}
