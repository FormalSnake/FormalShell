import Quickshell

// A popout built the first time something opens it. Bar cells, PanelIpc
// and the IPC handlers that drive a panel's own verbs all hold one of
// these instead of the panel: it answers `isOpen` false while nothing has
// been built, and the first open, toggle or load() creates the panel
// synchronously (Panel.qml's DismissTwins is a Variants, which LazyLoader
// cannot build off-thread). A panel whose bar cell reads its data
// (weather, usage, tailscale, system update, github) stays eager in
// shell.qml, as does the media panel, whose Video decode feeds the bar's
// animated cover.
LazyLoader {
    id: root

    readonly property bool isOpen: root.item ? root.item.isOpen : false

    function load() {
        root.active = true;
        return root.item;
    }

    function open(x, screen) {
        root.load().open(x, screen);
    }

    function close() {
        if (root.item)
            root.item.close();
    }

    function toggle(x, screen) {
        root.load().toggle(x, screen);
    }

    function toggleFrom(item) {
        root.load().toggleFrom(item);
    }
}
