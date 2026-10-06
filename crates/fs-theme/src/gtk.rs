//! Which GTK theme name the shell writes to
//! `/org/gnome/desktop/interface/gtk-theme` for a given mode. An empty
//! settings.json value (unset key, or explicitly "") falls back to the
//! adw-gtk3 pair every install ships with, so a NixOS module that generates
//! its own theme pair only has to set `gtk.theme`/`gtk.themeDark` once the
//! package is actually on the system.

pub fn gtk_theme_name(dark: bool, light_name: &str, dark_name: &str) -> String {
    let (name, default) = if dark {
        (dark_name, "adw-gtk3-dark")
    } else {
        (light_name, "adw-gtk3")
    };
    if name.is_empty() { default } else { name }.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Empty settings.json values (unset gtk.theme/gtk.themeDark) must keep
    /// today's dconf write byte for byte: adw-gtk3 light, adw-gtk3-dark dark.
    #[test]
    fn defaults_on_empty_config() {
        assert_eq!(gtk_theme_name(false, "", ""), "adw-gtk3");
        assert_eq!(gtk_theme_name(true, "", ""), "adw-gtk3-dark");
    }

    #[test]
    fn configured_names_win() {
        assert_eq!(
            gtk_theme_name(false, "elementary-matugen-light", "elementary-matugen-dark"),
            "elementary-matugen-light"
        );
        assert_eq!(
            gtk_theme_name(true, "elementary-matugen-light", "elementary-matugen-dark"),
            "elementary-matugen-dark"
        );
    }

    /// A name set for one mode only still falls back to the default for the
    /// other, rather than leaking the configured mode's name across.
    #[test]
    fn falls_back_per_mode() {
        assert_eq!(
            gtk_theme_name(false, "elementary-matugen-light", ""),
            "elementary-matugen-light"
        );
        assert_eq!(
            gtk_theme_name(true, "elementary-matugen-light", ""),
            "adw-gtk3-dark"
        );
        assert_eq!(
            gtk_theme_name(true, "", "elementary-matugen-dark"),
            "elementary-matugen-dark"
        );
        assert_eq!(
            gtk_theme_name(false, "", "elementary-matugen-dark"),
            "adw-gtk3"
        );
    }
}
