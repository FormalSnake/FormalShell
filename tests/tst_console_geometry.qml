import QtQuick
import QtTest
import "../shell/Console/geometry.js" as Geometry

TestCase {
    name: "ConsoleGeometry"

    readonly property var screen: ({ x: 0, y: 0, width: 1920, height: 1080 })
    readonly property var topBar: ({ top: 40, bottom: 0, left: 0, right: 0 })
    readonly property var noBar: ({ top: 0, bottom: 0, left: 0, right: 0 })

    function test_half_of_the_area_under_the_bar() {
        var g = Geometry.consoleGeometry(screen, topBar, 0.5, 10);
        compare(g.x, 10);
        compare(g.y, 50);
        compare(g.width, 1900);
        compare(g.height, 505);
    }

    function test_second_output_keeps_its_own_origin() {
        var g = Geometry.consoleGeometry({ x: 1920, y: -200, width: 1280, height: 720 }, topBar, 0.5, 10);
        compare(g.x, 1930);
        compare(g.y, -150);
        compare(g.width, 1260);
    }

    // A bottom bar takes its band off the bottom: the console drops from
    // the top edge and covers half of what is left above the bar.
    function test_a_bottom_bar_shortens_the_area_from_below() {
        var g = Geometry.consoleGeometry(screen, { top: 0, bottom: 40, left: 0, right: 0 }, 0.5, 10);
        compare(g.y, 10);
        compare(g.height, 505);
    }

    // A left bar takes its band off the left: the console starts past it
    // and is that much narrower, at full height under no top bar.
    function test_a_left_bar_narrows_the_console_from_the_left() {
        var g = Geometry.consoleGeometry(screen, { top: 0, bottom: 0, left: 40, right: 0 }, 0.5, 10);
        compare(g.x, 50);
        compare(g.y, 10);
        compare(g.width, 1860);
        compare(g.height, 525);
    }

    function test_share_is_clamped_at_both_ends() {
        compare(Geometry.consoleGeometry(screen, noBar, 3, 0).height, 1080);
        compare(Geometry.consoleGeometry(screen, noBar, 0.01, 0).height, 216);
    }

    function test_unreadable_share_falls_back_to_half() {
        compare(Geometry.consoleGeometry(screen, noBar, "nonsense", 0).height,
                Geometry.consoleGeometry(screen, noBar, 0.5, 0).height);
    }

    function test_margin_wider_than_the_screen_never_goes_negative() {
        var g = Geometry.consoleGeometry(screen, topBar, 0.5, 4000);
        verify(g.width >= 1);
        verify(g.height >= 1);
    }

    function test_no_screen_is_no_geometry() {
        compare(Geometry.consoleGeometry(null, topBar, 0.5, 10), null);
        compare(Geometry.consoleGeometry({ x: 0, y: 0, width: 0, height: 0 }, topBar, 0.5, 10), null);
    }

    // The one-off drop-down's argv (ConsoleService.runOnce). The console's
    // own command, its app id swapped so the standing console keeps its
    // identity, and the command appended the one way every emulator the
    // config note names accepts.
    function test_oneOffArgv_swaps_the_app_id_and_appends_the_command() {
        var argv = Geometry.oneOffArgv(["ghostty", "--class=dev.formalshell.console"],
            "dev.formalshell.console", "dev.formalshell.console.run", "nix run nixpkgs#hello; read");
        compare(argv.join("\u0001"), ["ghostty", "--class=dev.formalshell.console.run",
            "-e", "sh", "-c", "nix run nixpkgs#hello; read"].join("\u0001"));
    }

    function test_oneOffArgv_handles_the_id_in_its_own_argument() {
        var argv = Geometry.oneOffArgv(["foot", "--app-id", "con"], "con", "con.run", "true");
        compare(argv.join(" "), "foot --app-id con.run -e sh -c true");
    }

    // An argv that never names the app id would spawn a second window
    // answering to the console's own id, which is worse than not running.
    function test_oneOffArgv_refuses_an_argv_that_never_names_the_app_id() {
        compare(Geometry.oneOffArgv(["ghostty"], "con", "con.run", "true"), null);
        compare(Geometry.oneOffArgv([], "con", "con.run", "true"), null);
        compare(Geometry.oneOffArgv(null, "con", "con.run", "true"), null);
        compare(Geometry.oneOffArgv(["ghostty", "--class=con"], "con", "con", "true"), null);
    }
}
