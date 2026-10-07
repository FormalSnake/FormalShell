use fs_info::notification_icon::*;

const THEME_ICONS: [&str; 3] = ["firefox", "dialog-information", "signal-desktop"];

fn resolve_with(entry: &IconSource) -> String {
    resolve(
        entry,
        |name| {
            if THEME_ICONS.contains(&name) {
                format!("image://icon/{name}")
            } else {
                String::new()
            }
        },
        |desktop_id, app_name| {
            let lookup = |key: &str| match key {
                "org.signal.Signal" => Some("signal-desktop".to_string()),
                "Slack" => Some("/opt/slack/icon.png".to_string()),
                "unthemed" => Some("no-such-icon".to_string()),
                _ => None,
            };
            lookup(desktop_id).or_else(|| lookup(app_name))
        },
    )
}

fn notif(image: &str, app_icon: &str, desktop_entry: &str, app_name: &str) -> IconSource {
    IconSource {
        image: image.into(),
        app_icon: app_icon.into(),
        desktop_entry: desktop_entry.into(),
        app_name: app_name.into(),
    }
}

#[test]
fn the_notifications_own_image_wins() {
    let n = notif("image://qsimage/12", "firefox", "org.signal.Signal", "");
    assert_eq!(resolve_with(&n), "image://qsimage/12");
}

#[test]
fn the_app_icon_comes_next() {
    let n = notif("", "firefox", "org.signal.Signal", "");
    assert_eq!(resolve_with(&n), "image://icon/firefox");
}

#[test]
fn the_named_desktop_entry_comes_third() {
    let n = notif("", "", "org.signal.Signal", "");
    assert_eq!(resolve_with(&n), "image://icon/signal-desktop");
}

#[test]
fn the_sender_name_finds_an_entry_when_no_hint_did() {
    assert_eq!(
        resolve_with(&notif("", "", "", "Slack")),
        "file:///opt/slack/icon.png"
    );
}

#[test]
fn nothing_resolving_leaves_the_card_its_bell() {
    assert_eq!(resolve_with(&notif("", "", "", "Some Daemon")), "");
}

#[test]
fn an_absolute_path_becomes_a_file_url() {
    assert_eq!(
        resolve_with(&notif("", "/tmp/shot.png", "", "")),
        "file:///tmp/shot.png"
    );
}

#[test]
fn a_url_is_taken_as_given() {
    assert_eq!(
        resolve_with(&notif("", "file:///tmp/shot.png", "", "")),
        "file:///tmp/shot.png"
    );
    assert_eq!(
        resolve_with(&notif("", "image://icon/firefox", "", "")),
        "image://icon/firefox"
    );
}

#[test]
fn an_unresolvable_app_icon_falls_through_to_the_entry() {
    let n = notif("", "no-such-icon", "org.signal.Signal", "");
    assert_eq!(resolve_with(&n), "image://icon/signal-desktop");
}

#[test]
fn an_entry_whose_own_icon_is_unthemed_resolves_to_nothing() {
    assert_eq!(resolve_with(&notif("", "", "unthemed", "")), "");
}

#[test]
fn an_image_path_hint_naming_a_missing_icon_is_dropped() {
    let n = notif("image://icon/no-such-icon", "firefox", "", "");
    assert_eq!(resolve_with(&n), "image://icon/firefox");
}

#[test]
fn an_image_path_hint_carrying_a_path_becomes_a_file_url() {
    let n = notif("image://icon//tmp/shot.png", "", "", "");
    assert_eq!(resolve_with(&n), "file:///tmp/shot.png");
}

#[test]
fn an_image_path_hint_naming_a_real_icon_is_kept() {
    let n = notif("image://icon/dialog-information", "", "", "");
    assert_eq!(resolve_with(&n), "image://icon/dialog-information");
}

#[test]
fn a_provider_url_with_a_query_is_left_alone() {
    let n = notif("image://icon/a?fallback=b", "", "", "");
    assert_eq!(resolve_with(&n), "image://icon/a?fallback=b");
}

#[test]
fn a_missing_entry_is_no_entry_at_all() {
    assert_eq!(resolve_with(&IconSource::default()), "");
}
