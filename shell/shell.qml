//@ pragma ShellId formalshell
import Quickshell
import QtQuick

import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Menu
import qs.Surfaces.Notifications
import qs.Surfaces.Osd
import qs.Surfaces.Panels
import qs.Ipc

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Background {}
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar { audioPanel: audioPanelInstance }
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

    // Same reasoning again: one instance per panel kind, opened on the
    // focused screen at summon time. Only audio exists as of M6 Task 1.
    AudioPanel { id: audioPanelInstance }

    DebugIpc { menu: menu }
    ThemeIpc {}
    WallpaperIpc {}
    MenuIpc { menu: menu }
    NotificationsIpc { center: notificationsCenter }
    OsdIpc { osd: osd }
    PanelIpc { registry: ({ audio: audioPanelInstance }) }
    ClipboardIpc {}
}
