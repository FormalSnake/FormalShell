import QtQuick
import QtTest
import "../shell/Network/wifiqr.js" as WifiQr

TestCase {
    name: "WifiQr"

    // escapeValue

    function test_escape_backslash_is_doubled() {
        compare(WifiQr.escapeValue("a\\b"), "a\\\\b");
    }

    function test_escape_semicolon() {
        compare(WifiQr.escapeValue("a;b"), "a\\;b");
    }

    function test_escape_comma() {
        compare(WifiQr.escapeValue("a,b"), "a\\,b");
    }

    function test_escape_colon() {
        compare(WifiQr.escapeValue("a:b"), "a\\:b");
    }

    // Backslash first, or each escape added afterwards would itself be
    // re-escaped by the backslash pass.
    function test_escape_applies_backslash_before_the_others() {
        compare(WifiQr.escapeValue("\\;"), "\\\\\\;");
    }

    function test_escape_leaves_ordinary_text_untouched() {
        compare(WifiQr.escapeValue("FORMALTEST"), "FORMALTEST");
    }

    function test_escape_empty_and_missing_value() {
        compare(WifiQr.escapeValue(""), "");
        compare(WifiQr.escapeValue(undefined), "");
        compare(WifiQr.escapeValue(null), "");
    }

    // buildPayload — security branches

    function test_payload_wpa_branch() {
        var r = WifiQr.buildPayload({ ssid: "FORMALTEST", keyMgmt: "wpa-psk", password: "formaltest-psk" });
        compare(r.ok, true);
        compare(r.payload, "WIFI:T:WPA;S:FORMALTEST;P:formaltest-psk;;");
    }

    function test_payload_nopass_branch_for_key_mgmt_none() {
        var r = WifiQr.buildPayload({ ssid: "GUEST", keyMgmt: "none" });
        compare(r.ok, true);
        compare(r.payload, "WIFI:T:nopass;S:GUEST;P:;;");
    }

    function test_payload_nopass_branch_for_absent_key_mgmt() {
        var r = WifiQr.buildPayload({ ssid: "GUEST" });
        compare(r.ok, true);
        compare(r.payload, "WIFI:T:nopass;S:GUEST;P:;;");
    }

    // An open network has no secret to share, so a psk that somehow came
    // back alongside key-mgmt "none" is dropped rather than published.
    function test_payload_nopass_never_echoes_a_stray_psk() {
        var r = WifiQr.buildPayload({ ssid: "GUEST", keyMgmt: "none", password: "leftover" });
        compare(r.payload, "WIFI:T:nopass;S:GUEST;P:;;");
    }

    // NetworkManager models WEP as key-mgmt "none" plus a wep-key0.
    function test_payload_wep_branch_from_wep_key_with_no_key_mgmt() {
        var r = WifiQr.buildPayload({ ssid: "OLDNET", keyMgmt: "none", wepKey: "abcde" });
        compare(r.ok, true);
        compare(r.payload, "WIFI:T:WEP;S:OLDNET;P:abcde;;");
    }

    function test_payload_wpa_wins_over_a_wep_key_when_key_mgmt_is_set() {
        var r = WifiQr.buildPayload({ ssid: "NET", keyMgmt: "wpa-psk", password: "pw", wepKey: "abcde" });
        compare(r.payload, "WIFI:T:WPA;S:NET;P:pw;;");
    }

    // buildPayload — hidden

    function test_payload_hidden_flag() {
        var r = WifiQr.buildPayload({ ssid: "NET", keyMgmt: "wpa-psk", password: "pw", hidden: "yes" });
        compare(r.payload, "WIFI:T:WPA;S:NET;P:pw;H:true;;");
    }

    function test_payload_hidden_no_omits_the_flag() {
        var r = WifiQr.buildPayload({ ssid: "NET", keyMgmt: "wpa-psk", password: "pw", hidden: "no" });
        compare(r.payload, "WIFI:T:WPA;S:NET;P:pw;;");
    }

    // buildPayload — escaping reaches both fields

    function test_payload_escapes_ssid_and_password() {
        var r = WifiQr.buildPayload({ ssid: "a;b,c:d\\e", keyMgmt: "wpa-psk", password: "p:q;r" });
        compare(r.payload, "WIFI:T:WPA;S:a\\;b\\,c\\:d\\\\e;P:p\\:q\\;r;;");
    }

    // buildPayload — refusals

    function test_payload_refuses_enterprise_wpa_eap() {
        var r = WifiQr.buildPayload({ ssid: "CORP", keyMgmt: "wpa-eap", password: "pw" });
        compare(r.ok, false);
        compare(r.error, "enterprise");
    }

    function test_payload_refuses_enterprise_ieee8021x() {
        var r = WifiQr.buildPayload({ ssid: "CORP", keyMgmt: "ieee8021x", password: "pw" });
        compare(r.ok, false);
        compare(r.error, "enterprise");
    }

    function test_payload_refuses_missing_ssid() {
        var r = WifiQr.buildPayload({ ssid: "", keyMgmt: "wpa-psk", password: "pw" });
        compare(r.ok, false);
        compare(r.error, "no_ssid");
    }

    function test_payload_refuses_secured_network_with_no_readable_psk() {
        var r = WifiQr.buildPayload({ ssid: "NET", keyMgmt: "wpa-psk", password: "" });
        compare(r.ok, false);
        compare(r.error, "no_password");
    }

    function test_payload_refuses_empty_fields() {
        var r = WifiQr.buildPayload({});
        compare(r.ok, false);
        compare(r.error, "no_ssid");
    }

    // parseFields

    function test_parse_fields_maps_the_five_nmcli_lines_in_order() {
        var f = WifiQr.parseFields("FORMALTEST\nwpa-psk\nformaltest-psk\nno\n\n");
        compare(f.ssid, "FORMALTEST");
        compare(f.keyMgmt, "wpa-psk");
        compare(f.password, "formaltest-psk");
        compare(f.hidden, "no");
        compare(f.wepKey, "");
    }

    // A short read must leave the missing fields empty, never shift the
    // remaining values up into the wrong slots.
    function test_parse_fields_short_read_leaves_later_fields_empty() {
        var f = WifiQr.parseFields("GUEST\nnone");
        compare(f.ssid, "GUEST");
        compare(f.keyMgmt, "none");
        compare(f.password, "");
        compare(f.hidden, "");
        compare(f.wepKey, "");
    }

    function test_parse_fields_empty_output() {
        var f = WifiQr.parseFields("");
        compare(f.ssid, "");
        compare(f.wepKey, "");
    }

    // parseMatrix

    function test_parse_matrix_collapses_two_characters_per_module() {
        var m = WifiQr.parseMatrix("##  ##\n  ##  \n######\n");
        compare(m.length, 3);
        compare(m[0], "101");
        compare(m[1], "010");
        compare(m[2], "111");
    }

    function test_parse_matrix_keeps_an_all_light_quiet_zone_row() {
        var m = WifiQr.parseMatrix("      \n##  ##\n      \n");
        compare(m.length, 3);
        compare(m[0], "000");
        compare(m[1], "101");
        compare(m[2], "000");
    }

    function test_parse_matrix_without_a_trailing_newline() {
        var m = WifiQr.parseMatrix("####\n  ##");
        compare(m.length, 2);
        compare(m[0], "11");
        compare(m[1], "01");
    }

    function test_parse_matrix_empty_input() {
        compare(WifiQr.parseMatrix("").length, 0);
        compare(WifiQr.parseMatrix(undefined).length, 0);
        compare(WifiQr.parseMatrix(null).length, 0);
    }

    function test_parse_matrix_odd_length_row_is_not_a_module_grid() {
        compare(WifiQr.parseMatrix("#####\n#####\n").length, 0);
    }

    function test_parse_matrix_non_square_is_rejected() {
        compare(WifiQr.parseMatrix("##  ##\n  ##  \n").length, 0);
    }

    function test_parse_matrix_ragged_rows_are_rejected() {
        compare(WifiQr.parseMatrix("##  ##\n  ##\n######\n").length, 0);
    }

    function test_parse_matrix_arbitrary_text_is_rejected() {
        compare(WifiQr.parseMatrix("qrencode: failed to encode\n").length, 0);
    }
}
