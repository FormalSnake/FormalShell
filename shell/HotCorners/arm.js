.pragma library

// Pure arming state machine for one hot corner (HotCorners.qml drives it).
// No Quickshell, no Config, no clock of its own: every transition takes the
// caller's `nowMs`, so the whole rule set is testable head-on the way
// corners.js is.
//
// The problem it exists for: firing a corner maps the action's OWN surface
// (the lock plate, the screensaver overlay) over the corner, which takes the
// pointer with it. When that surface goes away the compositor hands the
// pointer straight back to a corner the cursor never really left, and the
// enter that arrives is indistinguishable, on its own, from a fresh
// approach. Re-arming on that enter relocks the session the instant it is
// unlocked, under a parked cursor (owner report, 2026-08-26).
//
// The rule: after the action ENDS, the corner stays disarmed until the
// pointer has genuinely left the surface AND a quiet period has passed since
// the end. The hand-back is caught twice over, because neither signal is
// available on every compositor:
//
//   1. `pointerInside` at the end, read off the MouseArea. If the cursor is
//      still on the corner, no leave has happened yet and none is invented.
//   2. An enter arriving inside the cooldown, which is what the hand-back
//      looks like when the surface's hover state was dropped while the
//      action owned the pointer, so `pointerInside` read false. Such an
//      enter cancels the leave that preceded it instead of firing.
//
// Moving out and back in after the cooldown is an ordinary approach again
// and fires normally.

// The quiet period after an action ends, in ms. The same 400 as
// Theme.motion.reveal, the shell's longest surface reveal, on the reasoning
// that a corner must not fire again until the surface it fired is fully off
// screen and the compositor has settled its pointer focus. It is a constant
// here rather than the token because `motion.enabled: false` zeroes that
// token, and this is a correctness guard, not an animation.
var REARM_COOLDOWN_MS = 400;

// Whether an action reports its own end back to the shell, which is what
// starts the cooldown at the right moment rather than at the fire.
//
// "lock" does only while this shell owns the surface. An external locker
// (`lock.command`: hyprlock, swaylock, loginctl) owns the session on its own
// terms and never reports back, so its corner takes the same path a launcher
// action does: the end is the fire, and the leave requirement is the whole
// guard. That is weaker (a locker held up for a minute outlives the
// cooldown), and it is the most this shell can honestly say about a process
// it only spawned.
function reportsEnd(action, externalLock) {
    if (action === "lock")
        return externalLock !== true;
    return action === "screensaver";
}

function initial() {
    return { armed: true, running: false, endedAtMs: 0, left: false };
}

// The state a corner surface should come up in, given what its action is
// doing right now. These windows are not permanent: the Variants model
// behind them is rebuilt whenever the output list or the config changes, so
// a screen waking, a monitor being plugged in or a settings.json save while
// the session is locked destroys every corner and builds a fresh one. Coming
// up plainly armed there is the same relock by another road, because the
// enter the compositor sends the new surface at unlock lands on a corner
// with no memory of having fired. `endedAtMs` is the controller's record of
// when this action last ended, 0 if it never has.
function adopt(nowMs, actionRunning, endedAtMs) {
    if (actionRunning === true)
        return _state(false, true, 0, false);
    if (endedAtMs > 0 && (nowMs - endedAtMs) < REARM_COOLDOWN_MS)
        return _state(false, false, endedAtMs, false);
    return initial();
}

function _state(armed, running, endedAtMs, left) {
    return { armed: armed, running: running, endedAtMs: endedAtMs, left: left };
}

// May an enter start the dwell? Either the corner is plainly armed, or its
// action is over, the pointer has left since, and the quiet period is up.
function isArmed(state, nowMs) {
    if (state.armed)
        return true;
    if (state.running)
        return false;
    return state.left && (nowMs - state.endedAtMs) >= REARM_COOLDOWN_MS;
}

// The corner fired. `reportsEnd` decides whether the cooldown waits for the
// action's own end or starts here.
function onFire(state, nowMs, actionReportsEnd) {
    if (actionReportsEnd === true)
        return _state(false, true, 0, false);
    return _state(false, false, nowMs, false);
}

// The action's own surface went away (the lock unmapped, the screensaver
// stopped). `pointerInside` is the corner's live hover state at that moment:
// false means the cursor is somewhere else entirely and the leave
// requirement is already met.
function onActionEnd(state, nowMs, pointerInside) {
    if (!state.running)
        return state;
    return _state(false, false, nowMs, pointerInside !== true);
}

function onEnter(state, nowMs) {
    if (isArmed(state, nowMs))
        return initial();
    // Inside the cooldown this is the compositor handing the pointer back,
    // so whatever leave preceded it belonged to the same unmap and stops
    // counting.
    return _state(false, state.running, state.endedAtMs, false);
}

function onExit(state) {
    if (state.armed)
        return state;
    // The action's own surface taking the pointer is not the pointer
    // leaving, so a leave while it is up says nothing.
    if (state.running)
        return state;
    return _state(false, false, state.endedAtMs, true);
}
