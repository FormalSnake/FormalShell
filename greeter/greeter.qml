//@ pragma ShellId formalshell-greeter
import Quickshell
import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Greetd
import qs.Core as Core
import qs.Components

// greetd entry point (DESIGN.md's Lock/greeter translation, spec §9): a
// separate -p target from shell.qml, sharing Core/Theme/Components so it
// renders as the lock screen's visual twin — read
// shell/Surfaces/Lock/LockSurface.qml first, its clock/date/input-cell
// column is mirrored here almost verbatim.
//
// No WlSessionLock: unlike the lock screen (which secures an
// already-running session against the same machine's other windows),
// greetd spawns this process into its own disposable compositor instance
// with no other client ever attached — there is nothing for a "lock"
// primitive to exclude here, so a plain per-output PanelWindow is the
// whole surface. WlrKeyboardFocus.OnDemand (not Exclusive) mirrors
// Screensaver.qml's own per-output overlay for the same reason: with a
// Variants loop potentially spawning more than one surface (multi-monitor
// greeter), OnDemand defers to the compositor's normal focus semantics
// instead of every surface individually claiming exclusive keyboard input.
//
// No Core.State reference anywhere below (unlike LockSurface's blurred-
// wallpaper backdrop): State.qml derives its path from $HOME and, on
// FileNotFound, WRITES a fresh state.json — exactly the "cannot read a
// real user's $XDG_STATE_HOME/state.json and must not try" the plan warns
// about, except here it'd be the `greeter` system user's own $HOME getting
// a stray write. Flat Theme.color.background only; DESIGN.md's blur
// exception (rule 8) stays lock-screen-only, not extended here.
//
// Theme/settings sourcing: Core.Theme and Core.Config are reused
// unmodified, not re-implemented for a "system path". Both already fail
// soft — Theme.qml falls back to the Flexoki palette the moment
// theme.json isn't found under the running process's $XDG_STATE_HOME, and
// Config.qml's get() returns its fallback the same way for settings.json
// — so the greeter user simply inherits whichever behaviour its own
// $HOME (or an XDG_STATE_HOME/XDG_CONFIG_HOME override that a future
// greetd wiring points at a shared system path) resolves to, with zero
// greeter-specific sourcing code. The plan's "theme comes from a
// system-readable path, or falls back to Flexoki" is satisfied by that
// inheritance, not by anything new here.
//
// Session/user "selection": Quickshell.Services.Greetd exposes no
// enumeration of users or sessions at all (verified against greetd's
// connection.cpp — create_session/cancel_session/
// post_auth_message_response/start_session is the entire wire protocol),
// so per the plan no picker is invented here. Typing a username into the
// one input cell isn't "selection" in that sense, it's the same kind of
// free-text entry the password step already is — an ordinary greetd
// conversation, just started by us instead of a display manager. The
// session a successful login launches is a configured default
// (greeter.sessionCommand in settings.json, see Core/Config.qml) rather
// than something chosen here; Task 4's NixOS module is where a real
// deployment gets a proper option instead of this settings.json key.
ShellRoot {
    id: root

    // Raw text of the most recent greetd auth_message, "" until the first
    // one arrives — see _promptLabel below for the brief
    // Authenticating-but-no-message-yet gap right after createSession().
    property string _promptMessage: ""
    property bool _promptEcho: false
    // True only between an auth_message with responseRequired true and
    // this surface's own respond() call answering it — the one moment the
    // input cell is actually asking for something typeable.
    property bool _awaitingResponse: false
    // Uppercase-rendered (MetaLabel does the case transform) failure text
    // for the input cell's meta row; "" means no error is showing. Mirrors
    // Lock.qml's authError convention, but greetd hands back a plain
    // string rather than a PamResult enum, so it's shown verbatim rather
    // than mapped through a second table of messages.
    property string authError: ""

    readonly property string _promptLabel: {
        if (root.authError !== "")
            return root.authError;
        if (root._awaitingResponse)
            return root._promptMessage !== "" ? root._promptMessage : "PASSWORD";
        if (Greetd.state === GreetdState.Inactive)
            return "USER";
        return "AUTHENTICATING";
    }

    readonly property bool _inputEnabled: Greetd.available
        && (Greetd.state === GreetdState.Inactive || root._awaitingResponse)

    // greeter.sessionCommand (Core/Config.qml's settings.json, argv array):
    // the session a successful login launches. ["niri"] is the one
    // compositor every other smoke rig in this repo already exercises —
    // Task 4's nixosModules.formalshell-greeter is where a real deployment
    // gets a proper option instead of this settings.json key.
    readonly property var _sessionCommand: Core.Config.get("greeter.sessionCommand", ["niri"])

    // The sole entry point into the greetd conversation, dispatched by
    // Greetd.state exactly like Lock.qml dispatches on PamContext.active —
    // one function, called from every output's TextInput.onAccepted.
    function submit(text) {
        if (!Greetd.available)
            return;
        if (Greetd.state === GreetdState.Inactive) {
            if (text === "")
                return;
            root.authError = "";
            Greetd.createSession(text);
        } else if (root._awaitingResponse) {
            root._awaitingResponse = false;
            Greetd.respond(text);
        }
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root._promptMessage = message;
            root._promptEcho = echoResponse;
            root._awaitingResponse = responseRequired;
        }

        // greetd resets its own state to Inactive right after this signal
        // (connection.cpp's setActive(false)/setInactive()) — no manual
        // phase reset needed here, _promptLabel/_inputEnabled above react
        // to Greetd.state directly.
        function onAuthFailure(message) {
            root.authError = message !== "" ? message : "AUTHENTICATION FAILED";
            root._awaitingResponse = false;
        }

        function onError(message) {
            root.authError = message !== "" ? message : "GREETD ERROR";
            root._awaitingResponse = false;
        }

        // "Performing animations and such should be done *before* calling
        // launch" (Greetd::launch's own doc) — nothing here to animate, so
        // this fires immediately on the state flipping to ReadyToLaunch.
        function onReadyToLaunch() {
            Greetd.launch(root._sessionCommand, [], true);
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: surface
                required property var modelData
                screen: modelData
                color: Core.Theme.color.background

                anchors { top: true; bottom: true; left: true; right: true }

                WlrLayershell.namespace: "formalshell:greeter"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                property date _now: new Date()

                onVisibleChanged: {
                    if (surface.visible)
                        Qt.callLater(function () { userInput.forceActiveFocus(); });
                }

                Rectangle {
                    anchors.fill: parent
                    color: Core.Theme.color.background
                }

                Column {
                    id: greeterColumn
                    anchors.centerIn: parent
                    spacing: Core.Theme.spacing.lg

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(surface._now, "hh:mm")
                        color: Core.Theme.color.foreground
                        font.family: Core.Theme.font.display
                        font.pixelSize: 120
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(surface._now, "dddd, MMMM d")
                        color: Core.Theme.color.foregroundDim
                        font.family: Core.Theme.font.family
                        font.pixelSize: Core.Theme.font.title
                    }

                    Cell {
                        id: inputCell
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 320
                        selected: root.authError !== "" || !Greetd.available

                        Column {
                            width: parent.width
                            spacing: Core.Theme.spacing.xs
                            visible: Greetd.available

                            MetaLabel {
                                text: root._promptLabel
                            }

                            TextInput {
                                id: userInput
                                width: parent.width
                                color: inputCell.foreground
                                font.family: Core.Theme.font.family
                                font.pixelSize: Core.Theme.font.body
                                echoMode: root._awaitingResponse && !root._promptEcho ? TextInput.Password : TextInput.Normal
                                enabled: root._inputEnabled
                                focus: true
                                selectByMouse: true
                                cursorVisible: true

                                onAccepted: {
                                    root.submit(userInput.text);
                                    userInput.text = "";
                                }
                            }
                        }

                        // Honest unavailable state (plan-wide constraint):
                        // no GREETD_SOCK means there is no session to start
                        // at all, so this replaces the interactive column
                        // rather than leaving a field that would silently
                        // no-op on every keystroke.
                        MetaLabel {
                            width: parent.width
                            visible: !Greetd.available
                            text: "GREETD SOCKET UNAVAILABLE"
                        }
                    }
                }

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: surface._now = new Date()
                }
            }
        }
    }
}
