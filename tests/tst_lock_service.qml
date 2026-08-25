import QtQuick
import QtTest
import "../shell/Services/lock.js" as Lock

// LockService's routing (M45 D2): `lock.command` set spawns that argv and
// never raises the built-in surface; unset raises the surface and spawns
// nothing. The two sides arrive here as the same callbacks LockService.qml
// passes in (CompositorService.spawn and its own _raise), so this drives the
// real decision rather than a copy of it.
TestCase {
    name: "LockService"

    property var spawned: []
    property int raised: 0

    function init() {
        spawned = [];
        raised = 0;
    }

    function _spawn(argv) {
        var next = spawned.slice();
        next.push(argv);
        spawned = next;
    }

    function _raise() {
        raised++;
        return "ok";
    }

    function _lock(command) {
        return Lock.lock(command, _spawn, _raise);
    }

    function test_a_command_spawns_that_argv_and_never_raises_the_surface() {
        compare(_lock(["hyprlock", "--immediate"]), "ok");
        compare(spawned.length, 1);
        compare(spawned[0], ["hyprlock", "--immediate"]);
        compare(raised, 0);
    }

    function test_no_command_raises_the_surface_and_spawns_nothing() {
        compare(_lock([]), "ok");
        compare(raised, 1);
        compare(spawned.length, 0);
    }

    function test_the_surface_reply_is_passed_straight_back() {
        compare(Lock.lock([], _spawn, function () { return "error: lock not ready"; }),
                "error: lock not ready");
        compare(spawned.length, 0);
    }

    function test_external_is_the_command_being_set() {
        verify(Lock.isExternal(["swaylock"]));
        verify(!Lock.isExternal([]));
    }

    // settings.json is user input, and a half-built argv spawned with a hole
    // in it is worse than no command at all.
    function test_malformed_commands_are_no_command() {
        var cases = [undefined, null, "hyprlock", [""], ["hyprlock", 3], {}];
        for (var i = 0; i < cases.length; i++) {
            compare(Lock.argv(cases[i]), [], "case " + i);
            verify(!Lock.isExternal(cases[i]), "case " + i);
        }
    }

    function test_status_reports_external_with_a_null_locked() {
        var s = Lock.status(["hyprlock"], null);
        compare(s.external, true);
        compare(s.locked, null);
        compare(s.secure, null);
        compare(s.authError, null);
        compare(s.blanked, null);
    }

    function test_status_reports_the_surface_when_no_command_is_set() {
        var surface = { locked: true, secure: true, authError: "Wrong password", blanked: false };
        var s = Lock.status([], surface);
        compare(s.external, false);
        compare(s.locked, true);
        compare(s.secure, true);
        compare(s.authError, "Wrong password");
        compare(s.blanked, false);
    }
}
