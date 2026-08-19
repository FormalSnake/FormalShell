import QtQuick
import QtTest
import "../shell/Console/geometry.js" as Geometry

TestCase {
    name: "ConsoleGeometry"

    readonly property var screen: ({ x: 0, y: 0, width: 1920, height: 1080 })

    function test_half_of_the_area_under_the_bar() {
        var g = Geometry.consoleGeometry(screen, 40, 0.5, 10);
        compare(g.x, 10);
        compare(g.y, 50);
        compare(g.width, 1900);
        // Bottom edge lands on half the usable height: 40 + 10 + 510 = 560,
        // which is 40 + (1080 - 40 - 10) / 2 rounded.
        compare(g.height, 505);
    }

    function test_second_output_keeps_its_own_origin() {
        var g = Geometry.consoleGeometry({ x: 1920, y: -200, width: 1280, height: 720 }, 40, 0.5, 10);
        compare(g.x, 1930);
        compare(g.y, -150);
        compare(g.width, 1260);
    }

    function test_share_is_clamped_at_both_ends() {
        compare(Geometry.consoleGeometry(screen, 0, 3, 0).height, 1080);
        compare(Geometry.consoleGeometry(screen, 0, 0.01, 0).height, 216);
    }

    function test_unreadable_share_falls_back_to_half() {
        compare(Geometry.consoleGeometry(screen, 0, "nonsense", 0).height,
                Geometry.consoleGeometry(screen, 0, 0.5, 0).height);
    }

    function test_margin_wider_than_the_screen_never_goes_negative() {
        var g = Geometry.consoleGeometry(screen, 40, 0.5, 4000);
        verify(g.width >= 1);
        verify(g.height >= 1);
    }

    function test_no_screen_is_no_geometry() {
        compare(Geometry.consoleGeometry(null, 40, 0.5, 10), null);
        compare(Geometry.consoleGeometry({ x: 0, y: 0, width: 0, height: 0 }, 40, 0.5, 10), null);
    }
}
