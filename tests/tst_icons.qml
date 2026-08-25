import QtQuick
import QtTest
import "../shell/Theme/icons.js" as Icons

// M41 Task 2 (spec "Icons", D2): shell/Theme/icons.js's glyph()/family()
// against both tables. Every name here is one this milestone's surfaces
// need; M42+ tasks append more as they're ported.
TestCase {
    name: "Icons"

    readonly property var names: [
        "wifi", "wifi-off", "bluetooth", "bluetooth-connected",
        "bluetooth-off", "volume",
        "volume-1", "volume-2", "volume-x", "mic", "mic-off", "battery",
        "battery-charging", "battery-full", "battery-low", "battery-medium",
        "battery-warning", "sun", "moon",
        "bell", "bell-off", "clock", "calendar", "search", "command", "x",
        "check", "lock", "lock-open", "refresh-cw", "settings", "power",
        "monitor", "cpu", "memory-stick", "hard-drive", "thermometer",
        "activity", "download", "upload", "arrow-up", "arrow-down",
        "arrow-left", "arrow-right", "chevron-up", "chevron-down",
        "chevron-left", "chevron-right", "circle-help", "circle-alert",
        "triangle-alert", "info", "play", "pause", "skip-back",
        "skip-forward", "shuffle", "repeat", "repeat-1", "music",
        "image", "camera", "video",
        "clipboard", "keyboard", "terminal", "git-branch", "package",
        "package-plus", "gauge", "network", "cloud",
        "cloudy", "cloud-fog", "cloud-drizzle", "cloud-rain",
        "cloud-rain-wind", "cloud-hail", "cloud-snow", "cloud-lightning",
        "cloud-sun", "cloud-moon", "monitor-off",
        "zap", "plus", "minus", "trash",
        "pencil", "external-link", "ellipsis", "menu", "grid-2x2", "list",
        "star", "heart", "globe", "map-pin", "user", "users", "home",
        "folder", "file", "save", "copy", "share-2", "send", "mail",
        "message-square", "phone", "headphones", "gamepad-2", "printer",
        "usb", "plug", "plug-zap", "fingerprint"
    ]

    // "circle-help" is its own fallback, and "plug-zap" is nerd.js's one
    // deliberate fallback (no MDI glyph exists for a charging/live plug) so
    // both are excluded from the "resolved to something real" assertion
    // against the nerd set specifically.
    readonly property var nerdFallbackNames: ["circle-help", "plug-zap"]

    function test_every_name_resolves_in_lucide() {
        var fallback = Icons.glyph("lucide", "circle-help");
        for (var i = 0; i < names.length; i++) {
            var name = names[i];
            if (name === "circle-help") continue;
            verify(Icons.glyph("lucide", name) !== fallback, name + " fell back in lucide");
        }
    }

    function test_every_name_resolves_in_nerd_except_the_declared_fallback() {
        var fallback = Icons.glyph("nerd", "circle-help");
        for (var i = 0; i < names.length; i++) {
            var name = names[i];
            if (nerdFallbackNames.indexOf(name) !== -1) continue;
            verify(Icons.glyph("nerd", name) !== fallback, name + " fell back in nerd");
        }
    }

    function test_plug_zap_is_the_declared_nerd_fallback() {
        compare(Icons.glyph("nerd", "plug-zap"), Icons.glyph("nerd", "circle-help"));
    }

    function test_unknown_name_yields_circle_help_in_every_set() {
        compare(Icons.glyph("lucide", "not-a-real-icon"), Icons.glyph("lucide", "circle-help"));
        compare(Icons.glyph("nerd", "not-a-real-icon"), Icons.glyph("nerd", "circle-help"));
    }

    function test_family_nerd_is_empty_and_lucide_is_named() {
        compare(Icons.family("nerd"), "");
        verify(Icons.family("lucide").length > 0);
    }

    function test_unknown_set_falls_back_to_lucide() {
        compare(Icons.glyph("bogus-set", "wifi"), Icons.glyph("lucide", "wifi"));
        compare(Icons.family("bogus-set"), Icons.family("lucide"));
    }
}
