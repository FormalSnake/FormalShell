pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core as Core
import "manifest.js" as Manifest

// The plugin registry: the only QML that touches the filesystem for
// ~/.config/formalshell/plugins. One Process runs manifest.js's scanCommand()
// and feeds its whole stdout into manifest.js's resolve(); every rule about
// what a manifest may say lives there, not here.
//
// Four kinds, mapped onto surfaces the shell already owns:
//   "bar"     one Cell in a Bar region        (Surfaces/Bar/widgets/PluginBarModule.qml)
//   "panel"   one bar-anchored card           (Surfaces/Plugins/PluginPanel.qml)
//   "overlay" one full-screen summoned card   (Surfaces/Plugins/PluginOverlay.qml)
//   "service" no surface at all               (created below)
//
// Panel and overlay hosts are created by a Variants over `surfacePlugins` in
// shell.qml, so they cannot be named as ids there the way the twelve builtin
// panels are. Each host registers ITSELF here on completion instead, and
// PanelIpc's registry binding merges `surfaces` with that static map. Keys
// carry manifest.js's "plugin:" prefix, so a plugin can never collide with a
// builtin panel name by construction.
//
// Service plugins go through Qt.createComponent rather than a Loader for two
// reasons: a service entry root is any QtObject (Loader's behaviour with a
// non-Item root is not something this shell relies on anywhere else), and a
// failed component gives a real errorString() that Loader's status enum
// cannot. If someone later folds services onto a Loader, that error text is
// gone.
Singleton {
    id: root

    readonly property string directory: {
        const xdgConfig = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return xdgConfig + "/formalshell/plugins";
    }

    property var plugins: []
    property var byId: ({})
    property var warnings: []

    // Load failures the hosts and the service creator report back, so
    // `plugins status` can answer "did this plugin's entry file actually
    // load" without anyone grepping the engine's stderr. [{ id, message }].
    property var errors: []

    // Flips true once the first scan has finished one way or another, never
    // back, matching Config.loaded's contract.
    property bool loaded: false

    readonly property var barPlugins: Manifest.barPlugins(root.plugins)
    readonly property var surfacePlugins: Manifest.surfacePlugins(root.plugins)
    readonly property var servicePlugins: Manifest.servicePlugins(root.plugins)

    // "plugin:<id>" -> the live PluginPanel/PluginOverlay instance. Replaced
    // wholesale on every mutation so PanelIpc's registry binding re-fires.
    property var surfaces: ({})

    // JSON text rather than the array itself: a `var` array property
    // re-signals on every settings.json write regardless of content, which
    // would rescan (and close any open plugin surface) on a config edit that
    // has nothing to do with plugins.
    readonly property string disabledIds: JSON.stringify(Core.Config.get("plugins.disabled", []))

    function registerSurface(key, surface) {
        var next = {};
        for (var k in root.surfaces)
            next[k] = root.surfaces[k];
        next[key] = surface;
        root.surfaces = next;
    }

    function unregisterSurface(key) {
        var next = {};
        for (var k in root.surfaces)
            if (k !== key)
                next[k] = root.surfaces[k];
        root.surfaces = next;
    }

    function reportError(id, message) {
        var next = root.errors.filter(function (e) { return e.id !== id; });
        next.push({ id: id, message: message });
        root.errors = next;
    }

    // Closes every open plugin surface before the scan, deliberately rather
    // than as a flicker: shell.qml's Variants may destroy and recreate its
    // delegates when the model identity changes, and a surface torn down
    // mid-open would leave PanelRegistry pointing at a dead object.
    function rescan() {
        for (var key in root.surfaces)
            if (root.surfaces[key].isOpen)
                root.surfaces[key].close();
        root._destroyServices();
        root.errors = [];
        scanProc.running = false;
        scanProc.command = Manifest.scanCommand(root.directory);
        scanProc.running = true;
    }

    property var _serviceObjects: []

    function _destroyServices() {
        for (var i = 0; i < root._serviceObjects.length; i++)
            root._serviceObjects[i].destroy();
        root._serviceObjects = [];
    }

    function _createServices() {
        var list = root.servicePlugins;
        for (var i = 0; i < list.length; i++)
            root._createService(list[i]);
    }

    function _createService(plugin) {
        var component = Qt.createComponent(plugin.entryUrl, Component.Asynchronous);
        var settle = function () {
            if (component.status === Component.Ready) {
                var obj = component.createObject(root);
                if (obj)
                    root._serviceObjects = root._serviceObjects.concat([obj]);
                else
                    root._serviceFailed(plugin, "entry created no object");
            } else if (component.status === Component.Error) {
                root._serviceFailed(plugin, component.errorString());
            }
        };
        if (component.status === Component.Loading)
            component.statusChanged.connect(settle);
        else
            settle();
    }

    function _serviceFailed(plugin, message) {
        root.reportError(plugin.id, message);
        console.warn("PluginService: plugin \"" + plugin.id + "\" failed to load:", message);
    }

    // Config's settings.json load is async, so the disabled list can still be
    // empty the instant this singleton completes. Driving off the property
    // actually changing (CalendarEventsService's own rationale) means a
    // settings.json that resolves a moment later still parks its plugins.
    Component.onCompleted: root.rescan()
    onDisabledIdsChanged: root.rescan()

    Process {
        id: scanProc

        stdout: StdioCollector {
            onStreamFinished: {
                var result = Manifest.resolve(text, JSON.parse(root.disabledIds));
                root.plugins = result.plugins;
                root.byId = result.byId;
                root.warnings = result.warnings;
                root.loaded = true;
                for (var i = 0; i < result.warnings.length; i++)
                    console.warn("PluginService:", result.warnings[i]);
                root._createServices();
            }
        }
    }
}
