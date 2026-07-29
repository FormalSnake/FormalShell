import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core
import qs.Surfaces.Bar.widgets
import "../../Bar/layout.js" as Layout

// The bar (DESIGN.md §3 Bar, spec §1, M6 Tasks 1+3, M8b Task 3 retrofit,
// M10 Task 3 settings-driven retrofit): three regions — left, center,
// right — each populated from `bar.layout` in settings.json (left/center/
// right arrays of widget names, resolved by ../../Bar/layout.js) rather
// than a fixed declaration order; an absent or partial `bar.layout` falls
// back region-by-region to exactly today's arrangement (workspaces+active
// window left, clock+now-playing center, battery/audio/network/bluetooth/
// weather/tray/indicators right), so a user with no config sees no change.
// Layout entries name either a built-in widget (resolved against
// `_builtinComponents` below, each pre-wired with the panel/screen context
// only Bar.qml has) or a `bar.modules[]` custom module via a "custom:<id>"
// name — `command` (CommandModule.qml, Waybar-JSON-compatible polled
// output) or `qml` (QmlModule.qml, a user-supplied file in a Loader). An
// unknown widget name or a dangling module reference is dropped with a
// console warning, never a crash. Every widget cell is a `standalone` Cell
// (DESIGN.md §3): borderless at rest, hover-cursor fill+border only on
// mouseover, separated from its neighbor by a small gap plus its own
// padding — omarchy's discrete-module bar, not the M1-M3 fused ledger
// strip this surface used to be. The region-boundary rules (left|center,
// center|right, the bar's own bottom edge) stay: they mark a structural
// region boundary the spec already committed to, not the per-widget
// rule-sharing this task retired.
PanelWindow {
    id: bar
    required property var modelData
    property var audioPanel: null
    property var calendarPanel: null
    property var networkPanel: null
    property var bluetoothPanel: null
    property var powerPanel: null
    property var weatherPanel: null
    property var mediaPanel: null
    screen: modelData
    anchors { top: true; left: true; right: true }

    function _resolveLayout() {
        var result = Layout.resolve(Config.get("bar", null));
        for (var i = 0; i < result.warnings.length; i++)
            console.warn("Bar:", result.warnings[i]);
        return result;
    }

    // Recomputes (and re-warns) whenever Config.settings changes — Config.get()
    // reads that property internally, so this binding tracks it same as any
    // other Config.get() consumer in the shell.
    readonly property var _layout: bar._resolveLayout()

    // Max implicit height across every currently-loaded cell in a region,
    // read off each delegate's *loaded item* (Loader.item), never the Loader
    // itself: a Loader given no explicit size mirrors its item's actual size
    // through its own implicitHeight too, so reading Loader.implicitHeight
    // directly here would close a real cycle back through this very
    // property (confirmed by reproducing it) — the widget's own
    // content-derived implicitHeight has no such coupling to the height its
    // delegate below assigns it.
    function _regionHeight(repeater) {
        var max = 0;
        for (var i = 0; i < repeater.count; i++) {
            var loader = repeater.itemAt(i);
            var item = loader ? loader.item : null;
            if (item && item.implicitHeight > max)
                max = item.implicitHeight;
        }
        return max;
    }

    readonly property real _cellHeight: Math.max(bar._regionHeight(leftRepeater), bar._regionHeight(centerRepeater), bar._regionHeight(rightRepeater))
    implicitHeight: bar._cellHeight
    color: Theme.color.background

    // Panel.qml anchors every popout's top edge under the bar — it has no
    // other way to know this bar's actual (content-derived) height, since
    // Wayland gives clients no cross-window geometry.
    Binding {
        target: Theme
        property: "barHeight"
        value: bar._cellHeight
    }

    // Bottom edge: one rule against the desktop.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.borderWidth
        color: Theme.color.rule
    }

    // Built-in widget registry: each Component wraps the widget with the
    // context (this bar's screen/width, or an owning popout panel instance)
    // that only Bar.qml knows, so a Layout.resolve() entry can instantiate
    // any of them purely by name.
    Component {
        id: workspacesComponent
        Workspaces {
            outputName: bar.screen ? bar.screen.name : ""
        }
    }
    Component {
        id: activeWindowComponent
        ActiveWindow {
            maxWidth: bar.width * 0.4
        }
    }
    Component {
        id: clockComponent
        Clock {
            panel: bar.calendarPanel
        }
    }
    Component {
        id: nowPlayingComponent
        NowPlaying {
            panel: bar.mediaPanel
        }
    }
    Component {
        id: batteryComponent
        Battery {
            panel: bar.powerPanel
        }
    }
    Component {
        id: audioComponent
        AudioWidget {
            panel: bar.audioPanel
        }
    }
    Component {
        id: networkComponent
        NetworkWidget {
            panel: bar.networkPanel
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothWidget {
            panel: bar.bluetoothPanel
        }
    }
    Component {
        id: weatherComponent
        WeatherWidget {
            panel: bar.weatherPanel
        }
    }
    Component {
        id: trayComponent
        Tray {
        }
    }
    Component {
        id: indicatorsComponent
        Indicators {
        }
    }
    Component {
        id: commandModuleComponent
        CommandModule {
        }
    }
    Component {
        id: qmlModuleComponent
        QmlModule {
        }
    }

    readonly property var _builtinComponents: ({
        workspaces: workspacesComponent,
        activeWindow: activeWindowComponent,
        clock: clockComponent,
        nowPlaying: nowPlayingComponent,
        battery: batteryComponent,
        audio: audioComponent,
        network: networkComponent,
        bluetooth: bluetoothComponent,
        weather: weatherComponent,
        tray: trayComponent,
        indicators: indicatorsComponent
    })

    // Shared by every region below: a builtin entry loads straight from the
    // registry above, a module entry picks CommandModule/QmlModule by the
    // module's own `type` and hands it the module definition once loaded
    // (module isn't a `required property` on either widget specifically so
    // it can be set here, after creation, rather than at construction time).
    Component {
        id: regionDelegate
        Loader {
            id: entryLoader
            required property var modelData
            height: bar._cellHeight
            // A hidden widget (Battery with no laptop battery, NowPlaying
            // with no player, Tray with no items, Indicators with nothing
            // active) sets `visible: false` on itself expecting Row to drop
            // its slot entirely — but Row only inspects its *direct*
            // children's `visible`, and every entry here loads behind this
            // Loader, whose own `visible` defaults true regardless of its
            // item's. A live `visible: entryLoader.item.visible` expression
            // binding here feeds back into the very `implicitWidth`/
            // `implicitHeight`/`_cellHeight` cycle the comment above
            // already flags as fragile (confirmed by reproducing it — a
            // sustained "Binding loop detected" storm that leaves the
            // entire bar unrendered, not just the one hidden widget), so
            // this mirrors the item's visible imperatively instead: one
            // assignment per real visibleChanged emission, never a tracked
            // dependency of the Loader's own binding graph.
            sourceComponent: entryLoader.modelData.kind === "builtin"
                ? bar._builtinComponents[entryLoader.modelData.name]
                : (entryLoader.modelData.module.type === "command" ? commandModuleComponent : qmlModuleComponent)
            onLoaded: {
                if (entryLoader.modelData.kind === "module")
                    entryLoader.item.module = entryLoader.modelData.module;
                entryLoader.visible = entryLoader.item.visible;
            }
            Connections {
                target: entryLoader.item
                function onVisibleChanged() {
                    entryLoader.visible = entryLoader.item.visible;
                }
            }
        }
    }

    Row {
        id: leftRegion
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.md

        Repeater {
            id: leftRepeater
            model: bar._layout.regions.left
            delegate: regionDelegate
        }
    }

    Rectangle {
        anchors.left: leftRegion.right
        anchors.leftMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.spacing.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: centerRegion
        anchors.centerIn: parent
        spacing: Theme.space.sm

        Repeater {
            id: centerRepeater
            model: bar._layout.regions.center
            delegate: regionDelegate
        }
    }

    Rectangle {
        anchors.right: rightRegion.left
        anchors.rightMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.spacing.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: rightRegion
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.sm

        Repeater {
            id: rightRepeater
            model: bar._layout.regions.right
            delegate: regionDelegate
        }
    }
}
