.pragma library

// Which GTK theme name _syncSystemScheme() writes to
// /org/gnome/desktop/interface/gtk-theme for a given mode. An empty
// settings.json value (unset key, or explicitly "") falls back to the
// adw-gtk3 pair every install ships with, so a NixOS module that generates
// its own theme pair only has to set gtk.theme/gtk.themeDark once the
// package is actually on the system.
function gtkThemeName(dark, lightName, darkName) {
    if (dark)
        return darkName || "adw-gtk3-dark";
    return lightName || "adw-gtk3";
}
