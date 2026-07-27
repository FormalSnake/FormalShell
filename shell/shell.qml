//@ pragma ShellId formalshell
import Quickshell
import QtQuick

import qs.Surfaces.Bar

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            Bar {}
        }
    }
}
