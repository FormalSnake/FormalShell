//@ pragma ShellId formalshell
// UseQApplication: kept in place, out of scope to reassess for M32. Its
// only known justification was QsMenuAnchor.open() in Tray.qml's old
// native-QMenu context-menu path, which M32 removed for a shell-owned
// QsMenuOpener surface (TrayMenu.qml) after a Hyprland popup-grab bug tore
// the native QMenu down on click (see Tray.qml's own header). Whether
// anything else in quickshell's systray/icon rendering still needs
// QApplication mode is unverified.
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
                menu: menuInstance
                appMenuPanel: appMenuPanelInstance
                audioPanel: audioPanelInstance
                calendarPanel: calendarPanelInstance
                networkPanel: networkPanelInstance
                bluetoothPanel: bluetoothPanelInstance
                airpodsPanel: airpodsPanelInstance
                dualsensePanel: dualsensePanelInstance
                powerPanel: powerPanelInstance
                weatherPanel: weatherPanelInstance
                mediaPanel: mediaPanelInstance
                githubPanel: githubPanelInstance
                usagePanel: usagePanelInstance
                tailscalePanel: tailscalePanelInstance
                systemUpdatePanel: systemUpdatePanelInstance
                displayPanel: displayPanelInstance
                monitorPanel: monitorPanelInstance
                trayMenu: trayMenuInstance
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
    // `menuInstance`, not a bare `menu`: Bar.qml carries a property of that
    // name and is instantiated inside a Variants delegate `Component`, where
    // an object's OWN property shadows an outer id of the same name — so
    // `Bar { menu: menu }` bound the property to itself and every launcher
    // cell got null (probe-verified in-VM, 2026-08-19: the same binding at
    // this file's top level resolves to the id and works, which is exactly
    // what made it look fine here for MenuIpc/CalendarPanel/MonitorPanel).
    // The `*Instance` name every panel in this file already uses removes the
    // collision rather than relying on which scope wins where.
    Menu { id: menuInstance; center: notificationsCenter }

    // Same reasoning as Menu: one instance, opened on the focused screen at
    // summon time.
    Center { id: notificationsCenter }

    // Same reasoning again: one instance, shown on the focused screen at
    // trigger time.
    Osd { id: osd }

    // WlSessionLock manages its own per-screen surfaces internally (see
    // Lock.qml's header comment) — one instance here covers every output.
    Lock { id: lock }

    // LockService is the one lock trigger every caller goes through (IPC,
    // the hot corner, the screensaver chain, the launcher's Lock row), and
    // the built-in surface handle it needs exists only here.
    Binding { target: LockService; property: "lockScreen"; value: lock }

    // Same "one controller, many surfaces" reasoning as Lock, minus the
    // WlSessionLock auto-management (see Screensaver.qml's own header
    // comment) — one instance here, its internal Variants loop covers every
    // output.
    Screensaver { id: screensaver }

    // Corner triggers for the two surfaces above. Same split again: one
    // controller here, its own Variants loop covering every output. It takes
    // the screensaver handle directly and locks through LockService rather
    // than going through either IPC target, so a corner behaves identically
    // to `lock lock` / `screensaver start` without a round trip through the
    // socket. The launcher handle is for the corners configured with an
    // action string, which resolve exactly as the launcher's own rows do.
    HotCorners { screensaver: screensaver; menu: menuInstance }

    // Same "one controller, shown on the focused screen at trigger time"
    // reasoning as Osd — but this one's trigger is a real polkit
    // authentication request, not an IPC call.
    PolkitDialog { id: polkitDialog }

    // Same reasoning again: one instance per panel kind, opened on the
    // focused screen at summon time.
    AppMenuPanel { id: appMenuPanelInstance }
    AudioPanel { id: audioPanelInstance }
    CalendarPanel { id: calendarPanelInstance; menu: menuInstance }
    NetworkPanel { id: networkPanelInstance }
    BluetoothPanel { id: bluetoothPanelInstance }
    AirpodsPanel { id: airpodsPanelInstance }
    DualsensePanel { id: dualsensePanelInstance }
    PowerPanel { id: powerPanelInstance }
    WeatherPanel { id: weatherPanelInstance }
    MediaPanel { id: mediaPanelInstance }
    GithubPanel { id: githubPanelInstance }
    UsagePanel { id: usagePanelInstance }
    TailscalePanel { id: tailscalePanelInstance }
    SystemUpdatePanel { id: systemUpdatePanelInstance }
    DisplayPanel { id: displayPanelInstance }
    MonitorPanel { id: monitorPanelInstance; menu: menuInstance }
    RegionPicker { id: regionPickerInstance }

    // Same "one controller, opened on the focused screen at trigger time"
    // reasoning as Menu/Center/Osd (M32): one TrayMenu instance shared by
    // every bar output's Tray widget, its content swapped per item via
    // openItem() rather than one instance per screen.
    TrayMenu { id: trayMenuInstance }

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
        target: menuInstance
        function onSelectionResolved(token, value, cancelled) {
            ReminderService.resolveInput(token, value, cancelled);
        }
    }

    // Dev surface, reachable only through `gallery open|toggle` — no bar
    // cell, no bar.layout entry, and deliberately absent from PanelIpc's
    // registry below. Its own Loader stays inactive until summoned, so an
    // ordinary session pays nothing for it.
    Gallery { id: galleryInstance }

    DebugIpc { menu: menuInstance }
    ThemeIpc {}
    WallpaperIpc {}
    MenuIpc { menu: menuInstance }
    NotificationsIpc { center: notificationsCenter }
    OsdIpc { osd: osd }
    // The static sixteen merged with every plugin surface that has
    // registered itself. Plugin keys carry manifest.js's "plugin:" prefix, so
    // a plugin can never shadow a builtin name and PanelIpc needs no
    // reserved-id list. PluginService.surfaces is replaced wholesale on every
    // register/unregister, so this binding re-fires.
    PanelIpc {
        registry: {
            var reg = { appmenu: appMenuPanelInstance, audio: audioPanelInstance, calendar: calendarPanelInstance, network: networkPanelInstance, bluetooth: bluetoothPanelInstance, airpods: airpodsPanelInstance, dualsense: dualsensePanelInstance, power: powerPanelInstance, weather: weatherPanelInstance, media: mediaPanelInstance, github: githubPanelInstance, usage: usagePanelInstance, tailscale: tailscalePanelInstance, systemupdate: systemUpdatePanelInstance, display: displayPanelInstance, monitor: monitorPanelInstance };
            var surfaces = PluginService.surfaces;
            for (var key in surfaces)
                reg[key] = surfaces[key];
            return reg;
        }
    }
    CalendarIpc { panel: calendarPanelInstance }
    ClipboardIpc {}
    ConsoleIpc {}
    MonitorIpc {}
    NetworkIpc { panel: networkPanelInstance }
    BluetoothIpc {}
    AirpodsIpc {}
    MediaIpc {}
    TrayIpc { trayMenu: trayMenuInstance }
    BarIpc {}
    LockIpc {}
    ScreensaverIpc { screensaver: screensaver }
    // The image/wallpaper picker is the menu's "wallpaper" route (M23), not
    // a surface of its own — see PickerIpc.qml's header for why the target
    // keeps its own name and selection file regardless.
    PickerIpc { picker: menuInstance }
    ScreenshotIpc { picker: regionPickerInstance }
    CaptureIpc {}
    RecordIpc {}
    ReminderIpc {}
    NightLightIpc {}
    GalleryIpc { gallery: galleryInstance }
    PluginsIpc {}
}
