import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Components
import "../../../Bar/launchericon.js" as LauncherIcon

// The launcher cell (DESIGN.md §3 Bar, M39 Task 1): the shell's mark at the
// head of the bar's left region, and the menu's only pointer-reachable
// summon path, every other route into it is a compositor keybind or the
// `menu` IPC target. It leads DEFAULT_LAYOUT.left rather than joining the
// opt-in builtins for exactly that reason: a bar with no launcher cell
// leaves a mouse user with no way to open the menu at all.
//
// The mark defaults to the command glyph, shadcn's own Command palette sign,
// drawn through `Icon` so the set follows `theme.icons` like every other icon
// in the shell. `bar.launcherIcon` replaces it with the machine's distro
// logo, another icon name, or an image the owner points at; the grammar and
// every fallback live in Bar/launchericon.js.
Cell {
    id: root

    // shell.qml's single Menu instance, handed down through Bar.qml.
    property var menu: null

    readonly property bool _menuOpen: root.menu ? root.menu.isOpen : false

    readonly property string _configured: Config.get("bar.launcherIcon", "")
    readonly property var _osRelease: LauncherIcon.parseOsRelease(osReleaseFile.text())
    // check=true so a distro icon the theme cannot resolve comes back "" and
    // the resolver falls through to the icon set, rather than handing the
    // Image a missing-texture box.
    readonly property var _spec: {
        var spec = LauncherIcon.resolve(root._configured, root._osRelease,
            function (name) { return Quickshell.iconPath(name, true); });
        if (spec.kind !== "image")
            return spec;
        // `~` is the caller's to expand, launchericon.js stays pure and
        // nothing in it knows $HOME. An Image `source` is a URL, so a bare
        // path has to carry the scheme or Qt resolves it against this
        // component's own directory instead of the filesystem root.
        var path = spec.value;
        if (path.indexOf("~/") === 0)
            path = Quickshell.env("HOME") + path.slice(1);
        if (path.indexOf("/") === 0)
            path = "file://" + path;
        return { kind: "image", value: path };
    }

    // /etc/os-release is only read when the owner actually asked for the
    // distro mark: every other value resolves without it, and a file this
    // widget never needs should not be opened once per screen.
    FileView {
        id: osReleaseFile
        path: root._configured === "distro" ? "/etc/os-release" : ""
    }

    tooltipText: "LAUNCHER"

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: root._spec.kind === "icon"
        name: root._spec.kind === "icon" ? root._spec.value : "command"
        color: root.foreground
    }

    // A supplied image, sized to the glyph it stands in for so the bar's
    // cell row keeps one optical height whichever mark is drawn.
    Image {
        anchors.verticalCenter: parent.verticalCenter
        visible: root._spec.kind === "image"
        source: root._spec.kind === "image" ? root._spec.value : ""
        width: Theme.fontSize.body
        height: Theme.fontSize.body
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
    }

    panelOpen: root._menuOpen

    interactive: true
    // Toggle rather than open: a second click on the mark closes the menu,
    // the same contract `menu toggle` over IPC already has.
    onClicked: {
        if (!root.menu)
            return;
        if (root.menu.isOpen)
            root.menu.close();
        else
            root.menu.open();
    }
}
