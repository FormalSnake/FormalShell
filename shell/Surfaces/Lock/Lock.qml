import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.Core as Core

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
//
// M7 Task 4 (lock hardening) adds three things on top of Task 3's base
// lock: idle blanking with a wall-clock resume guard, a parallel
// fingerprint PAM flow, and a three-way error split (wrong password / pam
// error / account locked) instead of one blanket message,
// see `blanked`, `pamFingerprint` and `_resultError()` below.
Item {
    id: root

    // Failure text for the field's error caption; "" means no error is
    // showing. Cleared the moment a fresh lock() starts. Mapped from
    // PamResult by _resultError() so wrong password, a pam-level error and
    // an exhausted retry count each read distinctly rather than one blanket
    // "Authentication failed".
    property string authError: ""
    property bool authenticating: false

    property string _pendingPassword: ""

    // Idle blanking (spec §8, Task 4): once locked, `idleMonitor` mirrors
    // the compositor's own ext-idle-notify-v1 idle state — the real,
    // session-wide "no input anywhere" signal, not just activity inside
    // this surface's own input cell — so an organically-elapsed idle
    // timeout un-blanks the instant the compositor sees ANY input again,
    // no matter which output it lands on.
    //
    // `_resumeGuardActive` is the second, independent half: a suspend/
    // resume gap. `respectInhibitors: false` is deliberate — once the
    // session is actually locked, an app-held idle-inhibit (e.g. a video
    // call) should not keep a *locked* screen lit; that guarantee is worth
    // more than convenience here.
    //
    // Reads idleMonitor.isIdle/_resumeGuardActive into locals BEFORE the
    // `&&`/`||`, not inline — reproduced directly: with `sessionLock.locked
    // && (idleMonitor.isIdle || ...)` written inline, the very first
    // evaluation happens while `locked` is still false, so JS's `&&`
    // short-circuits before ever reading the right-hand side at all; QML's
    // dependency capture never sees those reads, so they're never
    // registered as bindings this property re-evaluates on, and
    // isIdleChanged firing later does nothing. Reading them unconditionally
    // first registers the dependency regardless of `locked`'s value, so
    // isIdleChanged correctly triggers a re-evaluation, which then reads
    // `sessionLock.locked` fresh (see lock()'s own comment for why that
    // specific read is safe despite the missing-notify bug).
    readonly property bool blanked: {
        const isIdle = idleMonitor.isIdle;
        const resumeGuard = root._resumeGuardActive;
        return sessionLock.locked && (isIdle || resumeGuard);
    }
    readonly property int blankAfterSeconds: Core.Config.get("lock.blankAfterSeconds", 30)

    property bool _resumeGuardActive: false
    property double _lastTickMs: 0
    readonly property int _tickIntervalMs: 1000

    // Fingerprint as a parallel PAM flow (spec §8): "enrolled" has no
    // hardware-probing API in this shell's ground truth (no Fprintd
    // binding), so it is expressed the same way every other optional
    // feature here is — a settings.json key. Empty (the default, and the
    // only state a VM with no reader can honestly test) means
    // `pamFingerprint` never starts: no prompt, password flow unaffected.
    readonly property string _fingerprintService: Core.Config.get("lock.fingerprintPamService", "")

    property alias locked: sessionLock.locked
    readonly property alias secure: sessionLock.secure

    // idleMonitor.enabled and tickTimer.running are driven imperatively from
    // here and _unlock() below rather than bound declaratively to
    // `sessionLock.locked` — verified (against session_lock.cpp) that
    // WlSessionLock::setLocked() only emits lockStateChanged() on its
    // *unlock* path (realizeLockTarget()'s locking branch never emits it),
    // so a QML binding of the form `enabled: sessionLock.locked` evaluates
    // once at construction (false) and then never re-fires when lock()
    // actually flips it true — reproduced directly: a live binding stuck at
    // enabled:false forever while `sessionLock.locked` itself correctly read
    // true on every fresh IPC status() call. `blanked` above is safe despite
    // reading the same property because its `&&` means a stale `false` read
    // for `locked` only ever suppresses a result that would already be
    // false; these two have no such combinator to hide behind.
    function lock() {
        root.authError = "";
        root._resumeGuardActive = false;
        root._lastTickMs = Date.now();
        sessionLock.locked = true;
        idleMonitor.enabled = true;
        tickTimer.start();
        if (root._fingerprintService !== "")
            fingerprintRetryTimer.restart();
    }

    // The only unlock path (see both PamContexts' onCompleted below) — pairs
    // with lock() so idleMonitor/tickTimer's imperative state always mirrors
    // sessionLock.locked exactly, never drifting into "still enabled after
    // unlock."
    function _unlock() {
        sessionLock.locked = false;
        idleMonitor.enabled = false;
        tickTimer.stop();
    }

    function _resultError(result) {
        switch (result) {
        case PamResult.MaxTries: return "Account locked";
        case PamResult.Failed: return "Wrong password";
        default: return "PAM error";
        }
    }

    // Resume-from-suspend guard: driven by `tickTimer` below reading
    // Date.now() (wall clock, moves during suspend) rather than an
    // accumulated tick count (which would not, since a suspended process
    // simply stops ticking and resumes counting from where it left off).
    // A gap much larger than the timer's own interval means real time
    // jumped further than one interval's worth since the last tick — the
    // machine was suspended (or the clock was stepped) — and the safe
    // default on waking is "blank now", not "keep trusting whatever the
    // idle monitor's own timeout was mid-counting when it happened."
    function _tick() {
        const now = Date.now();
        if (root._lastTickMs > 0 && now - root._lastTickMs > root._tickIntervalMs * 3)
            root._resumeGuardActive = true;
        root._lastTickMs = now;
    }

    // Called from every LockSurface's `activity` signal (real key/pointer
    // input reaching any output). Needed in addition to idleMonitor's own
    // isIdle transition below: a resume-guard trip can blank the surface
    // while isIdle is still false (the compositor's own idle timer is
    // monotonic and may not have elapsed yet), so isIdleChanged alone would
    // never fire to clear it in that case.
    function wake() {
        root._resumeGuardActive = false;
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
        // start() returns whether the conversation actually started
        // (PamContext::startConversation() logs qCritical and bails without
        // ever emitting completed/onError when `config` names a PAM service
        // /etc/pam.d/<config> doesn't have, e.g. formalshell-lock never
        // declared) — without this check that failure is a permanent silent
        // no-op: authenticating latches true forever, no error ever shows,
        // and the typed password sits in _pendingPassword indefinitely.
        if (!pam.start()) {
            root.authenticating = false;
            root._pendingPassword = "";
            root.authError = "PAM error";
        }
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
                root._unlock();
            } else {
                root.authError = root._resultError(result);
            }
        }
    }

    // Parallel fingerprint flow: independent PamContext, independent
    // conversation — it shares no state with `pam` above, so a pending
    // fingerprint attempt never disables or blocks the password field (spec
    // §8's "either can succeed" while both stay usable). `config` is only
    // ever non-empty when settings.json enrolls one; see
    // `_fingerprintService` above for why that's the only "enrolled" this
    // shell can express.
    PamContext {
        id: pamFingerprint
        config: root._fingerprintService

        // Fingerprint modules (e.g. pam_fprintd) don't typically prompt for
        // typed input, but respond immediately if one is ever requested so
        // this conversation can never sit blocked waiting on a field this
        // surface doesn't have.
        onPamMessage: {
            if (pamFingerprint.responseRequired)
                pamFingerprint.respond("");
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.authError = "";
                root._unlock();
            } else {
                root.authError = root._resultError(result);
                // A single failed scan shouldn't lock the reader out for
                // the rest of the session — retry — but MaxTries means the
                // method itself says "should not be used again" (PamResult
                // doc), so it stops here and leaves password as the sole
                // remaining path.
                if (result !== PamResult.MaxTries)
                    fingerprintRetryTimer.restart();
            }
        }
    }

    Timer {
        id: fingerprintRetryTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (sessionLock.locked && root._fingerprintService !== "" && !pamFingerprint.active)
                pamFingerprint.start();
        }
    }

    // `running` starts false and is toggled imperatively by lock()/_unlock()
    // — not bound to `sessionLock.locked` — see lock()'s comment for why.
    Timer {
        id: tickTimer
        interval: root._tickIntervalMs
        running: false
        repeat: true
        onTriggered: root._tick()
    }

    // `enabled` starts false and is toggled imperatively by lock()/_unlock()
    // — not bound to `sessionLock.locked` — see lock()'s comment for why.
    IdleMonitor {
        id: idleMonitor
        enabled: false
        timeout: root.blankAfterSeconds
        respectInhibitors: false
        onIsIdleChanged: {
            // Real input resuming (compositor-reported, not just "our own
            // TextInput got a key") is exactly the signal that also clears
            // a resume-guard trip — see `blanked`'s comment above.
            if (!idleMonitor.isIdle)
                root._resumeGuardActive = false;
        }
    }

    WlSessionLock {
        id: sessionLock

        surface: Component {
            LockSurface {
                authError: root.authError
                authenticating: root.authenticating
                blanked: root.blanked
                fingerprintEnrolled: root._fingerprintService !== ""
                onSubmit: password => root.submitPassword(password)
                onActivity: root.wake()
            }
        }
    }
}
