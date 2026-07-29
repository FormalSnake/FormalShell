import QtQuick
import QtTest
import "../shell/Bar/commandOutput.js" as CommandOutput

TestCase {
    name: "CommandOutput"

    function test_valid_output_is_parsed() {
        var s = CommandOutput.resolve(0, '{"text": "CMD 42", "tooltip": "hi", "class": "warning"}');
        compare(s.text, "CMD 42");
        compare(s.tooltip, "hi");
        compare(s["class"], "warning");
    }

    function test_missing_tooltip_and_class_default_to_empty() {
        var s = CommandOutput.resolve(0, '{"text": "CMD 42"}');
        compare(s.text, "CMD 42");
        compare(s.tooltip, "");
        compare(s["class"], "");
    }

    function test_non_zero_exit_renders_module_error() {
        var s = CommandOutput.resolve(1, '{"text": "CMD 42"}');
        compare(s.text, "MODULE ERROR");
        compare(s.tooltip, "");
        compare(s["class"], "");
    }

    function test_malformed_json_renders_module_error() {
        var s = CommandOutput.resolve(0, "not json");
        compare(s.text, "MODULE ERROR");
    }

    function test_empty_output_renders_module_error() {
        var s = CommandOutput.resolve(0, "");
        compare(s.text, "MODULE ERROR");
    }

    function test_missing_text_field_renders_module_error() {
        var s = CommandOutput.resolve(0, '{"tooltip": "hi"}');
        compare(s.text, "MODULE ERROR");
    }

    function test_non_string_text_field_renders_module_error() {
        var s = CommandOutput.resolve(0, '{"text": 42}');
        compare(s.text, "MODULE ERROR");
    }

    function test_error_state_matches_resolved_error_shape() {
        compare(JSON.stringify(CommandOutput.errorState()), JSON.stringify(CommandOutput.resolve(1, "")));
    }
}
