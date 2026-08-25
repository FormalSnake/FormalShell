import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services

// The shell's polkit consent surface (M16 Task 4, laptop feature parity
// with omarchy, reimplemented against `~/Developer/omarchy/shell/plugins/
// polkit/PolkitAgent.qml`'s flow-tracking, read-reference only, never
// copied). One centred card over the modal scrim, shown for as long as
// PolkitService.isActive holds a live authentication request (M45 D4): a
// section label, the action's own message in sans, the identity being
// asked to authenticate as a section label over its mono name, the shadcn
// input, and an outline Cancel beside a default Authenticate.
// Deliberately without AuthPrompt.qml's clock/date, which belong to the
// lock screen alone. No shake (the lock screen's own idiom is the field's
// error state, nothing more physical), no fingerprint branch
// (password-only here).
//
// The typed password only ever reaches `flow.submit()` below, never
// logged, never mirrored into settings/state, never touched by the
// `debug` IPC dump (CLAUDE.md's secrets discipline for this task).
PanelWindow {
    id: root

    readonly property var _flow: PolkitService.flow
    readonly property bool _active: PolkitService.isActive

    // Local, transient UI state, never read from `flow.failed` directly:
    // that property stays true for the rest of the *flow* (module.md: a
    // failed attempt auto-starts a fresh session for a retry), so binding
    // to it would leave "WRONG PASSWORD" stuck on screen through a
    // subsequent successful retry. `authenticationFailed` below is the
    // real, transient signal this state actually tracks.
    property bool submitted: false
    property bool errorState: false

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    readonly property bool _inputEnabled: !!(root._flow && root._flow.isResponseRequired) && !root.submitted

    function _identityName() {
        var flow = root._flow;
        if (!flow || !flow.selectedIdentity)
            return "";
        var identity = flow.selectedIdentity;
        return identity.displayName || identity.string || "";
    }

    // PAM's own conversation prompt, verbatim (trimmed), never the
    // static "Enter Password" once a real one has arrived. A single-
    // prompt password-only stack never notices ("Password: " trimmed
    // reads the same as the fallback); a 2FA/U2F stack's later prompts
    // ("Verification code: ", "Please touch the device.") show their own
    // question instead of a placeholder that no longer matches what's
    // being asked for.
    function _fieldPlaceholder() {
        var flow = root._flow;
        var prompt = flow ? flow.inputPrompt.trim() : "";
        return prompt !== "" ? prompt : "Enter Password";
    }

    function _submit() {
        var flow = root._flow;
        if (!flow || !flow.isResponseRequired)
            return;
        root.submitted = true;
        root.errorState = false;
        flow.submit(passwordInput.text);
        passwordInput.text = "";
    }

    function _cancel() {
        var flow = root._flow;
        passwordInput.text = "";
        root.submitted = false;
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    function _refocus() {
        if (root._active && root._inputEnabled)
            passwordInput.forceFocus();
    }

    // A fresh request (this flip going true, not just any change while
    // already active, a mid-conversation supplementary message must not
    // reset the field the user is mid-typing into) starts clean.
    on_ActiveChanged: {
        if (root._active) {
            root.submitted = false;
            root.errorState = false;
            passwordInput.text = "";
            Qt.callLater(root._refocus);
        }
    }

    Connections {
        target: root._flow

        function onAuthenticationFailed() {
            root.errorState = true;
            root.submitted = false;
            passwordInput.text = "";
            Qt.callLater(root._refocus);
        }

        // `isResponseRequired` (and so `_inputEnabled`) starts false and
        // only flips true once the PAM stack actually asks for a
        // password, reproduced directly: that flip lands AFTER
        // `isActive`'s own, so the `on_ActiveChanged` refocus below fires
        // too early (`_inputEnabled` still false, `_refocus()` no-ops) and
        // nothing else ever retried, leaving real Wayland keyboard focus
        // parked on `backdrop`, which has no key handler beyond Escape,
        // forever. Every real keystroke silently went nowhere; the field
        // itself was correctly enabled (a live binding), just never
        // actually focused.
        //
        // Also the only place a second (or later) PAM prompt in the same
        // session can clear `submitted`: quickshell's AuthFlow::request()
        // (flow.cpp) flips `isResponseRequired` true again for every
        // conversation prompt, not just the first, a 2FA/U2F stack that
        // asks twice would otherwise leave `submitted` latched from the
        // first `_submit()` forever (it's only ever cleared by a fresh
        // request or a failed one), stranding the card on "CHECKING…"
        // with the field permanently disabled.
        function onIsResponseRequiredChanged() {
            if (root._flow && root._flow.isResponseRequired)
                root.submitted = false;
            Qt.callLater(root._refocus);
        }
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4), same idiom as
    // every other floating surface here, `_active` dropping (auth
    // succeeded, or the daemon/user cancelled) is this surface's only
    // "close" path; there is no summon/dismiss API of its own to call.
    visible: root._active || card.opacity > 0
    color: "transparent"

    // Top, matching Menu.qml's own layer, not Overlay: reproduced
    // directly, an Overlay-layer surface with `keyboardFocus: Exclusive`
    // never actually received wtype's synthetic keystrokes in the smoke
    // rig (Screensaver.qml is this shell's only other Overlay surface, and
    // its own keyboard-dismiss path has never been wtype-exercised
    // either, Menu.qml's Top+Exclusive combination is the one proven
    // working here).
    WlrLayershell.namespace: "formalshell:polkit"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Exclusive, not OnDemand: unlike Panel.qml/Center.qml (pointer-driven,
    // keyboard nav is a secondary aid claimed only after a real click
    // already triggered open()), this surface needs to already be
    // receiving keystrokes the instant it maps, no prior click ever
    // happens, the request is entirely OS-triggered. Menu.qml's own search
    // field is the sibling case (typed input from the first frame) and
    // makes the identical choice. Reproduced directly: OnDemand here never
    // actually received wtype's synthetic keystrokes in the smoke rig even
    // though the card rendered: no real keyboard focus ever reached an
    // on-demand layer surface with no preceding pointer interaction.
    WlrLayershell.keyboardFocus: root._active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    Item {
        id: backdrop
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root._cancel()

        // The modal scrim (spec "Depth"): plain black at half opacity, the
        // same one the launcher and the lock screen draw, fading with the
        // card so a request arrives as one motion.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root._active ? 0.5 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root._refocus()
        }

        Card {
            id: card
            anchors.centerIn: parent

            // Enter/exit fade (DESIGN.md §4): opacity only, no slide. A
            // screen-centred card has no edge to slide in from, the same
            // reasoning the screensaver's own entrance carve-out documents.
            opacity: root._active ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root._refocus()
            }

            Column {
                id: column
                // The field's own width carries the card: the request text
                // wraps to it and the footer sits under it.
                width: Theme.space.popupWidthNarrow
                spacing: Theme.space.sectionGap

                SectionLabel {
                    text: "Authentication required"
                }

                Text {
                    width: parent.width
                    text: root._flow ? root._flow.message : ""
                    color: Theme.color.foreground
                    font.family: Theme.fontFamilySans
                    font.pixelSize: Theme.fontSize.body
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: Theme.space.rowGap
                    visible: root._identityName() !== ""

                    SectionLabel {
                        text: "Identity"
                    }

                    // An account name, so mono (spec "Type").
                    Text {
                        width: parent.width
                        text: root._identityName()
                        color: Theme.color.mutedForeground
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSize.bodySmall
                        elide: Text.ElideRight
                    }
                }

                // The field stays mounted through a submitted attempt so the
                // card does not resize under the pointer; it is the disabled
                // state, and the placeholder, that say an attempt is in
                // flight.
                Input {
                    id: passwordInput
                    width: parent.width
                    enabled: root._inputEnabled
                    echoMode: (root._flow && root._flow.responseVisible) ? TextInput.Normal : TextInput.Password
                    placeholder: root.submitted ? "Checking" : root._fieldPlaceholder()
                    error: root.errorState
                    errorText: "Wrong password"

                    Keys.onEscapePressed: root._cancel()
                    onAccepted: root._submit()
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.space.controlGap

                    Button {
                        variant: "outline"
                        text: "Cancel"
                        onClicked: root._cancel()
                    }

                    Button {
                        text: "Authenticate"
                        enabled: root._inputEnabled
                        onClicked: root._submit()
                    }
                }
            }
        }
    }
}
