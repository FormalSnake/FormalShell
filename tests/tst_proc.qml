import QtQuick
import QtTest
import "../shell/Core/proc.js" as Proc

// PR_SET_PDEATHSIG on the shell's long-lived children (shell/Core/proc.js
// carries the why). The wrapper is four argv entries, so what a test can
// still get wrong is the order: setpriv reads its own options first and
// everything past `--` is the command, and a wrapped command that lost its
// own arguments (or gained setpriv's) would run something else entirely.
TestCase {
    name: "Proc"

    function test_the_wrapped_command_survives_verbatim() {
        var argv = Proc.dieWithParent(["wl-paste", "--type", "text", "--watch", "sh", "-c", "cat"]);
        compare(argv.slice(4), ["wl-paste", "--type", "text", "--watch", "sh", "-c", "cat"]);
    }

    // `--` is what keeps a child's own flags out of setpriv's option parser:
    // without it `wl-paste --type` is setpriv's to reject.
    function test_setpriv_options_end_before_the_command() {
        var argv = Proc.dieWithParent(["cava", "-p", "/tmp/cfg"]);
        compare(argv.slice(0, 4), ["setpriv", "--pdeathsig", "TERM", "--"]);
        compare(argv.indexOf("--"), 3);
    }

    function test_an_empty_command_is_not_an_error() {
        compare(Proc.dieWithParent([]), ["setpriv", "--pdeathsig", "TERM", "--"]);
        compare(Proc.dieWithParent(undefined), ["setpriv", "--pdeathsig", "TERM", "--"]);
    }

    // The caller passes the array it already built; wrapping must not write
    // into it, since RecordingService and the screensaver both hand over the
    // return value of a pure builder that other call sites reuse.
    function test_the_caller_s_array_is_left_alone() {
        var argv = ["ttfx", "--effect", "rain"];
        Proc.dieWithParent(argv);
        compare(argv, ["ttfx", "--effect", "rain"]);
    }

    function test_app_launch_goes_by_desktop_id_under_uwsm() {
        compare(Proc.appLaunch("HYPRLAND_INSTANCE_SIGNATURE", { id: "org.gnome.Nautilus" }, null),
                ["uwsm", "app", "--", "org.gnome.Nautilus.desktop"]);
    }

    function test_an_action_launches_by_its_parsed_command() {
        var action = { command: ["firefox", "--private-window"] };
        compare(Proc.appLaunch("x", { id: "firefox" }, action),
                ["uwsm", "app", "--", "firefox", "--private-window"]);
    }

    function test_an_id_uwsm_rejects_launches_by_command() {
        var entry = { id: "Modrinth App", command: ["ModrinthApp"] };
        compare(Proc.appLaunch("x", entry, null), ["uwsm", "app", "--", "ModrinthApp"]);
    }

    function test_a_terminal_entry_by_command_keeps_its_terminal() {
        var entry = { id: "My Tool", command: ["htop"], runInTerminal: true };
        compare(Proc.appLaunch("x", entry, null), ["uwsm", "app", "-T", "--", "htop"]);
    }

    // No uwsm session: the caller falls back to execute().
    function test_no_uwsm_session_means_no_argv() {
        compare(Proc.appLaunch("", { id: "firefox" }, null), null);
        compare(Proc.appLaunch(undefined, { id: "firefox" }, null), null);
        compare(Proc.appLaunch("x", { id: "firefox" }, { command: [] }), null);
    }
}
