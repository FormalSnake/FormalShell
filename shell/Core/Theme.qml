pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
// Self-module import, for the Config sibling singleton (motion.enabled),
// same pattern as AppleMusicArtService's `import qs.Services`.
import qs.Core
import "../Theme/palette.js" as Palette
import "../Theme/presets.js" as Presets
import "../Theme/style.js" as Style
import "../Theme/tokens.js" as Tokens
import "../Bar/layout.js" as BarLayout

Singleton {
    id: root

    // Palette.fallback()'s dark defaults, `color`'s own placeholder below
    // before the first real palette lands (`_applyPalette`, near the
    // FileView at the bottom of this file). Computed once and shared across
    // every property there instead of 26 separate calls.
    readonly property var _bootFallback: Palette.fallback()

    // True once `_applyPalette` has run for real at least once. Every
    // Behavior on `color` below is gated on it, so the very first palette
    // (the common no-wallpaper case, straight off `_bootFallback`; a real
    // matugen palette on a session that starts with a wallpaper already
    // set) replaces the placeholder outright instead of crossfading from it
    // (M51 D6/D9's boot rule). Background.qml's `_suppressTopFade` guards
    // the wallpaper crossfade the same way, for the same reason.
    //
    // Public, and one third of shell.qml's startup reveal gate (M52): the
    // boot surfaces wait on it so they map already carrying the real
    // palette. Both FileView branches funnel through `_applyPalette`, so an
    // absent theme.json flips this as surely as a parsed one.
    property bool paletteReady: false

    // The palette crossfade, spelled once (M54 Task 1): 26 Behaviors below
    // take it, and an inline component keeps each of them one line. It
    // carries the curve but not the clock, since an inline component has no
    // access to this file's ids and `motion.reveal` is behind one.
    component RevealAnim: ColorAnimation {
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Tokens.MOTION_CURVES.effectsSlow
    }

    // theme.json's shadcn color roles (M51 D6): every key crossfades to a
    // new palette over `motion.reveal` on a mode toggle, a matugen
    // recolour, a preset swap or the Flexoki pin, in step with the
    // wallpaper. A `Behavior` only ever attaches to a property, never to
    // whatever value happens to be sitting in a `var`, which is why this is
    // a nested object with one `property color` per key rather than the
    // plain map `color` held before M51: `_applyPalette` below writes one
    // key at a time so each Behavior sees the change, since replacing this
    // object outright would replace the Behaviors along with it. `color`
    // itself stays a plain, non-readonly `var`: several unit tests
    // (tests/tst_button.qml and its siblings) still swap the whole thing for
    // a sentinel map mid-test, and a plain object serves every consumer here
    // exactly as this one does, since nothing outside this file cares
    // whether `.background` resolves off a QtObject or a map. `mode` alone
    // carries no Behavior: `_stateAlpha` below reads it as a lookup key, not
    // a colour, so it has nothing to crossfade.
    property var color: QtObject {
        property string mode: root._bootFallback.mode
        property color background: root._bootFallback.background
        property color foreground: root._bootFallback.foreground
        property color card: root._bootFallback.card
        property color cardForeground: root._bootFallback.cardForeground
        property color popover: root._bootFallback.popover
        property color popoverForeground: root._bootFallback.popoverForeground
        property color primary: root._bootFallback.primary
        property color primaryForeground: root._bootFallback.primaryForeground
        property color secondary: root._bootFallback.secondary
        property color secondaryForeground: root._bootFallback.secondaryForeground
        property color muted: root._bootFallback.muted
        property color mutedForeground: root._bootFallback.mutedForeground
        property color accent: root._bootFallback.accent
        property color accentForeground: root._bootFallback.accentForeground
        property color destructive: root._bootFallback.destructive
        property color destructiveForeground: root._bootFallback.destructiveForeground
        property color warning: root._bootFallback.warning
        property color warningForeground: root._bootFallback.warningForeground
        property color border: root._bootFallback.border
        property color input: root._bootFallback.input
        property color ring: root._bootFallback.ring
        property color chart1: root._bootFallback.chart1
        property color chart2: root._bootFallback.chart2
        property color chart3: root._bootFallback.chart3
        property color chart4: root._bootFallback.chart4
        property color chart5: root._bootFallback.chart5

        Behavior on background { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on foreground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on card { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on cardForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on popover { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on popoverForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on primary { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on primaryForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on secondary { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on secondaryForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on muted { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on mutedForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on accent { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on accentForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on destructive { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on destructiveForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on warning { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on warningForeground { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on border { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on input { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on ring { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on chart1 { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on chart2 { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on chart3 { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on chart4 { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
        Behavior on chart5 { enabled: root.paletteReady; RevealAnim { duration: root.motion.reveal } }
    }

    // theme.preset (M49 D1): one table of defaults behind the chrome knobs
    // below, resolved once here. An explicit settings key always wins over
    // the table, and no surface ever reads a `theme.*` key or the preset
    // name itself. `_presetDefaults` is what a malformed number falls back
    // to, since the preset's own value is the right answer there, not
    // metamorphosis's.
    readonly property var _preset: Presets.resolve(Config.get("theme.preset", "metamorphosis"), Config.get)
    readonly property var _presetDefaults: Presets.defaults(root._preset.preset)
    readonly property string preset: root._preset.preset

    // The preset's chrome table (M59 T1) and its habits, the two things a
    // surface reads instead of ever learning which theme is live: `style`
    // is one box description per role (shell/Theme/style.js documents the
    // schema, shell/Theme/themes/ holds a file per theme) and `habit` says
    // which shape a surface takes where themes differ in more than chrome.
    readonly property var style: root._preset.style
    readonly property var habit: root.style.habits

    // What style.js resolves a box against: the live palette and the
    // arithmetic a `.pragma library` has no access to. Built per call
    // rather than held, so a binding that calls `box()` registers its
    // dependency on every palette key the resolution reads.
    function _styleCtx() {
        return {
            mode: root.color.mode,
            surfaceOpacity: root.surfaceOpacity,
            radius: root._radiusTokens,
            color: name => root.color[name],
            alpha: (c, a) => Qt.alpha(c, a),
            tint: (c, over) => Qt.tint(c, over)
        };
    }

    // One role's box, drawable: colours resolved, alphas taken per mode,
    // the radius off the step ladder. `state` falls back to the role's base
    // state, so a primitive passes its own state string through without
    // knowing which states a table bothers to describe, and `"pill"`
    // survives as itself because it needs the extent of the item being
    // drawn (Components/Box.qml resolves it).
    function box(role, state) {
        return Style.resolve(root.style, role, state, root._styleCtx());
    }

    // The `window` role's two states, unresolved (M60 P7): ThemeEngine
    // publishes them to Hyprland as hyprlang variables, where a palette
    // role names the variable formalshell-colors.conf carries rather than a
    // colour this palette could hand over, so the compositor's frame keeps
    // following the wallpaper without the chrome file being rewritten.
    readonly property var windowChrome: ({
        focused: Style.entry(root.style, "window", "rest"),
        backdrop: Style.entry(root.style, "window", "inactive")
    })

    // Whether the live table describes a state at all, for a state only one
    // habit's surfaces draw (M60 T3): a bar cell marking an open panel by
    // filling itself under wingpanel still has to fall back to the ghost's
    // own box under a table that leaves that mark to a line along the edge.
    function hasState(role, state) {
        return Style.hasState(root.style, role, state);
    }

    // The keyboard cursor composed over the box a control already carries
    // (M59 T6): one table entry decides what a cursor looks like wherever it
    // lands. `halo` is a second answer from `on`, because a list draws one
    // halo for every row under it (cursor.js's `ownsCursorHalo` walk) while
    // each of those rows still swaps its own border.
    function withCursor(box, on, halo) {
        return on ? Style.withCursor(box, root.box("cursor"), halo) : box;
    }

    // A resolved box's radius against the item drawing it. `pill` survives
    // resolution as itself because it needs that item's extent, so a
    // primitive keeping its own layers (Switch's knob riding its track)
    // resolves it here rather than spelling out the ternary Box carries.
    function boxRadius(box, extent) {
        return box.radius === "pill" ? root.pillRadius(extent) : box.radius;
    }

    // The halo the `cursor` entry declares, resolved, for the surfaces that
    // draw one by hand rather than through a Box: a list owns a single halo
    // for all of its rows, so that one cannot come out of a row's own box. A
    // table declaring no ring layer reads as nothing rather than as
    // undefined.
    readonly property var cursorRing: {
        var rings = root.box("cursor").rings;
        return rings.length > 0 ? rings[0] : ({ spread: 0, color: "transparent" });
    }

    // shadcn's border width (spec "Depth", 2026-08-25): 1px everywhere.
    // `radius` is the preset's base (10 on metamorphosis, shadcn's own
    // `--radius: 0.625rem`; 0 on retro) with an explicit `theme.radius`
    // winning over it; radiusSm/Md/Lg/Xl derive from it per
    // `Tokens.radiusTokens`, which squares every step at a base of 0.
    readonly property int borderWidth: 1
    readonly property int radius: Math.round(Tokens.clamp(root._preset.radius, 0, Infinity, root._presetDefaults.radius))
    readonly property var _radiusTokens: Tokens.radiusTokens(radius)
    readonly property int radiusSm: _radiusTokens.sm
    readonly property int radiusMd: _radiusTokens.md
    readonly property int radiusLg: _radiusTokens.lg
    readonly property int radiusXl: _radiusTokens.xl

    // The room the cursor's halo needs outside a row (DESIGN.md §1 "Ring"):
    // a clipping container grows its clip rect by this and insets its
    // content by the same, and the app grid leaves it in its gutter. That
    // reservation is geometry rather than chrome, so it stays a number here,
    // taken off the spread the table's own ring layer asks for.
    readonly property int ringWidth: root.cursorRing.spread

    // The pill shapes (the switch track and knob, the workspace dots and
    // pill, the bell badge, the LED pips, the calendar and unread dots) are
    // half their own extent while the base radius is positive, and square at
    // 0 (M49 D2). Tied to the radius rather than the preset, so
    // `theme.radius: 0` squares them on metamorphosis too.
    function pillRadius(extent) {
        return root.radius > 0 ? extent / 2 : 0;
    }

    // The corner a picture takes at its own size (`Tokens.coverRadius`): the
    // radius ladder is sized for controls, and `radiusSm` on the bar's 17px
    // album art reads as a lozenge rather than a rounded square. `Cover` is
    // the only caller.
    function coverRadius(extent) {
        return Tokens.coverRadius(root.radiusSm, extent);
    }

    // shadcn font-weight tokens (spec "Type").
    readonly property var weight: Tokens.WEIGHTS

    // fontBaseSize is the rem root (default 13, the shell's existing body
    // size, so fontScale is 1.0 out of the box). Retheming this one number
    // rescales every font token in `fontSize` proportionally.
    property real fontBaseSize: 13
    readonly property real fontScale: Tokens.fontScale(fontBaseSize)
    readonly property var fontSize: Tokens.fontTokens(fontBaseSize)

    // spacingScale tracks fontScale by default (a larger base font gets
    // roomier spacing automatically) but can be pinned independently.
    property real spacingScale: fontScale
    readonly property var space: Tokens.spacingTokens(spacingScale)

    // Letter-spacing tokens (DESIGN.md §2.3's meta-row tracking, plus the
    // wider variant the lock/greeter date label uses), scale with
    // fontScale, since tracking is a font metric, not a layout gap.
    readonly property var letterSpacing: Tokens.letterSpacingTokens(fontScale)

    // Which output edge the bar sits on (`bar.position`, one of top,
    // bottom, left, right; anything else is top). `barVertical` is the
    // left/right pair, where the strip's regions run top to bottom and each
    // cell turns its content along it.
    readonly property string barPosition: BarLayout.position(Config.get("bar.position", BarLayout.DEFAULT_POSITION))
    readonly property bool barVertical: BarLayout.isVertical(root.barPosition)

    // How much of its edge the bar occupies: its cell row plus the margin
    // band around it, which is also its exclusive zone. Bar.qml binds this
    // from its own window extent; the value here only covers the window
    // before the first Bar instance maps.
    property real barThickness: space.barCellHeight + space.barMargin * 2

    // The screen frame (Surfaces/Frame/Frame.qml): `frame.thickness` is
    // its band on the three edges the bar is not on, 0 (the default) means
    // no frame at all, and `frame.radius` is the corner of the rounded
    // cut-out it leaves for the desktop, squared along with everything
    // else when the base radius is 0.
    //
    // A table says whether it wears one at all (`habits.frame`, owner
    // 2026-09-18). pantheon's ring is transparent under the wingpanel band
    // (M62) but reserves its band all the same, so a window sat
    // `frame.thickness` in from an edge with nothing drawn there and the
    // gaps read as too wide. A table that says no reads the key as 0
    // whatever settings.json holds, rather than the key being ignored per
    // surface. `debug dump`'s `frame` block reports both numbers.
    readonly property bool frameHabit: root.habit.frame !== false
    readonly property real frameRequested: Math.round(Tokens.clamp(Config.get("frame.thickness", 0), 0, Infinity, 0))
    readonly property real frameThickness: root.frameHabit ? root.frameRequested : 0
    readonly property bool frameEnabled: root.frameThickness > 0
    readonly property real frameRadius: Math.round(Tokens.clamp(Config.get("frame.radius", root.radius > 0 ? 20 : 0), 0, Infinity, 0))

    // The bar's thickness on its own edge and 0 on the other three
    // (Frame.qml paints around exactly this), and the same with the frame's
    // band on those three, which is what every surface that has to clear
    // the edges (panels, toasts, the centre, the console) reads: Wayland
    // gives clients no cross-window geometry, so the strip publishes its
    // own occupied edge.
    readonly property var barInset: BarLayout.insets(root.barPosition, root.barThickness, 0)
    readonly property var edgeInset: BarLayout.insets(root.barPosition, root.barThickness, root.frameThickness)

    // Two faces by context (spec "Type", DESIGN.md §1): sans carries words,
    // mono carries values. Both are fontconfig aliases, never a hardcoded
    // family (CLAUDE.md hard rule). The intended pair is Geist Sans and
    // Geist Mono, chosen through the user's own fontconfig defaults.
    // `theme.fonts: "mono"` (retro's default) points the sans alias at the
    // mono face, so every surface draws in one face without a single one of
    // them branching on the key.
    readonly property string fonts: root._preset.fonts
    readonly property string fontFamilySans: root._preset.fonts === "mono" ? "monospace" : "sans-serif"
    readonly property string fontFamilyMono: "monospace"

    // Which set `Components/Icon.qml` looks a name up in, `lucide` or
    // `nerd`; anything else falls back to lucide in shell/Theme/icons.js.
    readonly property string iconSet: root._preset.icons

    // The alpha of every `card`/`popover` fill on the three surfaces
    // Hyprland blurs behind (DESIGN.md §1 "Translucency and blur"): the bar
    // cells, the panels and the launcher card. The shell blurs nothing
    // itself; this alpha is what lets the compositor's blur read through,
    // and `blurBehind` is what says whether the compositor blurs there at
    // all. Retro sets 1.0 and no blur, so the same cards read as solid.
    readonly property real surfaceOpacity: Tokens.clamp(root._preset.surfaceOpacity, 0, 1, root._presetDefaults.surfaceOpacity)
    readonly property bool blurBehind: root._preset.blur

    // `theme.dither` is the one texture knob (M49 D3): on, content imagery
    // renders through the retro dither pass instead of drawing plain.
    // The two full-screen passes take their own keys, defaulting to this
    // one, so a preset carries the texture everywhere and either surface
    // can still opt out.
    readonly property bool dither: root._preset.dither
    readonly property bool wallpaperDither: root._preset.wallpaperDither
    readonly property bool lockDither: root._preset.lockDither

    // Qt.alpha rather than Qt.rgba(c.r, c.g, c.b, alpha): no channel
    // extraction needed to add an alpha on top of a color already in hand.
    function surface(c) {
        return Qt.alpha(c, root.surfaceOpacity);
    }

    // --- Interaction states -------------------------------------------------
    // Hover and press, as a wash of the surface's own ink rather than an
    // opaque `accent` chip; and, for a control that already carries a fill,
    // the same two states as a blend toward `background` (shadcn's
    // `hover:bg-primary/90`), since a wash over a colour reads as the fill
    // going muddy. The table's own `wash` entry carries the four numbers
    // and the arithmetic behind them; these names are what every caller
    // already reads. `accent` keeps the states that are not the pointer's:
    // selected, and a list's own cursor row.
    readonly property color hoverFill: Style.wash(root.style, "hover", root._styleCtx())
    readonly property color pressFill: Style.wash(root.style, "press", root._styleCtx())

    function hoverFilled(c) {
        return Qt.tint(c, Style.wash(root.style, "filledHover", root._styleCtx()));
    }

    function pressFilled(c) {
        return Qt.tint(c, Style.wash(root.style, "filledPress", root._styleCtx()));
    }

    // --- DESIGN.md §1 motion tokens -----------------------------------------
    // Two families, and the property picks the family (M54 D1/D2). A
    // surface never spells a duration or a curve of its own: it writes
    // `Behavior on x { Anim {} }`, `Behavior on opacity { Anim { kind:
    // "effects" } }`, `Behavior on color { CAnim {} }`, and the primitive
    // (Components/Anim.qml) reads this object by kind.
    //
    // `spatialFast` 350 / `spatial` 500 / `spatialSlow` 650 pace anything
    // with a position or a size: x, y, width, height, margins, scale,
    // radius, rotation, an emerge, a morph, a cursor's travel. Their curves
    // carry a y control above 1, so what travels overshoots its rest by a
    // few pixels and settles back.
    // `effectsFast` 150 / `effects` 200 / `effectsSlow` 300 pace anything
    // with neither: opacity, colour, a progress that only drives alpha.
    // They never overshoot.
    // `emphasized` 400 is the workspace pill alone and `emphasizedDecel` a
    // toast arriving from off screen (a curve on `spatial`'s clock, so it
    // has no duration here). `reveal` 400 is the full-screen fades, the
    // wallpaper and palette crossfades and the lock's blank and wake, on
    // `effectsSlow`'s curve.
    // `curves` is the bezier per kind as `easing.bezierCurve` wants it,
    // control points then the (1, 1) end point.
    //
    // motion.enabled=false in settings.json zeroes every duration
    // (Tokens.motionTokens) and pins `Deform` to identity (M54 D5), the
    // shell's reduced-motion switch, since no Wayland analog of
    // prefers-reduced-motion exists. The "breathing" opacity pulse
    // (PowerPanel's charging state) and the screensaver's frame effect
    // remain §4's other two continuous-motion carve-outs and keep their own
    // pacing, unaffected by motion.enabled. `marqueePxPerSec`/
    // `marqueeHoldMs` (the now-playing bar cell's overflow scroll) are the
    // fourth carve-out (M16 Task 11), unlike the pulse and the screensaver,
    // it DOES respect motion.enabled, but the consumer gates on
    // `motionEnabled` directly rather than this object zeroing the rate
    // to 0.
    readonly property bool motionEnabled: Config.get("motion.enabled", true) === true
    // Every clock stretched by this factor, for the rig alone (`debug
    // motionScale`, Ipc/DebugIpc.qml): a screencopy costs about as much as a
    // whole entrance, so a mid-flight pose can only be photographed slowed
    // down. Never read from settings.json.
    property real motionScale: 1
    // The clocks a theme's table names for itself (M60 T2, T4, M64): a
    // drawer's entrance, which the popover habit takes at Gala's 150ms while
    // the metamorphosis names the spatial family it has always ridden, the
    // toast stack's arrival and restack, and the window switcher's own fade,
    // which under the habit that draws it is a second Gala constant rather
    // than the drawer's. All resolved against the unzeroed tokens, since the
    // reduced-motion switch and the rig's scale are applied below with every
    // other duration.
    readonly property var _emerge: Style.motion(root.style, "emerge",
        Tokens.motionTokens(true), Tokens.MOTION_CURVES)
    readonly property var _arrive: Style.motion(root.style, "arrive",
        Tokens.motionTokens(true), Tokens.MOTION_CURVES)
    readonly property var _restack: Style.motion(root.style, "restack",
        Tokens.motionTokens(true), Tokens.MOTION_CURVES)
    readonly property var _switcher: Style.motion(root.style, "switcher",
        Tokens.motionTokens(true), Tokens.MOTION_CURVES)

    readonly property var motion: {
        var m = Tokens.motionTokens(root.motionEnabled);
        var c = Tokens.MOTION_CURVES;
        var s = root.motionScale;
        return {
            emerge: (root.motionEnabled ? root._emerge.duration : 0) * s,
            arrive: (root.motionEnabled ? root._arrive.duration : 0) * s,
            restack: (root.motionEnabled ? root._restack.duration : 0) * s,
            switcher: (root.motionEnabled ? root._switcher.duration : 0) * s,
            // The window a staggered restack is spread over, for the one
            // consumer that divides it by the number of cards moving
            // (Surfaces/Notifications/Toasts.qml). Zero is a pile that
            // moves as one, which is every table but the bubble's.
            restackStagger: (root.motionEnabled ? root._restack.stagger : 0) * s,
            spatialFast: m.spatialFast * s,
            spatial: m.spatial * s,
            spatialSlow: m.spatialSlow * s,
            effectsFast: m.effectsFast * s,
            effects: m.effects * s,
            effectsSlow: m.effectsSlow * s,
            emphasized: m.emphasized * s,
            reveal: m.reveal * s,
            curves: {
                spatialFast: c.spatialFast,
                spatial: c.spatial,
                spatialSlow: c.spatialSlow,
                effectsFast: c.effectsFast,
                effects: c.effects,
                effectsSlow: c.effectsSlow,
                emphasized: c.emphasized,
                emphasizedDecel: c.emphasizedDecel,
                reveal: c.effectsSlow,
                emerge: root._emerge.curve,
                switcher: root._switcher.curve,
                arrive: root._arrive.curve,
                restack: root._restack.curve
            },
            pulseDuration: 900,
            pulseEasing: Easing.InOutQuad,
            marqueePxPerSec: m.marqueePxPerSec,
            marqueeHoldMs: m.marqueeHoldMs
        };
    }

    readonly property string _stateDir: {
        const xdgState = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
        return xdgState + "/formalshell";
    }

    // Re-attempt the watch until it actually attaches: FileView's underlying
    // QFileSystemWatcher silently fails to watch a path (or its parent dir)
    // when neither exists yet, which is the normal state at shell startup,
    // ThemeEngine hasn't written its first theme.json yet, so a bare
    // watchChanges: true here would watch nothing, forever, and never notice
    // ThemeEngine's later out-of-band Process writes (verified: theme.json
    // changed on disk with matugen colors, this FileView never reloaded).
    // reload() re-runs FileView's internal updateWatchedFiles(), so once the
    // state dir exists, which happens within ThemeEngine's very first
    // startup run, the watch attaches for real and takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: themeJsonFile.reload()
    }

    // Live theme.json watch: ThemeEngine writes this file atomically, we just
    // read it. Absent or failing palette.validate() (e.g. mid-write, or no
    // engine run yet) falls back to palette.js's static zinc defaults.
    FileView {
        id: themeJsonFile
        path: root._stateDir + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyThemeJson()
        onLoadFailed: error => {
            root._applyPalette(Palette.fallback());
            if (error === FileViewError.FileNotFound)
                rewatchTimer.restart();
        }
    }

    function _applyThemeJson() {
        var parsed = null;
        try {
            parsed = JSON.parse(themeJsonFile.text());
        } catch (e) {
            parsed = null;
        }
        // Per-key fallback, not whole-file: a theme.json written before a
        // token existed (or mid-write with one bad value) keeps every other
        // live matugen color and only substitutes zinc for that key.
        root._applyPalette(Palette.mergeWithFallback(parsed));
    }

    // Writes one palette onto `color` a key at a time, the tail every
    // palette-change path (theme.json present, absent, or mid-write) funnels
    // through, so each property's own Behavior sees the change and
    // crossfades to it rather than the object underneath the Behaviors
    // getting replaced outright.
    function _applyPalette(palette) {
        root.color.mode = palette.mode;
        Palette.COLOR_KEYS.forEach(key => root.color[key] = palette[key]);
        root.paletteReady = true;
    }
}
