.pragma library

// Pure model for the launcher's Mirror view: turns what QtMultimedia's
// MediaDevices reports into the rows the view lists and cycles through.
// No Qt access, so it is testable head-on.
//
// A device arrives as { id, description, greyOnly }. `description` is the
// V4L2 card name, which uvcvideo cuts at 31 bytes and usually writes as
// "<product>: <interface>" ("ASUS FHD webcam: ASUS FHD webca" for the
// colour sensor, "ASUS FHD webcam: ASUS IR camera" for the IR one, and
// "Integrated Camera: Integrated I" on boards that truncate the interface
// name). `greyOnly` is true when every pixel format the device offers is
// Y8 or Y16, which is how an IR sensor presents itself even when its card
// name says nothing.

var IR_WORD = /\b(ir|infrared)\b/i;

function isIr(device) {
    return device.greyOnly === true || IR_WORD.test(String(device.description || ""));
}

// The product half of a "<product>: <interface>" card name, unless the
// interface half names the sensor itself (an IR one). The interface half
// is a truncated copy of the product name often enough that using it would
// print "ASUS FHD webca".
function name(description) {
    var text = String(description || "").trim();
    var at = text.indexOf(": ");
    if (at < 0)
        return text;
    var product = text.slice(0, at).trim();
    var iface = text.slice(at + 2).trim();
    if (product === "")
        return iface;
    if (iface !== "" && IR_WORD.test(iface))
        return iface;
    return product;
}

function label(description, ir) {
    var text = name(description);
    if (text === "")
        text = "Camera";
    if (ir && !IR_WORD.test(text))
        text += " IR";
    return text;
}

// /dev/video2 sorts after /dev/video10 as a string.
function _number(id) {
    var match = /(\d+)$/.exec(String(id));
    return match ? parseInt(match[1], 10) : Number.MAX_SAFE_INTEGER;
}

// Colour cameras first, then IR, each in node order, so the first row is
// the one a mirror should open on. Two rows with the same label get a
// running number, which keeps a pair of identical webcams apart.
function rows(devices) {
    var out = (devices || []).map(function (d) {
        var ir = isIr(d);
        return { id: String(d.id), ir: ir, label: label(d.description, ir) };
    });
    out.sort(function (a, b) {
        if (a.ir !== b.ir)
            return a.ir ? 1 : -1;
        return _number(a.id) - _number(b.id);
    });
    var seen = {};
    for (var i = 0; i < out.length; i++) {
        var count = (seen[out[i].label] = (seen[out[i].label] || 0) + 1);
        if (count > 1)
            out[i].label += " " + count;
    }
    return out;
}

function indexOf(list, id) {
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return i;
    }
    return -1;
}

// The camera to show after the list changed: the current one while it is
// still plugged in, otherwise the first row, "" when there is none.
function pick(list, currentId) {
    if (indexOf(list, currentId) >= 0)
        return currentId;
    return list.length > 0 ? list[0].id : "";
}

// The id `delta` places after `currentId`, wrapping both ways. A list of
// one stays on its only camera.
function step(list, currentId, delta) {
    if (list.length === 0)
        return "";
    var at = indexOf(list, currentId);
    if (at < 0)
        return list[0].id;
    var next = (at + delta) % list.length;
    if (next < 0)
        next += list.length;
    return list[next].id;
}
