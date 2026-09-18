.pragma library

// elementary OS 8's material as a table (M60 T1, the 2026-09-17 spec's
// Part 2). Every number is transcribed from elementary's own GPL sources,
// the file named beside the block that uses it: `stylesheet`'s gtk-4.0
// `_exported.scss` for the tokens, `_index.scss` for the mixins,
// `widgets/*.scss` for the roles. Nothing is ported; the recipes are read
// and our own primitives draw them.
//
// Two facts decide half the alphas below. GTK's `alpha(c, f)` MULTIPLIES,
// and the `highlight` base is white in light but white at 0.2 in dark, so a
// line elementary writes as `alpha(@highlight_color, 0.3)` lands at white
// 0.3 in light and white 0.06 in dark: the dark material is quiet, and
// every highlight-derived alpha here is written as that product rather than
// as the factor. Second, the shell's surfaces are darker than elementary's
// dark theme (zinc's `card` is #18181b where elementary's view is #3a3a3a),
// so the handful of places black at 0.05 would vanish outright carry a
// deeper dark value; each one says so.
//
// Every primitive composes a `Components/Box.qml` (M60 T1b), so a role may
// carry whatever elementary's recipe asks for. FrameRing is the one
// exception, a Shape that takes the band's fill and the cut-out's hairline
// as colours. What Box draws of a layer list is the rest of the story: no
// INSET cast and no hairline outside the box, so `inset-shadow()` arrives
// as the unblurred line it leaves along the top edge (INSET below) and
// elementary's lit lower lip is dropped. A layer drawn under the fill is
// covered wherever something sits on top of it, which is what the scale's
// own highlight does to its trough in elementary too.

// The two border tokens (`_index.scss`). Literal black rather than the
// `border` palette role: a rim that is black at an alpha is what makes this
// material read as pressed out of one sheet, and matugen's `border` is a
// mid-grey step that would flatten every edge to the same line.
var BORDERS = { light: 0.2, dark: 0.75 };          // toplevel frames
var CONTROL_BORDER = { light: 0.2, dark: 0.3 };    // buttons, fields, knobs

// `outset-highlight("full")`: the lit rim inside a raised control, top
// brightest, sides barely there. The dark column is the product described
// above (0.3/0.2/0.07 of white at 0.2).
var HIGHLIGHT = [
    { inset: true, y: 1, color: "white", alpha: { light: 0.3, dark: 0.06 } },
    { inset: true, y: -1, color: "white", alpha: { light: 0.2, dark: 0.04 } },
    { inset: true, x: 1, color: "white", alpha: { light: 0.07, dark: 0.014 } },
    { inset: true, x: -1, color: "white", alpha: { light: 0.07, dark: 0.014 } }
];

// `%outset-background`: the one gradient this material has, over the fill
// of anything raised. Same highlight base, so the same product in dark.
var FACE = { from: ["white", { light: 0.2, dark: 0.04 }], to: ["white", 0] };

// `inset-shadow()`, as far as Box draws it: elementary stacks two blurred
// inset shadows of black 0.05 and hangs a lit lip outside the lower edge.
// Box draws neither an inset cast nor an outside hairline, so what is left
// is their sum along the top edge as one unblurred line, which is the cue
// that reads as sunken anyway. The dark value is deepened for the reason in
// the header: black at 0.1 over zinc is not a shadow.
var INSET = [{ inset: true, y: 1, color: "black", alpha: { light: 0.1, dark: 0.3 } }];

// The elevation ladder, `outset-shadow(n)` for a control and `shadow(n)`
// for a surface. The dark alphas elementary gives in brackets are its own
// values, not a product of anything.
var OUTSET_1 = [{ y: 1, blur: 1, color: "black", alpha: 0.05 }];
var OUTSET_2 = [
    { y: 1, blur: 1, color: "black", alpha: 0.07 },
    { y: 1, blur: 2, color: "black", alpha: 0.08 }
];
var SHADOW_1 = [
    { y: 1, blur: 3, color: "black", alpha: { light: 0.12, dark: 0.42 } },
    { y: 1, blur: 2, color: "black", alpha: { light: 0.24, dark: 0.44 } }
];
var SHADOW_2 = [
    { y: 3, blur: 4, color: "black", alpha: { light: 0.15, dark: 0.25 } },
    { y: 3, blur: 3, spread: -3, color: "black", alpha: { light: 0.35, dark: 0.45 } }
];

// The radii elementary pins, by number rather than by step: the ladder the
// preset's base of 6 gives (2/4/6/10) is what everything else takes.
var R_CONTROL = 3;    // buttons, entries, checks, indicators (`rem(3px)`)
var R_POPOVER = 6;    // popovers and windows
var R_CARD = 9;       // cards, notification bubbles, the switcher
var R_TRACK = 16;     // the switch track, round at any height it is given

// The keyboard cursor: elementary's focus is the accent on the border plus
// `0 0 0 2px alpha(accent, 0.3)` outside it, so the halo is a 2px ring at
// 0.3 rather than shadcn's 3px at 0.5. `Theme.ringWidth` follows the spread,
// which is what reserves the room a clipping list leaves around a row.
var CURSOR_LAYERS = [{ spread: 2, color: "ring", alpha: 0.3 }];

// What the pointer paints. elementary states two of these and not the other
// two: a menu row's hover and a list's selection are both `alpha(fg, 0.15)`
// (`widgets/menu.scss`, `widgets/list.scss`), and a button's hover is
// GTK's own shade of its fill with no rule in the stylesheet at all. So
// `hover` is elementary's, `press` is one step past it (shadcn's 0.16 would
// land UNDER the hover we just took, which would read as the press
// lifting), and the two filled steps keep shadcn's numbers, since blending
// a coloured control toward `background` is the answer elementary reaches
// by shading and we have no shade to reach for.
var WASH = {
    hover: { color: "foreground", alpha: 0.15 },
    press: { color: "foreground", alpha: 0.22 },
    filledHover: { color: "background", alpha: 0.1 },
    filledPress: { color: "background", alpha: 0.18 }
};

var STYLE = {
    roles: {
        // wingpanel's band (`data/styles/Application.css`, one paint per
        // answer `wingpanel-interface/BackgroundManager.vala` gives for what
        // is under the panel; shell/Theme/barpaint.js carries the decision
        // and Surfaces/Bar/BarWingpanel.qml draws it). `rest` is the base
        // the five merge over: no fill, no line facing the desktop (the
        // edge stands at width 0, which is what Bar reads for it), and the
        // white ink the two dark bands and the light-wallpaper band all
        // take.
        //
        // The names say which INK a paint carries, not how dark its band
        // is, which is the spec's own reading of wingpanel's classes:
        // `dark` is dark ink over a bright wallpaper, `light` light ink
        // over a dark one, and the two translucent paints are named after
        // the fill they add.
        //
        // The cast wingpanel hangs under its translucent-dark panel
        // (`0 1px 3px black 0.15, 0 1px 1px black 0.3`) is not here: the
        // bar's window is exactly the band's thickness and reserves that
        // same thickness, so there is no row under the band to blur into.
        //
        // Each paint's ink carries ONE shadow where elementary writes two,
        // the offset one: Qt draws a text shadow as `Text.Raised` with a
        // 1px offset and has no blur to give the `0 0 2px` half, so the
        // pair collapses to its lower member (black 0.6 bare, black 0.3
        // under a fill of its own, white 0.25 for dark ink).
        "bar": {
            rest: {
                fill: "transparent",
                radius: 0,
                edge: { color: "black", alpha: 0.3, width: 0 },
                ink: ["white", 1],
                inkShadow: ["black", 0.6]
            },
            // A calm dark wallpaper: the base as it stands, white ink
            // straight onto the desktop with no band drawn at all.
            light: {},
            // A calm bright one: the same bare band, dark ink, and the
            // shadow turns white with it.
            dark: { ink: ["black", 0.65], inkShadow: ["white", 0.25] },
            // The one paint whose ink carries no shadow at all: over white
            // at 0.5 the band is its own contrast, and elementary drops the
            // `text-shadow` on `panel.translucent.color-light`.
            translucentLight: {
                fill: "white",
                fillAlpha: 0.5,
                ink: ["black", 0.65],
                inkShadow: ["transparent", 1],
                layers: [
                    { inset: true, y: 1, color: "white", alpha: 0.15 },
                    { inset: true, y: -1, color: "white", alpha: 0.03 }
                ]
            },
            // A fill of its own under the ink, so the shadow steps back to
            // the lighter pair elementary gives the translucent panel
            // (`0 0 2px black 0.15, 0 1px 2px black 0.3`).
            translucentDark: { fill: "black", fillAlpha: 0.3, inkShadow: ["black", 0.3] },
            maximized: { fill: "black", fillAlpha: 1 }
        },

        // No elementary counterpart: a screen frame is ours. It is the bar's
        // own band carried round the output, so it takes the band's own five
        // paints (M62) off the same sampler, and what wingpanel draws along
        // the panel box's inside edge lands on the hairline the ring already
        // has along its cut-out.
        //
        // FrameRing is a Shape rather than a Box: it reads `fill` and
        // `border` and nothing else, so `translucentDark`'s cast has no
        // layer list to go in and is dropped. It would fall on the desktop
        // inside the cut-out, which is where windows are.
        //
        // FrameRing reads `border.width` unguarded, so every state here
        // carries a border; the two bare paints carry a transparent one,
        // since a ring with no fill has no edge to draw either.
        "frame": {
            rest: {
                fill: "transparent",
                radius: 0,
                border: { color: "transparent", width: 1 }
            },
            light: {},
            dark: {},
            translucentLight: {
                fill: "white",
                fillAlpha: 0.5,
                border: { color: "white", alpha: 0.15, width: 1 }
            },
            translucentDark: {
                fill: "black",
                fillAlpha: 0.3,
                border: { color: "black", alpha: BORDERS, width: 1 }
            },
            maximized: {
                fill: "black",
                fillAlpha: 1,
                border: { color: "black", alpha: BORDERS, width: 1 }
            }
        },

        // The card (`widgets/card.scss`): the view fill, the lit rim, a 1px
        // black line round it and shadow(2) under it. elementary hangs that
        // line outside as `0 0 0 1px`, and it is a border here instead: a
        // card is drawn by three different things (a Box, a `Shoulders`
        // shape joined to the bar, a Drawer's own frame) and only the first
        // of them draws a ring layer, so the line would go missing on the
        // two that matter most. Its alpha is the toplevel `borders` rather
        // than elementary's 0.1, which is a line over a #fafafa desktop and
        // nothing at all over ours. `opaque` is the same card on a namespace
        // the compositor does not blur (the capture picker, over a frozen
        // screenshot), the rule DESIGN.md §1 states for every theme.
        "card": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: R_CARD,
                border: { color: "black", alpha: BORDERS, width: 1 },
                layers: HIGHLIGHT.concat(SHADOW_2)
            },
            opaque: { fillAlpha: 1 }
        },

        // The notification bubble (`notifications/data/application.css`,
        // `src/AbstractBubble.vala`): the view, radius 9, the `borders` line
        // and two casts, the near one tight and the far one wide. Opaque
        // rather than elementary's 0.8 (M62): `formalshell:notifications`
        // carries no blur layerrule, so an alpha there is a plain
        // see-through card rather than the frosted one elementary's own
        // compositor draws. The line is a border for the reason the card's is, which
        // also lets urgency swap it for `destructive` rather than draw a
        // second one inside it. `flat` is a row inside the notification
        // centre, which already carries a card of its own: it drops the
        // fill and every layer, and critical keeps its rim through the
        // flattening because that rim is what urgency asked for.
        "notification": {
            rest: {
                fill: "card",
                fillAlpha: 1,
                radius: R_CARD,
                border: { color: "black", alpha: BORDERS, width: 1 },
                layers: HIGHLIGHT.concat([
                    { y: 1, blur: 3, color: "black", alpha: 0.2 },
                    { y: 3, blur: 9, color: "black", alpha: 0.3 }
                ])
            },
            critical: { border: { color: "destructive", width: 1 } },
            flat: { fill: "transparent", border: null, layers: [] },
            flatCritical: {
                fill: "transparent",
                border: { color: "destructive", width: 1 },
                layers: []
            }
        },

        // The tooltip (`widgets/tooltip.scss`): a dark plate at 0.9 on
        // shadow(1), radius 3, and no rim at all, the cast being what lifts
        // it off whatever it is over.
        "popover": {
            fill: "popover",
            fillAlpha: 0.9,
            radius: R_CONTROL,
            layers: SHADOW_1
        },

        // The tray menu, which is GTK's popover (`widgets/popover.scss`):
        // the background fill, a toplevel rim, the lit inside edge and
        // shadow(2) under it, radius 6. Rows in it hover at `fg 0.15`,
        // which is the wash below.
        "menu": {
            fill: "popover",
            fillAlpha: "surface",
            radius: R_POPOVER,
            border: { color: "black", alpha: BORDERS, width: 1 },
            layers: HIGHLIGHT.concat(SHADOW_2)
        },

        // Every bar cell, list row and chip. elementary's list row carries
        // no chrome at all and answers the pointer with `fg 0.15`, so the
        // resting tile here is the plate a row sits on rather than a raised
        // button: a panel is a column of these, and rows wearing a button's
        // material would read as a stack of buttons. `ghost` is the bar's
        // own cells, and the filled states stay opaque, a fill IS the
        // statement.
        "cell": {
            rest: {
                fill: "card",
                fillAlpha: "surface",
                radius: R_CONTROL,
                border: { color: "black", alpha: CONTROL_BORDER, width: 1 }
            },
            ghost: { fill: "transparent", border: null },
            // An open wingpanel indicator (`data/styles/Application.css`):
            // the cell fills with `highlight` at 0.6 rather than carrying a
            // line along the band's edge, which is why `cell.mark` below
            // never draws under this habit. White at 0.6 in light and at
            // 0.12 in dark, the GTK product described in the header.
            // wingpanel's own white 0.3 for the maximized band is dropped:
            // the cell is handed the band's ink, not which paint it is
            // under, and one fill reads on all five.
            ghostOpen: {
                fill: "white",
                fillAlpha: { light: 0.6, dark: 0.12 },
                border: null
            },
            hover: { wash: WASH.hover },
            active: { fill: "primary", fillAlpha: 1 },
            selected: { fill: "accent", fillAlpha: 1 },
            destructive: { border: { color: "destructive", width: 1 } },
            warning: { border: { color: "warning", width: 1 } }
        },

        // No elementary counterpart: wingpanel marks an open indicator with
        // the `ghostOpen` fill above and draws no line, so this is what a
        // cell outside a band would take, and nothing on the bar reaches it.
        "cell.mark": { fill: "primary", radius: "sm" },

        // The suggested action (`widgets/button.scss`, `.suggested-action`):
        // the accent under the same raised material every button wears, its
        // rim a shade of the fill, which arrives here as black over the
        // accent since the table cannot mix two colours.
        "button.default": {
            rest: {
                fill: "primary",
                radius: R_CONTROL,
                border: { color: "black", alpha: 0.3, width: 1 },
                face: FACE,
                layers: HIGHLIGHT.concat(OUTSET_2)
            },
            hover: { tint: [WASH.filledHover.color, WASH.filledHover.alpha] },
            press: {
                tint: [WASH.filledPress.color, WASH.filledPress.alpha],
                face: null,
                layers: INSET
            }
        },

        // `.destructive-action`: elementary fills it with STRAWBERRY_500,
        // which is `destructive` here, and wears the same material.
        "button.destructive": {
            rest: {
                fill: "destructive",
                radius: R_CONTROL,
                border: { color: "black", alpha: 0.3, width: 1 },
                face: FACE,
                layers: HIGHLIGHT.concat(OUTSET_2)
            },
            hover: { tint: [WASH.filledHover.color, WASH.filledHover.alpha] },
            press: {
                tint: [WASH.filledPress.color, WASH.filledPress.alpha],
                face: null,
                layers: INSET
            }
        },

        // The plain button: `bg 0` under the face, a control rim, the lit
        // edges and outset-shadow(2). shadcn's outline variant is the one
        // every surface reaches for when it wants a button with no colour
        // of its own, so this is where elementary's own button lands.
        "button.outline": {
            rest: {
                fill: "secondary",
                radius: R_CONTROL,
                border: { color: "black", alpha: CONTROL_BORDER, width: 1 },
                face: FACE,
                layers: HIGHLIGHT.concat(OUTSET_2)
            },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press, face: null, layers: INSET }
        },

        // The flat button (`.flat`): nothing until the pointer arrives.
        "button.ghost": {
            rest: { fill: "transparent", radius: R_CONTROL },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press }
        },

        // The chosen option in a `ButtonGroup`, which is granite's mode
        // switch: the raised button inside the sunken trough below, the one
        // reading that survives a row where every other option is flat.
        "button.selected": {
            rest: {
                fill: "secondary",
                radius: R_CONTROL,
                border: { color: "black", alpha: CONTROL_BORDER, width: 1 },
                face: FACE,
                layers: HIGHLIGHT.concat(OUTSET_2)
            },
            hover: { wash: WASH.hover },
            press: { wash: WASH.press, face: null, layers: INSET }
        },

        // The text field (`widgets/entry.scss`): the view fill sunk into
        // the surface, a control rim, radius 3, and the accent border with
        // its 2px halo on focus. The fill carries the well on top of the
        // sunken line: opaque `background` against a translucent `card`.
        "input": {
            rest: {
                fill: "background",
                radius: R_CONTROL,
                border: { color: "input", width: 1 },
                layers: INSET
            },
            focus: {
                border: { color: "ring", width: 1 },
                layers: INSET.concat(CURSOR_LAYERS)
            },
            error: { border: { color: "destructive", width: 1 } }
        },

        // `selected_bg_color`, which is the accent.
        "input.selection": { fill: "primary" },

        // The switch (`widgets/switch.scss`): a sunken trough under the
        // accent when on, radius 16 so it is round at any height. The fill
        // takes a deeper black than elementary's 0.05, which over zinc is
        // nothing, and the sunken line sits on top of it.
        "switch.track": {
            off: {
                fill: "black",
                fillAlpha: { light: 0.08, dark: 0.4 },
                radius: R_TRACK,
                layers: INSET
            },
            on: { fill: "primary" }
        },

        // The knob: `bg 0`, a control rim and outset-shadow(3) in
        // elementary, whose own alphas are not transcribed here, so the
        // knob is its fill until they are. Pill rather than elementary's 99,
        // which is the same circle by another name.
        "switch.knob": { fill: "secondary", radius: "pill" },

        // The scale (`widgets/scale.scss`): a sunken trough with the accent
        // filling it, both round. The groove's dark is deepened for the same
        // reason the switch track's is, and the sunken line runs along
        // whatever the fill leaves of it. No rim: the fill sits inside the
        // groove rather than over it, so a line round the trough would be
        // drawn on one side of the knob and painted over on the other.
        "track.groove": {
            fill: "black",
            fillAlpha: { light: 0.08, dark: 0.4 },
            radius: "pill",
            layers: INSET
        },
        "track.fill": { fill: "primary", radius: "pill" },

        // No elementary counterpart: the one mark a Track can carry
        // (AudioPanel's overdrive boundary) is cut through groove and fill
        // alike, so it takes the colour of the surface behind both.
        "track.notch": { fill: "background" },

        // The well a `ButtonGroup`'s row and a `Segmented`'s segments sit
        // in: elementary's linked container, sunk the way an entry is. The
        // chip that marks the chosen segment is the raised button, concentric
        // inside it, so the trough takes the step above the chip's own 3.
        "trough": {
            fill: "black",
            fillAlpha: { light: 0.05, dark: 0.25 },
            radius: "md",
            border: { color: "black", alpha: CONTROL_BORDER, width: 1 },
            layers: INSET
        },
        "segmented.chip": {
            fill: "secondary",
            radius: R_CONTROL,
            border: { color: "black", alpha: CONTROL_BORDER, width: 1 },
            face: FACE,
            layers: HIGHLIGHT.concat(OUTSET_1)
        },

        // Focus (`_index.scss`): the accent on the border and
        // `0 0 0 2px alpha(accent, 0.3)` outside it.
        "cursor": {
            border: { color: "ring", width: 1 },
            layers: CURSOR_LAYERS
        },

        // Gala's modal dim (`lib/Constants.vala`): 125 of 255, a touch
        // under the half shadcn takes.
        "scrim": { fill: "black", fillAlpha: 125 / 255, radius: 0 },

        // Gala's window switcher (`lib/Widgets/WindowSwitcher.vala`, M60 T6):
        // the background level at 0.6 over the compositor's blur, a toplevel
        // rim, and one lit stroke a pixel and a half inside that rim at
        // radius 8, which is what the ring's own band leaves under a radius
        // of 9. The stroke is Gala's, drawn on a Clutter canvas rather than
        // written as a GTK `alpha(@highlight_color, 0.3)`, so it carries
        // 0.3 in both modes instead of the product every highlight in this
        // file takes.
        "switcher": {
            fill: "background",
            fillAlpha: 0.6,
            radius: R_CARD,
            border: { color: "black", alpha: BORDERS, width: 1 },
            layers: [{ inset: true, spread: 1.5, color: "white", alpha: 0.3 }]
        },

        // The window itself, which the shell does not draw: Hyprland does,
        // off the variables ThemeEngine publishes into
        // formalshell-chrome.conf (chrome.js, M60 P7). elementary's focused
        // window is a 1px `borders` frame over `shadow(4)` and a backdrop
        // one drops to `shadow(2)`, and what a compositor can take of that
        // is one cast: the range, the power and the offset below are the
        // focused numbers, and a backdrop window differs by its colour
        // alone. The frame takes the `border` role rather than the literal
        // black the cards carry, since a window's rim lies on the wallpaper
        // instead of on a sheet of this material.
        "window": {
            rest: {
                border: { color: "border", width: 1 },
                shadow: {
                    enabled: true,
                    range: 24,
                    renderPower: 3,
                    offset: [0, 6],
                    color: "black",
                    alpha: 0.35
                }
            },
            inactive: { shadow: { color: "black", alpha: 0.25 } }
        }
    },

    wash: WASH,

    // Gala's menu map (`lib/Constants.vala`) on elementary's own curve
    // (`_animate.scss`): 150ms, and the one easing every transition in the
    // stylesheet rides, written as the control points plus the end point
    // Qt's `easing.bezierCurve` wants. It never overshoots, which is what a
    // popover dropping out of its cell asks for: the card arrives and stops
    // rather than settling back onto the bar.
    //
    // The bubble's two clocks (`notifications/data/application.css`'s
    // `bubble` keyframes, M60 T4) ride the same curve: 400ms for the flip a
    // bubble arrives on, and 200ms for the pile closing up behind it, spread
    // over a 150ms window so N bubbles move one after another rather than
    // together. The restack takes `emphasizedDecel` instead of the curve
    // above because it is the one clock here that is a card travelling
    // rather than appearing, and it must not pass the place it is going to:
    // a bubble overshooting into its neighbour reads as the pile bouncing.
    motion: {
        emerge: { duration: 150, curve: [0.4, 0, 0.2, 1, 1, 1] },
        arrive: { duration: 400, curve: [0.4, 0, 0.2, 1, 1, 1] },
        restack: { duration: 200, curve: "emphasizedDecel", stagger: 150 }
    },

    // Pantheon's habits, the shapes that differ from Omarchy in more than
    // chrome: wingpanel's band, a popover that drops out of its cell rather
    // than budding off the line, elementary's notification bubble,
    // Slingshot's grid as the launcher's default route, and Gala's window
    // switcher. Each lands with its own task (M60 T2 to T6); until then
    // nothing reads them, and the chrome above stands on its own.
    habits: {
        bar: "wingpanel",
        emerge: "popover",
        notification: "bubble",
        launcher: "grid",
        switcher: true,
        // The panel elementary shows over a calm sky, on every wallpaper: the
        // owner's busy band tripped wingpanel's own rule into a black wash
        // and that is not the picture they were after.
        paint: "transparent"
    }
};
