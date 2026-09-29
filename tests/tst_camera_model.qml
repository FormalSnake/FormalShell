import QtQuick
import QtTest
import "../shell/Camera/model.js" as Camera

TestCase {
    name: "CameraModel"

    // The two card names the g815's uvcvideo reports (v4l2-ctl on the
    // machine, 2026-09-29): one USB device, a colour and an IR interface.
    readonly property var asusColour: ({ id: "/dev/video0", description: "ASUS FHD webcam: ASUS FHD webca", greyOnly: false })
    readonly property var asusIr: ({ id: "/dev/video2", description: "ASUS FHD webcam: ASUS IR camera", greyOnly: true })

    function test_label_takes_the_product_when_the_interface_is_a_truncated_copy() {
        compare(Camera.label(asusColour.description, false), "ASUS FHD webcam");
    }

    function test_label_takes_the_interface_when_it_names_the_ir_sensor() {
        compare(Camera.label(asusIr.description, true), "ASUS IR camera");
    }

    function test_label_marks_an_ir_camera_whose_name_does_not() {
        compare(Camera.label("Integrated Camera: Integrated I", true), "Integrated Camera IR");
    }

    function test_label_leaves_a_plain_name_alone() {
        compare(Camera.label("Logitech BRIO", false), "Logitech BRIO");
        compare(Camera.label("", false), "Camera");
    }

    function test_rows_put_colour_before_ir_whatever_the_node_order() {
        var list = Camera.rows([asusIr, asusColour]);
        compare(list.map(function (r) { return r.id; }), ["/dev/video0", "/dev/video2"]);
        compare(list.map(function (r) { return r.ir; }), [false, true]);
    }

    function test_rows_treat_a_grey_only_device_as_ir_without_a_name_hint() {
        var list = Camera.rows([{ id: "/dev/video4", description: "Integrated Camera: Integrated I", greyOnly: true }]);
        compare(list[0].ir, true);
        compare(list[0].label, "Integrated Camera IR");
    }

    function test_rows_treat_an_ir_name_as_ir_even_with_colour_formats() {
        var list = Camera.rows([{ id: "/dev/video2", description: "HP IR Camera", greyOnly: false }]);
        compare(list[0].ir, true);
    }

    function test_rows_sort_nodes_numerically() {
        var list = Camera.rows([
            { id: "/dev/video10", description: "B", greyOnly: false },
            { id: "/dev/video2", description: "A", greyOnly: false }
        ]);
        compare(list.map(function (r) { return r.id; }), ["/dev/video2", "/dev/video10"]);
    }

    function test_rows_number_identical_labels() {
        var list = Camera.rows([
            { id: "/dev/video0", description: "USB Camera", greyOnly: false },
            { id: "/dev/video2", description: "USB Camera", greyOnly: false }
        ]);
        compare(list.map(function (r) { return r.label; }), ["USB Camera", "USB Camera 2"]);
    }

    function test_rows_of_nothing_is_empty() {
        compare(Camera.rows([]).length, 0);
        compare(Camera.rows(null).length, 0);
    }

    function test_pick_keeps_the_current_camera_while_it_is_listed() {
        var list = Camera.rows([asusColour, asusIr]);
        compare(Camera.pick(list, "/dev/video2"), "/dev/video2");
    }

    function test_pick_falls_back_to_the_first_row_or_nothing() {
        var list = Camera.rows([asusIr, asusColour]);
        compare(Camera.pick(list, "/dev/video9"), "/dev/video0");
        compare(Camera.pick([], "/dev/video0"), "");
    }

    function test_step_cycles_forward_and_wraps() {
        var list = Camera.rows([asusColour, asusIr]);
        compare(Camera.step(list, "/dev/video0", 1), "/dev/video2");
        compare(Camera.step(list, "/dev/video2", 1), "/dev/video0");
    }

    function test_step_cycles_backward_and_wraps() {
        var list = Camera.rows([asusColour, asusIr]);
        compare(Camera.step(list, "/dev/video0", -1), "/dev/video2");
    }

    function test_step_stays_on_a_single_camera() {
        var list = Camera.rows([asusColour]);
        compare(Camera.step(list, "/dev/video0", 1), "/dev/video0");
    }

    function test_step_starts_at_the_first_row_from_an_unknown_id() {
        var list = Camera.rows([asusColour, asusIr]);
        compare(Camera.step(list, "", 1), "/dev/video0");
        compare(Camera.step([], "", 1), "");
    }
}
