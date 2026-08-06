pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Connectivity edge-watcher for every surface that polls a remote backend
// (Weather/Github/Tailscale panels, AppleMusicArtService). `online` is
// link-level — any Networking device connected — deliberately not
// Networking.connectivity, which needs NM's captive-portal probe opted in
// (`connectivityCheckEnabled`) and reads Unknown otherwise. `reconnected()`
// fires once per offline→online edge, after a short settle so DHCP/DNS on a
// fresh wifi association aren't raced by the very fetch the signal exists
// to retrigger; consumers refresh immediately instead of waiting out their
// own poll interval (up to 15min for weather) on a stale or UNAVAILABLE
// surface. The edge also fires when Networking's async device population
// brings the first connected device up shortly after launch — that
// deliberately covers "shell started before the network was up", at the
// cost of one redundant (idempotent) refetch on sessions that started
// online.
Singleton {
    id: root

    readonly property bool online: Networking.devices.values.some(function (d) { return d.connected; })

    signal reconnected()

    onOnlineChanged: {
        if (root.online)
            settleTimer.restart();
        else
            settleTimer.stop();
    }

    Timer {
        id: settleTimer
        interval: 3000
        onTriggered: root.reconnected()
    }
}
