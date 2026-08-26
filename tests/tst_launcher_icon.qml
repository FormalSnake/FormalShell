import QtQuick
import QtTest
import "../shell/Bar/launchericon.js" as LauncherIcon
import "../shell/Theme/icons/distro.js" as Distro

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
        compare(LauncherIcon.resolve("", {}, themeMiss, Distro.glyphOrTux).value, "command");
        compare(LauncherIcon.resolve("", {}, themeMiss, Distro.glyphOrTux).kind, "icon");
        compare(LauncherIcon.resolve("command", {}, themeMiss, Distro.glyphOrTux).value, "command");
    }

    // Named separately from "command" so the day a real FormalShell mark
    // exists there is one place to change, not a search for every caller
    // that happened to spell it "command".
    function test_formalshell_is_the_shells_mark_today() {
        compare(LauncherIcon.resolve("formalshell", {}, themeMiss, Distro.glyphOrTux).value, "command");
    }

    function test_a_bare_name_is_an_icon_name() {
        var spec = LauncherIcon.resolve("snowflake", {}, themeMiss, Distro.glyphOrTux);
        compare(spec.kind, "icon");
        compare(spec.value, "snowflake");
    }

    function test_a_path_is_an_image() {
        ["/opt/mark.svg", "~/.config/mark.png", "file:///opt/mark.svg"].forEach(function (p) {
            var spec = LauncherIcon.resolve(p, {}, themeMiss, Distro.glyphOrTux);
            compare(spec.kind, "image", p + " should be an image");
            compare(spec.value, p);
        });
    }

    // LOGO is what the freedesktop spec provides for exactly this, and it is
    // preferred over ID because a distro that ships an icon names it there.
    function test_distro_prefers_the_logo_key() {
        var spec = LauncherIcon.resolve("distro", nixos, themeHit, Distro.glyphOrTux);
        compare(spec.kind, "image");
        verify(spec.value.indexOf("nix-snowflake") >= 0);
    }

    function test_distro_falls_back_to_id_when_there_is_no_logo() {
        var spec = LauncherIcon.resolve("distro", { ID: "debian" }, themeHit, Distro.glyphOrTux);
        compare(spec.kind, "image");
        verify(spec.value.indexOf("debian") >= 0);
    }

    // The common NixOS case: no nixos-icons installed, so the icon theme
    // resolves nothing. The mark still has to be the REAL NixOS logo, which
    // is what the bundled font-logos table is for. It must never be Lucide's
    // generic weather snowflake, which is the bug the owner reported.
    function test_the_real_logo_is_used_when_the_theme_has_nothing() {
        var spec = LauncherIcon.resolve("distro", nixos, themeMiss, Distro.glyphOrTux);
        compare(spec.kind, "glyph");
        compare(spec.value, Distro.LOGOS["nixos"]);
        verify(spec.value !== "snowflake");
    }

    // An unrecognised Linux still gets a Linux mark rather than the shell's
    // own: asking for "distro" asked for a distro.
    function test_an_unknown_distro_still_gets_tux() {
        var spec = LauncherIcon.resolve("distro", { ID: "temple" }, themeMiss, Distro.glyphOrTux);
        compare(spec.kind, "glyph");
        compare(spec.value, Distro.FALLBACK);
    }

    function test_distro_with_no_os_release_at_all_is_the_shell_mark() {
        var spec = LauncherIcon.resolve("distro", {}, themeMiss, function () { return ""; });
        compare(spec.kind, "icon");
        compare(spec.value, "command");
    }

    // The table is generated from the font's own cmap, so what matters is
    // that the major IDs are present and distinct rather than that any one
    // codepoint is memorised.
    function test_the_logo_table_covers_the_major_distros() {
        ["nixos", "arch", "debian", "ubuntu", "fedora", "opensuse-tumbleweed",
         "gentoo", "alpine", "void", "manjaro", "endeavouros", "pop",
         "linuxmint", "kali", "rocky", "almalinux", "artix", "guix"].forEach(function (id) {
            var g = Distro.glyph(id);
            verify(g !== "", id + " has no logo");
            verify(g !== Distro.FALLBACK, id + " fell through to tux");
        });
        verify(Distro.glyph("nixos") !== Distro.glyph("arch"));
        compare(Distro.glyph("NixOS"), Distro.glyph("nixos"));
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
