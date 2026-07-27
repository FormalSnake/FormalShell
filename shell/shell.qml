//@ pragma ShellId formalshell
import Quickshell
import QtQuick

import qs.Surfaces.Background
import qs.Surfaces.Bar
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

    DebugIpc {}
    ThemeIpc {}
    WallpaperIpc {}
}
