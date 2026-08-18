//@ pragma ShellId formalshell
// UseQApplication: QsMenuAnchor.open() (the tray's DBusMenu path in
// Surfaces/Bar/widgets/Tray.qml) hard-fails with a qCritical unless
// quickshell runs in QApplication mode — platform menus are QMenus.
//@ pragma UseQApplication
import Quickshell
import QtQuick

import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Menu
import qs.Surfaces.Notifications
import qs.Surfaces.Osd
import qs.Surfaces.Panels
import qs.Surfaces.Lock
import qs.Surfaces.Screensaver
import qs.Surfaces.HotCorners
import qs.Surfaces.Capture
import qs.Surfaces.Plugins
import qs.Surfaces.Polkit
import qs.Surfaces.Gallery
import qs.Ipc
import qs.Plugins
import qs.Reminders
import qs.Services

ShellRoot {
    // Single-instance takeover lock (post-M16 addendum) — wired first so a
    // stale/duplicate instance is caught before any surface renders. See
    // InstanceLock.qml's own header comment for the takeover protocol.
    InstanceLock {}

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Background {}
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {
                appMenuPanel: appMenuPanelInstance
                audioPanel: audioPanelInstance
                calendarPanel: calendarPanelInstance
                networkPanel: networkPanelInstance
                bluetoothPanel: bluetoothPanelInstance
                powerPanel: powerPanelInstance
                weatherPanel: weatherPanelInstance
                mediaPanel: mediaPanelInstance
                githubPanel: githubPanelInstance
                usagePanel: usagePanelInstance
                tailscalePanel: tailscalePanelInstance
                systemUpdatePanel: systemUpdatePanelInstance
                center: notificationsCenter
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            // center: notificationsCenter suppresses this screen's toast
            // stack while the history center is open — see Toasts.qml's own
            // header comment for why the two surfaces can't coexist.
            Toasts { center: notificationsCenter }
        }
    }

    // One instance, not per-screen: it opens on the focused screen at
    // summon time rather than living on every output.
    Menu { id: menu; center: notificationsCenter }

    // Same reasoning as Menu: one instance, opened on the focused screen at
    // summon time.
    Center { id: notificationsCenter }

    // Same reasoning again: one instance, shown on the focused screen at
    // trigger time.
    Osd { id: osd }

    // WlSessionLock manages its own per-screen surfaces internally (see
    // Lock.qml's header comment) — one instance here covers every output.
    Lock { id: lock }

    // Same "one controller, many surfaces" reasoning as Lock, minus the
    // WlSessionLock auto-management (see Screensaver.qml's own header
    // comment) — one instance here, its internal Variants loop covers every
    // output.
    Screensaver { id: screensaver; lockScreen: lock }

    // Corner triggers for the two surfaces above. Same split again — one
    // controller here, its own Variants loop covering every output — and it
    // takes handles on both rather than going through their IPC targets, so
    // a corner behaves identically to `lock lock` / `screensaver start`
    // without a round trip through the socket.
    HotCorners { lockScreen: lock; screensaver: screensaver }

    // Same "one controller, shown on the focused screen at trigger time"
    // reasoning as Osd — but this one's trigger is a real polkit
    // authentication request, not an IPC call.
    PolkitDialog { id: polkitDialog }

    // Same reasoning again: one instance per panel kind, opened on the
    // focused screen at summon time.
    AppMenuPanel { id: appMenuPanelInstance }
    AudioPanel { id: audioPanelInstance }
    CalendarPanel { id: calendarPanelInstance; menu: menu }
    NetworkPanel { id: networkPanelInstance }
    BluetoothPanel { id: bluetoothPanelInstance }
    AirpodsPanel { id: airpodsPanelInstance }
    PowerPanel { id: powerPanelInstance }
    WeatherPanel { id: weatherPanelInstance }
    MediaPanel { id: mediaPanelInstance }
    GithubPanel { id: githubPanelInstance }
    UsagePanel { id: usagePanelInstance }
    TailscalePanel { id: tailscalePanelInstance }
    SystemUpdatePanel { id: systemUpdatePanelInstance }
    DisplayPanel { id: displayPanelInstance }
    RegionPicker { id: regionPickerInstance }

    // Plugin-declared surfaces (shell/Plugins/manifest.js): created from the
    // scanned manifests rather than named here, because nobody knows their
    // ids at authoring time. Each host registers ITSELF with PluginService on
    // completion, and PanelIpc's registry below merges that map in.
    // PluginService.rescan() closes every open plugin surface before the
    // model changes, so a reload never tears one down mid-open.
    Variants {
        model: PluginService.surfacePlugins.filter(p => p.kind === "panel")

        delegate: Component {
            PluginPanel {}
        }
    }

    Variants {
        model: PluginService.surfacePlugins.filter(p => p.kind === "overlay")

        delegate: Component {
            PluginOverlay {}
        }
    }

    // The menu's "reminder-set" input prompt answers here: Menu emits
    // selectionResolved for every input/select round trip. Routing it at the
    // shell root keeps the reference one-directional, so nothing under
    // Reminders/ ever holds a handle on the menu. resolveInput ignores every
    // token but its own, so CalendarPanel's two-step prompt on the same
    // signal is untouched.
    Connections {
        target: menu
        function onSelectionResolved(token, value, cancelled) {
            ReminderService.resolveInput(token, value, cancelled);
        }
    }

    // Dev surface, reachable only through `gallery open|toggle` — no bar
    // cell, no bar.layout entry, and deliberately absent from PanelIpc's
    // registry below. Its own Loader stays inactive until summoned, so an
    // ordinary session pays nothing for it.
    Gallery { id: galleryInstance }

    DebugIpc { menu: menu }
    ThemeIpc {}
    WallpaperIpc {}
    MenuIpc { menu: menu }
    NotificationsIpc { center: notificationsCenter }
    OsdIpc { osd: osd }
    // The static thirteen merged with every plugin surface that has
    // registered itself. Plugin keys carry manifest.js's "plugin:" prefix, so
    // a plugin can never shadow a builtin name and PanelIpc needs no
    // reserved-id list. PluginService.surfaces is replaced wholesale on every
    // register/unregister, so this binding re-fires.
    PanelIpc {
        registry: {
            var reg = { appmenu: appMenuPanelInstance, audio: audioPanelInstance, calendar: calendarPanelInstance, network: networkPanelInstance, bluetooth: bluetoothPanelInstance, airpods: airpodsPanelInstance, power: powerPanelInstance, weather: weatherPanelInstance, media: mediaPanelInstance, github: githubPanelInstance, usage: usagePanelInstance, tailscale: tailscalePanelInstance, systemupdate: systemUpdatePanelInstance, display: displayPanelInstance };
            var surfaces = PluginService.surfaces;
            for (var key in surfaces)
                reg[key] = surfaces[key];
            return reg;
        }
    }
    CalendarIpc { panel: calendarPanelInstance }
    ClipboardIpc {}
    NetworkIpc { panel: networkPanelInstance }
    BluetoothIpc {}
    AirpodsIpc {}
    MediaIpc {}
    TrayIpc {}
    BarIpc {}
    LockIpc { lockScreen: lock }
    ScreensaverIpc { screensaver: screensaver }
    // The image/wallpaper picker is the menu's "wallpaper" route (M23), not
    // a surface of its own — see PickerIpc.qml's header for why the target
    // keeps its own name and selection file regardless.
    PickerIpc { picker: menu }
    ScreenshotIpc { picker: regionPickerInstance }
    CaptureIpc {}
    RecordIpc {}
    ReminderIpc {}
    NightLightIpc {}
    GalleryIpc { gallery: galleryInstance }
    PluginsIpc {}
}
