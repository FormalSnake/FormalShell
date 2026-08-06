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
import qs.Surfaces.Picker
import qs.Surfaces.Polkit
import qs.Surfaces.Gallery
import qs.Ipc
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

    // Same "one controller, shown on the focused screen at trigger time"
    // reasoning as Osd — but this one's trigger is a real polkit
    // authentication request, not an IPC call.
    PolkitDialog { id: polkitDialog }

    // Same reasoning again: one instance per panel kind, opened on the
    // focused screen at summon time.
    AudioPanel { id: audioPanelInstance }
    CalendarPanel { id: calendarPanelInstance; menu: menu }
    NetworkPanel { id: networkPanelInstance }
    BluetoothPanel { id: bluetoothPanelInstance }
    PowerPanel { id: powerPanelInstance }
    WeatherPanel { id: weatherPanelInstance }
    MediaPanel { id: mediaPanelInstance }
    GithubPanel { id: githubPanelInstance }
    UsagePanel { id: usagePanelInstance }
    TailscalePanel { id: tailscalePanelInstance }
    DisplayPanel { id: displayPanelInstance }
    ImagePicker { id: imagePickerInstance }

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
    PanelIpc { registry: ({ audio: audioPanelInstance, calendar: calendarPanelInstance, network: networkPanelInstance, bluetooth: bluetoothPanelInstance, power: powerPanelInstance, weather: weatherPanelInstance, media: mediaPanelInstance, github: githubPanelInstance, usage: usagePanelInstance, tailscale: tailscalePanelInstance, display: displayPanelInstance }) }
    CalendarIpc { panel: calendarPanelInstance }
    ClipboardIpc {}
    NetworkIpc { panel: networkPanelInstance }
    BluetoothIpc {}
    MediaIpc {}
    TrayIpc {}
    LockIpc { lockScreen: lock }
    ScreensaverIpc { screensaver: screensaver }
    PickerIpc { picker: imagePickerInstance }
    ScreenshotIpc {}
    NightLightIpc {}
    GalleryIpc { gallery: galleryInstance }
}
