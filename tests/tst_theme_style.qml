import QtQuick
import QtTest
import "../shell/Theme/palette.js" as Palette
import "../shell/Theme/presets.js" as Presets
import "../shell/Theme/style.js" as Style
import "../shell/Theme/tokens.js" as Tokens
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/retro.js" as Retro
import "../shell/Theme/themes/pantheon.js" as Pantheon

// M59 T1 to T3: the chrome tables and the resolver behind `Theme.style`.
// Two halves, and the first is the one that keeps a theme honest: every
// table is walked against `Style.ROLES` so a role or a state left out
// fails here rather than resolving to nothing at draw time and painting an
// invisible surface. The second exercises the resolution itself against a
// fake palette, since the arithmetic (per-mode alphas, the surface alpha,
// the state falling back to its base) is what every primitive now depends
// on.
TestCase {
    name: "ThemeStyle"

    readonly property var tables: ({
        metamorphosis: Metamorphosis.STYLE,
        retro: Retro.STYLE,
        pantheon: Pantheon.STYLE
    })

    // A palette whose every role answers with its own name, so a resolved
    // colour says which role it came from.
    function ctx(mode) {
        return {
            mode: mode || "dark",
            surfaceOpacity: 0.85,
            radius: { sm: 6, md: 8, lg: 10, xl: 14 },
            color: function (name) { return "role:" + name; },
            alpha: function (c, a) { return c + "@" + a; },
            tint: function (c, over) { return c + "+" + over; }
        };
    }

    function tableNames() {
        var out = [];
        for (var name in tables)
            out.push(name);
        return out;
    }

    // --- The tables ------------------------------------------------------

    function test_every_table_carries_every_role_and_state() {
        var names = tableNames();
        var roles = Style.roleNames();
        verify(roles.length > 0);
        for (var t = 0; t < names.length; t++) {
            var style = tables[names[t]];
            for (var r = 0; r < roles.length; r++) {
                var role = roles[r];
                verify(!!style.roles[role], names[t] + " is missing the role " + role);
                var states = Style.statesFor(role);
                for (var s = 0; s < states.length; s++) {
                    verify(!!style.roles[role][states[s]],
                        names[t] + " is missing " + role + "." + states[s]);
                }
            }
        }
    }

    // The states a habit brings with it (T3): a table that takes the habit
    // has to describe every one of them, and a table that does not is not
    // asked for any. Which is what lets `Theme.hasState` be the question a
    // surface asks before naming one.
    function test_every_table_carries_the_states_its_habits_ask_for() {
        var names = tableNames();
        for (var t = 0; t < names.length; t++) {
            var style = tables[names[t]];
            var required = Style.habitStates(style);
            for (var role in required) {
                for (var s = 0; s < required[role].length; s++) {
                    var state = required[role][s];
                    verify(Style.hasState(style, role, state),
                        names[t] + " takes a habit that needs " + role + "." + state);
                }
            }
        }
        // The strip habit asks for none of them, and metamorphosis carries
        // none: a table cannot pick up another theme's chrome by accident.
        verify(!Style.hasState(Metamorphosis.STYLE, "bar", "translucentDark"));
        verify(!Style.hasState(Metamorphosis.STYLE, "cell", "ghostOpen"));
    }

    function test_every_colour_a_table_names_is_a_palette_role_or_a_literal() {
        var names = tableNames();
        for (var t = 0; t < names.length; t++) {
            var used = Style.colorNames(tables[names[t]]);
            verify(used.length > 0);
            for (var i = 0; i < used.length; i++) {
                var known = Palette.COLOR_KEYS.indexOf(used[i]) !== -1
                    || Style.LITERAL_COLORS[used[i]] !== undefined;
                verify(known, names[t] + " names the unknown colour " + used[i]);
            }
        }
    }

    // An alpha outside 0..1 is a CSS percentage or a byte that reached the
    // table by mistake, and both modes are checked because a `{ light,
    // dark }` pair can be wrong on one side alone.
    function test_every_alpha_is_a_fraction_in_both_modes() {
        var names = tableNames();
        var modes = ["dark", "light"];
        for (var t = 0; t < names.length; t++) {
            var alphas = Style.alphaValues(tables[names[t]]);
            verify(alphas.length > 0);
            for (var i = 0; i < alphas.length; i++) {
                for (var m = 0; m < modes.length; m++) {
                    var a = Style.alphaFor(alphas[i].value, ctx(modes[m]));
                    verify(typeof a === "number" && isFinite(a),
                        names[t] + " " + alphas[i].path + " is not a number in " + modes[m]);
                    verify(a >= 0 && a <= 1,
                        names[t] + " " + alphas[i].path + " is " + a + " in " + modes[m]);
                }
            }
        }
    }

    // An ink-shadow layer reaches Components/InkGlow.qml as a MultiEffect's
    // offsets and blur, so a field that is not a number lands there as a NaN
    // rather than as a glow that looks wrong. The alphas themselves are
    // covered by the walk above, which takes each layer's own.
    function test_every_ink_shadow_layer_is_an_offset_a_blur_and_a_colour() {
        var names = tableNames();
        var seen = 0;
        for (var t = 0; t < names.length; t++) {
            var style = tables[names[t]];
            var found = Style.inkShadowLayers(style);
            for (var i = 0; i < found.length; i++) {
                var layer = found[i].layer;
                var where = names[t] + " " + found[i].path;
                verify(typeof layer === "object" && layer !== null, where + " is not a layer");
                var fields = ["x", "y", "blur"];
                for (var f = 0; f < fields.length; f++) {
                    var value = layer[fields[f]];
                    verify(value === undefined || (typeof value === "number" && isFinite(value)),
                        where + "." + fields[f] + " is not a number");
                }
                verify(typeof layer.color === "string", where + " names no colour");
                seen++;
            }
        }
        // metamorphosis and retro declare none, so pantheon's own are the
        // whole set and an empty walk would pass vacuously.
        compare(seen, Style.inkShadowLayers(Pantheon.STYLE).length);
        verify(seen > 0);
        compare(Style.inkShadowLayers(Metamorphosis.STYLE).length, 0);
    }

    function test_every_radius_is_a_step_or_a_number() {
        var names = tableNames();
        var roles = Style.roleNames();
        for (var t = 0; t < names.length; t++) {
            for (var r = 0; r < roles.length; r++) {
                var states = Style.statesFor(roles[r]);
                var walk = states.length === 0 ? [null] : states;
                for (var s = 0; s < walk.length; s++) {
                    var value = Style.entry(tables[names[t]], roles[r], walk[s]).radius;
                    if (value === undefined)
                        continue;
                    var ok = typeof value === "number" || Style.RADIUS_STEPS.indexOf(value) !== -1;
                    verify(ok, names[t] + " " + roles[r] + " has the radius " + value);
                }
            }
        }
    }

    // The clocks a table names for itself (M60 T2): a duration and a curve,
    // each either its own number or the name of one of the shell's motion
    // families, so a typo lands here rather than on a surface running at
    // Qt's linear default.
    function test_every_table_declares_a_clock_for_every_habit_that_has_one() {
        var names = tableNames();
        var families = Tokens.motionTokens(true);
        var curves = Tokens.MOTION_CURVES;
        for (var t = 0; t < names.length; t++) {
            var style = tables[names[t]];
            for (var k = 0; k < Style.MOTION_KEYS.length; k++) {
                var key = Style.MOTION_KEYS[k];
                var entry = style.motion ? style.motion[key] : null;
                verify(!!entry, names[t] + " is missing the clock " + key);
                var duration = entry.duration;
                verify(typeof duration === "number"
                    ? duration > 0 : families[duration] !== undefined,
                    names[t] + " " + key + " has the duration " + duration);
                var curve = entry.curve;
                if (typeof curve === "string") {
                    verify(curves[curve] !== undefined,
                        names[t] + " " + key + " names the unknown curve " + curve);
                } else {
                    verify(curve.length === 6 || curve.length === 12,
                        names[t] + " " + key + " has " + curve.length + " control numbers");
                    compare(curve[curve.length - 1], 1);
                    compare(curve[curve.length - 2], 1);
                }
                // The optional third key: the window a staggered clock is
                // spread over, in milliseconds like the duration beside it.
                // Absent reads as no stagger at all.
                var stagger = entry.stagger;
                if (stagger !== undefined) {
                    verify(typeof stagger === "number" && stagger > 0,
                        names[t] + " " + key + " has the stagger " + stagger);
                }
                compare(Style.motion(style, key, families, curves).stagger,
                    stagger === undefined ? 0 : stagger);
            }
        }
    }

    // The band's paint policy is the table's (M62, owner 2026-09-18):
    // pantheon never fills it, the strip habit keeps wingpanel's rule as a
    // value nothing reads.
    function test_the_paint_policy_is_the_tables() {
        compare(Pantheon.STYLE.habits.paint, "transparent");
        compare(Metamorphosis.STYLE.habits.paint, "auto");
    }

    function test_every_table_declares_the_habits_and_the_washes() {
        var names = tableNames();
        for (var t = 0; t < names.length; t++) {
            var style = tables[names[t]];
            for (var key in Style.HABITS) {
                verify(style.habits[key] !== undefined, names[t] + " is missing the habit " + key);
                verify(Style.HABITS[key].indexOf(style.habits[key]) !== -1,
                    names[t] + " habit " + key + " is " + style.habits[key]);
            }
            for (var w = 0; w < Style.WASH_KEYS.length; w++) {
                var wash = style.wash[Style.WASH_KEYS[w]];
                verify(!!wash, names[t] + " is missing the wash " + Style.WASH_KEYS[w]);
                verify(typeof wash.color === "string");
            }
        }
    }

    // The shipped look, spelled out: the three boxes every surface in the
    // shell is made of, so a table edit that moved one of them has to say
    // so here.
    function test_metamorphosis_is_the_shipped_chrome() {
        var style = Metamorphosis.STYLE;
        var card = Style.resolve(style, "card", null, ctx("dark"));
        compare(card.fill, "role:card@0.85");
        compare(card.radius, 14);
        compare(card.border.color, "role:border");
        compare(card.border.width, 1);
        compare(card.face, null);
        compare(card.casts.length, 0);
        compare(card.rings.length, 0);

        var cell = Style.resolve(style, "cell", "rest", ctx("dark"));
        compare(cell.fill, "role:card@0.85");
        compare(cell.radius, 8);
        compare(cell.border.color, "role:border");

        // A filled state is opaque: a fill IS the statement, and the
        // surface alpha it would inherit from the resting box is what left
        // an active cell reading as the wallpaper behind it.
        compare(Style.resolve(style, "cell", "active", ctx("dark")).fill, "role:primary");
        compare(Style.resolve(style, "cell", "selected", ctx("dark")).fill, "role:accent");

        var tooltip = Style.resolve(style, "popover", null, ctx("dark"));
        compare(tooltip.fill, "role:popover@0.85");
        compare(tooltip.radius, 6);
        compare(Style.resolve(style, "menu", null, ctx("dark")).radius, 8);
    }

    // T6: the cursor is one ring layer plus a border, not a rectangle each
    // primitive draws for itself.
    function test_the_cursor_is_a_ring_layer_at_the_shipped_numbers() {
        var cursor = Style.resolve(Metamorphosis.STYLE, "cursor", null, ctx("dark"));
        compare(cursor.border.color, "role:ring");
        compare(cursor.border.width, 1);
        compare(cursor.rings.length, 1);
        compare(cursor.rings[0].spread, 3);
        compare(cursor.rings[0].color, "role:ring@0.5");
        compare(cursor.casts.length, 0);
    }

    // T5: the three marks a control paints that are not boxes of their own
    // shape, so the table still decides what colour each of them is.
    function test_the_marks_a_control_paints_come_off_the_table() {
        var style = Metamorphosis.STYLE;
        var mark = Style.resolve(style, "cell.mark", null, ctx("dark"));
        compare(mark.fill, "role:primary");
        compare(mark.radius, 6);
        compare(Style.resolve(style, "track.notch", null, ctx("dark")).fill, "role:background");
        compare(Style.resolve(style, "input.selection", null, ctx("dark")).fill, "role:primary");
    }

    // T6: the cursor composes over whatever box carries it, and its halo is
    // a second answer from its border, because a list draws one halo for
    // every row under it while each of those rows still swaps its border.
    function test_the_cursor_composes_over_a_box() {
        var style = Metamorphosis.STYLE;
        var ghost = Style.resolve(style, "button.ghost", "rest", ctx("dark"));
        var cursor = Style.resolve(style, "cursor", null, ctx("dark"));

        var haloed = Style.withCursor(ghost, cursor, true);
        compare(haloed.fill, ghost.fill);
        compare(haloed.radius, ghost.radius);
        compare(haloed.border.color, "role:ring");
        compare(haloed.rings.length, 1);
        compare(haloed.rings[0].spread, 3);

        var bordered = Style.withCursor(ghost, cursor, false);
        compare(bordered.border.color, "role:ring");
        compare(bordered.rings.length, 0);

        // The box it composed over is left as it was, so a resolved box can
        // be handed to two controls.
        compare(ghost.border, null);
        compare(ghost.rings.length, 0);
    }

    function test_the_scrim_is_black_at_a_half() {
        var scrim = Style.resolve(Metamorphosis.STYLE, "scrim", null, ctx("dark"));
        compare(scrim.fill, Style.LITERAL_COLORS.black + "@0.5");
        compare(scrim.radius, 0);
    }

    // The bar's line is one edge rather than a border: three of its four
    // sides are the screen's own edges.
    function test_the_bar_carries_one_edge_and_no_border() {
        var bar = Style.resolve(Metamorphosis.STYLE, "bar", null, ctx("dark"));
        compare(bar.fill, "role:card@0.85");
        compare(bar.border, null);
        compare(bar.edge.color, "role:border");
        compare(bar.edge.width, 1);
    }

    // Retro differs by scalars presets.js owns, so it is the same table
    // and not a copy of it that could drift.
    function test_retro_is_the_metamorphosis_table() {
        compare(Retro.STYLE, Metamorphosis.STYLE);
    }

    function test_a_preset_hands_back_its_own_table() {
        function get(path, fallback) { return fallback; }
        compare(Presets.resolve("metamorphosis", get).style, Metamorphosis.STYLE);
        compare(Presets.resolve("retro", get).style, Retro.STYLE);
        compare(Presets.resolve("pantheon", get).style, Pantheon.STYLE);
        compare(Presets.defaults("metamorphosis").style, Metamorphosis.STYLE);
    }

    // --- Pantheon (M60 T1) ------------------------------------------------
    //
    // The numbers that carry elementary's material, so a table edit that
    // flattened one of them has to say so here.

    // A raised control: the face gradient over the fill, the lit top line
    // inside it, the control rim and outset-shadow(2) under it.
    function test_the_pantheon_button_is_raised() {
        var button = Style.resolve(Pantheon.STYLE, "button.outline", "rest", ctx("light"));
        compare(button.fill, "role:secondary");
        compare(button.radius, 3);
        compare(button.face.from, "#ffffff@0.2");
        compare(button.face.to, "#ffffff@0");
        compare(button.border.color, "#000000@0.2");
        compare(button.hairlines.length, 4);
        compare(button.hairlines[0].edge, "top");
        compare(button.hairlines[0].color, "#ffffff@0.3");
        compare(button.casts.length, 2);
        compare(button.casts[1].blur, 2);
        compare(button.casts[1].color, "#000000@0.08");

        // Pressed, it sinks: no gradient, no lift, one dark line along the
        // top edge instead.
        var press = Style.resolve(Pantheon.STYLE, "button.outline", "press", ctx("light"));
        compare(press.face, null);
        compare(press.casts.length, 0);
        compare(press.hairlines.length, 1);
        compare(press.hairlines[0].color, "#000000@0.1");
    }

    // The card, layer for layer: the four highlight lines inside it, the 1px
    // black line round it (a border rather than elementary's outside ring,
    // since a Shoulders shape and a Drawer frame draw one and not the
    // other), and shadow(2)'s two casts under it.
    function test_the_pantheon_card_carries_every_layer_kind() {
        var card = Style.resolve(Pantheon.STYLE, "card", null, ctx("dark"));
        compare(card.fill, "role:card@0.85");
        compare(card.radius, 9);
        compare(card.border.color, "#000000@0.75");
        compare(card.border.width, 1);
        compare(card.hairlines.length, 4);
        compare(card.rings.length, 0);
        compare(card.casts.length, 2);
        compare(card.casts[0].y, 3);
        compare(card.casts[0].blur, 4);
        compare(card.casts[0].color, "#000000@0.25");
        compare(card.casts[1].spread, -3);
        compare(card.casts[1].color, "#000000@0.45");
        compare(Style.resolve(Pantheon.STYLE, "card", "opaque", ctx("dark")).fill, "role:card");
    }

    // GTK's alpha() multiplies and the dark highlight base is white at 0.2,
    // so every dark highlight alpha here is that product: a line elementary
    // writes as alpha(highlight, 0.3) is white at 0.06, not at 0.3.
    function test_the_pantheon_highlight_is_the_product_in_dark() {
        var light = Style.resolve(Pantheon.STYLE, "card", null, ctx("light"));
        var dark = Style.resolve(Pantheon.STYLE, "card", null, ctx("dark"));
        compare(light.hairlines[0].color, "#ffffff@0.3");
        compare(dark.hairlines[0].color, "#ffffff@0.06");
        compare(light.hairlines[1].color, "#ffffff@0.2");
        compare(dark.hairlines[1].color, "#ffffff@0.04");
        compare(dark.hairlines[2].color, "#ffffff@0.014");
        compare(Style.resolve(Pantheon.STYLE, "button.outline", "rest", ctx("dark")).face.from,
            "#ffffff@0.04");
    }

    // elementary's focus is the accent on the border plus a 2px halo at
    // 0.3, where shadcn's is 3px at 0.5; `Theme.ringWidth` follows the
    // spread, so the room a clipping list reserves follows the table.
    function test_the_pantheon_cursor_is_a_two_pixel_halo() {
        var cursor = Style.resolve(Pantheon.STYLE, "cursor", null, ctx("dark"));
        compare(cursor.border.color, "role:ring");
        compare(cursor.rings.length, 1);
        compare(cursor.rings[0].spread, 2);
        compare(cursor.rings[0].color, "role:ring@0.3");

        // The field hangs the same halo on its focus state, over the sunken
        // line it keeps at rest.
        var focus = Style.resolve(Pantheon.STYLE, "input", "focus", ctx("dark"));
        compare(focus.rings.length, 1);
        compare(focus.rings[0].spread, 2);
        compare(focus.hairlines.length, 1);
    }

    // The bubble (elementary's notification): the view on two casts, opaque
    // since its namespace carries no blur (M62), and a row inside the centre
    // drops every one of them.
    function test_the_pantheon_bubble_flattens_inside_the_centre() {
        var bubble = Style.resolve(Pantheon.STYLE, "notification", "rest", ctx("dark"));
        compare(bubble.fill, "role:card");
        compare(bubble.radius, 9);
        compare(bubble.casts.length, 2);
        compare(bubble.casts[1].blur, 9);
        compare(bubble.border.color, "#000000@0.75");
        compare(Style.resolve(Pantheon.STYLE, "notification", "critical", ctx("dark")).border.color,
            "role:destructive");

        var flat = Style.resolve(Pantheon.STYLE, "notification", "flat", ctx("dark"));
        compare(flat.fill, Style.LITERAL_COLORS.transparent);
        compare(flat.border, null);
        compare(flat.casts.length, 0);
        compare(flat.hairlines.length, 0);
        compare(Style.resolve(Pantheon.STYLE, "notification", "flatCritical", ctx("dark")).border.color,
            "role:destructive");
    }

    // Gala dims a modal group at 125 of 255, a touch under shadcn's half.
    function test_the_pantheon_scrim_is_gala_s_dim() {
        var scrim = Style.resolve(Pantheon.STYLE, "scrim", null, ctx("dark"));
        compare(scrim.fill, Style.LITERAL_COLORS.black + "@" + (125 / 255));
    }

    // wingpanel's band, one paint per answer its sampling gives (T3): the
    // two bare paints differ in ink alone, the two translucent ones add a
    // fill, and a window covering the output takes it solid. The cast
    // wingpanel hangs under its translucent-dark panel is deliberately not
    // in the table: the bar's window is the band's own thickness.
    function test_the_pantheon_band_has_a_paint_per_reading() {
        var style = Pantheon.STYLE;
        var white = Style.LITERAL_COLORS.white;
        var black = Style.LITERAL_COLORS.black;

        var light = Style.resolve(style, "bar", "light", ctx("dark"));
        compare(light.fill, Style.LITERAL_COLORS.transparent);
        compare(light.ink, white);
        compare(light.casts.length, 0);
        // Both layers elementary writes (O6): the wide halo, then the
        // offset one under it.
        compare(light.inkShadow.length, 2);
        compare(light.inkShadow[0].color, black + "@0.3");
        compare(light.inkShadow[0].blur, 2);
        compare(light.inkShadow[0].y, 0);
        compare(light.inkShadow[1].color, black + "@0.6");
        compare(light.inkShadow[1].blur, 2);
        compare(light.inkShadow[1].y, 1);

        var dark = Style.resolve(style, "bar", "dark", ctx("dark"));
        compare(dark.fill, Style.LITERAL_COLORS.transparent);
        compare(dark.ink, black + "@0.65");
        // Dark ink carries no shadow.
        compare(dark.inkShadow.length, 0);

        // A fill of its own under the ink steps the shadow back to
        // elementary's lighter pair, and white on white at 0.5 carries none
        // at all.
        var translucentDark = Style.resolve(style, "bar", "translucentDark", ctx("dark"));
        compare(translucentDark.fill, black + "@0.3");
        compare(translucentDark.ink, white);
        compare(translucentDark.inkShadow.length, 2);
        compare(translucentDark.inkShadow[0].color, black + "@0.15");
        compare(translucentDark.inkShadow[1].color, black + "@0.3");

        var translucentLight = Style.resolve(style, "bar", "translucentLight", ctx("dark"));
        compare(translucentLight.fill, white + "@0.5");
        compare(translucentLight.ink, black + "@0.65");
        compare(translucentLight.inkShadow.length, 0);
        compare(translucentLight.hairlines.length, 2);
        compare(translucentLight.hairlines[0].color, white + "@0.15");
        compare(translucentLight.hairlines[1].edge, "bottom");
        compare(translucentLight.hairlines[1].color, white + "@0.03");

        // A window over the output keeps the bare band's pair: the ink is
        // still white and the fill under it is not the band's own material.
        var maximized = Style.resolve(style, "bar", "maximized", ctx("dark"));
        compare(maximized.fill, black);
        compare(maximized.ink, white);
        compare(maximized.inkShadow.length, 2);
        compare(maximized.inkShadow[1].color, black + "@0.6");

        // Every band draws its own edge at width 0: wingpanel has no line
        // facing the desktop, and Bar reads the width either way.
        compare(Style.resolve(style, "bar", null, ctx("dark")).edge.width, 0);
    }

    // The screen frame's ring under the same habit (M62): with
    // `frame.thickness` set the bar's band is a stretch of the ring, so the
    // ring carries the band's own five paints. FrameRing draws a fill and a
    // border and nothing else, so what wingpanel puts along the panel box's
    // inside edge lands on the border and its cast is dropped.
    function test_the_pantheon_ring_takes_the_bands_paint() {
        var style = Pantheon.STYLE;
        var white = Style.LITERAL_COLORS.white;
        var black = Style.LITERAL_COLORS.black;
        var clear = Style.LITERAL_COLORS.transparent;

        // Both bare paints: nothing drawn at all, and a border that is
        // present (FrameRing reads its width unguarded) and invisible.
        var bare = ["light", "dark"];
        for (var i = 0; i < bare.length; i++) {
            var box = Style.resolve(style, "frame", bare[i], ctx("dark"));
            compare(box.fill, clear, bare[i] + " draws a fill");
            compare(box.border.color, clear, bare[i] + " draws a line");
            compare(box.border.width, 1);
        }

        var translucentDark = Style.resolve(style, "frame", "translucentDark", ctx("dark"));
        compare(translucentDark.fill, black + "@0.3");
        compare(translucentDark.border.color, black + "@0.75");
        compare(translucentDark.casts.length, 0);

        var translucentLight = Style.resolve(style, "frame", "translucentLight", ctx("dark"));
        compare(translucentLight.fill, white + "@0.5");
        compare(translucentLight.border.color, white + "@0.15");

        compare(Style.resolve(style, "frame", "maximized", ctx("dark")).fill, black);

        // The base under all five, which is what a paint the sampler has
        // not answered yet resolves to.
        compare(Style.resolve(style, "frame", "", ctx("dark")).fill, clear);
    }

    // metamorphosis' ring has no states and is the card fill under the
    // toplevel line whatever string it is handed: the frame role gained a
    // `rest` with M62 and nothing about the shipped frame moved.
    function test_the_metamorphosis_ring_ignores_a_paint() {
        var rest = Style.resolve(Metamorphosis.STYLE, "frame", null, ctx("dark"));
        compare(rest.fill, "role:card@0.85");
        compare(rest.border.color, "role:border");
        compare(rest.border.width, 1);
        compare(rest.radius, 0);
        compare(Style.resolve(Metamorphosis.STYLE, "frame", "translucentDark", ctx("dark")).fill,
            "role:card@0.85");
    }

    // An open indicator fills instead of carrying a line along the band
    // (`cell.mark`, which nothing under this habit reaches), and the fill is
    // the highlight at 0.6: white in light, the GTK product in dark.
    function test_the_pantheon_open_indicator_fills_its_cell() {
        var open = Style.resolve(Pantheon.STYLE, "cell", "ghostOpen", ctx("light"));
        compare(open.fill, Style.LITERAL_COLORS.white + "@0.6");
        compare(open.border, null);
        compare(open.radius, 3);
        compare(Style.resolve(Pantheon.STYLE, "cell", "ghostOpen", ctx("dark")).fill,
            Style.LITERAL_COLORS.white + "@0.12");
    }

    // The switcher's card (M60 T6): Gala's background level at 0.6, the
    // toplevel rim, and the lit stroke inside it, which is the one inset
    // ring in any table and so the one layer that lands in `insetRings`
    // rather than under the fill. Gala draws it on a canvas rather than
    // through GTK's `alpha()`, so unlike every highlight in this material it
    // carries 0.3 in dark too.
    function test_the_pantheon_switcher_is_galas_card() {
        var card = Style.resolve(Pantheon.STYLE, "switcher", null, ctx("dark"));
        compare(card.fill, "role:background@0.6");
        compare(card.radius, 9);
        compare(card.border.color, "#000000@0.75");
        compare(card.rings.length, 0);
        compare(card.insetRings.length, 1);
        compare(card.insetRings[0].spread, 1.5);
        compare(card.insetRings[0].color, "#ffffff@0.3");
        compare(Style.resolve(Pantheon.STYLE, "switcher", null, ctx("light")).insetRings[0].color,
            "#ffffff@0.3");

        // The selected cell is a fill rather than the cursor's ring, which
        // is what Gala marks the window you are about to focus with.
        var selected = Style.resolve(Pantheon.STYLE, "cell", "selected", ctx("dark"));
        compare(selected.fill, "role:accent");
        compare(selected.radius, 3);
    }

    // The table on the habit the switcher is off under still carries the
    // role, so the role list is one list; it is the plain card there.
    function test_the_metamorphosis_switcher_is_the_plain_card() {
        var card = Style.resolve(Metamorphosis.STYLE, "switcher", null, ctx("dark"));
        var plain = Style.resolve(Metamorphosis.STYLE, "card", "rest", ctx("dark"));
        compare(card.fill, plain.fill);
        compare(card.radius, plain.radius);
        compare(card.border.color, plain.border.color);
        compare(card.insetRings.length, 0);
        compare(Metamorphosis.STYLE.habits.switcher, false);
    }

    // The habits Part 2 names, which the surfaces read from M60 T2 on.
    function test_pantheon_declares_pantheon_habits() {
        var habits = Pantheon.STYLE.habits;
        compare(habits.bar, "wingpanel");
        compare(habits.emerge, "popover");
        compare(habits.notification, "bubble");
        compare(habits.launcher, "grid");
        compare(habits.switcher, true);
    }

    // The screen frame is a habit, not a settings key alone (M66): under a
    // table that wears no ring, `frame.thickness` reserves nothing, so the
    // gaps a user sets are the whole margin round a window.
    function test_only_the_framed_look_wears_a_ring() {
        compare(Metamorphosis.STYLE.habits.frame, true);
        compare(Pantheon.STYLE.habits.frame, false);
    }

    // --- The resolver ----------------------------------------------------

    function test_a_state_absent_from_a_role_reads_as_its_base() {
        var style = Metamorphosis.STYLE;
        var rest = Style.resolve(style, "cell", "rest", ctx("dark"));
        var unknown = Style.resolve(style, "cell", "nonsense", ctx("dark"));
        compare(unknown.fill, rest.fill);
        compare(unknown.radius, rest.radius);
        compare(Style.resolve(style, "cell", null, ctx("dark")).fill, rest.fill);
    }

    // A state carrying one key keeps the rest of its base under it, which
    // is what makes `hover` a wash over the resting box rather than a box
    // of its own.
    function test_a_partial_state_merges_over_its_base() {
        var style = Metamorphosis.STYLE;
        var hover = Style.resolve(style, "cell", "hover", ctx("dark"));
        compare(hover.fill, "role:card@0.85");
        compare(hover.radius, 8);
        compare(hover.wash, "role:foreground@0.1");

        var ghost = Style.resolve(style, "cell", "ghost", ctx("dark"));
        compare(ghost.fill, Style.LITERAL_COLORS.transparent);
        compare(ghost.border, null);
        compare(ghost.radius, 8);

        // `off` is the base state of a role that has no `rest`.
        var on = Style.resolve(style, "switch.track", "on", ctx("dark"));
        compare(on.fill, "role:primary");
        compare(on.radius, "pill");
    }

    // The wash is a lift on a dark theme and a knock-down on a light one,
    // which is what makes it read the same over any wallpaper: the ink is
    // always the far end from the surface it sits on, and white needs the
    // larger alpha to move the same distance.
    function test_an_alpha_pair_resolves_per_mode() {
        var wash = Metamorphosis.STYLE.wash;
        var dark = Style.alphaFor(wash.hover.alpha, ctx("dark"));
        var light = Style.alphaFor(wash.hover.alpha, ctx("light"));
        verify(dark > light);
        verify(Style.alphaFor(wash.press.alpha, ctx("dark")) > dark);
        verify(Style.alphaFor(wash.press.alpha, ctx("light")) > light);
        // The bar strip is `card`, not `background`, so the hover has that
        // much less room to read against than a shadcn ghost button does:
        // zinc's own accent-over-card is white at 0.07, and the wash steps
        // past it.
        verify(dark > 0.07);
        verify(light > 0.043);
    }

    // shadcn's `/90` on a control that already carries a colour, the same
    // either way round: a fill blends toward `background` rather than
    // washing toward the ink.
    function test_the_filled_steps_match_across_modes() {
        var wash = Metamorphosis.STYLE.wash;
        compare(Style.alphaFor(wash.filledHover.alpha, ctx("dark")),
            Style.alphaFor(wash.filledHover.alpha, ctx("light")));
        verify(Style.alphaFor(wash.filledPress.alpha, ctx("dark"))
            > Style.alphaFor(wash.filledHover.alpha, ctx("dark")));
    }

    // Anything that is not the light theme is the dark one, the same
    // default Palette.fallback() takes for a theme.json with no `mode`.
    function test_an_unknown_mode_reads_as_dark() {
        var wash = Metamorphosis.STYLE.wash;
        compare(Style.alphaFor(wash.hover.alpha, ctx("")),
            Style.alphaFor(wash.hover.alpha, ctx("dark")));
    }

    function test_surface_takes_the_theme_alpha_and_an_absent_alpha_is_opaque() {
        compare(Style.alphaFor("surface", ctx("dark")), 0.85);
        compare(Style.alphaFor(undefined, ctx("dark")), 1);
        compare(Style.alphaFor(0.2, ctx("light")), 0.2);
    }

    function test_a_tint_folds_into_the_fill_and_leaves_it_opaque() {
        var press = Style.resolve(Metamorphosis.STYLE, "button.default", "press", ctx("dark"));
        compare(press.fill, "role:primary+role:background@0.18");
        compare(press.wash, null);
        // The variants with no colour of their own take the wash instead.
        compare(Style.resolve(Metamorphosis.STYLE, "button.ghost", "press", ctx("dark")).wash,
            "role:foreground@0.16");
    }

    function test_a_radius_step_resolves_and_pill_survives() {
        compare(Style.radiusFor("sm", ctx("dark").radius), 6);
        compare(Style.radiusFor("xl", ctx("dark").radius), 14);
        compare(Style.radiusFor(3, ctx("dark").radius), 3);
        compare(Style.radiusFor("pill", ctx("dark").radius), "pill");
        compare(Style.radiusFor(undefined, ctx("dark").radius), 0);
    }

    // CSS box-shadow's own reading (the spec's shape): blur makes a cast,
    // spread alone a ring, neither a hairline.
    function test_a_layer_is_read_by_its_blur_and_its_spread() {
        compare(Style.layerKind({ blur: 4, color: "black" }), "cast");
        compare(Style.layerKind({ blur: 4, spread: 2, color: "black" }), "cast");
        compare(Style.layerKind({ spread: 1, color: "black" }), "ring");
        compare(Style.layerKind({ inset: true, y: 1, color: "white" }), "hairline");

        var split = Style.layers([
            { inset: true, y: 1, color: "white", alpha: 0.3 },
            { spread: 1, color: "black", alpha: 0.1 },
            { y: 3, blur: 4, color: "black", alpha: 0.15 }
        ]);
        compare(split.hairlines.length, 1);
        compare(split.rings.length, 1);
        compare(split.casts.length, 1);
        compare(Style.layers(undefined).casts.length, 0);
    }

    // A positive offset names the near edge and a negative one the far
    // edge, so `0 1px` reads as a lit top lip and `0 -1px` as a lower one.
    function test_a_hairline_names_one_edge() {
        compare(Style.hairline({ inset: true, y: 1 }).edge, "top");
        compare(Style.hairline({ inset: true, y: -2 }).edge, "bottom");
        compare(Style.hairline({ inset: true, y: -2 }).thickness, 2);
        compare(Style.hairline({ inset: true, x: 1 }).edge, "left");
        compare(Style.hairline({ inset: true, x: -1 }).edge, "right");
        compare(Style.hairline({ inset: true, x: -1 }).inset, true);
        compare(Style.hairline({ x: 1 }).inset, false);
        compare(Style.hairline({ inset: true }), null);
    }

    // A theme that omits a role resolves to an empty box rather than
    // throwing, so the validation test above is what catches it and a
    // running shell never dies on a lookup.
    function test_an_unknown_role_resolves_to_an_empty_box() {
        var box = Style.resolve(Metamorphosis.STYLE, "nonsense", null, ctx("dark"));
        compare(box.fill, Style.LITERAL_COLORS.transparent);
        compare(box.radius, 0);
        compare(box.border, null);
        compare(box.hairlines.length, 0);
    }

    function test_a_wash_resolves_off_the_table() {
        compare(Style.wash(Metamorphosis.STYLE, "hover", ctx("dark")), "role:foreground@0.1");
        compare(Style.wash(Metamorphosis.STYLE, "hover", ctx("light")), "role:foreground@0.06");
        compare(Style.wash(Metamorphosis.STYLE, "filledPress", ctx("dark")), "role:background@0.18");
        compare(Style.wash(Metamorphosis.STYLE, "nonsense", ctx("dark")),
            Style.LITERAL_COLORS.transparent);
    }

    // --- The window (M60 P7) ---------------------------------------------
    //
    // The one role nothing in the shell draws: Hyprland does, off the
    // variables chrome.js renders, so the entry is read raw rather than
    // resolved and its shape is what has to hold. Every number is checked
    // against the range Hyprland's own option carries
    // (src/config/values/ConfigValues.cpp, 0.56), since a value outside one
    // takes the whole config's parse with it.
    function test_every_table_declares_a_window_hyprland_can_draw() {
        var names = tableNames();
        for (var t = 0; t < names.length; t++) {
            var name = names[t];
            var focused = Style.entry(tables[name], "window", "rest");
            var backdrop = Style.entry(tables[name], "window", "inactive");

            verify(!!focused.border, name + " declares no window frame");
            verify(focused.border.width >= 0 && focused.border.width <= 20,
                name + " frames a window at " + focused.border.width + "px");
            verify(typeof focused.border.color === "string");

            var cast = focused.shadow;
            verify(!!cast, name + " declares no window shadow");
            compare(typeof cast.enabled, "boolean");
            verify(cast.range >= 0 && cast.range <= 100, name + " casts at range " + cast.range);
            verify(cast.renderPower >= 1 && cast.renderPower <= 4,
                name + " casts at power " + cast.renderPower);
            compare(cast.offset.length, 2);
            for (var o = 0; o < 2; o++) {
                verify(cast.offset[o] >= -250 && cast.offset[o] <= 250,
                    name + " casts at offset " + cast.offset.join(" "));
            }

            // A backdrop window differs by its colour alone, which is all a
            // compositor with one range and one offset can take of
            // elementary's second elevation.
            verify(!!backdrop.shadow && typeof backdrop.shadow.color === "string",
                name + " declares no backdrop shadow colour");
        }
    }

    function test_the_shipped_window_casts_nothing() {
        var focused = Style.entry(Metamorphosis.STYLE, "window", "rest");
        compare(focused.shadow.enabled, false);
        compare(focused.border.color, "primary");
        compare(focused.border.width, 1);
        compare(Style.entry(Retro.STYLE, "window", "rest").shadow.enabled, false);
    }

    // elementary's focused window: `shadow(4)` as Hyprland draws it, under a
    // 1px `borders` frame, which under matugen is the `border` role.
    function test_the_pantheon_window_is_elementarys_shadow() {
        var focused = Style.entry(Pantheon.STYLE, "window", "rest");
        compare(focused.border.color, "border");
        compare(focused.border.width, 1);
        compare(focused.shadow.enabled, true);
        compare(focused.shadow.range, 24);
        compare(focused.shadow.renderPower, 3);
        compare(focused.shadow.offset[1], 6);
        compare(focused.shadow.alpha, 0.35);
        compare(Style.entry(Pantheon.STYLE, "window", "inactive").shadow.alpha, 0.25);
    }
}
