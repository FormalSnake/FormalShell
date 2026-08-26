import QtQuick
import QtTest
import "../shell/Bar/launchericon.js" as LauncherIcon

// `bar.launcherIcon`: the launcher cell's mark. A grammar rather than an
// enum, so what matters is that each shape resolves to the right KIND (a
// glyph the icon set draws, or an image the caller points an Image at) and
// that every fallback lands on something drawable rather than on a
// missing-texture box.
TestCase {
    name: "LauncherIcon"

    readonly property var nixos: ({ ID: "nixos", LOGO: "nix-snowflake" })
    function themeHit(name) { return "/usr/share/icons/hicolor/48x48/apps/" + name + ".png"; }
    function themeMiss(name) { return ""; }

    function test_the_default_is_the_shells_own_mark() {
        compare(LauncherIcon.resolve("", {}, themeMiss).value, "command");
        compare(LauncherIcon.resolve("", {}, themeMiss).kind, "icon");
        compare(LauncherIcon.resolve("command", {}, themeMiss).value, "command");
    }

    // Named separately from "command" so the day a real FormalShell mark
    // exists there is one place to change, not a search for every caller
    // that happened to spell it "command".
    function test_formalshell_is_the_shells_mark_today() {
        compare(LauncherIcon.resolve("formalshell", {}, themeMiss).value, "command");
    }

    function test_a_bare_name_is_an_icon_name() {
        var spec = LauncherIcon.resolve("snowflake", {}, themeMiss);
        compare(spec.kind, "icon");
        compare(spec.value, "snowflake");
    }

    function test_a_path_is_an_image() {
        ["/opt/mark.svg", "~/.config/mark.png", "file:///opt/mark.svg"].forEach(function (p) {
            var spec = LauncherIcon.resolve(p, {}, themeMiss);
            compare(spec.kind, "image", p + " should be an image");
            compare(spec.value, p);
        });
    }

    // LOGO is what the freedesktop spec provides for exactly this, and it is
    // preferred over ID because a distro that ships an icon names it there.
    function test_distro_prefers_the_logo_key() {
        var spec = LauncherIcon.resolve("distro", nixos, themeHit);
        compare(spec.kind, "image");
        verify(spec.value.indexOf("nix-snowflake") >= 0);
    }

    function test_distro_falls_back_to_id_when_there_is_no_logo() {
        var spec = LauncherIcon.resolve("distro", { ID: "debian" }, themeHit);
        compare(spec.kind, "image");
        verify(spec.value.indexOf("debian") >= 0);
    }

    // The common NixOS case: no nixos-icons installed, so the icon theme
    // resolves nothing. The mark has to come from the icon set instead of
    // rendering an empty box.
    function test_distro_falls_back_to_the_icon_set_when_the_theme_has_nothing() {
        var spec = LauncherIcon.resolve("distro", nixos, themeMiss);
        compare(spec.kind, "icon");
        compare(spec.value, "snowflake");
    }

    // A distro with neither a theme icon nor a glyph of its own still draws
    // the shell's mark rather than nothing.
    function test_an_unknown_distro_falls_all_the_way_back() {
        var spec = LauncherIcon.resolve("distro", { ID: "temple" }, themeMiss);
        compare(spec.kind, "icon");
        compare(spec.value, "command");
    }

    function test_distro_with_no_os_release_at_all() {
        var spec = LauncherIcon.resolve("distro", {}, themeMiss);
        compare(spec.kind, "icon");
        compare(spec.value, "command");
    }

    function test_os_release_parsing() {
        var os = LauncherIcon.parseOsRelease(
            '# a comment\n'
            + 'NAME="NixOS"\n'
            + 'ID=nixos\n'
            + "PRETTY_NAME='NixOS 26.11'\n"
            + 'LOGO=nix-snowflake\n'
            + '\n'
            + 'MALFORMED\n');
        compare(os.ID, "nixos");
        compare(os.NAME, "NixOS");
        compare(os.PRETTY_NAME, "NixOS 26.11");
        compare(os.LOGO, "nix-snowflake");
        compare(os.MALFORMED, undefined);
    }

    function test_os_release_of_nothing_is_not_a_crash() {
        compare(LauncherIcon.distroIconName(LauncherIcon.parseOsRelease("")), "");
        compare(LauncherIcon.distroIconName(null), "");
    }
}
