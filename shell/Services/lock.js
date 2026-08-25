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
function lock(command, spawn, raise) {
    var resolved = argv(command);
    if (resolved.length === 0)
        return raise();
    spawn(resolved);
    return "ok";
}

// `lock status`'s payload. A foreign locker never reports back, so every
// field the built-in surface owns reads null in the external case rather
// than a stale value or an invented one.
function status(command, surface) {
    if (isExternal(command))
        return { external: true, locked: null, secure: null, authError: null, blanked: null };
    return {
        external: false,
        locked: surface.locked,
        secure: surface.secure,
        authError: surface.authError,
        blanked: surface.blanked
    };
}
