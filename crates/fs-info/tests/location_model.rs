use fs_info::location::*;
use serde_json::json;

fn ap(mac: &str) -> AccessPoint {
    AccessPoint { mac_address: mac.into(), signal_strength: None, frequency: None }
}

#[test]
fn iwd_objects_give_every_bss_but_nomap() {
    let text = json!({ "type": "a{oa{sa{sv}}}", "data": [{
        "/net/connman/iwd/0/3/aa_psk": { "net.connman.iwd.Network": { "Name": { "type": "s", "data": "Home" } } },
        "/net/connman/iwd/0/3/aa_psk/2c9682fd9f57": { "net.connman.iwd.BasicServiceSet": { "Address": { "type": "s", "data": "2C:96:82:FD:9F:57" } } },
        "/net/connman/iwd/0/3/bb_psk": { "net.connman.iwd.Network": { "Name": { "type": "s", "data": "Cafe_nomap" } } },
        "/net/connman/iwd/0/3/bb_psk/111111111111": { "net.connman.iwd.BasicServiceSet": { "Address": { "type": "s", "data": "11:11:11:11:11:11" } } }
    }] })
    .to_string();
    assert_eq!(access_points_from_iwd(&text), vec![ap("2c:96:82:fd:9f:57")]);
    assert_eq!(access_points_from_iwd("nope"), vec![]);
}

#[test]
fn nmcli_unescapes_and_converts_signal() {
    let text = "2C\\:96\\:82\\:FD\\:9F\\:57:Home:70:5260 MHz\n11\\:11\\:11\\:11\\:11\\:11:Cafe_nomap:50:2412 MHz\n";
    assert_eq!(
        access_points_from_nmcli(text),
        vec![AccessPoint {
            mac_address: "2c:96:82:fd:9f:57".into(),
            signal_strength: Some(-65),
            frequency: Some(5260),
        }]
    );
}

#[test]
fn scan_head_picks_the_parser() {
    assert_eq!(
        access_points_from_scan("nm\n2C\\:96\\:82\\:FD\\:9F\\:57:Home:70:5260 MHz").len(),
        1
    );
    assert_eq!(access_points_from_scan("none\n"), vec![]);
}

#[test]
fn parse_geolocate_tells_wifi_from_ip() {
    assert_eq!(
        parse_geolocate(r#"{"location":{"lat":29.1,"lng":-13.5},"accuracy":30}"#),
        Some(Fix { latitude: 29.1, longitude: -13.5, accuracy: 30.0, source: Source::Wifi })
    );
    assert_eq!(
        parse_geolocate(r#"{"location":{"lat":28.9,"lng":-13.5},"accuracy":25000,"fallback":"ipf"}"#)
            .unwrap()
            .source
            .as_str(),
        "ip"
    );
    assert_eq!(parse_geolocate(r#"{"error":{}}"#), None);
}

#[test]
fn place_key_rounds_to_a_kilometre() {
    assert_eq!(place_key(29.118083, -13.566583), "29.12,-13.57");
    assert_eq!(place_key(f64::NAN, 1.0), "");
    assert_eq!(
        reverse_url("29.12,-13.57"),
        "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=en&lat=29.12&lon=-13.57"
    );
}

#[test]
fn parse_place_joins_town_and_region() {
    assert_eq!(
        parse_place(r#"{"name":"Teguise","address":{"city":"Teguise","state":"Canary Islands"}}"#),
        "Teguise, Canary Islands"
    );
    assert_eq!(parse_place(r#"{"address":{"village":"Nazaret"}}"#), "Nazaret");
    assert_eq!(parse_place("nope"), "");
}
