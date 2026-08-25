.pragma library

// Which bar widget opens which panel (M42 D4), the one place that mapping
// lives. Keys are Bar/layout.js's BUILTIN_WIDGETS names as a user writes
// them in bar.layout; values are PanelIpc's registry keys as shell.qml wires
// them. The two vocabularies differ where a widget and its panel were never
// named alike ("battery" opens "power", "clock" opens "calendar",
// "systemUpdate" registers lowercase), which is exactly why this is a table
// and not a lowercase() call.
//
// "microphone" is here because MicWidget's middle click opens the audio
// panel; it has none of its own. "activeWindow" is deliberately absent even
// though it opens AppMenuPanel: that panel drives the focused window's own
// menu rather than a shell surface, so a positional keybind landing on it
// would open something different on every window. Everything else left out
// (tray, bell, indicators, chevron, launcher, visualizer, keyboardLayout)
// opens no panel at all, and neither "custom:" modules nor "plugin:" entries
// are keyed here since panelAt() only ever looks at builtins.
var WIDGET_PANELS = {
    airpods: "airpods",
    audio: "audio",
    battery: "power",
    bluetooth: "bluetooth",
    clock: "calendar",
    display: "display",
    dualsense: "dualsense",
    github: "github",
    microphone: "audio",
    monitor: "monitor",
    network: "network",
    nowPlaying: "media",
    systemUpdate: "systemupdate",
    tailscale: "tailscale",
    usage: "usage",
    weather: "weather"
};

// The nth panel-bearing cell of the resolved right region, 1-based, in
// layout order (leftmost first, which for a right-anchored region is the
// spec's "from the screen centre outward"). `resolved` is Bar/layout.js's
// resolve() result whole. Cells that open no panel are skipped rather than
// counted, and a cell hidden behind a collapsed chevron still counts: the
// keybind addresses the layout the user configured, not what is on screen
// this second. Out of range (including n < 1) is "".
function panelAt(resolved, n) {
    var entries = (resolved && resolved.regions && Array.isArray(resolved.regions.right)) ? resolved.regions.right : [];
    var seen = 0;
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.kind !== "builtin")
            continue;
        var panel = WIDGET_PANELS[entry.name];
        if (!panel)
            continue;
        seen++;
        if (seen === n)
            return panel;
    }
    return "";
}
