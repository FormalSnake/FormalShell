//! The iPhone mirror against the notification model: the replace path, the
//! quiet and DND tiers and the source-keyed grouping, with fs-info's reducer
//! standing where `NotificationService.qml` runs `Model.add`.

use fs_devices::iphone::{
    CentreEntry, DedupeRule, Event, Notification, PhoneFields, dedupe_rules, default_dedupe,
    parse_event, superseded, to_notification,
};
use fs_info::notifications as nm;
use serde_json::{Value, json};

const LINE_SMS: &str = r#"{"type": "notification", "id": 4012, "appId": "com.apple.MobileSMS", "appName": "Messages", "title": "Alex", "subtitle": "", "body": "Still on for Friday?", "deviceName": "Kyan's iPhone", "deviceHandle": "/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6", "positiveAction": null, "negativeAction": "Clear", "category": 4, "categoryCount": 2, "silent": false, "important": false, "preexisting": false, "session": 77, "ts": 1790000000.0}"#;
const LINE_CALL: &str = r#"{"type": "notification", "id": 4013, "appId": "com.apple.mobilephone", "appName": "Phone", "title": "Mum", "subtitle": "", "body": "mobile", "deviceName": "Kyan's iPhone", "deviceHandle": "/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6", "positiveAction": "Answer", "negativeAction": "Decline", "category": 1, "categoryCount": 1, "silent": false, "important": true, "preexisting": false, "session": 77, "ts": 1790000001.0}"#;

fn rules() -> Vec<DedupeRule> {
    dedupe_rules(&default_dedupe())
}

fn parse_notification(line: &str) -> Notification {
    match parse_event(line) {
        Some(Event::Notification(n)) => n,
        other => panic!("not a notification: {other:?}"),
    }
}

fn phone() -> Notification {
    parse_notification(LINE_SMS)
}

/// A local desktop client's notification, as the server layer hands `add`.
fn local(id: &str, summary: &str, body: &str) -> nm::Notif {
    nm::Notif {
        id: id.into(),
        app_name: "Messages".into(),
        summary: summary.into(),
        body: body.into(),
        urgency: nm::Urgency::Normal,
        ..nm::Notif::default()
    }
}

/// The notification for a phone arrival, as `notifyPhone` injects it.
fn phone_notif(record: &Notification) -> nm::Notif {
    let m = to_notification(record);
    nm::Notif {
        id: format!("iphone-{}-{}", record.session, record.id),
        app_name: m.app_name,
        summary: m.summary,
        body: m.body,
        urgency: nm::Urgency::try_from(m.urgency).unwrap(),
        actions: m
            .actions
            .iter()
            .map(|a| nm::Action {
                key: a.key.into(),
                label: a.label.clone(),
            })
            .collect(),
        source: "iphone".into(),
        phone: Some(json!({
            "id": m.phone.id,
            "session": record.session,
            "bundleId": m.phone.bundle_id,
            "title": m.phone.title,
            "subtitle": m.phone.subtitle,
            "body": m.phone.body,
        })),
        ..nm::Notif::default()
    }
}

fn phone_str(phone: &Value, key: &str) -> String {
    phone[key].as_str().unwrap_or_default().to_string()
}

fn centre_entry(entry: &nm::Entry) -> CentreEntry {
    CentreEntry {
        id: entry.id.clone(),
        app_name: entry.app_name.clone(),
        desktop_entry: entry.desktop_entry.clone(),
        summary: entry.summary.clone(),
        body: entry.body.clone(),
        source: entry.source.clone(),
        local: entry.local,
        phone: entry.phone.as_ref().map(|p| PhoneFields {
            bundle_id: phone_str(p, "bundleId"),
            title: phone_str(p, "title"),
            subtitle: phone_str(p, "subtitle"),
            body: phone_str(p, "body"),
        }),
        arrived_at: entry.arrived_at as f64,
    }
}

fn all_entries(state: &nm::State) -> Vec<CentreEntry> {
    state
        .popups
        .iter()
        .chain(&state.pending)
        .chain(&state.past)
        .map(centre_entry)
        .collect()
}

fn add(state: &nm::State, notif: &nm::Notif, now: i64) -> nm::State {
    nm::add(state, notif, now, &nm::AddOpts::default())
}

fn add_quiet(state: &nm::State, notif: &nm::Notif, now: i64) -> nm::State {
    nm::add(
        state,
        notif,
        now,
        &nm::AddOpts {
            quiet: true,
            ..nm::AddOpts::default()
        },
    )
}

fn entry_of(notif: &nm::Notif, arrived_at: i64) -> nm::Entry {
    let s = add(&nm::State::new(), notif, arrived_at);
    s.popups[0].clone()
}

// The replace path end to end through the notification reducer: a phone card
// on screen, then the desktop client raising the same message, leaves one
// card, the local one.
#[test]
fn local_arrival_replaces_phone_card() {
    let now = 100000;
    let mut s = nm::State::new();
    s = add(&s, &phone_notif(&phone()), now);
    s = add(&s, &local("9", "Alex", "Still on for Friday?"), now + 3000);
    assert_eq!(s.popups.len(), 2);
    let incoming = centre_entry(s.popups.iter().find(|p| p.id == "9").unwrap());
    let stale = superseded(&rules(), &incoming, &all_entries(&s), (now + 3000) as f64);
    assert_eq!(stale, vec!["iphone-77-4012".to_string()]);
    s = nm::dismiss_many(&s, &stale);
    assert_eq!(s.popups.len(), 1);
    assert_eq!(s.popups[0].id, "9");
    assert_eq!(s.pending.len() + s.past.len(), 0);
}

#[test]
fn local_arrival_replaces_quiet_phone_entry_in_history() {
    let now = 100000;
    let record = Notification {
        silent: true,
        ..phone()
    };
    let mut s = add_quiet(&nm::State::new(), &phone_notif(&record), now);
    assert_eq!(s.popups.len(), 0);
    assert_eq!(s.pending.len(), 1);
    let incoming = centre_entry(&entry_of(
        &local("9", "Alex", "Still on for Friday?"),
        now + 1000,
    ));
    let stale = superseded(&rules(), &incoming, &all_entries(&s), (now + 1000) as f64);
    assert_eq!(stale.len(), 1);
    s = nm::dismiss_many(&s, &stale);
    assert_eq!(s.pending.len(), 0);
}

#[test]
fn quiet_add_goes_to_pending_without_dnd() {
    let s = add_quiet(&nm::State::new(), &phone_notif(&phone()), 1000);
    assert_eq!(s.popups.len(), 0);
    assert_eq!(s.pending.len(), 1);
    assert_eq!(s.pending[0].source, "iphone");
    assert_eq!(s.pending[0].phone.as_ref().unwrap()["id"], 4012);
}

#[test]
fn phone_and_local_cards_never_group() {
    let a = entry_of(&phone_notif(&phone()), 1000);
    let b = entry_of(&local("9", "Alex", "different"), 1000);
    assert_ne!(nm::group_key(&a), nm::group_key(&b));
    assert_eq!(nm::group_entries(&[a, b]).len(), 2);
}

#[test]
fn critical_phone_entry_still_waits_behind_dnd() {
    let call = parse_notification(LINE_CALL);
    let s = nm::set_dnd(&nm::State::new(), true);
    let s = add(&s, &phone_notif(&call), 1000);
    assert_eq!(s.popups.len(), 0);
    assert_eq!(s.pending.len(), 1);
}
