import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Pam

// The lock screen (DESIGN.md §Lock/greeter, spec §8, M7 Task 3): a plain Item
// wrapper around the actual WlSessionLock, needed because WlSessionLock's
// QML_ELEMENT default property is `surface` (Component-typed) — a bare
// (unqualified) PamContext child declared directly inside a WlSessionLock
// gets swept into that default-property slot as an anonymous Component and
// silently discarded the moment an explicit `surface: Component {...}` is
// also given, leaving `pam`'s id attached to an object that was never
// actually instantiated (reproduced: "ReferenceError: pam is not defined"
// from inside root's own functions, while PamContext's own signal handlers,
// bound at the same never-happened construction, never fired either).
// Wrapping in a plain Item (default property `data`, list-typed, no such
// conflict) fixes it; `locked`/`secure` are forwarded so LockIpc and anyone
// else external still reads/writes lock state exactly as before.
//
// WlSessionLock creates one LockSurface per Wayland output on its own once
// `locked` flips true — unlike every other top-layer surface in this shell
// there is no manual per-screen Variants loop to write. PamContext lives
// here, not per surface: one authentication attempt applies regardless of
// which output's input cell the user is looking at.
//
// See nix/testvm.nix's security.pam.services.formalshell-lock comment for
// why this config name exists rather than reusing "login" (console-specific
// checks this isn't) — a real deployment needs the same system-side
// declaration (Task 7 documents it; the home-manager module alone cannot
// create a PAM service).
Item {
    id: root

    // Uppercase failure text for the input cell's meta row; "" means no
    // error is showing. Cleared the moment a fresh lock() starts.
    property string authError: ""
    property bool authenticating: false

    property string _pendingPassword: ""

    property alias locked: sessionLock.locked
    readonly property alias secure: sessionLock.secure

    function lock() {
        root.authError = "";
        sessionLock.locked = true;
    }

    // Called by LockSurface's TextInput.onAccepted (forwarded through the
    // submit signal bound at the surface Component below) — the sole unlock
    // path. No IPC verb mirrors this on purpose: a headless "type this
    // password" hook would bypass the exact TextInput/PamContext wiring a
    // real unlock exercises, so the smoke rig authenticates with real
    // synthetic keystrokes (wtype) instead of a shortcut IPC call.
    function submitPassword(password) {
        if (pam.active)
            return;
        root._pendingPassword = password;
        root.authError = "";
        root.authenticating = true;
        pam.start();
    }

    PamContext {
        id: pam
        config: "formalshell-lock"

        // pam_unix's password prompt arrives as a message with
        // responseRequired true; respond immediately with whatever
        // submitPassword() buffered rather than surfacing a second prompt —
        // this lock screen only ever has one field to answer with.
        onPamMessage: {
            if (pam.responseRequired) {
                pam.respond(root._pendingPassword);
                root._pendingPassword = "";
            }
        }

        // onError always precedes a completed(PamResult.Error) emission
        // (qml.cpp's onError doubles as onCompleted(Error)), so this alone
        // covers every failure path — wrong password, pam error, max tries.
        onCompleted: result => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                root.authError = "";
                sessionLock.locked = false;
            } else {
                root.authError = "AUTHENTICATION FAILED";
            }
        }
    }

    WlSessionLock {
        id: sessionLock

        surface: Component {
            LockSurface {
                authError: root.authError
                authenticating: root.authenticating
                onSubmit: password => root.submitPassword(password)
            }
        }
    }
}
