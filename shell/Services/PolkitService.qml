pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.Core as Core

// The shell's polkit agent (M16 Task 4, laptop feature parity with
// omarchy). `PolkitAgent`'s componentComplete() attempts real D-Bus
// registration the instant it's constructed (verified against the pinned
// quickshell source, src/services/polkit/qml.cpp), so `polkit.enabled`
// (settings.json, default true) gates it through a Loader rather than a
// property on the element itself; disabling the setting means the shell
// never even tries to register, not "registers and is ignored". When
// another agent already owns the session (isRegistered stays false, the
// e1504g today runs polkit-kde-authentication-agent-1, see
// SWITCHOVER.md), this logs one line and PolkitDialog.qml simply never has
// a flow to show, the two agents never fight over the registration.
Singleton {
    id: root

    // Config.loaded gated: polkit.enabled's fallback is true, so reading
    // this before settings.json resolves would register the agent and then
    // immediately tear it down again the instant a real `false` lands.
    readonly property bool enabled: Core.Config.loaded && Core.Config.get("polkit.enabled", true) === true
    readonly property bool isRegistered: agentLoader.item ? agentLoader.item.isRegistered : false
    readonly property bool isActive: agentLoader.item ? agentLoader.item.isActive : false
    readonly property var flow: agentLoader.item ? agentLoader.item.flow : null

    Loader {
        id: agentLoader
        active: root.enabled

        sourceComponent: PolkitAgent {
            id: agent
            path: "/org/formalshell/PolkitAgent"

            // Fires on every later transition too (an agent losing its
            // registration mid-session would be worth knowing about), but
            // the first evaluation matters most and doesn't reliably raise
            // a change signal if it settles on the same value the bindable
            // property defaulted to, Qt.callLater reads the settled value
            // once construction has actually finished, regardless.
            onIsRegisteredChanged: {
                if (agent.isRegistered)
                    console.log("formalshell: polkit agent registered at", agent.path);
                else
                    console.warn("formalshell: polkit agent not registered: another agent may already own this session");
            }

            Component.onCompleted: Qt.callLater(function () {
                if (!agent.isRegistered)
                    console.warn("formalshell: polkit agent not registered: another agent may already own this session");
            });
        }
    }
}
