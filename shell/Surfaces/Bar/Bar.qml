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
import qs.Components
import qs.Plugins
import qs.Surfaces.Frame
import qs.Surfaces.Bar.widgets
import "../../Bar/layout.js" as Layout

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
// One of those names, "chevron" (M24, ChevronWidget.qml), is a collapse
// boundary rather than a readout: every entry on its governed side of the
// same region hides behind it, which layout.js hands over as a per-entry
// `collapsible` flag and the region delegate below gates on. Its position in
// bar.layout is the whole of its configuration. Which side it governs is the
// side away from the region's own anchored edge (M25, layout.js's
// governsBefore), so the reveal grows into empty bar and the chevron itself
// keeps its x.
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
    // The single Center instance (shell.qml's notificationsCenter), the
    // bell widget toggles it directly, same object NotificationsIpc drives.
    property var center: null
    screen: modelData
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

    // Recomputes (and re-warns) whenever Config.settings changes, Config.get()
    // reads that property internally, so this binding tracks it same as any
    // other Config.get() consumer in the shell.
    readonly property var _layout: bar._resolveLayout()

    readonly property string _position: Theme.barPosition
    readonly property bool _vertical: Theme.barVertical
    readonly property var _strip: Layout.stripGeometry(Theme.space, bar._position)

    // The strip's own length: what the regions share out, and what a
    // cell's width cap is a fraction of.
    readonly property real _along: bar._vertical ? stripArea.height : stripArea.width

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
            // bar's length and the title marquee is the one cell that can
            // take whatever it is given.
            maxWidth: Math.min(220, bar._along * 0.15)
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
            // Every entry is the bar's own cell thickness across the strip,
            // and its own length along it (`_along` below), whichever axis
            // each of those is on this bar.
            width: bar._vertical ? bar._cellThickness : entryLoader._along
            height: bar._vertical ? entryLoader._along : bar._cellThickness
            readonly property real _implicitAlong: bar._vertical ? entryLoader.implicitHeight : entryLoader.implicitWidth
            // A hidden widget (Battery with no laptop battery, NowPlaying
            // with no player, Tray with no items, Indicators with nothing
            // active) sets `visible: false` on itself expecting Row to drop
            // its slot entirely, but Row only inspects its *direct*
            // children's `visible`, and every entry here loads behind this
            // Loader, whose own `visible` defaults true regardless of its
            // item's. Binding straight to `entryLoader.item.visible` looks
            // right and even renders right once, but permanently kills that
            // *same* item's own `visible` binding from ever updating again
            // (confirmed by reproducing it in isolation, reading a
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
            // The entry's length along the strip: its width on a horizontal
            // bar, its height on a vertical one, so the collapse animates
            // the same term on either.
            property real _along: entryLoader.modelData.collapsible
                ? (entryLoader._collapsedAway ? 0 : entryLoader._implicitAlong)
                : entryLoader._implicitAlong
            // Governed entries only. Every other cell keeps the instant width
            // tracking it has always had, so a title rename or a battery tick
            // never gains motion it didn't ask for. Theme.motion.standard is
            // already 0 when motion is disabled (Theme/tokens.js's
            // motionTokens) and a zero-duration animation lands on the same
            // end state, so honoring that setting needs no branch here.
            Behavior on _along {
                enabled: entryLoader.modelData.collapsible
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easingInOut }
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
            // that are empty at creation and gain content later, Indicators
            // when its first glyph turns on, Tray registering its first item
            //, and never the ones with content from the start, which is why
            // the chevron's own collapse/expand has always worked. It
            // escaped notice for the same reason: the indicators row's ONE
            // cell with a live label, the reminder countdown, re-measures
            // itself out of the deadlock every second and drags the rest of
            // the row open behind it, so a live screen recording and a
            // stay-awake toggle were invisible on their own but both
            // appeared beside a pending reminder (g815, 2026-08-19).
            // tests/tst_bar_entry_reveal.qml pins both halves of that.
            visible: entryLoader._shown
                && (!entryLoader.modelData.collapsible || entryLoader._along > 0)
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

    // The frame's ring (Surfaces/Frame/FrameRing.qml), behind the strip
    // and only while the window is the whole output.
    FrameRing {
        anchors.fill: parent
        visible: bar._framed
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
            Rectangle {
                id: hairline
                width: bar._vertical ? Theme.borderWidth : parent.width
                height: bar._vertical ? parent.height : Theme.borderWidth
                x: bar._position === "left" ? parent.width - hairline.width : 0
                y: bar._position === "top" ? parent.height - hairline.height : 0
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
        // Room along the strip is shared in a fixed order. The centre sits at
        // the middle while it can, and slides toward the shorter end once the
        // two end regions together with it outgrow the strip, the start region
        // winning over the end one. What still does not fit clips at the
        // centre's side of each end region, never at the strip's own end, so
        // the cells against the screen edge (an end region's permanent cells,
        // past its chevron) stay whatever an expanded group costs: a vertical
        // bar has a third of a wide bar's length, and a right region long
        // enough to be worth a chevron overflows it the moment it opens.
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
            // Capped to whatever space actually remains before centerRegion
            // (custom command/qml modules have no fixed count), so overflow
            // clips here instead of drawing over the clock.
            width: bar._vertical
                ? leftRail.implicitWidth
                : Math.min(leftRail.implicitWidth, Math.max(0, centerRegion.x - bar._strip.edgeInset - Theme.space.sm))
            height: bar._vertical
                ? Math.min(leftRail.implicitHeight, Math.max(0, centerRegion.y - bar._strip.edgeInset - Theme.space.sm))
                : leftRail.implicitHeight

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
            // Mirror of leftRegion's cap: never draws back past centerRegion's
            // far edge, regardless of how many built-ins plus custom modules
            // settings.json's bar.layout.right names.
            width: bar._vertical
                ? rightRail.implicitWidth
                : Math.min(rightRail.implicitWidth, Math.max(0, parent.width - bar._strip.edgeInset - Theme.space.sm - centerRegion.x - centerRegion.width))
            height: bar._vertical
                ? Math.min(rightRail.implicitHeight, Math.max(0, parent.height - bar._strip.edgeInset - Theme.space.sm - centerRegion.y - centerRegion.height))
                : rightRail.implicitHeight

            // Held against the region's own end, so what the clip removes is
            // the start of the rail, on the centre's side.
            Rail {
                id: rightRail
                vertical: bar._vertical
                x: bar._vertical ? 0 : rightRegion.width - rightRail.width
                y: bar._vertical ? rightRegion.height - rightRail.height : 0
                spacing: Theme.space.sm

                Repeater {
                    id: rightRepeater
                    model: bar._layout.regions.right
                    delegate: regionDelegate
                }
            }
        }
    }
}
