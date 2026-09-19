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
// `barCellWidth` (44) is `barCellHeight`'s counterpart on a vertical bar,
// and it is wider rather than equal because the two strips carry content
// differently: a horizontal cell reads an icon and its label side by side
// along the strip, while a vertical one stacks them upright (Cell.qml's
// content box, Components/CellRow.qml), so the strip has to be as wide as
// the widest label instead of as tall as one line. 44 holds four mono
// characters at the default `fontBaseSize` plus `controlPaddingY` either
// side, which is every percentage and temperature the bar renders; a label
// longer than that hides itself rather than overflowing
// (Components/CellLabel.qml).
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
// `popupWidthBubble` is elementary's own notification width
// (`notifications/data/application.css`, M60 T4). It is beside the snap
// points rather than on the ladder: a transcribed number that happens to
// sit between `Narrow` and `Default`, and only the bubble takes it.
// `popupHeightMenu{,Split,App}` are the launcher card's three settled
// heights, one per level kind (the grid root and every row list or grid, the
// split with its preview, an app view): the card never sizes to its rows, so
// typing scrolls results inside a card that stays put, and only a level
// change can morph it. `LAUNCHER` below caps each at a share of the output.
// `switcherIcon` and `switcherInset` are Gala's two window-switcher numbers
// (`lib/Widgets/WindowSwitcherIcon.vala`, M60 T6): the app icon a cell
// carries, and the room the card keeps off every edge of the output, which
// is also what caps how many cells fit across before the row wraps.
// `keycapHeight` is shadcn's `<Kbd>` (`h-5`): one key's cap, and its
// narrowest width too, so a one-letter cap is square.
var SEMANTIC_SPACING_BASE = {
    controlGap: 8, controlPaddingX: 12, controlPaddingY: 6,
    controlHeight: 32, barCellHeight: 28, barCellWidth: 44, barMargin: 6,
    popupRowHeight: 28, rowGap: 4, iconGap: 8,
    panelPadding: 12, sectionGap: 16, screenPadding: 12,
    trackThickness: 6,
    popupWidthNarrow: 320, popupWidthDefault: 380, popupWidthWide: 480, popupWidthMenu: 560,
    popupWidthMenuSplit: 840, popupWidthMenuApp: 900,
    popupWidthBubble: 332,
    popupHeightMenu: 520, popupHeightMenuSplit: 560, popupHeightMenuApp: 720,
    switcherIcon: 64, switcherInset: 64,
    keycapHeight: 20
};

function spacingTokens(scale) {
    var out = {};
    for (var key in SPACING_BASE)
        out[key] = Math.round(SPACING_BASE[key] * scale);
    for (var semanticKey in SEMANTIC_SPACING_BASE)
        out[semanticKey] = Math.round(SEMANTIC_SPACING_BASE[semanticKey] * scale);
    return out;
}

// The launcher's counts and ceilings, unscaled: a column count and a share
// of the output are not lengths. `heightShare` caps the card at that much of
// the output's height (`appHeightShare` for an app view, a whole surface
// rather than a list). `pickerColumns` and `emojiColumns` are the two fixed
// grids; the app grid's count comes off its own width instead. `rootApps` is
// how many of the ranked apps the root's Applications section carries: the
// commands follow it, so a machine with two hundred apps must not push them
// two hundred cells down. The Apps route lists the rest.
var LAUNCHER = {
    heightShare: 0.6,
    appHeightShare: 0.82,
    pickerColumns: 4,
    emojiColumns: 8,
    rootApps: 8
};

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

// The corner a picture takes at its own size (owner, 2026-08-26: "make sure
// that the album art is slightly rounded ... don't make it a circle with how
// small it is"). The radius ladder above is sized for controls, so `sm` on
// the bar's 17px cover is a third of the way to a circle and reads as a
// lozenge. A quarter of the shorter side instead, capped at `sm` so a large
// cover keeps a step off the ladder and floored at 2 so it never rounds away
// to nothing. `sm` is already 0 at a zero base, so retro squares covers the
// way it squares everything else without a second check on the preset.
function coverRadius(sm, extent) {
    if (!(sm > 0))
        return 0;
    var e = (typeof extent === "number" && isFinite(extent)) ? extent : 0;
    return Math.max(2, Math.min(sm, Math.round(e / 4)));
}

// --- §4 motion tokens ---------------------------------------------------

// Two families and the property picks the family (M54 D1/D2): `spatial*`
// paces anything with a position or a size (x, y, width, height, margins,
// scale, radius, rotation, an emerge, a morph, a cursor), `effects*` paces
// anything with none (opacity, colour, a progress that only drives alpha).
// The spatial curves carry a y control point above 1, so what travels
// overshoots its rest by a few pixels and settles back; the effects curves
// never do, since an opacity past 1 is not a look, it is a clamp. Material
// 3 Expressive's own numbers, the same set caelestia runs on, read at
// ce84c7b: mechanics and values, no ported code.
//
// `emphasized` is the workspace pill alone (two edges on one clock at
// different durations is what makes it stretch across the gap) and
// `emphasizedDecel` a toast's arrival from off screen; both are curves M3
// defines outside the two families. `emphasizedDecel` has no duration of
// its own, it runs on `spatial`.
//
// `reveal` paces the full-screen fades: the wallpaper and palette
// crossfades, the lock's blank and wake and the screensaver's own
// enter/exit (§4 rule 6, owner's call 2026-08-12), on `effectsSlow`'s
// curve since a full-screen swap is opacity end to end.
//
// `enabled: false` (the motion.enabled settings key) zeroes every duration
// and leaves the curves alone: a zero-duration animation lands on the same
// end state whatever curve it carries, so disabling motion never moves a
// pixel of chrome, and `Deform` holds identity (M54 D5).
//
// `marqueePxPerSec`/`marqueeHoldMs` pace the now-playing bar cell's
// overflow scroll (owner-requested, M16 Task 11), a constant scroll rate,
// not a duration, so `enabled` doesn't zero them the way it zeroes the
// durations above; the caller (MarqueeText.qml's `_marquee`) gates the
// whole animation on `Theme.motionEnabled` directly and falls back to the
// elide instead of scrolling at 0px/s.
var MOTION_BASE = {
    spatialFast: 350, spatial: 500, spatialSlow: 650,
    effectsFast: 150, effects: 200, effectsSlow: 300,
    emphasized: 400, reveal: 400,
    marqueePxPerSec: 30, marqueeHoldMs: 2000
};

function motionTokens(enabled) {
    return {
        spatialFast: enabled ? MOTION_BASE.spatialFast : 0,
        spatial: enabled ? MOTION_BASE.spatial : 0,
        spatialSlow: enabled ? MOTION_BASE.spatialSlow : 0,
        effectsFast: enabled ? MOTION_BASE.effectsFast : 0,
        effects: enabled ? MOTION_BASE.effects : 0,
        effectsSlow: enabled ? MOTION_BASE.effectsSlow : 0,
        emphasized: enabled ? MOTION_BASE.emphasized : 0,
        reveal: enabled ? MOTION_BASE.reveal : 0,
        marqueePxPerSec: MOTION_BASE.marqueePxPerSec,
        marqueeHoldMs: MOTION_BASE.marqueeHoldMs
    };
}

// One cubic bezier per kind as Qt wants it for `easing.bezierCurve`: the
// two control points followed by the end point, which is always (1, 1).
// `emphasized` is two segments (12 numbers), M3's own shape: a long flat
// lead-in to (1/6, 0.4) and a fast decel out of it.
var MOTION_CURVES = {
    spatialFast: [0.42, 1.67, 0.21, 0.9, 1, 1],
    spatial: [0.38, 1.21, 0.22, 1, 1, 1],
    spatialSlow: [0.39, 1.29, 0.35, 0.98, 1, 1],
    effectsFast: [0.31, 0.94, 0.34, 1, 1, 1],
    effects: [0.34, 0.8, 0.34, 1, 1, 1],
    effectsSlow: [0.34, 0.88, 0.34, 1, 1, 1],
    emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
    emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
};

// `reveal` rides `effectsSlow`'s curve on its own longer clock. An unknown
// kind falls back to the default spatial curve rather than throwing: a
// binding that lost its curve would land the animation on Qt's linear
// default, which reads as a machine moving something.
function motionCurve(kind) {
    if (kind === "reveal")
        return MOTION_CURVES.effectsSlow;
    return MOTION_CURVES[kind] || MOTION_CURVES.spatial;
}

// The velocity deform (M54 D7), caelestia's constants verbatim
// (blobrect.cpp at ce84c7b). `maxStretch` caps the squash at 35% however
// fast a card travels, `deadBand` is the px/s under which a sample counts
// as standing still, `stiffness`/`damping` are the spring the three matrix
// components ride (underdamped: it overshoots and settles), and `epsilon`
// is the deviation under which the matrix snaps to identity so a card at
// rest costs nothing. `amount` is per consumer, not a constant: 0.1 for
// the launcher, 0.15 for a popout, 0.25 for the OSD.
var DEFORM = { maxStretch: 0.35, deadBand: 5, stiffness: 200, damping: 16, epsilon: 0.002 };
