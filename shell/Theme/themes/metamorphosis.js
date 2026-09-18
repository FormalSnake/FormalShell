.pragma library

// The shipped look as a table (M59 T1): shadcn chrome on Omarchy habits,
// the 2026-08-25 redesign. Every number here was read off the primitive
// that drew it before this file existed, so the primitives that now render
// `Theme.box(role, state)` paint the frames they painted then.
//
// What the table does NOT carry: ink (text and icon colour, which is
// content rather than chrome), geometry (a control's padding, its height,
// the concentric radius a nested box takes from its owner) and motion. The
// scalars a preset already owns stay in presets.js: radius base, icons,
// fonts, surface alpha, blur, dither.
//
// Colours are role names resolved at draw time, so matugen keeps driving
// the palette; alphas are literals here, which is what makes a theme
// readable as one file. `shell/Theme/style.js` documents the schema and
// resolves it.

// The keyboard cursor's halo (T6): shadcn's `ring-[3px] ring-ring/50`, one
// ring layer rather than a rectangle each primitive drew for itself.
var CURSOR_LAYERS = [{ spread: 3, color: "ring", alpha: 0.5 }];

// The cast Hyprland is asked for round a window (M60 P7): none. Nothing in
// this look shadows anything (docs/DESIGN.md "Chrome"), so the numbers
// beside the switch are the compositor's own defaults and the published
// file asks it for nothing it was not already doing. Its default colour is
// `rgba(1a1a1aee)`, so plain black at that opacity is the nearest this
// table can name.
var NO_CAST = {
    enabled: false,
    range: 4,
    renderPower: 3,
    offset: [0, 0],
    color: "black",
    alpha: 0.93
};

// What the pointer paints. `hover` and `press` are a wash of the surface's
// own ink, never an opaque `accent` chip: every surface that takes a hover
// is drawn at the surface alpha, so an opaque fill on top of it lands at a
// delta the wallpaper behind the blur decides, and a bright wallpaper
// cancels the lift outright. A wash of the ink stacks on whatever resolved
// there instead, so the lift keeps its size and its direction over every
// wallpaper. That is what `accent` already is on an opaque page: zinc's
// `#27272a` is `card` under white at 0.07, `#f4f4f5` is `card` under black
// at 0.043. `hover` steps past both, since a bar cell sits on `card` rather
// than on `background` and has that much less room to read against;
// `press` is the same wash one step further on.
//
// `filledHover`/`filledPress` are shadcn's `hover:bg-primary/90` for a
// control that already carries a colour: the fill blended toward
// `background` and left opaque. Dropping the fill's own alpha instead is
// what `/90` means on an opaque page and something else here, a primary
// button on a translucent panel goes see-through and the wallpaper reads
// straight through its label.
var WASH = {
    hover: { color: "foreground", alpha: { dark: 0.1, light: 0.06 } },
    press: { color: "foreground", alpha: { dark: 0.16, light: 0.1 } },
    filledHover: { color: "background", alpha: 0.1 },
    filledPress: { color: "background", alpha: 0.18 }
};

var STYLE = {
    roles: {
        // The strip (DESIGN.md §3 Bar): the card fill with no border at all,
        // and one hairline along the edge facing the desktop. `edge` rather
        // than `border` because three of the four sides are the screen's own
        // edges, and the line is drawn in two segments around the gap a
        // joined card opens in it, which is Bar's own geometry. One state,
        // since the strip habit has one paint; the five a sampled band
        // takes are wingpanel's (style.js's HABIT_STATES).
        "bar": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: 0,
                edge: { color: "border", width: 1 }
            }
        },

        // The screen frame's ring. Its corner is `frame.radius`, a settings
        // key rather than a step off the ladder, so the radius here is the
        // band's own square outer edge and FrameRing keeps deciding the cut
        // out it leaves for the desktop.
        "frame": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: 0,
                border: { color: "border", width: 1 }
            }
        },

        // Every floating surface's frame. `opaque` is the same box on a
        // namespace the compositor does not blur (the capture picker's, over
        // a frozen screenshot): a translucent card with nothing blurred
        // behind it reads as a rendering fault rather than as depth, so a
        // surface is either on Hyprland's blur list or opaque
        // (DESIGN.md §1 "Translucency and blur").
        "card": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: "xl",
                border: { color: "border", width: 1 }
            },
            opaque: { fillAlpha: 1 }
        },

        // A notification card, on the same unblurred footing as the capture
        // picker: a toast has nothing behind it. `flat` is a row inside the
        // notification centre, which already carries a card of its own, so
        // the row paints neither fill nor border and the list reads as rows
        // rather than as tiles. Critical keeps its border through the
        // flattening, since that border is what urgency asked for
        // (DESIGN.md §5, no full-bleed rows).
        "notification": {
            rest: {
                fill: "card",
                fillAlpha: 1,
                radius: "xl",
                border: { color: "border", width: 1 }
            },
            critical: { border: { color: "destructive", width: 1 } },
            flat: { fill: "transparent", border: null },
            flatCritical: { fill: "transparent", border: { color: "destructive", width: 1 } }
        },

        // The tooltip's own frame, and the tray menu's, one step down the
        // radius ladder: a menu, not a panel (M43 D6).
        "popover": {
            fill: "popover",
            fillAlpha: "surface",
            radius: "sm",
            border: { color: "border", width: 1 }
        },

        "menu": {
            fill: "popover",
            fillAlpha: "surface",
            radius: "md",
            border: { color: "border", width: 1 }
        },

        // Every bar cell, list row and chip. `ghost` is the bar's own cells:
        // the strip behind them already carries the fill and the line, so a
        // resting ghost paints neither and the bar reads as one surface.
        // The filled states are opaque on purpose, a fill IS the statement;
        // `destructive` and `warning` put their colour on the border alone
        // (DESIGN.md §5, no full-bleed rows).
        "cell": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: "md",
                border: { color: "border", width: 1 }
            },
            ghost: { fill: "transparent", border: null },
            hover: { wash: WASH.hover },
            active: { fill: "primary", fillAlpha: 1 },
            selected: { fill: "accent", fillAlpha: 1 },
            destructive: { border: { color: "destructive", width: 1 } },
            warning: { border: { color: "warning", width: 1 } }
        },

        // The open-panel mark a bar cell draws along the edge facing the
        // desktop (DESIGN.md §3 Bar). A line rather than a box: how long and
        // how thick it is belongs to the cell, which knows which edge its bar
        // sits on, and only its colour and its ends are the theme's.
        "cell.mark": { fill: "primary", radius: "sm" },

        // shadcn's button variants. The two that carry a colour of their own
        // blend toward `background` under the pointer; the three that do not
        // take the ink wash, `selected` included, which is what keeps a
        // chosen option in a `ButtonGroup` reading as chosen while the
        // pointer sits on it.
        "button.default": {
            rest: { fill: "primary", radius: "md" },
            hover: { tint: [WASH.filledHover.color, WASH.filledHover.alpha] },
            press: { tint: [WASH.filledPress.color, WASH.filledPress.alpha] }
        },

        "button.destructive": {
            rest: { fill: "destructive", radius: "md" },
            hover: { tint: [WASH.filledHover.color, WASH.filledHover.alpha] },
            press: { tint: [WASH.filledPress.color, WASH.filledPress.alpha] }
        },

        "button.outline": {
            rest: { fill: "transparent", radius: "md", border: { color: "border", width: 1 } },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press }
        },

        "button.ghost": {
            rest: { fill: "transparent", radius: "md" },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press }
        },

        "button.selected": {
            rest: { fill: "background", radius: "md", border: { color: "border", width: 1 } },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press }
        },

        // The text field: no fill of its own, the `input` border at rest,
        // the ring and its halo while it holds focus, `destructive` on an
        // error (the caption under it is the primitive's).
        "input": {
            rest: { fill: "transparent", radius: "md", border: { color: "input", width: 1 } },
            focus: { border: { color: "ring", width: 1 }, layers: CURSOR_LAYERS },
            error: { border: { color: "destructive", width: 1 } }
        },

        // What a dragged selection paints behind the text it covers; the
        // text's own ink over it is `primaryForeground`, which is content
        // rather than chrome and so stays in the field.
        "input.selection": { fill: "primary" },

        "switch.track": {
            off: { fill: "muted", radius: "pill" },
            on: { fill: "primary" }
        },

        "switch.knob": { fill: "background", radius: "pill" },

        // The groove is shadcn's own `primary/20` rather than `muted`:
        // `muted` and `accent` resolve to the same zinc step in the dark
        // fallback, so a groove painted `muted` vanishes on a row carrying a
        // `selected` or `active` fill.
        "track.groove": { fill: "primary", fillAlpha: 0.2, radius: "sm" },
        "track.fill": { fill: "primary", radius: "sm" },

        // The one mark a track can carry, cut through groove and fill alike
        // (AudioPanel's overdrive boundary), so it takes the colour of the
        // surface behind both rather than either of theirs.
        "track.notch": { fill: "background" },

        // The well a `ButtonGroup`'s row of ghost buttons and a `Segmented`'s
        // segments sit in, and the chip that marks the chosen one. The chip's
        // radius is the concentric step its owner passes it, this is the
        // free-standing value.
        "trough": { fill: "muted", radius: "md" },
        "segmented.chip": {
            fill: "background",
            radius: "md",
            border: { color: "border", width: 1 }
        },

        // The keyboard cursor, composed over whatever box carries it: the
        // ring on the border and its halo outside. Radius comes from the box
        // it lands on, which is why there is none here.
        "cursor": {
            border: { color: "ring", width: 1 },
            layers: CURSOR_LAYERS
        },

        // The modal backdrop: plain black over the live desktop, the
        // compositor's `ignore_alpha` for the modal namespaces keeping the
        // blur behind the card above it.
        "scrim": { fill: "black", fillAlpha: 0.5, radius: 0 },

        // The window switcher's card (M60 T6). This table's `switcher` habit
        // is off, so nothing instantiates that surface here and the entry is
        // the plain card: the role list is one list, and a preset that turned
        // the habit on would get shadcn's own chrome rather than a hole.
        "switcher": {
            fill: "card",
            fillAlpha: "surface",
            radius: "xl",
            border: { color: "border", width: 1 }
        },

        // And one icon's tile inside it, the cursor filling solid the way
        // every other selected cell in this table does.
        "switcher.cell": {
            rest: { fill: "transparent", radius: "md" },
            selected: { fill: "accent", fillAlpha: 1, radius: "md" }
        },

        // The one role the shell does not draw: Hyprland does, off
        // formalshell-chrome.conf (chrome.js). The frame is the wallpaper's
        // own colour at the compositor's default width, which is what
        // docs/examples/hyprland/formalshell.conf has hung on
        // `col.active_border` since it shipped, so a host on this table
        // sees the window chrome it already had.
        "window": {
            rest: {
                // The gaps Hyprland leaves between windows and round them
                // (M66): the numbers omarchy's own config carries, which is
                // what a session running this look already had.
                gapsIn: 4,
                gapsOut: 8,
                border: { color: "primary", width: 1 },
                shadow: NO_CAST
            },
            inactive: { shadow: NO_CAST }
        }
    },

    wash: WASH,

    // Every clock here names one of the shell's own families rather than a
    // number (DESIGN.md §1 "Motion"): the drawer's card buds off the line on
    // the clock everything else with a position or a size travels on,
    // overshoot included, a toast arrives from off screen on the decelerating
    // curve M3 defines for exactly that, and the pile closes up behind it on
    // the spatial family again, as one, with no stagger. The switcher's card
    // is a plain fade, so it takes the effects family; this table's habit
    // leaves the surface uninstantiated, and the entry is here for the same
    // reason its role above is.
    motion: {
        emerge: { duration: "spatial", curve: "spatial" },
        arrive: { duration: "spatial", curve: "emphasizedDecel" },
        restack: { duration: "spatial", curve: "spatial" },
        switcher: { duration: "effects", curve: "effects" }
    },

    // Omarchy's own habits (T7): the strip along one edge, a card that buds
    // off the line it came out of, one notification row per card, a list
    // launcher, and no window switcher.
    habits: {
        bar: "strip",
        emerge: "join",
        notification: "row",
        launcher: "list",
        switcher: false,
        frame: true,
        paint: "auto"
    }
};
