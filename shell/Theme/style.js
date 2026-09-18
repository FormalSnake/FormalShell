.pragma library

// The resolver behind `Theme.style` (M59 T2, the 2026-09-17 spec's Part 1):
// a theme is one table of box descriptions keyed by role, and this turns an
// entry plus a state into the numbers and colours `Components/Box.qml`
// draws. Pure functions with no palette of its own, so a table can be
// validated and its resolution exercised without the Quickshell singleton
// (tests/tst_theme_style.qml); `Theme.box()` is the one caller that supplies
// the live palette, the mode and the surface alpha.

// Every role a table must carry, and the states each one describes. An
// empty list is a role with one box and no states at all; otherwise the
// FIRST entry is the base every other state merges over, which is why
// `switch.track` reads `off` before `on` rather than alphabetically. A role
// or a state missing from a table fails tst_theme_style.qml, so a theme
// cannot silently fall back to another theme's chrome.
//
// `button` disabled is not here: it is opacity 0.5 on the whole control
// rather than a box of its own, and it stays in the primitive.
var ROLES = {
    "bar": [],
    "frame": [],
    "card": ["rest", "opaque"],
    "notification": ["rest", "critical", "flat", "flatCritical"],
    "popover": [],
    "menu": [],
    "cell": ["rest", "ghost", "hover", "active", "selected", "destructive", "warning"],
    "cell.mark": [],
    "button.default": ["rest", "hover", "press"],
    "button.outline": ["rest", "hover", "press"],
    "button.ghost": ["rest", "hover", "press"],
    "button.selected": ["rest", "hover", "press"],
    "button.destructive": ["rest", "hover", "press"],
    "input": ["rest", "focus", "error"],
    "input.selection": [],
    "switch.track": ["off", "on"],
    "switch.knob": [],
    "track.groove": [],
    "track.fill": [],
    "track.notch": [],
    "trough": [],
    "segmented.chip": [],
    "cursor": [],
    "scrim": []
};

// The habits (T7): what a surface reads instead of testing a theme name.
// Each key's allowed values, both columns of the spec's own table, so a
// typo in a table fails the test rather than reaching a `Loader` as a
// source that does not exist.
var HABITS = {
    bar: ["strip", "wingpanel"],
    emerge: ["join", "popover"],
    notification: ["row", "bubble"],
    launcher: ["list", "grid"],
    switcher: [true, false]
};

// The clocks a habit brings with it (M60 T2), one entry per key: a
// duration and a curve, each either a number (a curve is the control
// points `easing.bezierCurve` wants) or the name of one of the shell's own
// motion families (shell/Theme/tokens.js), which is how a table whose
// emerge rides the shipped clock says so instead of transcribing it.
// `emerge` paces a drawer's entrance and its exit: the metamorphosis card
// budding off the line, the pantheon popover dropping out of its cell.
var MOTION_KEYS = ["emerge"];

// The washes a pointer paints, one entry per state (T3). Kept beside the
// roles rather than inside them: every role that takes a pointer takes the
// same four, and `Theme.hoverFill` and friends derive from here.
var WASH_KEYS = ["hover", "press", "filledHover", "filledPress"];

// A radius step names one of `Theme.radius{Sm,Md,Lg,Xl}`; `pill` needs the
// item's own extent, so it survives resolution as itself and Box resolves
// it against what it is drawing.
var RADIUS_STEPS = ["sm", "md", "lg", "xl", "pill"];

// The three colours that are not palette roles. A table writes the name and
// this is where it lands; anything else is looked up in the live palette.
var LITERAL_COLORS = { black: "#000000", white: "#ffffff", transparent: "transparent" };

// The box every absent key defaults to, so a resolved box always carries
// the same keys and a binding in Box never guards for undefined.
function _defaults() {
    return {
        fill: LITERAL_COLORS.transparent,
        radius: 0,
        border: null,
        face: null,
        wash: null,
        edge: null,
        hairlines: [],
        rings: [],
        casts: []
    };
}

function roleNames() {
    var out = [];
    for (var role in ROLES)
        out.push(role);
    return out;
}

function statesFor(role) {
    return ROLES[role] || [];
}

// The raw entry for a role and a state, states merged key by key over the
// role's base state: a `hover` that carries a wash alone keeps the rest
// state's fill, radius and border under it. An unknown state reads as the
// base, which is what lets a primitive pass its own state string through
// without knowing which of them the table bothers to describe.
function entry(style, role, state) {
    var declared = style && style.roles ? style.roles[role] : null;
    if (!declared)
        return null;
    var states = statesFor(role);
    if (states.length === 0)
        return declared;
    var base = declared[states[0]] || null;
    if (!base)
        return null;
    if (!state || state === states[0] || !declared[state])
        return base;
    var out = {};
    for (var key in base)
        out[key] = base[key];
    var over = declared[state];
    for (var k in over)
        out[k] = over[k];
    return out;
}

// An alpha is a number, `"surface"` (the translucency the compositor blurs
// behind) or a `{ light, dark }` pair the palette's own mode picks between,
// which is how the metamorphosis washes and a per-mode cast fit one schema.
// Absent reads as opaque.
function alphaFor(value, ctx) {
    if (value === undefined || value === null)
        return 1;
    if (value === "surface")
        return ctx.surfaceOpacity;
    if (typeof value === "number")
        return value;
    if (typeof value === "object")
        return ctx.mode === "light" ? value.light : value.dark;
    return 1;
}

// One colour, resolved: a literal, or a palette role under the alpha the
// table asked for. `transparent` never takes an alpha, since adding one to
// it would produce black at that alpha rather than nothing.
function paint(name, alpha, ctx) {
    if (name === undefined || name === null || name === "transparent")
        return LITERAL_COLORS.transparent;
    var base = LITERAL_COLORS[name] !== undefined ? LITERAL_COLORS[name] : ctx.color(name);
    var a = alphaFor(alpha, ctx);
    return a >= 1 ? base : ctx.alpha(base, a);
}

function radiusFor(value, radius) {
    if (typeof value === "number")
        return value;
    if (value === "pill")
        return "pill";
    if (value !== undefined && radius[value] !== undefined)
        return radius[value];
    return 0;
}

// CSS box-shadow's own reading of a layer (the spec's shape): anything with
// a blur is a cast, anything with a spread and no blur is a ring, and what
// has neither is a hairline, one line along the edge its offset names.
function layerKind(layer) {
    if (layer.blur > 0)
        return "cast";
    if (layer.spread > 0)
        return "ring";
    return "hairline";
}

// Which edge a hairline lies along and how thick it is. A positive offset
// names the near edge (top, left) and a negative one the far edge, which is
// how `0 1px` reads as a lit top lip and `0 -1px` as a lit lower one. A
// layer with neither offset covers the whole box and has no line to draw.
function hairline(layer) {
    var y = layer.y || 0;
    var x = layer.x || 0;
    if (y !== 0)
        return { edge: y > 0 ? "top" : "bottom", thickness: Math.abs(y), inset: !!layer.inset };
    if (x !== 0)
        return { edge: x > 0 ? "left" : "right", thickness: Math.abs(x), inset: !!layer.inset };
    return null;
}

// The layer list split by kind, in the table's own order. Box draws casts
// under the fill and rings and hairlines around it, so each list is walked
// by its own Repeater and a box with none instantiates nothing.
//
// A cast is drawn outside the silhouette alone: MultiEffect casts a shadow
// of what it is given and masks the silhouette back out, so an INSET cast
// (elementary's `inset-shadow()`) is not rendered yet. No table carries one
// while metamorphosis is the only one on this mechanism.
function layers(list) {
    var out = { hairlines: [], rings: [], casts: [] };
    if (!list)
        return out;
    for (var i = 0; i < list.length; i++) {
        var layer = list[i];
        var kind = layerKind(layer);
        if (kind === "cast")
            out.casts.push(layer);
        else if (kind === "ring")
            out.rings.push(layer);
        else
            out.hairlines.push(layer);
    }
    return out;
}

// The whole box, drawable: colours resolved against the live palette,
// alphas against the mode, the radius against the step ladder, and `tint`
// folded into the fill (shadcn's `hover:bg-primary/90`, the fill blended
// toward a colour and left opaque, never the fill's own alpha dropped).
//
// `ctx` carries the palette and the arithmetic this file deliberately has
// no access to: `mode`, `surfaceOpacity`, a `radius` step map, `color(name)`
// for a palette role, `alpha(c, a)` and `tint(c, over)`.
function resolve(style, role, state, ctx) {
    var out = _defaults();
    var raw = entry(style, role, state);
    if (!raw)
        return out;

    out.fill = paint(raw.fill, raw.fillAlpha, ctx);
    if (raw.tint)
        out.fill = ctx.tint(out.fill, paint(raw.tint[0], raw.tint[1], ctx));
    out.radius = radiusFor(raw.radius, ctx.radius);

    if (raw.border)
        out.border = { color: paint(raw.border.color, raw.border.alpha, ctx), width: raw.border.width };
    if (raw.face) {
        out.face = {
            from: paint(raw.face.from[0], raw.face.from[1], ctx),
            to: paint(raw.face.to[0], raw.face.to[1], ctx)
        };
    }
    if (raw.wash)
        out.wash = paint(raw.wash.color, raw.wash.alpha, ctx);
    if (raw.edge)
        out.edge = { color: paint(raw.edge.color, raw.edge.alpha, ctx), width: raw.edge.width };

    var split = layers(raw.layers);
    for (var h = 0; h < split.hairlines.length; h++) {
        var line = hairline(split.hairlines[h]);
        if (!line)
            continue;
        line.color = paint(split.hairlines[h].color, split.hairlines[h].alpha, ctx);
        out.hairlines.push(line);
    }
    for (var r = 0; r < split.rings.length; r++) {
        out.rings.push({
            spread: split.rings[r].spread,
            color: paint(split.rings[r].color, split.rings[r].alpha, ctx)
        });
    }
    for (var c = 0; c < split.casts.length; c++) {
        var cast = split.casts[c];
        out.casts.push({
            x: cast.x || 0,
            y: cast.y || 0,
            blur: cast.blur,
            spread: cast.spread || 0,
            color: paint(cast.color, cast.alpha, ctx)
        });
    }
    return out;
}

// One clock, resolved: `{ duration, curve }` with a family name on either
// side standing for that family's own value. `m` and `c` are the motion
// tokens and the curve table, passed in for the same reason the palette is
// (this file holds no numbers of its own), unzeroed: `Theme.motion` owns
// the reduced-motion switch and the rig's scale. A key no table carries
// rides the spatial family, which is what a drawer rode before the tables
// named its clock.
function motion(style, key, m, c) {
    var raw = style && style.motion ? style.motion[key] : null;
    var duration = raw ? raw.duration : null;
    var curve = raw ? raw.curve : null;
    return {
        duration: typeof duration === "number" ? duration
            : (m[duration] !== undefined ? m[duration] : m.spatial),
        curve: (curve && curve.length !== undefined && typeof curve !== "string") ? curve
            : (c[curve] !== undefined ? c[curve] : c.spatial)
    };
}

// One wash, resolved: `Theme.hoverFill` and the two `*Filled()` helpers are
// this over the table's own `wash` entry, so the numbers live in the table
// and no caller changed its name.
function wash(style, key, ctx) {
    var entryValue = style && style.wash ? style.wash[key] : null;
    if (!entryValue)
        return LITERAL_COLORS.transparent;
    return paint(entryValue.color, entryValue.alpha, ctx);
}

// The keyboard cursor composed over whatever box carries it (T6): the
// cursor's own border in place of the box's, and its halo appended to the
// rings, so one table entry decides what a cursor looks like on a cell, a
// button or a segmented control. The halo is a second answer rather than
// part of the border, because a list draws one halo for every row it owns
// (cursor.js's `ownsCursorHalo` walk) while each of those rows still swaps
// its own border.
function withCursor(box, cursor, halo) {
    var out = {};
    for (var key in box)
        out[key] = box[key];
    if (cursor.border)
        out.border = cursor.border;
    if (halo)
        out.rings = box.rings.concat(cursor.rings);
    return out;
}

// Every colour name a table references, for the validation test: a name
// that is neither a literal nor a palette role would resolve to nothing at
// draw time and paint an invisible surface.
function colorNames(style) {
    var seen = {};
    var out = [];

    function take(name) {
        if (name === undefined || name === null || seen[name])
            return;
        seen[name] = true;
        out.push(name);
    }

    function takeBox(box) {
        take(box.fill);
        if (box.border)
            take(box.border.color);
        if (box.face) {
            take(box.face.from[0]);
            take(box.face.to[0]);
        }
        if (box.wash)
            take(box.wash.color);
        if (box.edge)
            take(box.edge.color);
        if (box.tint)
            take(box.tint[0]);
        for (var i = 0; box.layers && i < box.layers.length; i++)
            take(box.layers[i].color);
    }

    for (var role in ROLES) {
        var declared = style.roles[role];
        if (!declared)
            continue;
        var states = statesFor(role);
        if (states.length === 0) {
            takeBox(declared);
            continue;
        }
        for (var s = 0; s < states.length; s++) {
            if (declared[states[s]])
                takeBox(declared[states[s]]);
        }
    }
    for (var w = 0; w < WASH_KEYS.length; w++) {
        if (style.wash[WASH_KEYS[w]])
            take(style.wash[WASH_KEYS[w]].color);
    }
    return out;
}

// Every alpha a table names, as `{ path, value }` pairs, for the same test:
// an alpha outside 0..1 is a CSS percentage or a byte that reached the
// table by mistake.
function alphaValues(style) {
    var out = [];

    function take(path, value) {
        if (value !== undefined && value !== null && value !== "surface")
            out.push({ path: path, value: value });
    }

    function takeBox(path, box) {
        take(path + ".fillAlpha", box.fillAlpha);
        if (box.border)
            take(path + ".border.alpha", box.border.alpha);
        if (box.face) {
            take(path + ".face.from", box.face.from[1]);
            take(path + ".face.to", box.face.to[1]);
        }
        if (box.wash)
            take(path + ".wash.alpha", box.wash.alpha);
        if (box.edge)
            take(path + ".edge.alpha", box.edge.alpha);
        if (box.tint)
            take(path + ".tint", box.tint[1]);
        for (var i = 0; box.layers && i < box.layers.length; i++)
            take(path + ".layers[" + i + "]", box.layers[i].alpha);
    }

    for (var role in ROLES) {
        var declared = style.roles[role];
        if (!declared)
            continue;
        var states = statesFor(role);
        if (states.length === 0) {
            takeBox(role, declared);
            continue;
        }
        for (var s = 0; s < states.length; s++) {
            if (declared[states[s]])
                takeBox(role + "." + states[s], declared[states[s]]);
        }
    }
    for (var w = 0; w < WASH_KEYS.length; w++) {
        if (style.wash[WASH_KEYS[w]])
            take("wash." + WASH_KEYS[w], style.wash[WASH_KEYS[w]].alpha);
    }
    return out;
}
