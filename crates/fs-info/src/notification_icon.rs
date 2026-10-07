//! Which picture a notification card shows. Pure: every lookup that needs the
//! desktop (a themed icon name, a desktop entry) is injected.
//!
//! The order, first hit wins:
//!
//!   1. `image`, the `image-data`/`image-path` hint. The server resolved it
//!      already, leaving an `image://`, a `file:` url or "".
//!   2. `app_icon`, which the server does not resolve: an absolute path, a url
//!      or a themed name.
//!   3. the sender's desktop entry: the `desktop-entry` hint first, then a
//!      heuristic match on `app_name` for senders that supply neither hint.
//!      Its icon is a path or a themed name, same branching as 2.
//!   4. nothing, and the card draws its own bell.

const ICON_URL_PREFIX: &str = "image://icon/";

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct IconSource {
    pub image: String,
    pub app_icon: String,
    pub desktop_entry: String,
    pub app_name: String,
}

fn is_url(value: &str) -> bool {
    value.starts_with("file:") || value.starts_with("image:")
}

/// A name that may be an absolute path, an already-built url or a themed icon
/// name. `themed` answers "" for a name the icon theme does not carry, so a
/// missing icon never becomes the provider's magenta missing-texture pixmap,
/// which renders as a healthy image.
fn resolve_name(value: &str, themed: &impl Fn(&str) -> String) -> String {
    if value.is_empty() {
        String::new()
    } else if is_url(value) {
        value.to_string()
    } else if value.starts_with('/') {
        format!("file://{value}")
    } else {
        themed(value)
    }
}

/// The server hands every `image-path` hint that is not already a file url to
/// the icon provider verbatim, so a path and a themed name both arrive as
/// `image://icon/<whatever was sent>`. Unwrap those and resolve them
/// properly; every other url shape is taken as given, including one carrying
/// the provider's own query.
fn checked_image(value: &str, themed: &impl Fn(&str) -> String) -> String {
    match value.strip_prefix(ICON_URL_PREFIX) {
        Some(rest) if !value.contains('?') => resolve_name(rest, themed),
        _ => value.to_string(),
    }
}

/// `themed(name)` is a usable source or ""; `entry_lookup(desktop_id,
/// app_name)` is the sender's desktop entry icon, or `None` for no entry.
pub fn resolve(
    entry: &IconSource,
    themed: impl Fn(&str) -> String,
    entry_lookup: impl Fn(&str, &str) -> Option<String>,
) -> String {
    let image = checked_image(&entry.image, &themed);
    if !image.is_empty() {
        return image;
    }

    let app_icon = resolve_name(&entry.app_icon, &themed);
    if !app_icon.is_empty() {
        return app_icon;
    }

    match entry_lookup(&entry.desktop_entry, &entry.app_name) {
        Some(icon) => resolve_name(&icon, &themed),
        None => String::new(),
    }
}
