.pragma library

// LockService's decision, kept as plain JS so a test can drive it without a
// Quickshell engine (the same split corners.js and park.js already take).
//
// `lock.command` is an argv list: non-empty means an external locker owns
// the session (hyprlock, swaylock, `loginctl lock-session`), empty means the
// built-in WlSessionLock surface is raised. Exactly one of the two runs per
// request.

// settings.json is user input. Anything that is not a list of non-empty
// strings is no command at all rather than a half-built argv spawned with a
// hole in it.
function argv(value) {
    if (!Array.isArray(value))
        return [];
    var out = [];
    for (var i = 0; i < value.length; i++) {
        if (typeof value[i] !== "string" || value[i] === "")
            return [];
        out.push(value[i]);
    }
    return out;
}

function isExternal(value) {
    return argv(value).length > 0;
}

// Routes one lock request. `spawn(argv)` and `raise()` are the two sides;
// exactly one of them is called. Returns the caller's reply string.
//
// `missing` is true once a lookup found no such binary. The compositor's exec
// never reports back, so spawning it would leave the session unlocked with
// nothing said; the built-in surface locks instead.
function lock(command, spawn, raise, missing) {
    var resolved = argv(command);
    if (resolved.length === 0 || missing === true)
        return raise();
    spawn(resolved);
    return "ok";
}

// `lock status`'s payload. A foreign locker never reports back, so every
// field the built-in surface owns reads null in the external case rather
// than a stale value or an invented one.
function status(command, surface) {
    if (isExternal(command))
        return { external: true, locked: null, secure: null, authError: null, blanked: null, outputs: null };
    return {
        external: false,
        locked: surface.locked,
        secure: surface.secure,
        authError: surface.authError,
        blanked: surface.blanked,
        outputs: surface.outputs || {}
    };
}

// One line of `gdbus monitor --system --dest org.freedesktop.login1`. logind
// signals PrepareForSleep(true) before a suspend or hibernate and
// PrepareForSleep(false) once the machine is back:
//   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)
// Returns that boolean, or null for any other line.
function prepareForSleep(line) {
    var m = /\borg\.freedesktop\.login1\.Manager\.PrepareForSleep \((true|false),\)/.exec(line || "");
    return m ? m[1] === "true" : null;
}

// The built-in surface gets this long to report `secure` before the sleep
// inhibitor is let go anyway. logind's own InhibitDelayMaxSec (5s by
// default) caps the hold regardless; this keeps a lock that never lands from
// spending all of it.
var secureWaitMs = 3000;

// An external locker never reports back, so all the shell can give it is a
// head start before suspend proceeds.
var externalWaitMs = 1000;

// Why the sleep inhibitor can be released now, or "" to keep holding it.
// `result` is lock()'s reply, "already" when the session was locked before
// logind asked.
function sleepRelease(external, result, secure, elapsedMs) {
    if (result === "already")
        return "already";
    if (external)
        return elapsedMs >= externalWaitMs ? "external" : "";
    if (result !== "ok")
        return "failed";
    if (secure === true)
        return "secure";
    return elapsedMs >= secureWaitMs ? "timeout" : "";
}
