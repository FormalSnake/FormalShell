import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services

// The shell's polkit consent surface (M16 Task 4, laptop feature parity
// with omarchy — reimplemented against `~/Developer/omarchy/shell/plugins/
// polkit/PolkitAgent.qml`'s flow-tracking, read-reference only, never
// copied). One centered omarchy-card (DESIGN.md §Panels chrome) shown for
// as long as PolkitService.isActive holds a live authentication request:
// an uppercase "AUTHENTICATION REQUIRED" header, the action's own message,
// the identity being asked to authenticate as a dim meta row, and the
// AuthPrompt field idiom (masked `●` input, "CHECKING…" while a submitted
// attempt is in flight, "WRONG PASSWORD" in urgent italic on retry) —
// deliberately without AuthPrompt.qml's clock/date, which belong to the
// lock screen alone. No shake (the plan drops it — the lock screen's own
// idiom is the urgent border plus italic message, nothing more physical),
// no fingerprint branch (password-only here).
//
// The typed password only ever reaches `flow.submit()` below — never
// logged, never mirrored into settings/state, never touched by the
// `debug` IPC dump (CLAUDE.md's secrets discipline for this task).
PanelWindow {
    id: root

    readonly property var _flow: PolkitService.flow
    readonly property bool _active: PolkitService.isActive

    // Local, transient UI state — never read from `flow.failed` directly:
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

    readonly property real _cardWidth: Theme.space.popupWidthWide
    readonly property bool _inputEnabled: !!(root._flow && root._flow.isResponseRequired) && !root.submitted

    function _identityLabel() {
        var flow = root._flow;
        if (!flow || !flow.selectedIdentity)
            return "";
        var identity = flow.selectedIdentity;
        return "AS " + (identity.displayName || identity.string || "");
    }

    // PAM's own conversation prompt, verbatim (trimmed) — never the
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
            passwordInput.forceActiveFocus();
    }

    // A fresh request (this flip going true, not just any change while
    // already active — a mid-conversation supplementary message must not
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
        // password — reproduced directly: that flip lands AFTER
        // `isActive`'s own, so the `on_ActiveChanged` refocus below fires
        // too early (`_inputEnabled` still false, `_refocus()` no-ops) and
        // nothing else ever retried, leaving real Wayland keyboard focus
        // parked on `backdrop` — which has no key handler beyond Escape —
        // forever. Every real keystroke silently went nowhere; the field
        // itself was correctly enabled (a live binding), just never
        // actually focused.
        //
        // Also the only place a second (or later) PAM prompt in the same
        // session can clear `submitted`: quickshell's AuthFlow::request()
        // (flow.cpp) flips `isResponseRequired` true again for every
        // conversation prompt, not just the first — a 2FA/U2F stack that
        // asks twice would otherwise leave `submitted` latched from the
        // first `_submit()` forever (it's only ever cleared by a fresh
        // request or a failed one), stranding the card on "CHECKING…"
        // with the field permanently hidden.
        function onIsResponseRequiredChanged() {
            if (root._flow && root._flow.isResponseRequired)
                root.submitted = false;
            Qt.callLater(root._refocus);
        }
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4), same idiom as
    // every other floating surface here — `_active` dropping (auth
    // succeeded, or the daemon/user cancelled) is this surface's only
    // "close" path; there is no summon/dismiss API of its own to call.
    visible: root._active || card.opacity > 0
    color: "transparent"

    // Top, matching Menu.qml's own layer — not Overlay: reproduced
    // directly, an Overlay-layer surface with `keyboardFocus: Exclusive`
    // never actually received wtype's synthetic keystrokes in the smoke
    // rig (Screensaver.qml is this shell's only other Overlay surface, and
    // its own keyboard-dismiss path has never been wtype-exercised
    // either — Menu.qml's Top+Exclusive combination is the one proven
    // working here).
    WlrLayershell.namespace: "formalshell:polkit"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: -1
    // Exclusive, not OnDemand: unlike Panel.qml/Center.qml (pointer-driven,
    // keyboard nav is a secondary aid claimed only after a real click
    // already triggered open()), this surface needs to already be
    // receiving keystrokes the instant it maps — no prior click ever
    // happens, the request is entirely OS-triggered. Menu.qml's own search
    // field is the sibling case (typed input from the first frame) and
    // makes the identical choice. Reproduced directly: OnDemand here never
    // actually received wtype's synthetic keystrokes in the smoke rig even
    // though the card rendered — niri never shifted real keyboard focus to
    // an on-demand layer surface with no preceding pointer interaction.
    WlrLayershell.keyboardFocus: root._active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }

    Item {
        id: backdrop
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root._cancel()

        MouseArea {
            anchors.fill: parent
            onClicked: root._refocus()
        }

        Item {
            id: card
            anchors.centerIn: parent
            width: root._cardWidth
            // `popupPadding`, not `panelPadding` (DESIGN.md §1.3's
            // card-gutter split): this is a screen-centered summoned
            // surface like the menu and the notification center, not a
            // bar-anchored popout, so it keeps the roomier of the two
            // gutters rather than following panels down to 8.
            implicitHeight: column.implicitHeight + Theme.space.popupPadding * 2
            height: implicitHeight

            // Enter/exit fade (DESIGN.md §4): opacity only, no slide — a
            // screen-centered card has no edge to slide in from, the same
            // reasoning the screensaver's own entrance carve-out documents.
            opacity: root._active ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.color.background
                border.width: Theme.borderWidth
                border.color: Theme.color.rule
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root._refocus()
            }

            Column {
                id: column
                anchors.centerIn: parent
                width: parent.width - Theme.space.popupPadding * 2
                spacing: Theme.space.lg

                MetaLabel {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "AUTHENTICATION REQUIRED"
                }

                Text {
                    width: parent.width
                    text: root._flow ? root._flow.message : ""
                    color: Theme.color.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                MetaLabel {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root._identityLabel()
                }

                // Only shown for a state worth calling out (checking/error),
                // same rule AuthPrompt.qml's own `showLabel` documents — the
                // field below stays visible and typable through both states
                // (bar the brief window while an attempt is actually in
                // flight), so "on retry" reads as this line appearing above
                // an already-usable field, never the field disappearing.
                MetaLabel {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.submitted || root.errorState
                    text: root.submitted ? "CHECKING…" : "WRONG PASSWORD"
                    color: root.errorState ? Theme.color.urgent : Theme.color.foregroundDim
                    font.italic: root.errorState
                }

                Item {
                    id: fieldBox
                    width: parent.width
                    height: passwordInput.implicitHeight + Theme.space.lg * 2
                    visible: !root.submitted

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: "transparent"
                        // Theme.fieldBorderWidth: the same 3px-equivalent
                        // outline AuthPrompt.qml's own password field draws
                        // (audit "auth-field border parity") — previously
                        // computed here independently.
                        border.width: Theme.fieldBorderWidth
                        border.color: root.errorState ? Theme.color.urgent : Theme.color.rule
                    }

                    MetaLabel {
                        anchors.centerIn: parent
                        visible: passwordInput.text.length === 0
                        text: root._fieldPlaceholder()
                        // Faint placeholders (DESIGN.md §1.4, M19 Task 4):
                        // one band under the field's own label/status text
                        // above, which stays foregroundDim/urgent.
                        color: Theme.color.foregroundFaint
                    }

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: Theme.space.xxl
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.color.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                        echoMode: (root._flow && root._flow.responseVisible) ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        enabled: root._inputEnabled
                        selectByMouse: true

                        Keys.onEscapePressed: root._cancel()
                        onAccepted: root._submit()
                    }
                }
            }
        }
    }
}
