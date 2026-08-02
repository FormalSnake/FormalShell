import QtQuick
import QtTest
import "../shell/Network/model.js" as NetworkModel

TestCase {
    name: "NetworkModel"

    function row(name, connected, known, signalStrength) {
        return { name: name, connected: connected, known: known, signalStrength: signalStrength };
    }

    function names(rows) {
        return rows.map(function (r) { return r.name; }).join(",");
    }

    function test_sortWifiRows_connected_then_known_then_signal_desc() {
        var sorted = NetworkModel.sortWifiRows([
            row("A", false, true, 0.5),
            row("B", true, true, 0.2),
            row("C", false, false, 0.9),
            row("D", false, true, 0.8)
        ]);
        compare(names(sorted), "B,D,A,C");
    }

    function test_sortWifiRows_does_not_mutate_input() {
        var input = [row("A", false, true, 0.1), row("B", true, true, 0.9)];
        var before = JSON.stringify(input);
        NetworkModel.sortWifiRows(input);
        compare(JSON.stringify(input), before);
    }

    function test_sectionOf_known_vs_available() {
        compare(NetworkModel.sectionOf(row("A", false, true, 0.5)), "KNOWN");
        compare(NetworkModel.sectionOf(row("A", false, false, 0.5)), "AVAILABLE");
    }

    function test_failureText_mappings() {
        compare(NetworkModel.failureText(NetworkModel.ConnectionFailReason.NoSecrets), "PASSPHRASE REQUIRED");
        compare(NetworkModel.failureText(NetworkModel.ConnectionFailReason.WifiAuthTimeout), "WRONG PASSWORD");
        compare(NetworkModel.failureText(NetworkModel.ConnectionFailReason.WifiNetworkLost), "NETWORK LOST");
        compare(NetworkModel.failureText(NetworkModel.ConnectionFailReason.WifiClientFailed), "CONNECTION FAILED");
        compare(NetworkModel.failureText(NetworkModel.ConnectionFailReason.Unknown), "CONNECTION FAILED");
    }

    function test_isSecured_open_and_owe_are_unsecured() {
        compare(NetworkModel.isSecured(NetworkModel.WifiSecurityType.Open), false);
        compare(NetworkModel.isSecured(NetworkModel.WifiSecurityType.Owe), false);
        compare(NetworkModel.isSecured(NetworkModel.WifiSecurityType.Wpa2Psk), true);
        compare(NetworkModel.isSecured(NetworkModel.WifiSecurityType.Sae), true);
    }

    function test_isEnterprise_only_eap_types() {
        compare(NetworkModel.isEnterprise(NetworkModel.WifiSecurityType.WpaEap), true);
        compare(NetworkModel.isEnterprise(NetworkModel.WifiSecurityType.Wpa2Eap), true);
        compare(NetworkModel.isEnterprise(NetworkModel.WifiSecurityType.Wpa2Psk), false);
        compare(NetworkModel.isEnterprise(NetworkModel.WifiSecurityType.Open), false);
    }

    function test_signalBar_full_and_empty() {
        compare(NetworkModel.signalBar(0), "░░░░░");
        compare(NetworkModel.signalBar(1), "█████");
    }

    function test_signalBar_rounds_to_nearest_segment() {
        compare(NetworkModel.signalBar(0.5), "███░░");
        compare(NetworkModel.signalBar(0.2), "█░░░░");
    }

    function test_signalBar_clamps_out_of_range() {
        compare(NetworkModel.signalBar(-1), "░░░░░");
        compare(NetworkModel.signalBar(2), "█████");
    }
}
