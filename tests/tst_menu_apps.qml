import QtQuick
import QtTest
import "../shell/Menu/providers.js" as Providers

// The apps provider's row shape (M13b Task 1): labels are always the
// entry's display name (id only when the name is genuinely empty), the
// icon-theme name never leaks into the text `icon` slot, and `iconSource`
// carries the resolver's answer verbatim — "" on a failed lookup. The
// resolver is injected (Menu.qml passes Quickshell.iconPath with
// check=true); tests pass a stub so the shape stays covered headlessly.
TestCase {
    name: "MenuApps"

    function stubEntry(id, name, icon) {
        return { id: id, name: name, icon: icon, genericName: "" };
    }

    function resolver(name) {
        return name === "resolvable" ? "image://icon/resolvable" : "";
    }

    function test_label_is_display_name_never_id() {
        var rows = Providers.appsProvider([stubEntry("firefox", "Firefox Web Browser", "firefox")], resolver);
        compare(rows.length, 1);
        compare(rows[0].id, "apps.firefox");
        compare(rows[0].label, "Firefox Web Browser");
        compare(rows[0].kind, "app");
    }

    function test_label_falls_back_to_id_only_when_name_empty() {
        var rows = Providers.appsProvider([stubEntry("bare-id", "", "")], resolver);
        compare(rows[0].label, "bare-id");
    }

    function test_icon_theme_name_never_rendered_as_text() {
        var rows = Providers.appsProvider([stubEntry("mpv", "mpv Media Player", "mpv")], resolver);
        compare(rows[0].icon, "");
    }

    function test_icon_source_resolved_through_injected_lookup() {
        var rows = Providers.appsProvider([
            stubEntry("a", "App A", "resolvable"),
            stubEntry("b", "App B", "no-such-icon"),
            stubEntry("c", "App C", "")
        ], resolver);
        compare(rows[0].iconSource, "image://icon/resolvable");
        compare(rows[1].iconSource, "");
        compare(rows[2].iconSource, "");
    }

    function test_no_resolver_degrades_to_empty_icon_source() {
        var rows = Providers.appsProvider([stubEntry("a", "App A", "resolvable")]);
        compare(rows[0].iconSource, "");
    }
}
