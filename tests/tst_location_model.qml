import QtQuick
import QtTest
import "../shell/Location/model.js" as Loc

TestCase {
    name: "LocationModel"

    function test_iwd_objects_give_every_bss_but_nomap() {
        var text = JSON.stringify({ type: "a{oa{sa{sv}}}", data: [{
            "/net/connman/iwd/0/3/aa_psk": { "net.connman.iwd.Network": { Name: { type: "s", data: "Home" } } },
            "/net/connman/iwd/0/3/aa_psk/2c9682fd9f57": { "net.connman.iwd.BasicServiceSet": { Address: { type: "s", data: "2C:96:82:FD:9F:57" } } },
            "/net/connman/iwd/0/3/bb_psk": { "net.connman.iwd.Network": { Name: { type: "s", data: "Cafe_nomap" } } },
            "/net/connman/iwd/0/3/bb_psk/111111111111": { "net.connman.iwd.BasicServiceSet": { Address: { type: "s", data: "11:11:11:11:11:11" } } }
        }] });
        compare(Loc.accessPointsFromIwd(text), [{ macAddress: "2c:96:82:fd:9f:57" }]);
        compare(Loc.accessPointsFromIwd("nope"), []);
    }

    function test_nmcli_unescapes_and_converts_signal() {
        var text = "2C\\:96\\:82\\:FD\\:9F\\:57:Home:70:5260 MHz\n11\\:11\\:11\\:11\\:11\\:11:Cafe_nomap:50:2412 MHz\n";
        compare(Loc.accessPointsFromNmcli(text), [{ macAddress: "2c:96:82:fd:9f:57", signalStrength: -65, frequency: 5260 }]);
    }

    function test_scan_head_picks_the_parser() {
        compare(Loc.accessPointsFromScan("nm\n2C\\:96\\:82\\:FD\\:9F\\:57:Home:70:5260 MHz").length, 1);
        compare(Loc.accessPointsFromScan("none\n"), []);
    }

    function test_parse_geolocate_tells_wifi_from_ip() {
        compare(Loc.parseGeolocate('{"location":{"lat":29.1,"lng":-13.5},"accuracy":30}'),
            { latitude: 29.1, longitude: -13.5, accuracy: 30, source: "wifi" });
        compare(Loc.parseGeolocate('{"location":{"lat":28.9,"lng":-13.5},"accuracy":25000,"fallback":"ipf"}').source, "ip");
        compare(Loc.parseGeolocate('{"error":{}}'), null);
    }

    function test_place_key_rounds_to_a_kilometre() {
        compare(Loc.placeKey(29.118083, -13.566583), "29.12,-13.57");
        compare(Loc.placeKey(NaN, 1), "");
        compare(Loc.reverseUrl("29.12,-13.57"),
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=en&lat=29.12&lon=-13.57");
    }

    function test_parse_place_joins_town_and_region() {
        compare(Loc.parsePlace('{"name":"Teguise","address":{"city":"Teguise","state":"Canary Islands"}}'), "Teguise, Canary Islands");
        compare(Loc.parsePlace('{"address":{"village":"Nazaret"}}'), "Nazaret");
        compare(Loc.parsePlace("nope"), "");
    }
}
