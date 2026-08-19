import QtQuick
import QtTest
import "../shell/Compositor/hyprland/model.js" as Model

TestCase {
    name: "HyprlandWorkspaces"

    // Quickshell's HyprlandWorkspace shape, as far as the mapping reads it.
    function hws(id, name, monitor, flags) {
        flags = flags || {};
        return {
            id: id,
            name: name,
            monitor: monitor === null ? null : { name: monitor },
            active: flags.active === true,
            focused: flags.focused === true,
            urgent: flags.urgent === true
        };
    }

    function ids(model) {
        return model.map(function (w) { return w.id; }).join(",");
    }

    function test_maps_onto_the_contract() {
        var model = Model.mapWorkspaces([hws(2, "mail", "DP-1", { active: true, focused: true, urgent: true })]);
        compare(model.length, 1);
        compare(model[0].id, "2");        // opaque string, not the int
        compare(model[0].idx, 2);
        compare(model[0].name, "mail");
        compare(model[0].output, "DP-1");
        compare(model[0].isActive, true);
        compare(model[0].isFocused, true);
        compare(model[0].isUrgent, true);
    }

    function test_drops_special_workspaces() {
        var model = Model.mapWorkspaces([
            hws(1, "1", "DP-1", { active: true, focused: true }),
            hws(-99, "special:formalshell-console", "DP-1"),
            hws(2, "2", "DP-1")
        ]);
        compare(ids(model), "1,2");
    }

    function test_drops_a_shown_special_workspace_too() {
        // A special that is currently on screen is still an overlay, not a
        // workspace the bar can switch to.
        var model = Model.mapWorkspaces([
            hws(-99, "special:formalshell-console", "DP-1", { active: true, focused: true })
        ]);
        compare(model.length, 0);
    }

    function test_workspace_without_a_monitor_maps_to_empty_output() {
        var model = Model.mapWorkspaces([hws(3, "3", null)]);
        compare(model[0].output, "");
    }

    function test_handles_an_empty_list() {
        compare(Model.mapWorkspaces([]).length, 0);
        compare(Model.mapWorkspaces(null).length, 0);
    }
}
