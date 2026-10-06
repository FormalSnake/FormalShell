.pragma library

// The chrome tables live in themes/*.json so the Rust shell (crates/fs-theme)
// reads the same files. A `.pragma library` cannot import JSON, so each one
// is read once, synchronously, the first time this file is imported. Qt
// refuses an XHR GET on a local file unless QML_XHR_ALLOW_FILE_READ is set:
// shell.qml and greeter.qml set it with an Env pragma, the test runners in
// their own environment.
//
// Retro is the metamorphosis table on different preset scalars, so it has
// no file of its own (metamorphosis.json's `notes.retro`).

function _load(name) {
    var url = Qt.resolvedUrl("themes/" + name + ".json");
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, false);
    xhr.send();
    if (!xhr.responseText)
        throw new Error("themes.js: could not read " + url + " (is QML_XHR_ALLOW_FILE_READ set?)");
    return JSON.parse(xhr.responseText);
}

var METAMORPHOSIS = _load("metamorphosis");
var PANTHEON = _load("pantheon");
var RETRO = METAMORPHOSIS;
