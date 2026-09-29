import QtQuick
import QtTest
import "../shell/Localsend/model.js" as LM

TestCase {
    name: "LocalsendModel"

    // Real shapes off 0w0mewo/localsend-cli @ 7865fb1c.
    property string scanFound: "Found Devices: \n\tName: Kyan's iPhone, Version: 2.0, Address: 192.168.1.42:53317, Protocol: https\n\tName: Cool Mango, Version: 2.0, Address: 192.168.1.50:53317, Protocol: https\n"

    function test_parseScan_finds_every_peer() {
        var peers = LM.parseScan(scanFound);
        compare(peers.length, 2);
        compare(peers[0].name, "Kyan's iPhone");
        compare(peers[0].ip, "192.168.1.42");
        compare(peers[0].port, 53317);
        compare(peers[0].protocol, "https");
        compare(peers[1].name, "Cool Mango");
        compare(peers[1].ip, "192.168.1.50");
    }

    function test_parseScan_empty_on_no_devices() {
        // "No device found" lands on stderr, never matches the tab-led
        // peer line, whichever stream it's handed.
        compare(LM.parseScan("No device found\n").length, 0);
        compare(LM.parseScan("").length, 0);
    }

    function test_resolvePeer() {
        var peers = LM.parseScan(scanFound);
        compare(LM.resolvePeer(peers, "Cool Mango").ip, "192.168.1.50");
        compare(LM.resolvePeer(peers, "Nobody Here"), null);
    }

    function test_parseSlogLine_plain_values() {
        var e = LM.parseSlogLine('2026/09/29 13:35:10 INFO Done');
        compare(e.level, "INFO");
        compare(e.msg, "Done");
    }

    function test_parseSlogLine_quoted_values_with_spaces() {
        var e = LM.parseSlogLine('2026/09/29 13:35:10 INFO Start sending file="/tmp/my a.png"');
        compare(e.level, "INFO");
        compare(e.msg, "Start sending");
        compare(e.fields.file, "/tmp/my a.png");
    }

    function test_parseSlogLine_error_with_nested_error_field() {
        var e = LM.parseSlogLine('2026/09/29 13:35:10 ERROR Fail to send error="dial tcp: connection refused"');
        compare(e.level, "ERROR");
        compare(e.fields.error, "dial tcp: connection refused");
    }

    function test_parseSlogLine_no_level_is_null() {
        compare(LM.parseSlogLine("Waitting for receiving files (Ctrl-C to terminate)"), null);
        compare(LM.parseSlogLine(""), null);
    }

    function test_sendOutcome_exit0_no_errors_is_ok() {
        var out = LM.sendOutcome(0, '2026/09/29 13:35:10 INFO Start sending file=/tmp/a.png\n2026/09/29 13:35:10 INFO Done\n');
        compare(out.ok, true);
        compare(out.fatal, false);
        compare(out.failed.length, 0);
    }

    // The exact case the plan calls out: exit 0 with a per-file failure
    // buried in an ERROR line, never surfaced by the exit code alone.
    function test_sendOutcome_exit0_with_per_file_error_is_not_ok() {
        var stderr = '2026/09/29 13:35:10 INFO Start sending file=/tmp/a.png\n'
            + '2026/09/29 13:35:10 ERROR Fail to add file, skipping... file=/tmp/b.png error="no such file or directory"\n'
            + '2026/09/29 13:35:10 INFO Done\n';
        var out = LM.sendOutcome(0, stderr);
        compare(out.ok, false);
        compare(out.fatal, false);
        compare(out.failed.length, 1);
        compare(out.failed[0].file, "/tmp/b.png");
        compare(out.failed[0].error, "no such file or directory");
    }

    function test_sendOutcome_nonzero_exit_is_fatal() {
        var out = LM.sendOutcome(1, '2026/09/29 13:35:10 ERROR Fail to send error="IP address is required"\n');
        compare(out.ok, false);
        compare(out.fatal, true);
        compare(out.failed.length, 1);
    }

    function test_parseRecvLine_accepting() {
        var e = LM.parseRecvLine('2026/09/29 13:35:10 INFO Accepting file remote=192.168.1.42 session=abc-123');
        compare(e.type, "accepting");
        compare(e.remote, "192.168.1.42");
        compare(e.session, "abc-123");
    }

    function test_parseRecvLine_error() {
        var e = LM.parseRecvLine('2026/09/29 13:35:10 ERROR Upload error remote=192.168.1.42 session=abc-123 error="checksum mismatch"');
        compare(e.type, "error");
        compare(e.message, "Upload error: checksum mismatch");
    }

    function test_parseRecvLine_no_level_is_null() {
        compare(LM.parseRecvLine("Waitting for receiving files (Ctrl-C to terminate)"), null);
    }

    function test_parseRecvLine_received() {
        var e = LM.parseRecvLine('2026/09/29 13:35:10 INFO Recv file file="my photo.png" session=abc-123');
        compare(e.type, "received");
        compare(e.file, "my photo.png");
        compare(e.session, "abc-123");
    }
}
