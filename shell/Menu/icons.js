.pragma library

// Route icons for the launcher (M43 D2). The menu tree carries its icons as
// raw glyph strings (default-menu.jsonc, providers.js), which `Icon` cannot
// render: it resolves a NAME through the active set. This maps the shipped
// route ids onto Lucide names, so a row drawn from data still gets a named
// icon in whichever set `theme.icons` selects.
//
// An id that is not here resolves to "", and MenuRow falls back to the
// node's own glyph in the mono font, which is what keeps a user-defined
// menu.jsonc route, an emoji row (its icon IS the emoji) and a provider row
// carrying its own glyph working unchanged.

var ROUTE_ICONS = {
    // Root routes (default-menu.jsonc).
    "apps": "layout-grid",
    "clipboard": "clipboard",
    "calc": "calculator",
    "emoji": "smile",
    "nix": "snowflake",
    "keybinds": "keyboard",
    "wallpaper": "image",
    "monitor": "cpu",
    "panels": "grid-2x2",
    "tray": "inbox",
    "gpu": "gpu",

    "system": "settings",
    "system.lock": "lock",
    "system.suspend": "moon",
    "system.reboot": "refresh-cw",
    "system.shutdown": "power",
    "system.logout": "log-out",
    "system.notifications": "bell",

    "reminder": "alarm-clock",
    "reminder.set": "timer",
    "reminder.show": "clock",
    "reminder.clear": "x",

    "share": "share-2",
    "share.clipboard": "clipboard",
    "share.history": "history",
    "share.receive": "download",

    "clipssh": "terminal",

    "toggles": "toggle-left",
    "toggles.nightlight": "lightbulb",
    "toggles.stay-awake": "coffee",
    "toggles.dnd": "bell-off",
    "toggles.dark-mode": "moon",

    // Injected at tree-build time (providers.js's captureEntries).
    "capture": "camera",
    "capture.text": "scan-text",
    "capture.color": "pipette",
    "capture.record": "video",
    "capture.stop": "square",
    "capture.gif": "film",
    "capture.screenshot": "camera",
    "capture.region": "crop",
    "system.console": "terminal",
    "system.screensaver": "monitor-off",
    "system.plugins": "puzzle",
    "system.plugins.list": "list",
    "system.plugins.reload": "refresh-cw",
    "notifications": "bell",
    "notifications.clear": "trash",
    "notifications.markAllSeen": "check-check",
    "notifications.dismissAll": "x",
    "theme": "palette",
    "theme.retheme": "palette",
    "theme.mode-dark": "moon",
    "theme.mode-light": "sun",

    // supergfxctl switching (providers.js's gpuModeEntry).
    "gpu.mode": "arrow-left-right",
    "gpu.mode.integrated": "laptop",
    "gpu.mode.hybrid": "git-fork",

    // One row per name in shell.qml's PanelIpc registry
    // (providers.js's PANEL_ROWS).
    "panels.appmenu": "layout-grid",
    "panels.audio": "volume-2",
    "panels.calendar": "calendar",
    "panels.network": "wifi",
    "panels.bluetooth": "bluetooth",
    "panels.airpods": "headphones",
    "panels.dualsense": "gamepad-2",
    "panels.power": "battery",
    "panels.weather": "sun",
    "panels.media": "music",
    "panels.github": "git-branch",
    "panels.usage": "bot",
    "panels.tailscale": "network",
    "panels.systemupdate": "package",
    "panels.display": "monitor",
    "panels.monitor": "gauge"
};

// "" means "this row has no named icon": the caller draws the node's own
// glyph instead.
function iconFor(node) {
    if (!node || !node.id)
        return "";
    return ROUTE_ICONS[node.id] || "";
}
