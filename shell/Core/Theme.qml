pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
// Self-module import, for the Config sibling singleton (motion.enabled) —
// same pattern as AppleMusicArtService's `import qs.Services`.
import qs.Core
import "../Theme/palette.js" as Palette
import "../Theme/tokens.js" as Tokens

Singleton {
    id: root

    property var color: Palette.fallback()

    // shadcn's border/ring pair (spec "Depth", 2026-08-25): a 1px border
    // everywhere, plus a 3px ring halo at 0.5 alpha on focus. `radius`
    // reads `theme.radius` from settings.json (default 10, shadcn's own
    // `--radius: 0.625rem`); radiusSm/Md/Lg/Xl derive from it per
    // `Tokens.radiusTokens`.
    readonly property int borderWidth: 1
    readonly property int radius: Config.get("theme.radius", 10)
    readonly property var _radiusTokens: Tokens.radiusTokens(radius)
    readonly property int radiusSm: _radiusTokens.sm
    readonly property int radiusMd: _radiusTokens.md
    readonly property int radiusLg: _radiusTokens.lg
    readonly property int radiusXl: _radiusTokens.xl
    readonly property int ringWidth: 3
    readonly property real ringAlpha: 0.5

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
    // wider variant the lock/greeter date label uses) — scale with
    // fontScale, since tracking is a font metric, not a layout gap.
    readonly property var letterSpacing: Tokens.letterSpacingTokens(fontScale)

    // Live bar height, reported by Bar.qml's own content-derived
    // _cellHeight (a fixed literal here would drift the moment any bar cell
    // grows taller than the rest, per Bar.qml's own header comment). The 21
    // default only covers the brief window before the first Bar instance
    // binds it: fontSize.body (13) + space.controlPaddingY (4) * 2, the
    // same single-line-cell arithmetic Cell.qml's own implicitHeight uses,
    // now that Clock.qml collapsed to one line and no cell sets the bar
    // any taller (M23).
    property real barHeight: 21

    // Always the fontconfig `monospace` alias (DESIGN.md §1.3, CLAUDE.md
    // hard rule) — never a hardcoded family, never a second display face.
    // Replaces the legacy `font` object (M18 Task 6): every consumer only
    // ever read `.family`, so the stale size math (duplicating `fontSize`
    // above under different names) is gone with it.
    readonly property string fontFamily: "monospace"

    // --- DESIGN.md §4 motion tokens -----------------------------------------
    // `fast` (hover fills) / `standard` (surface enter/exit) / `slide` (the
    // enter/exit translate distance) / `easing` (the one ease-out curve every
    // transition uses) / `reveal` (the wallpaper crossfade duration,
    // §4's third carve-out) / `revealEasing` (its own curve — a full-screen
    // image swap reads better on InOutQuad than the control-chrome OutCubic).
    // motion.enabled=false in settings.json zeroes `fast`/`standard`/`reveal`
    // (Tokens.motionTokens) — the shell's reduced-motion switch, since no
    // Wayland analog of prefers-reduced-motion exists. The "breathing"
    // opacity pulse (PowerPanel's charging state) and the screensaver's
    // frame effect remain §4's other two continuous-motion carve-outs and
    // keep their own pacing, unaffected by motion.enabled. `marqueePxPerSec`/
    // `marqueeHoldMs` (the now-playing bar cell's overflow scroll) are the
    // fourth carve-out (M16 Task 11) — unlike the pulse and the screensaver,
    // it DOES respect motion.enabled, but the consumer gates on
    // `motionEnabled` directly rather than this object zeroing the rate
    // to 0.
    readonly property bool motionEnabled: Config.get("motion.enabled", true) === true
    readonly property var motion: {
        var m = Tokens.motionTokens(root.motionEnabled);
        return {
            fast: m.fast,
            standard: m.standard,
            slide: m.slide,
            easing: Easing.OutCubic,
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
    // when neither exists yet, which is the normal state at shell startup —
    // ThemeEngine hasn't written its first theme.json yet — so a bare
    // watchChanges: true here would watch nothing, forever, and never notice
    // ThemeEngine's later out-of-band Process writes (verified: theme.json
    // changed on disk with matugen colors, this FileView never reloaded).
    // reload() re-runs FileView's internal updateWatchedFiles(), so once the
    // state dir exists — which happens within ThemeEngine's very first
    // startup run — the watch attaches for real and takes over from here.
    Timer {
        id: rewatchTimer
        interval: 300
        onTriggered: themeJsonFile.reload()
    }

    // Live theme.json watch: ThemeEngine writes this file atomically, we just
    // read it. Absent or failing palette.validate() (e.g. mid-write, or no
    // engine run yet) falls back to the static Flexoki defaults.
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
        // live matugen color and only substitutes Flexoki for that key.
        root.color = Palette.mergeWithFallback(parsed);
    }
}
