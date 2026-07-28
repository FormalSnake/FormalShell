pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core as Core

// Session-wide idle detection (spec §10, M7 Task 5): one shared IdleMonitor
// on top of ext-idle-notify-v1. `respectInhibitors: true` means `isIdle`
// already folds any app's ext-idle-inhibit-v1 hold into its own value — the
// compositor negotiates the "input-idle" vs. plain "idle" notification kind
// per monitor.hpp's own doc, so a video call or similar keeps the whole
// session non-idle with no polling or IdleInhibitor-tracking of our own
// needed here. Screensaver.qml is the only consumer today; kept as its own
// singleton (rather than folded into Screensaver.qml) so a later consumer
// (e.g. Lock.qml's own pre-lock auto-lock, if that's ever wanted) can share
// the same live idle signal instead of standing up a second IdleMonitor.
//
// This is deliberately a *different* IdleMonitor instance from Lock.qml's
// own (see its header comment): that one is on-demand (enabled only while
// locked) and `respectInhibitors: false` on purpose, because a locked
// screen should blank regardless of an app-held inhibitor. This one is
// always-on and honors inhibitors, because the pre-lock screensaver should
// not.
//
// `monitor` stays disabled until Core.Config.loaded first flips true, and
// `timeout` is set from Core.Config.get(...) in that same moment — reproduced
// directly on the mac VM rig (2026-07-28): settings.json loads
// asynchronously, so binding `timeout` straight to a live Core.Config.get()
// read (with `enabled: true` from the start) makes the monitor initialize
// with the 300s fallback and then reconfigure to the real value a moment
// later once settings.json actually loads. That reconfiguration recreates
// IdleMonitor's underlying ext_idle_notification_v1 object a second time —
// and left isIdle stuck at false forever afterward, despite the
// compositor's own "idled" event demonstrably still firing (quickshell's
// own qCDebug confirmed it: the notification really did go idle; the
// binding chain exposing that to QML just never fired again post-recreate).
// Only ever creating the real notification ONCE, already carrying the
// correct timeout, avoids the recreation entirely — matching Lock.qml's own
// IdleMonitor, which never hits this because it doesn't enable until well
// after Config has settled. A live settings.json edit to
// screensaver.timeoutSeconds needs a shell restart to take effect; that is
// an acceptable trade for idle detection actually working at all.
Singleton {
    id: root

    property int timeoutSeconds: 300
    readonly property bool isIdle: monitor.isIdle

    function _armMonitor() {
        root.timeoutSeconds = Core.Config.get("screensaver.timeoutSeconds", 300);
        monitor.enabled = true;
    }

    Component.onCompleted: {
        if (Core.Config.loaded)
            root._armMonitor();
    }

    Connections {
        target: Core.Config
        function onLoadedChanged() {
            if (Core.Config.loaded)
                root._armMonitor();
        }
    }

    IdleMonitor {
        id: monitor
        enabled: false
        timeout: root.timeoutSeconds
        respectInhibitors: true
    }
}
