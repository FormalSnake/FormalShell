.pragma library

// Pure model groundwork for the audio panel's omarchy-style mixer (M15
// Task 1): stream filtering, label fallback chain, and the two volume
// clamps (device vs per-app overdrive). No Quickshell.Services.Pipewire
// access, so it's testable head-on (mirrors Network/model.js).

// Ported from omarchy's audio Model.js (MIT, Copyright (c) David
// Heinemeier Hansson): identifies true playback streams using only
// pre-bind-safe fields (isStream, isSink, type). PwNode.properties is
// invalid until the node is bound, and reading it while streams churn
// (a capture app starting, say) destabilized quickshell's Pipewire
// service in omarchy's own history — so this never touches `properties`.
function isPlaybackStream(node) {
    if (!node || !node.isStream) return false;
    if (node.isSink === true) return true;

    var mediaClass = String(node.type || "");
    return mediaClass.indexOf("Stream/Output/Audio") !== -1
        || mediaClass.indexOf("AudioOutStream") !== -1
        || mediaClass.indexOf("Output") !== -1;
}

// application.name -> node.description -> media.name -> node.name, the
// same order omarchy's rawStreamLabel reads. `props` must only be passed
// once the caller has confirmed node.ready (properties is invalid
// pre-bind, same constraint as isPlaybackStream above) — this function
// itself takes the already-read values so it stays free of that timing
// concern entirely.
function streamLabel(props, description, name) {
    var p = props || {};
    return p["application.name"] || description || p["media.name"] || name || "";
}

// Master output/input sliders clamp to 1.0 (DESIGN.md's flat track never
// overdrives past full); per-app streams allow 0..1.5 overdrive, per
// omarchy's mixer behavior.
function clampDevice(v) {
    return Math.max(0, Math.min(1, v));
}

function clampStream(v) {
    return Math.max(0, Math.min(1.5, v));
}
