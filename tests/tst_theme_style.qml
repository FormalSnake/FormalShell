import QtQuick
import QtTest
import "../shell/Theme/palette.js" as Palette
import "../shell/Theme/presets.js" as Presets
import "../shell/Theme/style.js" as Style
import "../shell/Theme/themes/metamorphosis.js" as Metamorphosis
import "../shell/Theme/themes/retro.js" as Retro

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

    readonly property var tables: ({ metamorphosis: Metamorphosis.STYLE, retro: Retro.STYLE })

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
        compare(Presets.resolve("shadcn", get).style, Metamorphosis.STYLE);
        compare(Presets.resolve("retro", get).style, Retro.STYLE);
        compare(Presets.defaults("shadcn").style, Metamorphosis.STYLE);
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
}
