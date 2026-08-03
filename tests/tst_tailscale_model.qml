import QtQuick
import QtTest
import "../shell/Tailscale/model.js" as Tailscale

TestCase {
    name: "TailscaleModel"

    // Shapes lifted from a real `tailscale status --json` run (see
    // Tailscale/model.js's header comment) rather than invented.

    readonly property string runningFixture: JSON.stringify({
        BackendState: "Running",
        Self: { HostName: "MyLaptop", TailscaleIPs: ["100.64.0.1", "fd7a:115c:a1e0::1"] },
        Peer: {
            "nodekey:aaa": { HostName: "Server", TailscaleIPs: ["100.64.0.2"], Online: true, OS: "linux" },
            "nodekey:bbb": { HostName: "Phone", TailscaleIPs: ["100.64.0.3"], Online: false, OS: "android" }
        }
    })

    readonly property string stoppedFixture: JSON.stringify({
        BackendState: "Stopped",
        Self: { HostName: "MyLaptop", TailscaleIPs: ["100.64.0.1"] },
        Peer: {}
    })

    readonly property string needsLoginFixture: JSON.stringify({
        BackendState: "NeedsLogin",
        Self: {},
        AuthURL: "https://login.tailscale.com/a/abc123"
    })

    // The real CLI prints a plain-text error (not JSON) when it can't reach
    // tailscaled — never valid JSON, so this fixture is deliberately not
    // JSON either.
    readonly property string noDaemonFixture: "Failed to connect to local tailscaled; (tailscaled not running?)\n"

    function test_running_parses_backend_state_and_self() {
        var s = Tailscale.parseStatus(runningFixture);
        compare(s.ok, true);
        compare(s.backendState, "Running");
        compare(s.running, true);
        compare(s.needsLogin, false);
        compare(s.selfName, "MyLaptop");
        compare(s.selfIps.length, 2);
        compare(s.selfIps[0], "100.64.0.1");
    }

    function test_running_peers_shaped_and_sorted_online_first_then_alpha() {
        var s = Tailscale.parseStatus(runningFixture);
        compare(s.peers.length, 2);
        // Server is online, Phone is offline — online sorts first regardless
        // of name.
        compare(s.peers[0].name, "Server");
        compare(s.peers[0].online, true);
        compare(s.peers[0].ip, "100.64.0.2");
        compare(s.peers[0].os, "linux");
        compare(s.peers[1].name, "Phone");
        compare(s.peers[1].online, false);
    }

    function test_running_peers_sort_alphabetically_within_same_online_state() {
        var fixture = JSON.stringify({
            BackendState: "Running",
            Self: { HostName: "Me", TailscaleIPs: ["100.64.0.1"] },
            Peer: {
                "nodekey:z": { HostName: "Zeta", TailscaleIPs: ["100.64.0.9"], Online: true, OS: "linux" },
                "nodekey:a": { HostName: "Alpha", TailscaleIPs: ["100.64.0.8"], Online: true, OS: "linux" }
            }
        });
        var s = Tailscale.parseStatus(fixture);
        compare(s.peers[0].name, "Alpha");
        compare(s.peers[1].name, "Zeta");
    }

    function test_stopped_reports_running_false_with_empty_peers() {
        var s = Tailscale.parseStatus(stoppedFixture);
        compare(s.ok, true);
        compare(s.backendState, "Stopped");
        compare(s.running, false);
        compare(s.needsLogin, false);
        compare(s.peers.length, 0);
    }

    function test_needs_login_reports_needsLogin_with_honest_null_self() {
        var s = Tailscale.parseStatus(needsLoginFixture);
        compare(s.ok, true);
        compare(s.backendState, "NeedsLogin");
        compare(s.needsLogin, true);
        compare(s.running, false);
        compare(s.selfName, null);
        compare(s.selfIps.length, 0);
    }

    function test_no_daemon_plain_text_output_is_honestly_unparsable() {
        var s = Tailscale.parseStatus(noDaemonFixture);
        compare(s.ok, false);
        compare(s.backendState, null);
        compare(s.peers.length, 0);
    }

    function test_empty_string_is_honestly_unparsable() {
        var s = Tailscale.parseStatus("");
        compare(s.ok, false);
    }

    function test_peer_missing_hostname_falls_back_to_id_not_blank() {
        var fixture = JSON.stringify({
            BackendState: "Running",
            Self: { HostName: "Me", TailscaleIPs: ["100.64.0.1"] },
            Peer: {
                "nodekey:noname": { TailscaleIPs: ["100.64.0.5"], Online: true }
            }
        });
        var s = Tailscale.parseStatus(fixture);
        compare(s.peers[0].name, "nodekey:noname");
        compare(s.peers[0].os, null);
    }

    function test_peer_missing_ips_reports_honest_null_ip() {
        var fixture = JSON.stringify({
            BackendState: "Running",
            Self: { HostName: "Me", TailscaleIPs: ["100.64.0.1"] },
            Peer: {
                "nodekey:noip": { HostName: "NoIp", Online: false }
            }
        });
        var s = Tailscale.parseStatus(fixture);
        compare(s.peers[0].ip, null);
    }

    function test_selfIp_returns_first_address() {
        var s = Tailscale.parseStatus(runningFixture);
        compare(Tailscale.selfIp(s), "100.64.0.1");
    }

    function test_selfIp_honest_null_when_no_addresses() {
        var s = Tailscale.parseStatus(needsLoginFixture);
        compare(Tailscale.selfIp(s), null);
    }

    function test_selfIp_honest_null_for_unparsable_status() {
        var s = Tailscale.parseStatus(noDaemonFixture);
        compare(Tailscale.selfIp(s), null);
    }
}
