//@ pragma ShellId formalshell
import Quickshell
import QtQuick

import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Menu
import qs.Surfaces.Notifications
import qs.Surfaces.Osd
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
            Bar {}
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Toasts {}
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

    DebugIpc { menu: menu }
    ThemeIpc {}
    WallpaperIpc {}
    MenuIpc { menu: menu }
    NotificationsIpc { center: notificationsCenter }
    OsdIpc { osd: osd }
}
