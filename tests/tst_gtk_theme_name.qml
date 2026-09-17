import QtQuick
import QtTest
import "../shell/Theme/gtk.js" as Gtk

TestCase {
    name: "GtkThemeName"

    // Empty settings.json values (unset gtk.theme/gtk.themeDark) must keep
    // today's dconf write byte for byte: adw-gtk3 light, adw-gtk3-dark dark.
    function test_defaults_on_empty_config() {
        compare(Gtk.gtkThemeName(false, "", ""), "adw-gtk3");
        compare(Gtk.gtkThemeName(true, "", ""), "adw-gtk3-dark");
    }

    function test_configured_names_win() {
        compare(Gtk.gtkThemeName(false, "elementary-matugen-light", "elementary-matugen-dark"),
            "elementary-matugen-light");
        compare(Gtk.gtkThemeName(true, "elementary-matugen-light", "elementary-matugen-dark"),
            "elementary-matugen-dark");
    }

    // A name set for one mode only still falls back to the default for the
    // other, rather than leaking the configured mode's name across.
    function test_falls_back_per_mode() {
        compare(Gtk.gtkThemeName(false, "elementary-matugen-light", ""), "elementary-matugen-light");
        compare(Gtk.gtkThemeName(true, "elementary-matugen-light", ""), "adw-gtk3-dark");
        compare(Gtk.gtkThemeName(true, "", "elementary-matugen-dark"), "elementary-matugen-dark");
        compare(Gtk.gtkThemeName(false, "", "elementary-matugen-dark"), "adw-gtk3");
    }
}
