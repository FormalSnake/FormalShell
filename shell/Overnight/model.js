.pragma library

// Pure model for OvernightService. The service lists /sys/class/leds as one
// "name<TAB>trigger<TAB>brightness" line per device and this file decides
// which of them overnight is allowed to turn off.
//
// Only an LED with no active trigger ("[none]" in its trigger file) is ours:
// writing 0 to a triggered LED's brightness detaches the trigger in the
// kernel, and logind's SetBrightness (what brightnessctl goes through) has no
// way to put it back. That rules out the Wi-Fi activity LED and the lock-key
// indicators. input<N>:: devices are skipped by name as well, since a lock
// key's LED with its trigger already gone still belongs to the keyboard, not
// to us. An LED already at 0 is left alone so disable() never turns on
// something that was off.

// asusctl's Aura zones. A zone the chassis lacks makes asusctl exit non-zero,
// which the service ignores.
var AURA_ZONES = ["keyboard", "logo", "lightbar", "lid", "rear-glow"];

// Percent, never 0: some panels treat a zero backlight or VCP 10 as off.
var SCREEN_PERCENT = 1;

function parseLeds(text) {
    var out = [];
    var lines = (text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("\t");
        if (fields.length < 3)
            continue;
        var name = fields[0];
        var brightness = parseInt(fields[2], 10);
        if (name === "" || /^input\d+::/.test(name))
            continue;
        if (fields[1].indexOf("[none]") === -1)
            continue;
        if (!(brightness > 0))
            continue;
        out.push({ name: name, brightness: brightness });
    }
    return out;
}

// { name: brightness } for State, where it has to survive a shell restart.
function ledSnapshot(leds) {
    var out = {};
    for (var i = 0; i < leds.length; i++)
        out[leds[i].name] = leds[i].brightness;
    return out;
}

// argv tail for the restore loop: name, value, name, value.
function restoreArgs(snapshot) {
    var out = [];
    var names = Object.keys(snapshot || {});
    for (var i = 0; i < names.length; i++) {
        var value = parseInt(snapshot[names[i]], 10);
        if (value > 0)
            out.push(names[i], String(value));
    }
    return out;
}
