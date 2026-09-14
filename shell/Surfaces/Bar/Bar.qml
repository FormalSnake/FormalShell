import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Compositor
import qs.Core
import qs.Components
import qs.Plugins
import qs.Surfaces.Frame
import qs.Surfaces.Bar.widgets
import "../../Bar/layout.js" as Layout
import "../../Bar/panels.js" as Panels
import "../../Components/tooltip.js" as Placement

// The bar (DESIGN.md §3 Bar, spec §1, M6 Tasks 1+3, M8b Task 3 retrofit,
// M10 Task 3 settings-driven retrofit): three regions, left, center,
// right, each populated from `bar.layout` in settings.json (left/center/
// right arrays of widget names, resolved by ../../Bar/layout.js) rather
// than a fixed declaration order; an absent or partial `bar.layout` falls
// back region-by-region to exactly today's arrangement (launcher+workspaces
// +active window left, clock+now-playing center, battery/audio/network/
// bluetooth/weather/tray/bell/indicators right), so a user with no config
// sees no change.
// Layout entries name either a built-in widget (resolved against
// `_builtinComponents` below, each pre-wired with the panel/screen context
// only Bar.qml has), a `bar.modules[]` custom module via a "custom:<id>"
// name, `command` (CommandModule.qml, Waybar-JSON-compatible polled
// output) or `qml` (QmlModule.qml, a user-supplied file in a Loader), or a
// drop-in plugin from ~/.config/formalshell/plugins via a "plugin:<id>"
// name (PluginBarModule.qml). A kind:"bar" plugin the layout never names is
// appended to its own manifest region by layout.js, so a plugin directory
// is visible without a settings.json edit. An unknown widget name or a
// dangling module/plugin reference is dropped with a console warning, never
// a crash.
// One of those names, "chevron" (M24, ChevronWidget.qml), is a boundary
// rather than a readout: every entry on its governed side of the same region
// is drawn in that chevron's second bar (BarOverflow.qml) instead of on the
// strip, which layout.js hands over as a per-entry `collapsible` flag and the
// region delegate below gates on. Its position in bar.layout is the whole of
// its configuration. Which side it governs is the side away from the region's
// own anchored edge (M25, layout.js's governsBefore), so the chevron itself
// keeps its x whatever it is holding.
// The strip is one continuous surface (DESIGN.md §3 Bar, M47 D1): a
// full-length `card` fill at `theme.surfaceOpacity` with a 1px `border`
// along its inner edge, and nothing else. The cells inside are ghosts,
// so this is the only fill and the only border the bar draws; the owner
// ran the floating-pill version on both boxes and asked for the shadcn
// navbar instead (2026-08-25). Its thickness is the cell row plus a
// `barMargin` band either side, and that whole thickness is the exclusive
// zone, so a tiled window stops under the border rather than behind it.
// Which output edge it runs along is `bar.position` (Theme.barPosition):
// top by default, or bottom, left, right. On a left or right bar the same
// three regions run top to bottom (`left` at the top, `right` at the
// bottom), every region is a column, and each cell stacks its content
// upright down the strip rather than turning it (Cell.barEdge,
// Bar/layout.js's labelRotation); nothing about the layout keys changes.
PanelWindow {
    id: bar
    required property var modelData
    // shell.qml's single Menu instance, the launcher cell's summon target.
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
    property var trayOverflow: null
    // The chevron's second bar (Surfaces/Bar/BarOverflow.qml), shared by
    // every output like the tray's.
    property var barOverflow: null
    // The single Center instance (shell.qml's notificationsCenter), the
    // bell widget toggles it directly, same object NotificationsIpc drives.
    property var center: null
    // shell.qml's startup reveal gate. Everything about this window's
    // geometry is config-derived (its edge, its thickness, whether it is the
    // strip or the whole output), and `exclusionMode: Auto` publishes the
    // reservation off that geometry, so mapping before settings.json lands
    // means publishing a zone twice and reflowing every tiled window with it.
    // Unmapped reserves nothing, which is why a session now shifts its
    // windows once, when the bar arrives, instead of over and over.
    property bool ready: false
    screen: modelData
    // Hidden while a fullscreen window covers this output, so it reaches
    // Hyprland's solitary / direct-scanout path (see CompositorService).
    visible: bar.ready && !CompositorService.outputCoveredByFullscreen(bar.modelData.name)
    // The strip spans its own edge end to end and hugs that edge. With the
    // screen frame on the window is the whole output instead: it paints
    // the frame's ring, the strip included, and its cells over it, so the
    // three are one surface under the compositor's blur (two blurred
    // surfaces meeting edge to edge showed their join as a line down the
    // strip) and one surface above windows (a window a scrolling layout
    // pushes past the edge slides under the strip, and a ring painted on
    // a lower layer let it show through). Input then stays on the strip
    // alone (`mask` below) and the reservation moves to Frame.qml's zone
    // for this edge, since a window anchored on all four edges has no one
    // edge to reserve against.
    readonly property bool _framed: Theme.frameEnabled
    anchors {
        top: bar._framed || bar._position !== "bottom"
        bottom: bar._framed || bar._position !== "top"
        left: bar._framed || bar._position !== "right"
        right: bar._framed || bar._position !== "left"
    }
    // The reservation is this one property and never `exclusiveZone`:
    // quickshell's setter for that property also writes exclusionMode back
    // to Normal (WlrLayershell::setExclusiveZone), which kills the binding
    // here, and the pair then freezes at whatever the first evaluation
    // produced. A bar created before settings.json landed froze on the
    // default strip's own zone and a bar created after it froze on 0, and a
    // framed window with a zone of 0 is boxed by Frame.qml's zones instead
    // of covering the output: the whole ring, strip included, drew one bar
    // thickness in from the edge and off the far side (e1504g, 2026-08-26).
    // Auto reserves the strip's thickness off the window's own implicit
    // size, which is the same number the explicit zone used to carry.
    WlrLayershell.exclusionMode: bar._framed ? ExclusionMode.Ignore : ExclusionMode.Auto
    mask: bar._framed ? stripMask : null

    Region {
        id: stripMask
        x: stripArea.x
        y: stripArea.y
        width: stripArea.width
        height: stripArea.height
    }

    // What a compositor layer rule addresses this strip by: the shipped
    // Hyprland example (docs/examples/hyprland/formalshell.conf) blurs
    // `formalshell:bar` behind the translucent cells.
    WlrLayershell.namespace: "formalshell:bar"

    function _resolveLayout() {
        var result = Layout.resolve(Config.get("bar", null), PluginService.barPlugins);
        for (var i = 0; i < result.warnings.length; i++)
            console.warn("Bar:", result.warnings[i]);
        return result;
    }

    // Private and always fresh: layout.js's _resolveRegion() returns new
    // arrays on every call, tracking Config.settings and
    // PluginService.barPlugins the same as the old raw binding did. Only
    // `_layout` below controls whether that freshness reaches consumers.
    readonly property var _resolvedLayout: bar._resolveLayout()

    // Republished only when the resolved regions' JSON differs from the
    // last publish, so the three region Repeaters below (~:644, :669, :700)
    // keep their model identity, and with it hover/press state and any open
    // panel, across a Config republish or plugin rescan that didn't
    // actually change the layout. Same split as HyprlandBackend.qml's
    // workspaces/windows dedupe.
    property var _layout: ({ regions: { left: [], center: [], right: [] }, warnings: [] })
    property string _layoutRegionsJson: ""

    function _publishLayout() {
        var json = JSON.stringify(bar._resolvedLayout.regions);
        if (json === bar._layoutRegionsJson)
            return;
        bar._layoutRegionsJson = json;
        bar._layout = bar._resolvedLayout;
    }

    on_ResolvedLayoutChanged: bar._publishLayout()
    Component.onCompleted: {
        bar._publishLayout();
        PanelRegistry.addBar(bar);
    }
    Component.onDestruction: PanelRegistry.removeBar(bar)

    // Where a panel's own cell sits on this strip, for an open with no click
    // to read one off (M53 D5, PanelIpc's `toggle`/`toggleAt` from a
    // compositor keybind). Answers with the same screen-relative
    // {anchor, screen} shape Panel.openFrom() builds from a real cell, or
    // null when this bar has no cell for that panel on the strip: nothing in
    // bar.layout opens it, the widget hid itself (a Battery with no
    // battery), or a chevron holds it in the second bar, where there is
    // nothing along the strip to hang under. The anchorless open, the frame
    // at the end of the bar, is still the honest answer to all three.
    function panelAnchor(name) {
        var repeaters = [leftRepeater, centerRepeater, rightRepeater];
        for (var r = 0; r < repeaters.length; r++) {
            for (var i = 0; i < repeaters[r].count; i++) {
                var slot = repeaters[r].itemAt(i);
                if (!slot || !slot.visible || slot.modelData.collapsible)
                    continue;
                // Layout.entryName covers a bar plugin, whose cell and whose
                // panel are registered under the one "plugin:<id>" name; a
                // custom module resolves to a "custom:" name no panel can
                // carry, which is the drop it should be.
                var opens = slot.modelData.kind === "builtin"
                    ? Panels.WIDGET_PANELS[slot.modelData.name]
                    : Layout.entryName(slot.modelData);
                if (opens !== name)
                    continue;
                var centre = slot.mapToItem(null, slot.width / 2, slot.height / 2);
                var offset = Placement.windowOrigin(bar.anchors,
                    Qt.size(bar.width, bar.height),
                    Qt.size(bar.screen.width, bar.screen.height));
                return {
                    anchor: Qt.point(centre.x + offset.x, centre.y + offset.y),
                    screen: bar.screen
                };
            }
        }
        return null;
    }

    readonly property string _position: Theme.barPosition
    readonly property bool _vertical: Theme.barVertical
    readonly property var _strip: Layout.stripGeometry(Theme.space, bar._position)

    // The strip's own length: what the regions share out, and what a
    // cell's width cap is a fraction of.
    readonly property real _along: bar._vertical ? stripArea.height : stripArea.width

    // The card joined to THIS strip, if any (M54 D6, PanelRegistry.join): a
    // join on another output or against another edge is somebody else's.
    readonly property var _join: {
        var j = PanelRegistry.join;
        if (!j || j.edge !== bar._position)
            return null;
        return (bar.modelData && j.screen === bar.modelData.name) ? j : null;
    }

    // The gap itself: one card's rect plus the fillets' `reach` at either
    // end, which is exactly the span Components/Shoulders.qml draws into. A
    // pure function of the join, with no clock of its own: the join is read
    // off the card's live rect, which the card's own clocks already carry,
    // and a second clock here left the line lagging the shoulders it has to
    // meet. Closed, the two segments meet at the start and the line is
    // whole.
    readonly property real _gapStart: bar._join
        ? Math.max(0, Math.min(bar._along, bar._join.x - bar._join.reach))
        : 0
    readonly property real _gapEnd: bar._join
        ? Math.max(bar._gapStart, Math.min(bar._along, bar._join.x + bar._join.width + bar._join.reach))
        : 0

    // The inward line's two segments in this window's own coordinates, for
    // `debug dump` (Ipc/DebugIpc.qml): a rig leg reads the gap a joined card
    // opened off the shell's own numbers instead of hunting for it in
    // pixels. A framed bar draws no hairline at all (FrameRing carries that
    // edge), so this is empty there rather than reporting a hidden rect.
    function lineRects() {
        if (bar._framed)
            return [];
        return [bar._rectOf(hairlineStart), bar._rectOf(hairlineEnd)];
    }

    function _rectOf(item) {
        var origin = item.mapToItem(null, 0, 0);
        return { x: origin.x, y: origin.y, width: item.width, height: item.height };
    }

    // What the strip has left over once all three regions have taken their
    // natural extent, the two end insets and the gap either side of the
    // centre are paid for. Negative means the layout is already clipping
    // (the two end regions' own width caps below).
    //
    // The one cell that sizes itself to this reads it as a term to add to
    // its OWN extent (widgets/Tray.qml), never as a width: the sum here
    // includes that cell, so the two cancel and the budget it works out
    // cannot move when it resizes. Anything that instead took this as room
    // to grow into would be reading a number its own growth shrinks.
    readonly property real _slack: bar._along - bar._strip.edgeInset * 2 - Theme.space.sm * 2
        - (bar._vertical ? leftRail.implicitHeight : leftRail.implicitWidth)
        - (bar._vertical ? centerRegion.implicitHeight : centerRegion.implicitWidth)
        - (bar._vertical ? rightRail.implicitHeight : rightRail.implicitWidth)

    // Each visible child's along-axis extent on a rail, in the order
    // `Layout.fitExtent` should spend the room in: the region's own
    // anchored edge first. `reversed` is true for the right region, whose
    // rail is right/bottom-aligned within its box (rightRail's own `x`/`y`
    // below), so its LAST child sits nearest that anchored edge and its
    // first is the one nearest the centre. A hidden or not-yet-present
    // child (Tray's own toggle-only state, a widget still animating open
    // from nothing) reads 0 here and `fitExtent` already skips those, so
    // no separate filter is needed beyond `visible`.
    function _railExtents(rail, vertical, reversed) {
        var out = [];
        var kids = rail.children;
        for (var i = 0; i < kids.length; i++) {
            var child = kids[reversed ? kids.length - 1 - i : i];
            if (child.visible)
                out.push(vertical ? child.height : child.width);
        }
        return out;
    }

    readonly property var _leftExtents: bar._railExtents(leftRail, bar._vertical, false)
    readonly property var _rightExtents: bar._railExtents(rightRail, bar._vertical, true)
    readonly property var _centerExtents: bar._railExtents(centerRegion, bar._vertical, false)

    // The room each end region has before it runs into the centre, the same
    // arithmetic the two regions' own width/height below used to hand
    // straight to a `Math.min`. Kept as properties so `roomState()` can
    // report against the same numbers the regions actually draw with.
    readonly property real _leftRoom: bar._vertical
        ? Math.max(0, centerRegion.y - bar._strip.edgeInset - Theme.space.sm)
        : Math.max(0, centerRegion.x - bar._strip.edgeInset - Theme.space.sm)
    readonly property real _rightRoom: bar._vertical
        ? Math.max(0, bar._along - bar._strip.edgeInset - Theme.space.sm - centerRegion.y - centerRegion.height)
        : Math.max(0, bar._along - bar._strip.edgeInset - Theme.space.sm - centerRegion.x - centerRegion.width)

    readonly property var _leftFit: Layout.fitExtent(bar._leftExtents, Theme.space.sm, bar._leftRoom)
    readonly property var _rightFit: Layout.fitExtent(bar._rightExtents, Theme.space.sm, bar._rightRoom)

    // Every cell on a rail regardless of room, `fitExtent`'s own answer with
    // no ceiling: what `roomState()` calls a region's `cells`, against
    // which `_leftFit`/`_rightFit`'s count is how many of them actually fit.
    readonly property int _leftTotal: Layout.fitExtent(bar._leftExtents, Theme.space.sm, Number.POSITIVE_INFINITY).count
    readonly property int _rightTotal: Layout.fitExtent(bar._rightExtents, Theme.space.sm, Number.POSITIVE_INFINITY).count
    readonly property int _centerTotal: Layout.fitExtent(bar._centerExtents, Theme.space.sm, Number.POSITIVE_INFINITY).count

    // The loaded widget behind bar.layout's one "nowPlaying" entry, wherever
    // a user put it, or null with none configured. Walks `bar._layout`
    // itself, the same array each region's Repeater already binds as
    // `model`, rather than assuming a region: bar.layout is free to put the
    // entry anywhere, or nowhere.
    readonly property var _regionRepeaters: ({ left: leftRepeater, center: centerRepeater, right: rightRepeater })

    function _nowPlayingWidget() {
        for (var r = 0; r < Layout.REGIONS.length; r++) {
            var region = Layout.REGIONS[r];
            var entries = bar._layout.regions[region];
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].kind === "builtin" && entries[i].name === "nowPlaying") {
                    var slot = bar._regionRepeaters[region].itemAt(i);
                    return slot ? slot.loadedItem : null;
                }
            }
        }
        return null;
    }

    // `bar room` (Ipc/BarIpc.qml, spec D7/D9): the slack, each region's own
    // cell and hidden counts, and the now-playing cell's own label budget,
    // for this one bar. A hidden count of 0 across every run is the room
    // rule holding; the smoke leg crowds the strip until it isn't.
    function roomState() {
        var nowPlaying = bar._nowPlayingWidget();
        return {
            screen: bar.modelData ? bar.modelData.name : "",
            edge: bar._position,
            slack: bar._along > 0 ? bar._slack : 0,
            regions: {
                left: { cells: bar._leftTotal, hidden: bar._leftTotal - bar._leftFit.count },
                center: { cells: bar._centerTotal, hidden: 0 },
                right: { cells: bar._rightTotal, hidden: bar._rightTotal - bar._rightFit.count }
            },
            nowPlaying: {
                budget: nowPlaying ? nowPlaying.labelBudget : -1,
                natural: nowPlaying ? nowPlaying.naturalLabelWidth : 0
            }
        };
    }

    // One thickness for every cell in every region, so a widget with a
    // taller line of content can no longer drag the whole strip with it.
    readonly property real _cellThickness: bar._strip.cellThickness
    implicitHeight: bar._vertical || bar._framed ? 0 : bar._strip.thickness
    implicitWidth: bar._vertical && !bar._framed ? bar._strip.thickness : 0
    // The window is the strip exactly, so the fill below covers it edge to
    // edge; this only decides what is behind that fill's own alpha.
    color: "transparent"


    // Every surface that has to clear the bar (panels, toasts, the center,
    // the console) reads this, through Theme.edgeInset: Wayland gives
    // clients no cross-window geometry, so the strip publishes its own
    // occupied edge.
    Binding {
        target: Theme
        property: "barThickness"
        value: bar._strip.thickness
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
            maxWidth: Math.min(bar._along * 0.25, Theme.space.popupWidthWide)
            // Gates the title marquee off while the bar's own PanelWindow
            // isn't on screen, same rationale as NowPlaying's own
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
            // The widget's own default cap, scaled down on a strip too
            // short to afford it: a vertical bar is a third of a wide
            // bar's length. `maxWidth` itself is the widget's own, worked
            // out against this cap and `slackAlong` below (M55 D7); binding
            // straight to it would fight the widget's own assignment.
            stripCap: Math.min(220, bar._along * 0.15)
            // The now-playing cell gives ground before an end region loses
            // a whole cell (M55 D7): the same room the tray reads
            // (`_slack` above), infinite until the strip has a measured
            // length of its own.
            slackAlong: bar._along > 0 ? bar._slack : Number.POSITIVE_INFINITY
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
            overflow: bar.trayOverflow
            // What the strip can still afford. The tray is the one region
            // cell with an unbounded item count, so it is the one that gives
            // ground when the bar runs out of edge; what it drops opens in
            // the second bar instead (TrayOverflow.qml).
            //
            // Infinity until the strip has a length of its own: every term
            // of `_slack` is measured off a window that does not exist for
            // the first frames, and a budget worked out against a zero-length
            // strip is not a tight one, it is no answer. The tray waits for a
            // real number rather than painting a guess.
            slackAlong: bar._along > 0 ? bar._slack : Number.POSITIVE_INFINITY
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
            overflow: bar.barOverflow
            // The delegate its second bar builds the group from, which is the
            // same one this strip uses: a Component carries its creation
            // context, so an entry instantiated over there still resolves the
            // panels and screen wired up here.
            entryDelegate: regionDelegate
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
        Item {
            id: entrySlot
            required property var modelData
            // A hidden widget (Battery with no laptop battery, NowPlaying
            // with no player, Tray with no items, Indicators with nothing
            // active) sets `visible: false` on itself expecting the Rail to
            // drop its slot entirely, but a positioner only inspects its
            // *direct* children's `visible`, and every entry here loads
            // behind the Loader below, whose own `visible` defaults true
            // regardless of its item's. Binding straight to
            // `entryLoader.item.visible` looks right and even renders right
            // once, but permanently kills that *same* item's own `visible`
            // binding from ever updating again (confirmed by reproducing it
            // in isolation, reading a Loader-hosted item's built-in
            // `visible` from an external binding, declarative or imperative,
            // silently detaches the item's own visible binding the moment
            // it's read this way; a property under any other name doesn't
            // have this problem). Each conditionally-hidden widget therefore
            // exposes its condition a second time under `shown` (Tray/
            // Indicators/Battery/NowPlaying) instead of `visible` itself; a
            // widget with no such property is always shown, so `true` is the
            // safe fallback rather than ever reading `.visible` here.
            readonly property bool _shown: entryLoader.item
                ? (entryLoader.item.shown !== undefined ? entryLoader.item.shown : true)
                : false

            // M52: a governed entry is not on the strip at all. Everything
            // on a chevron's governed side is drawn in that chevron's second
            // bar (BarOverflow.qml), the way the tray lives behind its own
            // dots, so `collapsible` is not a state here any more, it is a
            // statement about where the entry is drawn. `shown` stays the
            // widget's own statement about itself (a Battery with no
            // battery), never written from here, which would put two authors
            // on one property.
            readonly property bool _present: entrySlot._shown && !entrySlot.modelData.collapsible

            // The loaded widget itself, `bar._nowPlayingWidget()`'s own way
            // in past the Loader: an external id can't reach `entryLoader`
            // from outside this Component, so the slot hands its own load
            // out under a name that can.
            readonly property var loadedItem: entryLoader.item

            // Whether this slot may animate anything at all, asked of the
            // strip it landed in rather than of the bar. The same delegate
            // draws the cells of the chevron's second bar and of the tray's
            // (BarOverflow.qml, TrayOverflow.qml), where `bar` is still this
            // window but the surface arriving is the card, not the strip:
            // those rails hold `animate` false until their card has finished
            // opening, so a card opens with its cells already measured and
            // in place. A Repeater parents its delegates to the Repeater's
            // own parent, which is a Rail in all four places this delegate is
            // used.
            readonly property bool _animate: bar._revealed
                && !!entrySlot.parent && entrySlot.parent.animate !== false

            // The cell's own presence (DESIGN.md §1 Motion, M53 D2): a
            // widget that turns on opens its slot along the strip and fades
            // up in it, one that turns off shrinks and fades out, and the
            // Rail's `move` carries the cells beside it either way. Two
            // terms, since the slot is geometry and the ink in it is not
            // (M54 D2): the length runs `spatial` and springs a little past
            // the cell's own measurement before it settles, the fade runs
            // `effects` and lands well before it. Held flat until the
            // strip's entrance has settled (`_animate` above, the same arm
            // switch the cells' own width Behaviors take), so a session's
            // first second of service answers is one layout rather than a
            // dozen cells opening in sequence behind it.
            property real _progress: entrySlot._present ? 1 : 0
            property real _fade: entrySlot._present ? 1 : 0

            Behavior on _progress {
                enabled: entrySlot._animate
                Anim {}
            }

            Behavior on _fade {
                enabled: entrySlot._animate
                Anim { kind: "effects" }
            }

            // Every entry is the bar's own cell thickness across the strip,
            // and its own length along it, whichever axis each of those is
            // on this bar. Only this slot takes the presence term: the
            // Loader below keeps the item at its full implicit size, so
            // nothing an animation writes ever reaches what the item
            // measures.
            readonly property real _implicitAlong: bar._vertical ? entryLoader.implicitHeight : entryLoader.implicitWidth
            width: bar._vertical ? bar._cellThickness : entrySlot._implicitAlong * entrySlot._progress
            height: bar._vertical ? entrySlot._implicitAlong * entrySlot._progress : bar._cellThickness
            // Only while the slot is shorter than what it holds, so a
            // settled cell costs no clip node.
            clip: entrySlot._progress < 1

            // The presence driver and nothing measured, which is the whole
            // point: a `visible` that reads a width closes a cycle for an
            // entry whose extent is a MEASUREMENT rather than a fixed
            // number, and once that measurement has been 0 with the binding
            // holding the entry hidden, nothing ever produces the width that
            // would reopen it. It bit exactly the widgets that are empty at
            // creation and gain content later, Indicators when its first
            // glyph turns on and Tray registering its first item, and never
            // the ones with content from the start. It escaped notice for
            // the same reason: the indicators row's ONE cell with a live
            // label, the reminder countdown, re-measures itself out of the
            // deadlock every second and drags the rest of the row open
            // behind it, so a live screen recording and a stay-awake toggle
            // were invisible on their own but both appeared beside a pending
            // reminder (g815, 2026-08-19).
            // tests/tst_bar_entry_reveal.qml pins both halves of that.
            visible: entrySlot._present || entrySlot._progress > 0

            Loader {
                id: entryLoader
                width: bar._vertical ? bar._cellThickness : entrySlot._implicitAlong
                height: bar._vertical ? entrySlot._implicitAlong : bar._cellThickness
                // The fade lives here rather than on the slot: the Rail's
                // `add` transition writes the slot's own opacity, and an
                // animation writing a property drops whatever binding held
                // it.
                opacity: entrySlot._fade
                sourceComponent: {
                    switch (entrySlot.modelData.kind) {
                    case "builtin": return bar._builtinComponents[entrySlot.modelData.name];
                    case "plugin": return pluginModuleComponent;
                    }
                    return entrySlot.modelData.module.type === "command" ? commandModuleComponent : qmlModuleComponent;
                }
                onLoaded: {
                    // The one seam that makes every cell in the bar a ghost
                    // (DESIGN.md §3 Bar) and tells it which edge it sits on:
                    // each widget's root is either a `Cell`, which carries both
                    // properties itself, or one of the two group rails (Tray,
                    // Indicators), which forward them to the cells they hold.
                    // Set here rather than in the 25 registry Components above,
                    // so a new widget joins the strip by being listed.
                    entryLoader.item.ghost = true;
                    // A binding, not a value: settings.json lands after the
                    // first cells exist, and whether this Repeater resets
                    // before or after Theme.barPosition moves is not ordered,
                    // so a cell created against the default edge has to follow
                    // the bar to its real one.
                    entryLoader.item.barEdge = Qt.binding(function () { return bar._position; });
                    // Both guarded, unlike the two above, and between them
                    // they cover every widget root: `animateSize` is Cell's
                    // width Behavior, `animate` the `move` a Rail runs over
                    // the cells it holds, and the two group rails (Tray,
                    // Indicators) are the one widget kind rooted in the
                    // second rather than the first.
                    if (entryLoader.item.animateSize !== undefined)
                        entryLoader.item.animateSize = Qt.binding(function () { return entrySlot._animate; });
                    if (entryLoader.item.animate !== undefined)
                        entryLoader.item.animate = Qt.binding(function () { return entrySlot._animate; });
                    if (entrySlot.modelData.kind === "module")
                        entryLoader.item.module = entrySlot.modelData.module;
                    else if (entrySlot.modelData.kind === "plugin")
                        entryLoader.item.plugin = entrySlot.modelData.plugin;
                    else if (entrySlot.modelData.name === "chevron") {
                        entryLoader.item.region = entrySlot.modelData.region;
                        entryLoader.item.regionEntries = bar._layout.regions[entrySlot.modelData.region];
                    }
                }
            }
        }
    }

    // The strip's own entrance (DESIGN.md §1 Motion, M51 D2's grammar): the
    // window maps at its final geometry and the strip fades up behind it, so
    // the one reflow the map costs lands under a deliberate movement rather
    // than as a jump. The fade alone: Presence's own zoom is anchored to the
    // bar's edge and a scale on a surface as wide as the output pulls both
    // ends ~30px in, which reads as the bar being the wrong length rather
    // than as depth.
    Presence {
        id: presence
        open: bar.ready
        edge: bar._position
    }

    // Cells arm their own width Behaviors off this (Components/Cell.qml's
    // `animateSize`, pushed by the region delegate above). Held false until
    // the entrance above has settled, so the async service answers landing
    // over a session's first second (a battery percentage, a weather poll, a
    // now-playing title) join the layout the strip arrives with instead of
    // gliding twelve cells open one at a time behind it.
    readonly property bool _revealed: presence.open && presence.settled

    // The frame's ring (Surfaces/Frame/FrameRing.qml), behind the strip
    // and only while the window is the whole output.
    FrameRing {
        anchors.fill: parent
        visible: bar._framed
        edge: bar._position
        gapStart: bar._gapStart
        gapEnd: bar._gapEnd
    }

    // The strip: the whole window on its own, or the bar's edge of a
    // window that is the whole output. Everything the bar draws and lays
    // out lives in here, so nothing below has to know which of the two the
    // window is.
    Item {
        id: stripArea
        x: bar._framed && bar._position === "right" ? parent.width - bar._strip.thickness : 0
        y: bar._framed && bar._position === "bottom" ? parent.height - bar._strip.thickness : 0
        width: bar._framed && bar._vertical ? bar._strip.thickness : parent.width
        height: bar._framed && !bar._vertical ? bar._strip.thickness : parent.height

        opacity: presence.opacity

        // Declared before the regions, so it stacks behind every cell. With the
        // screen frame on, the ring below already paints the strip as part of
        // itself, so this fill is off and only the cells draw here.
        Rectangle {
            anchors.fill: parent
            visible: !bar._framed
            color: Theme.surface(Theme.color.card)

            // The hairline that separates the strip from the desktop, and the
            // only edge the bar draws: the one facing inward. A `border` on the
            // fill above would ring all four sides, three of which are the
            // screen's own edges. With the screen frame on, the frame's own
            // stroke runs this side too, round the corners into its band, and
            // this whole fill is off.
            //
            // Two segments rather than one (M54 D6): a card joined to the bar
            // opens a gap between them, its own rect plus a fillet's radius at
            // either end, and Components/Shoulders.qml draws the card's
            // concave shoulders into exactly that span, so the line runs into
            // the card instead of under it. The gap follows the join frame by
            // frame (see `_gapStart`) and is simply gone when none exists,
            // which is what leaves an ordinary session's line whole and still.
            Rectangle {
                id: hairlineStart
                width: bar._vertical ? Theme.borderWidth : bar._gapStart
                height: bar._vertical ? bar._gapStart : Theme.borderWidth
                x: bar._position === "left" ? parent.width - hairlineStart.width : 0
                y: bar._position === "top" ? parent.height - Theme.borderWidth : 0
                color: Theme.color.border
            }

            Rectangle {
                id: hairlineEnd
                width: bar._vertical ? Theme.borderWidth : Math.max(0, parent.width - bar._gapEnd)
                height: bar._vertical ? Math.max(0, parent.height - bar._gapEnd) : Theme.borderWidth
                x: bar._position === "left" ? parent.width - hairlineEnd.width : (bar._vertical ? 0 : bar._gapEnd)
                y: bar._position === "top" ? parent.height - Theme.borderWidth : (bar._vertical ? bar._gapEnd : 0)
                color: Theme.color.border
            }
        }

        // The three regions, each a Rail (a Row that stands up with the bar).
        // On a horizontal bar they sit `edgeInset` in from the left and right
        // ends and `cellInset` down from the top; on a vertical one the same
        // three run top to bottom, `edgeInset` in from the top and bottom ends
        // and `cellInset` in from the strip's outer edge. `left` is the start
        // of the strip and `right` its end whichever way it runs.
        //
        // Room along the strip is shared in a fixed order (DESIGN.md §3 Bar,
        // spec D7). The now-playing cell gives ground first, on its own
        // (widgets/NowPlaying.qml's `_refit`, fed the same `_slack` the tray
        // reads below): its label shrinks before anything else on the strip
        // moves. The centre sits at the middle while it can, and slides
        // toward the shorter end once the two end regions together with it
        // outgrow the strip, the start region winning over the end one, same
        // as before. What still does not fit past that clamp hides WHOLE
        // cells rather than clipping into one: an end region's own extent is
        // `Layout.fitExtent` over its rail's visible children (`_leftFit`/
        // `_rightFit` above), taken from the region's own anchored edge
        // inward, so the cap always lands on a cell boundary and the hidden
        // cell is always the one nearest the centre, never the one against
        // the screen edge. A cell comes back the moment the room does. The
        // chevron is unrelated to any of this: still config-only, still
        // collapsing whatever bar.layout put on its governed side, whether
        // the strip is crowded or not.
        //
        // Placed by x/y rather than anchors on purpose: the edge can change
        // while the regions exist (settings.json lands after the first frame),
        // and rebinding `anchors.top` to undefined and `anchors.bottom` to the
        // parent in the same pass leaves a moment where both hold, the anchor
        // system writes the height itself, and Qt 6 drops the QML binding on
        // that write, which left the end region stuck at a negative height
        // (VM, 2026-08-26).
        Item {
            id: leftRegion
            x: bar._vertical ? bar._strip.cellInset : bar._strip.edgeInset
            y: bar._vertical ? bar._strip.edgeInset : bar._strip.cellInset
            clip: true
            // Capped to `_leftFit`'s own answer, never to the raw room
            // before centerRegion directly: that raw number can land inside
            // a cell (custom command/qml modules have no fixed count), and
            // `fitExtent` is what snaps it back to the nearest cell boundary
            // behind it.
            width: bar._vertical ? leftRail.implicitWidth : bar._leftFit.extent
            height: bar._vertical ? bar._leftFit.extent : leftRail.implicitHeight

            // The start region is pinned to the strip's own start, so only
            // its far edge moves when a cell inside it opens or closes: the
            // clip travels with the rail instead of stepping to the new
            // extent in one frame while the cells behind it glide (M54 D10).
            // Both axes, since which one the region runs along is the bar's
            // edge.
            Behavior on width {
                enabled: bar._revealed
                Anim {}
            }

            Behavior on height {
                enabled: bar._revealed
                Anim {}
            }

            Rail {
                id: leftRail
                vertical: bar._vertical
                spacing: Theme.space.sm

                Repeater {
                    id: leftRepeater
                    model: bar._layout.regions.left
                    delegate: regionDelegate
                }
            }
        }

        Rail {
            id: centerRegion
            vertical: bar._vertical
            // The start region's natural extent plus a gap is the least the
            // centre can be pushed to; the end region's is the most.
            readonly property real _floor: bar._strip.edgeInset + Theme.space.sm
                + (bar._vertical ? leftRail.implicitHeight : leftRail.implicitWidth)
            readonly property real _ceiling: (bar._vertical ? parent.height : parent.width) - bar._strip.edgeInset
                - Theme.space.sm - (bar._vertical ? rightRail.implicitHeight : rightRail.implicitWidth)
                - (bar._vertical ? centerRegion.height : centerRegion.width)
            readonly property real _middle: ((bar._vertical ? parent.height : parent.width)
                - (bar._vertical ? centerRegion.height : centerRegion.width)) / 2
            readonly property real _along: Math.max(centerRegion._floor, Math.min(centerRegion._middle, centerRegion._ceiling))
            x: bar._vertical ? bar._strip.cellInset : centerRegion._along
            y: bar._vertical ? centerRegion._along : bar._strip.cellInset
            spacing: Theme.space.sm

            // The clamp above re-decides where the centre sits every time a
            // cell either side of it changes extent, so the region travels
            // to the answer instead of arriving at it (DESIGN.md §1 Motion,
            // M53 D2). The binding is untouched: a Behavior animates the
            // value the binding produces. Both axes, since which one the
            // clamp runs along is the bar's edge.
            Behavior on x {
                enabled: bar._revealed
                Anim {}
            }

            Behavior on y {
                enabled: bar._revealed
                Anim {}
            }

            Repeater {
                id: centerRepeater
                model: bar._layout.regions.center
                delegate: regionDelegate
            }
        }

        Item {
            id: rightRegion
            x: bar._vertical ? bar._strip.cellInset : parent.width - bar._strip.edgeInset - rightRegion.width
            y: bar._vertical ? parent.height - bar._strip.edgeInset - rightRegion.height : bar._strip.cellInset
            clip: true
            // Mirror of leftRegion's cap, `_rightFit` rather than `_leftFit`:
            // never draws back past centerRegion's far edge, regardless of
            // how many built-ins plus custom modules settings.json's
            // bar.layout.right names, and always on a cell boundary.
            width: bar._vertical ? rightRail.implicitWidth : bar._rightFit.extent
            height: bar._vertical ? bar._rightFit.extent : rightRail.implicitHeight

            // The end region is placed off its own extent, so a cell opening
            // or closing inside it moves the whole box: the box travels and
            // the strip's end stays put, rather than every cell in the
            // region jumping a slot (M53 D2).
            Behavior on x {
                enabled: bar._revealed
                Anim {}
            }

            Behavior on y {
                enabled: bar._revealed
                Anim {}
            }

            Behavior on width {
                enabled: bar._revealed
                Anim {}
            }

            Behavior on height {
                enabled: bar._revealed
                Anim {}
            }

            // Held against the region's own end, so what the clip removes is
            // the start of the rail, on the centre's side. The offset rides
            // the same clock the box does, so the rail keeps its grip on
            // that end through the travel instead of sliding inside the clip.
            Rail {
                id: rightRail
                vertical: bar._vertical
                x: bar._vertical ? 0 : rightRegion.width - rightRail.width
                y: bar._vertical ? rightRegion.height - rightRail.height : 0
                spacing: Theme.space.sm

                Behavior on x {
                    enabled: bar._revealed
                    Anim {}
                }

                Behavior on y {
                    enabled: bar._revealed
                    Anim {}
                }

                Repeater {
                    id: rightRepeater
                    model: bar._layout.regions.right
                    delegate: regionDelegate
                }
            }
        }
    }
}
