pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../Theme/palette.js" as Palette
import "../Theme/tokens.js" as Tokens

Singleton {
    id: root

    property var color: Palette.fallback()

    readonly property int borderWidth: 2
    readonly property int radius: 0

    // --- DESIGN.md §1 scale roots + state/border tokens -----------------
    // Additive to the legacy `font`/`spacing`/`control()`/`inverted()` below:
    // nothing here renames or reuses an existing key, so every surface still
    // consuming the legacy API keeps rendering identically until its own
    // retrofit task (M8b plan, Tasks 3-7) switches it over.

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

    // Live bar height, reported by Bar.qml's own content-derived
    // _cellHeight (a fixed literal here would drift the moment any bar cell
    // grows taller than the rest, per Bar.qml's own header comment). The 32
    // default only covers the brief window before the first Bar instance
    // binds it.
    property real barHeight: 32

    readonly property var font: ({
        family: "monospace",
        display: "monospace",
        baseSize: 13,
        caption: Math.round(13 * 0.833), bodySmall: Math.round(13 * 0.917),
        body: 13, subtitle: Math.round(13 * 1.083),
        title: Math.round(13 * 1.167), heading: Math.round(13 * 1.333)
    })

    readonly property var spacing: ({ scale: 1.0, xs: 2, sm: 4, md: 8, lg: 16 })

    // --- DESIGN.md §4 motion posture ---------------------------------------
    // State changes are instant or near-instant (no animated call site exists
    // for one today — nothing to tokenize until a surface actually needs the
    // 120-420ms eased transition DESIGN.md allows). The "breathing" opacity
    // pulse is the one documented alive idiom (charging, an active call);
    // PowerPanel.qml's charging pulse is its only call site today. The
    // screensaver's continuous frame effect (Screensaver.qml) is the other
    // named carve-out and isn't a QML Animation at all, so it has no token
    // here. Nothing moves geometry anywhere in the shell.
    readonly property var motion: ({
        pulseDuration: 900,
        pulseEasing: Easing.InOutQuad
    })

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

    // { bg: <foreground>, fg: <background> } — the cursor-row/accent-cell
    // inversion pair per DESIGN.md's "selection = inversion" rule.
    // `useAccent` (default false, preserving every existing call site's
    // behavior) swaps in the accent/onAccent pair for an urgent/accent-
    // carrying row instead of the plain foreground/background pair.
    function inverted(useAccent) {
        return Tokens.invertedPair(color, !!useAccent);
    }

    function control(state) {
        switch (state) {
        case "hover":
        case "focus":    return { fill: color.foreground, fillAlpha: 0.08, border: color.foreground, borderWidth: borderWidth, borderAlpha: 0.35 }
        case "selected": return { fill: color.accent,     fillAlpha: 0.18, border: color.accent,     borderWidth: borderWidth, borderAlpha: 0.9 }
        default:         return { fill: "transparent",    fillAlpha: 0.0,  border: "transparent",    borderWidth: 0,           borderAlpha: 0.0 }
        }
    }

    // --- DESIGN.md §1.1 four-state model, resolved against a color token -

    function _resolveColorToken(token) {
        if (typeof token === "string" && token.length > 0 && token[0] === "#")
            return token;
        var key = token || "foreground";
        return color[key] !== undefined ? color[key] : color.foreground;
    }

    // Raw alphas/width for a named state (`normal` / `hover-cursor` /
    // `selected` / `focus` / `pressed`), color-independent.
    function stateAppearance(state) {
        return Tokens.stateAppearance(state);
    }

    // Which named state applies given a control's current flags — see
    // `Tokens.resolveState` for the paint-priority rule.
    function resolveState(flags) {
        return Tokens.resolveState(flags);
    }

    // A named state resolved against a color token (a palette role or raw
    // hex), in the same { fill, fillAlpha, border, borderWidth, borderAlpha }
    // shape `control()` returns, for a drop-in swap once a surface retrofits.
    function stateStyle(state, colorToken) {
        var col = _resolveColorToken(colorToken);
        var appearance = Tokens.stateAppearance(state);
        return {
            fill: col, fillAlpha: appearance.fillAlpha,
            border: col, borderWidth: appearance.borderWidth, borderAlpha: appearance.borderAlpha
        };
    }

    // --- DESIGN.md §1.2 border specs --------------------------------------

    // `widths` may be a partial per-side override ({ top: 0 }, say, so a
    // menu row can drop its shared top edge); unset sides fall back to the
    // state/control's own uniform width.
    function borderSpec(colorToken, widths, defaultWidth, gradient) {
        return Tokens.borderSpec(_resolveColorToken(colorToken), widths, defaultWidth === undefined ? borderWidth : defaultWidth, gradient);
    }

    function uniformBorderSpec(colorToken, width) {
        return Tokens.uniformBorderSpec(_resolveColorToken(colorToken), width === undefined ? borderWidth : width);
    }

    function isUniformBorder(spec) {
        return Tokens.isUniformBorder(spec);
    }
}
