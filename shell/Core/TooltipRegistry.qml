pragma Singleton
import Quickshell

// The tooltip surfaces, one per output (M53 D10). Cell.qml and Button.qml
// used to load a card each, so walking the bar paid the 400ms delay at
// every cell; they now ask this for the one card their output already has.
// Wayland hands clients no cross-window geometry, so which surface answers
// for an item is a question only the surfaces themselves can settle
// (Tooltip.accepts, off the item's own window) rather than one this can
// work out from an item alone.
//
// The same shape PanelRegistry.bars carries and for the same reason: the
// surfaces live inside a Variants delegate nothing outside can address,
// while the items asking are scattered across every window in the shell.
// `hosts` is reassigned rather than mutated in place, so a consumer binding
// to it re-evaluates.
Singleton {
    id: root

    property var hosts: []

    function addHost(host) {
        if (root.hosts.indexOf(host) < 0)
            root.hosts = root.hosts.concat([host]);
    }

    function removeHost(host) {
        root.hosts = root.hosts.filter(function (other) { return other !== host; });
    }

    function show(item, text, barEdge) {
        var host = root._hostFor(item);
        if (host)
            host.show(item, text, barEdge);
    }

    // Every host, not just the owning one: an item whose window moved
    // output between the show and the leave would otherwise leave a card
    // standing on the output it came from.
    function hide(item) {
        for (var i = 0; i < root.hosts.length; i++)
            root.hosts[i].hide(item);
    }

    // The single-host fallback covers the window whose own screen has not
    // resolved yet (a surface asked about during its first frame): on a
    // one-output machine there is nowhere else the card could go.
    function _hostFor(item) {
        for (var i = 0; i < root.hosts.length; i++) {
            if (root.hosts[i].accepts(item))
                return root.hosts[i];
        }
        return root.hosts.length === 1 ? root.hosts[0] : null;
    }
}
