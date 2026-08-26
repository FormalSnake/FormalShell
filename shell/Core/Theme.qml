pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
// Self-module import, for the Config sibling singleton (motion.enabled),
// same pattern as AppleMusicArtService's `import qs.Services`.
import qs.Core
import "../Theme/palette.js" as Palette
import "../Theme/presets.js" as Presets
import "../Theme/tokens.js" as Tokens
import "../Bar/layout.js" as BarLayout

Singleton {
    id: root

    property var color: Palette.fallback()

    // theme.preset (M49 D1): one table of defaults behind the chrome knobs
    // below, resolved once here. An explicit settings key always wins over
    // the table, and no surface ever reads a `theme.*` key or the preset
    // name itself. `_presetDefaults` is what a malformed number falls back
    // to, since the preset's own value is the right answer there, not
    // shadcn's.
    readonly property var _preset: Presets.resolve(Config.get("theme.preset", "shadcn"), Config.get)
    readonly property var _presetDefaults: Presets.defaults(root._preset.preset)
    readonly property string preset: root._preset.preset

    // shadcn's border/ring pair (spec "Depth", 2026-08-25): a 1px border
    // everywhere, plus a 3px ring halo at 0.5 alpha on focus. `radius` is
    // the preset's base (10 on shadcn, shadcn's own `--radius: 0.625rem`;
    // 0 on retro) with an explicit `theme.radius` winning over it;
    // radiusSm/Md/Lg/Xl derive from it per `Tokens.radiusTokens`, which
    // squares every step at a base of 0.
    readonly property int borderWidth: 1
    readonly property int radius: Math.round(Tokens.clamp(root._preset.radius, 0, Infinity, root._presetDefaults.radius))
    readonly property var _radiusTokens: Tokens.radiusTokens(radius)
    readonly property int radiusSm: _radiusTokens.sm
    readonly property int radiusMd: _radiusTokens.md
    readonly property int radiusLg: _radiusTokens.lg
    readonly property int radiusXl: _radiusTokens.xl
    readonly property int ringWidth: 3
    readonly property real ringAlpha: 0.5

    // The pill shapes (the switch track and knob, the workspace dots and
    // pill, the bell badge, the LED pips, the calendar and unread dots) are
    // half their own extent while the base radius is positive, and square at
    // 0 (M49 D2). Tied to the radius rather than the preset, so
    // `theme.radius: 0` squares them on shadcn too.
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

    // That thickness on the bar's own edge and 0 on the other three, which
    // is what every surface that has to clear the bar (panels, toasts, the
    // centre, the console) reads: Wayland gives clients no cross-window
    // geometry, so the strip publishes its own occupied edge.
    readonly property var barInset: BarLayout.insets(root.barPosition, root.barThickness)

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

    // Qt.alpha rather than Qt.rgba: `color` arrives from theme.json as hex
    // strings, which have no .r/.g/.b to read, and Qt.rgba on those three
    // undefined values silently paints black at the right alpha.
    function surface(c) {
        return Qt.alpha(c, root.surfaceOpacity);
    }

    // --- Interaction states -------------------------------------------------
    // Hover and press, as a wash of the surface's own ink rather than an
    // opaque `accent` chip. Every surface that takes a hover is drawn at
    // `surfaceOpacity`, so an opaque fill on top of it lands at a delta the
    // wallpaper behind the blur decides, and a bright wallpaper cancels the
    // lift outright. `Tokens.stateAlpha`'s header carries the arithmetic.
    // `accent` keeps the states that are not the pointer's: selected, and a
    // list's own cursor row.
    readonly property var _stateAlpha: Tokens.stateAlpha(root.color.mode)
    readonly property color hoverFill: Qt.alpha(root.color.foreground, root._stateAlpha.hover)
    readonly property color pressFill: Qt.alpha(root.color.foreground, root._stateAlpha.press)

    // The same two states for a control that already carries a fill, where a
    // wash of the ink would read as the fill going muddy: shadcn's
    // `hover:bg-primary/90`, blended toward `background` and left opaque.
    function hoverFilled(c) {
        return Qt.tint(c, Qt.alpha(root.color.background, root._stateAlpha.filledHover));
    }

    function pressFilled(c) {
        return Qt.tint(c, Qt.alpha(root.color.background, root._stateAlpha.filledPress));
    }

    // --- DESIGN.md §4 motion tokens -----------------------------------------
    // `fast` (hover fills) / `standard` (surface enter/exit) / `emphasized`
    // (the bar's workspace pill, the one piece of chrome whose travel spans
    // the width of a row, on `emphasizedEasing`'s longer decel) / `slide` (the
    // enter/exit translate distance) / `easing` (the ease-out curve a
    // transition that ENTERS or EXITS uses) / `easingInOut` (the curve a
    // transition that MOVES something already on screen uses) / `reveal`
    // (the wallpaper crossfade duration,
    // §4's third carve-out) / `revealEasing` (its own curve, a full-screen
    // image swap reads better on InOutQuad than the control-chrome OutCubic).
    // motion.enabled=false in settings.json zeroes
    // `fast`/`standard`/`emphasized`/`reveal`
    // (Tokens.motionTokens), the shell's reduced-motion switch, since no
    // Wayland analog of prefers-reduced-motion exists. The "breathing"
    // opacity pulse (PowerPanel's charging state) and the screensaver's
    // frame effect remain §4's other two continuous-motion carve-outs and
    // keep their own pacing, unaffected by motion.enabled. `marqueePxPerSec`/
    // `marqueeHoldMs` (the now-playing bar cell's overflow scroll) are the
    // fourth carve-out (M16 Task 11), unlike the pulse and the screensaver,
    // it DOES respect motion.enabled, but the consumer gates on
    // `motionEnabled` directly rather than this object zeroing the rate
    // to 0.
    readonly property bool motionEnabled: Config.get("motion.enabled", true) === true
    readonly property var motion: {
        var m = Tokens.motionTokens(root.motionEnabled);
        return {
            fast: m.fast,
            standard: m.standard,
            emphasized: m.emphasized,
            emphasizedEasing: Easing.OutQuint,
            slide: m.slide,
            // OutQuint, not OutCubic: Qt's cubic easings are the weak
            // built-ins, and a decel that shallow reads as drift rather
            // than as a stop. OutQuint is cubic-bezier(0.23, 1, 0.32, 1),
            // the curve UI motion actually wants for an entrance.
            easing: Easing.OutQuint,
            // InOutQuart, cubic-bezier(0.77, 0, 0.175, 1). Something
            // already on screen that travels to a new place accelerates out
            // of rest and decelerates into it; an ease-out on a move starts
            // at full speed, which reads as a teleport that then slows down.
            // Entering and exiting take `easing` above, moving takes this.
            easingInOut: Easing.InOutQuart,
            reveal: m.reveal,
            revealEasing: Easing.InOutQuad,
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
            root.color = Palette.fallback();
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
        root.color = Palette.mergeWithFallback(parsed);
    }
}
