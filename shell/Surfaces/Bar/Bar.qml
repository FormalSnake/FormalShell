import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Core
// Aliased alongside the unqualified import above, the idiom CalendarPanel.qml
// documents: QtQuick exports its own type named State (the property-binding
// one), so a bare `State.barCollapsed` in the collapse gate below reads back
// undefined at runtime and every governed cell stays hidden forever, with no
// binding ever re-evaluating. Theme/Config carry no such collision and stay
// unqualified.
import qs.Core as Core
import qs.Plugins
import qs.Surfaces.Bar.widgets
import "../../Bar/layout.js" as Layout

// The bar (DESIGN.md §3 Bar, spec §1, M6 Tasks 1+3, M8b Task 3 retrofit,
// M10 Task 3 settings-driven retrofit): three regions — left, center,
// right — each populated from `bar.layout` in settings.json (left/center/
// right arrays of widget names, resolved by ../../Bar/layout.js) rather
// than a fixed declaration order; an absent or partial `bar.layout` falls
// back region-by-region to exactly today's arrangement (launcher+workspaces
// +active window left, clock+now-playing center, battery/audio/network/
// bluetooth/weather/tray/bell/indicators right), so a user with no config
// sees no change.
// Layout entries name either a built-in widget (resolved against
// `_builtinComponents` below, each pre-wired with the panel/screen context
// only Bar.qml has), a `bar.modules[]` custom module via a "custom:<id>"
// name — `command` (CommandModule.qml, Waybar-JSON-compatible polled
// output) or `qml` (QmlModule.qml, a user-supplied file in a Loader), or a
// drop-in plugin from ~/.config/formalshell/plugins via a "plugin:<id>"
// name (PluginBarModule.qml). A kind:"bar" plugin the layout never names is
// appended to its own manifest region by layout.js, so a plugin directory
// is visible without a settings.json edit. An unknown widget name or a
// dangling module/plugin reference is dropped with a console warning, never
// a crash.
// One of those names, "chevron" (M24, ChevronWidget.qml), is a collapse
// boundary rather than a readout: every entry on its governed side of the
// same region hides behind it, which layout.js hands over as a per-entry
// `collapsible` flag and the region delegate below gates on. Its position in
// bar.layout is the whole of its configuration. Which side it governs is the
// side away from the region's own anchored edge (M25, layout.js's
// governsBefore), so the reveal grows into empty bar and the chevron itself
// keeps its x.
// Every widget cell is a `standalone` Cell (DESIGN.md §3):
// borderless at rest, hover-cursor fill+border only on
// mouseover, separated from its neighbor by a small gap plus its own
// padding — omarchy's discrete-module bar, not the M1-M3 fused ledger
// strip this surface used to be. The region-boundary rules (left|center,
// center|right, the bar's own bottom edge) stay: they mark a structural
// region boundary the spec already committed to, not the per-widget
// rule-sharing this task retired.
PanelWindow {
    id: bar
    required property var modelData
    // shell.qml's single Menu instance — the launcher cell's summon target.
    property var menu: null
    property var appMenuPanel: null
    property var audioPanel: null
    property var calendarPanel: null
    property var networkPanel: null
    property var bluetoothPanel: null
    property var airpodsPanel: null
    property var dualsensePanel: null
    property var powerPanel: null
    property var weatherPanel: null
    property var mediaPanel: null
    property var githubPanel: null
    property var usagePanel: null
    property var tailscalePanel: null
    property var systemUpdatePanel: null
    property var displayPanel: null
    property var monitorPanel: null
    property var trayMenu: null
    // The single Center instance (shell.qml's notificationsCenter) — the
    // bell widget toggles it directly, same object NotificationsIpc drives.
    property var center: null
    screen: modelData
    anchors { top: true; left: true; right: true }

    function _resolveLayout() {
        var result = Layout.resolve(Config.get("bar", null), PluginService.barPlugins);
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
        id: launcherComponent
        LauncherWidget {
            menu: bar.menu
        }
    }
    Component {
        id: workspacesComponent
        Workspaces {
            outputName: bar.screen ? bar.screen.name : ""
        }
    }
    Component {
        id: activeWindowComponent
        ActiveWindow {
            panel: bar.appMenuPanel
            // A quarter of the bar under a hard px ceiling. The previous
            // flat 40% handed this one cell over a thousand pixels of a
            // wide display before the title's marquee engaged at all, so
            // "the title is too long" was the cap, not the marquee.
            maxWidth: Math.min(bar.width * 0.25, Theme.space.popupWidthWide)
            // Gates the title marquee off while the bar's own PanelWindow
            // isn't on screen — same rationale as NowPlaying's own
            // windowVisible below.
            windowVisible: bar.visible
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
            // M16 Task 11: gates the marquee off while the bar's own
            // PanelWindow isn't on screen.
            windowVisible: bar.visible
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
        id: airpodsComponent
        AirpodsWidget {
            panel: bar.airpodsPanel
        }
    }
    Component {
        id: dualsenseComponent
        DualsenseWidget {
            panel: bar.dualsensePanel
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
            menu: bar.trayMenu
        }
    }
    Component {
        id: githubComponent
        GithubWidget {
            panel: bar.githubPanel
        }
    }
    Component {
        id: usageComponent
        UsageWidget {
            panel: bar.usagePanel
        }
    }
    Component {
        id: tailscaleComponent
        TailscaleWidget {
            panel: bar.tailscalePanel
        }
    }
    Component {
        id: visualizerComponent
        Visualizer {
            // M16 Task 11's gate idiom, reused for VisualizerService's
            // shared cava process: registers this bar's on-screen state
            // rather than gating any local animation.
            windowVisible: bar.visible
        }
    }
    Component {
        id: bellComponent
        BellWidget {
            center: bar.center
        }
    }
    Component {
        id: indicatorsComponent
        Indicators {
        }
    }
    Component {
        id: microphoneComponent
        MicWidget {
            // M26 Task 9: middle click opens the audio panel, since the mic
            // has no panel of its own.
            panel: bar.audioPanel
        }
    }
    Component {
        id: keyboardLayoutComponent
        KeyboardLayoutWidget {
        }
    }
    Component {
        id: systemUpdateComponent
        SystemUpdateWidget {
            panel: bar.systemUpdatePanel
        }
    }
    Component {
        id: chevronComponent
        ChevronWidget {
        }
    }
    Component {
        id: displayComponent
        DisplayWidget {
            panel: bar.displayPanel
        }
    }
    Component {
        id: monitorComponent
        MonitorWidget {
            panel: bar.monitorPanel
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
    Component {
        id: pluginModuleComponent
        PluginBarModule {
        }
    }

    readonly property var _builtinComponents: ({
        launcher: launcherComponent,
        workspaces: workspacesComponent,
        activeWindow: activeWindowComponent,
        clock: clockComponent,
        nowPlaying: nowPlayingComponent,
        battery: batteryComponent,
        audio: audioComponent,
        network: networkComponent,
        bluetooth: bluetoothComponent,
        airpods: airpodsComponent,
        dualsense: dualsenseComponent,
        weather: weatherComponent,
        tray: trayComponent,
        github: githubComponent,
        usage: usageComponent,
        tailscale: tailscaleComponent,
        visualizer: visualizerComponent,
        bell: bellComponent,
        indicators: indicatorsComponent,
        microphone: microphoneComponent,
        keyboardLayout: keyboardLayoutComponent,
        systemUpdate: systemUpdateComponent,
        chevron: chevronComponent,
        display: displayComponent,
        monitor: monitorComponent
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
            // item's. Binding straight to `entryLoader.item.visible` looks
            // right and even renders right once, but permanently kills that
            // *same* item's own `visible` binding from ever updating again
            // (confirmed by reproducing it in isolation — reading a
            // Loader-hosted item's built-in `visible` from an external
            // binding, declarative or imperative, silently detaches the
            // item's own visible binding the moment it's read this way; a
            // property under any other name doesn't have this problem).
            // Each conditionally-hidden widget therefore exposes its
            // condition a second time under `shown` (Tray/Indicators/
            // Battery/NowPlaying) instead of `visible` itself; a widget with
            // no such property is always shown, so `true` is the safe
            // fallback rather than ever reading `.visible` here. `shown`
            // stays the outer term below, so a widget that hides itself stays
            // hidden whether the region's chevron is open or shut.
            sourceComponent: {
                switch (entryLoader.modelData.kind) {
                case "builtin": return bar._builtinComponents[entryLoader.modelData.name];
                case "plugin": return pluginModuleComponent;
                }
                return entryLoader.modelData.module.type === "command" ? commandModuleComponent : qmlModuleComponent;
            }
            // M24's collapse gate, driving the Loader's OWN width below
            // rather than a second thing routed through `shown`: `shown` is
            // the widget's statement about itself (a Battery with no battery),
            // and writing into it from here would put two authors on one
            // property. `collapsible` is layout.js's per-entry annotation
            // (true for every entry on the governed side of a chevron in the
            // same region), so a layout with no chevron leaves this term
            // false everywhere and the width below stays exactly what the
            // Loader would have sized itself to anyway.
            readonly property bool _collapsedAway: {
                if (!entryLoader.modelData.collapsible)
                    return false;
                var stored = Core.State.barCollapsed;
                return !stored || stored[entryLoader.modelData.region] !== false;
            }

            // M25: the governed group glides open and shut instead of
            // appearing in one frame. A collapsed entry animates to width 0,
            // and `clip` holds the cell's own content inside whatever width
            // the animation has reached. The Loader resizes its item to the
            // width it is given, so the cell wipes from its outer edge rather
            // than redrawing its content at every step.
            clip: true
            width: entryLoader.modelData.collapsible
                ? (entryLoader._collapsedAway ? 0 : entryLoader.implicitWidth)
                : entryLoader.implicitWidth
            // Governed entries only. Every other cell keeps the instant width
            // tracking it has always had, so a title rename or a battery tick
            // never gains motion it didn't ask for. Theme.motion.standard is
            // already 0 when motion is disabled (Theme/tokens.js's
            // motionTokens) and a zero-duration animation lands on the same
            // end state, so honoring that setting needs no branch here.
            Behavior on width {
                enabled: entryLoader.modelData.collapsible
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }
            readonly property bool _shown: entryLoader.item
                ? (entryLoader.item.shown !== undefined ? entryLoader.item.shown : true)
                : false
            // The width term is the chevron's, and it applies to governed
            // entries only. Row lays out (and spaces) its visible children,
            // so a cell that went invisible the moment the chevron shut
            // would have nothing left to animate, while one left visible at
            // width 0 would still be charged the region's own `spacing`, and
            // six of those is ~48px of dead bar. Width crossing 0 is the one
            // moment both are true at once.
            //
            // It must NOT apply to everything else, because for an entry
            // whose width is a MEASUREMENT rather than the chevron's own
            // number it closes a cycle: visible reads width, width reads the
            // item's implicitWidth, and once that measurement has been 0 with
            // this binding holding the entry hidden, nothing ever produces
            // the width that would reopen it. It bites exactly the widgets
            // that are empty at creation and gain content later — Indicators
            // when its first glyph turns on, Tray registering its first item
            // — and never the ones with content from the start, which is why
            // the chevron's own collapse/expand has always worked. It
            // escaped notice for the same reason: the indicators row's ONE
            // cell with a live label, the reminder countdown, re-measures
            // itself out of the deadlock every second and drags the rest of
            // the row open behind it, so a live screen recording and a
            // stay-awake toggle were invisible on their own but both
            // appeared beside a pending reminder (g815, 2026-08-19).
            // tests/tst_bar_entry_reveal.qml pins both halves of that.
            visible: entryLoader._shown
                && (!entryLoader.modelData.collapsible || entryLoader.width > 0)
            onLoaded: {
                if (entryLoader.modelData.kind === "module")
                    entryLoader.item.module = entryLoader.modelData.module;
                else if (entryLoader.modelData.kind === "plugin")
                    entryLoader.item.plugin = entryLoader.modelData.plugin;
                else if (entryLoader.modelData.name === "chevron") {
                    entryLoader.item.region = entryLoader.modelData.region;
                    entryLoader.item.regionEntries = bar._layout.regions[entryLoader.modelData.region];
                }
            }
        }
    }

    Row {
        id: leftRegion
        anchors.left: parent.left
        anchors.leftMargin: Theme.space.lg
        anchors.verticalCenter: parent.verticalCenter
        // Widget gap unified with center/right (M16 Task 1) — was the
        // legacy fixed scale's 8px "md" step; tightens to match the other
        // two regions' Theme.space.sm. Bumped to `lg` (M20 Task 1) so
        // widget-to-widget separation stays 2x the intra-cluster gap
        // (DESIGN.md §1.3's spacing law) now that pills within a cluster
        // (workspaces) sit `sm` apart.
        spacing: Theme.space.lg
        clip: true
        // A settings-driven left region can outgrow the gap before the
        // center region (custom command/qml modules have no fixed count) —
        // capped to whatever space actually remains left of centerRegion.x
        // so overflow clips here instead of drawing over the clock.
        width: Math.min(implicitWidth, Math.max(0, centerRegion.x - 2 * Theme.space.lg - Theme.borderWidth))

        Repeater {
            id: leftRepeater
            model: bar._layout.regions.left
            delegate: regionDelegate
        }
    }

    Rectangle {
        anchors.left: leftRegion.right
        anchors.leftMargin: Theme.space.lg
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.space.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: centerRegion
        anchors.centerIn: parent
        spacing: Theme.space.lg

        Repeater {
            id: centerRepeater
            model: bar._layout.regions.center
            delegate: regionDelegate
        }
    }

    Rectangle {
        anchors.right: rightRegion.left
        anchors.rightMargin: Theme.space.lg
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: parent.height - Theme.space.sm * 2
        color: Theme.color.rule
    }

    Row {
        id: rightRegion
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.lg
        clip: true
        // Mirror of leftRegion's cap: never draws left past centerRegion's
        // right edge, regardless of how many built-ins plus custom modules
        // settings.json's bar.layout.right names.
        width: Math.min(implicitWidth, Math.max(0, bar.width - 2 * Theme.space.lg - Theme.borderWidth - centerRegion.x - centerRegion.width))

        Repeater {
            id: rightRepeater
            model: bar._layout.regions.right
            delegate: regionDelegate
        }
    }
}
