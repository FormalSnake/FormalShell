import QtQuick
import Quickshell.Io
import qs.Core as Core
import qs.Services
import qs.Notifications
import "../../Menu/toggles.js" as Toggles

// Shell-condition batch: `when`/`checked` for EVERY node in the tree, not
// just the current level, whole-tree search can surface a node whose level
// the user hasn't descended into yet, and a submenu with an
// unevaluated-when child self-prunes to invisible (Model.visibleChildren),
// which would make that child undescendable and its own condition
// permanently unevaluated. `evaluate()` runs once per open() (open() clears
// both result caches first) and again on every level change, where the
// `undefined` guards make repeat calls within the same session cheap
// no-ops. Never per-keystroke, search filters purely against whatever's
// already cached. Results are merged into fresh objects so QML's
// var-property change detection fires.
Item {
    id: root

    property var condResults: ({})
    property var checkedResults: ({})

    // Fresh session: last session's condition results must not leak into
    // this one (a `when`/`checked` shell command can change between opens,
    // bluetooth power, mode toggle, device presence).
    function reset() {
        root.condResults = {};
        root.checkedResults = {};
    }

    function evaluate(nodes) {
        Object.keys(nodes).forEach(function (id) {
            var n = nodes[id];
            if (n.when !== undefined && root.condResults[n.id] === undefined) {
                if (Toggles.isStateCondition(n.when)) {
                    // "@state:" is a `checked` prefix only: a live `when`
                    // would mean re-running visibleChildren over every node
                    // (apps included) on each toggle flip, exactly the
                    // churn LiveMenuSources exists to avoid.
                    console.warn("Menu: \"@state:\" is not a `when` condition, hiding", n.id);
                    root.condResults = Toggles.withResult(root.condResults, n.id, false);
                } else {
                    root._run(n.id, n.when, "when");
                }
            }
            if (n.checked !== undefined && !Toggles.isStateCondition(n.checked)
                && root.checkedResults[n.id] === undefined)
                root._run(n.id, n.checked, "checked");
        });
    }

    function _run(nodeId, cond, kind) {
        var proc = _procComponent.createObject(root, { _nodeId: nodeId, _kind: kind });
        proc.command = ["sh", "-c", cond];
        proc.running = true;
    }

    Component {
        id: _procComponent

        Process {
            property string _nodeId
            property string _kind
            onExited: exitCode => {
                var id = _nodeId;
                var ok = exitCode === 0;
                var isWhen = _kind === "when";
                destroy();
                var source = isWhen ? root.condResults : root.checkedResults;
                var merged = Toggles.withResult(source, id, ok);
                if (isWhen) root.condResults = merged;
                else root.checkedResults = merged;
            }
        }
    }

    // Live source for "@state:" `checked` conditions (toggles.js). Every
    // read here is a plain property read, so this binding re-evaluates the
    // instant any of the four flips and hands a fresh object to the
    // delegate binding that reads it, the same var-change-detection
    // contract the condResults merge already depends on. Not gated on
    // isOpen the way LiveMenuSources is: four scalars cost nothing, and the
    // NightLightService read is a second construction site for that lazy
    // singleton, which Indicators.qml wants.
    readonly property var stateSnapshot: Toggles.snapshot({
        "nightlight.active": NightLightService.active,
        "screensaver.stayAwake": IdleService.stayAwake,
        "notifications.dnd": NotificationService.dnd,
        "theme.dark": Core.State.mode === "dark"
    })
}
