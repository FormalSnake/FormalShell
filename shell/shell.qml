//@ pragma ShellId formalshell
import Quickshell
import QtQuick

import qs.Surfaces.Background
import qs.Surfaces.Bar
import qs.Surfaces.Menu
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

    // One instance, not per-screen: it opens on the focused screen at
    // summon time rather than living on every output.
    Menu { id: menu }

    DebugIpc { menu: menu }
    ThemeIpc {}
    WallpaperIpc {}
}
