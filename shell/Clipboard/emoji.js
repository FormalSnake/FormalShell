.pragma library

// Whether a clipboard capture is nothing but emoji, counted in grapheme
// clusters, so the launcher can draw it as a picture rather than as a line
// of body text. Hand-rolled over code points: V4 has no Intl.Segmenter and
// its regex engine has no \p{Extended_Pictographic}.

// A capture this many clusters long or longer reads as text, not a picture.
var MAX_CLUSTERS = 8;

var ZWJ = 0x200D;
var VS15 = 0xFE0E;
var VS16 = 0xFE0F;
var KEYCAP = 0x20E3;

// BMP code points whose default presentation is emoji, so they count bare.
// Everything else in the BMP symbol blocks defaults to text and counts only
// with VS16 after it (❤ vs ❤️).
var BMP_EMOJI_DEFAULT = [
    [0x231A, 0x231B], [0x23E9, 0x23EC], [0x23F0, 0x23F0], [0x23F3, 0x23F3],
    [0x25FD, 0x25FE], [0x2614, 0x2615], [0x2648, 0x2653], [0x267F, 0x267F],
    [0x2693, 0x2693], [0x26A1, 0x26A1], [0x26AA, 0x26AB], [0x26BD, 0x26BE],
    [0x26C4, 0x26C5], [0x26CE, 0x26CE], [0x26D4, 0x26D4], [0x26EA, 0x26EA],
    [0x26F2, 0x26F3], [0x26F5, 0x26F5], [0x26FA, 0x26FA], [0x26FD, 0x26FD],
    [0x2705, 0x2705], [0x270A, 0x270B], [0x2728, 0x2728], [0x274C, 0x274C],
    [0x274E, 0x274E], [0x2753, 0x2755], [0x2757, 0x2757], [0x2795, 0x2797],
    [0x27B0, 0x27B0], [0x27BF, 0x27BF], [0x2B1B, 0x2B1C], [0x2B50, 0x2B50],
    [0x2B55, 0x2B55]
];

var BMP_EMOJI_TEXT = [
    [0x00A9, 0x00A9], [0x00AE, 0x00AE], [0x203C, 0x203C], [0x2049, 0x2049],
    [0x2122, 0x2122], [0x2139, 0x2139], [0x2194, 0x21AA], [0x231A, 0x23FF],
    [0x24C2, 0x24C2], [0x25AA, 0x25FE], [0x2600, 0x27BF], [0x2934, 0x2935],
    [0x2B05, 0x2B55], [0x3030, 0x3030], [0x303D, 0x303D], [0x3297, 0x3297],
    [0x3299, 0x3299]
];

function _inRanges(cp, ranges) {
    for (var i = 0; i < ranges.length; i++)
        if (cp >= ranges[i][0] && cp <= ranges[i][1]) return true;
    return false;
}

function _isRegional(cp) { return cp >= 0x1F1E6 && cp <= 0x1F1FF; }
function _isSkinTone(cp) { return cp >= 0x1F3FB && cp <= 0x1F3FF; }
function _isTag(cp) { return cp >= 0xE0020 && cp <= 0xE007E; }
function _isKeycapBase(cp) { return (cp >= 0x30 && cp <= 0x39) || cp === 0x23 || cp === 0x2A; }

function _isSupplementaryPictograph(cp) {
    return (cp >= 0x1F000 && cp <= 0x1FAFF && !_isRegional(cp)) || (cp >= 0x1FC00 && cp <= 0x1FFFD);
}

function _codePoints(text) {
    var out = [];
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length) {
            var d = text.charCodeAt(i + 1);
            if (d >= 0xDC00 && d <= 0xDFFF) {
                out.push((c - 0xD800) * 0x400 + (d - 0xDC00) + 0x10000);
                i++;
                continue;
            }
        }
        out.push(c);
    }
    return out;
}

// One emoji element at cps[i] (a pictograph with its presentation selector,
// skin tone and tag run), returning the index past it, or -1.
function _element(cps, i) {
    var cp = cps[i];
    var next = cps[i + 1];
    var j;
    if (_isSupplementaryPictograph(cp)) {
        j = i + 1;
        if (cps[j] === VS15) return -1;
        if (cps[j] === VS16) j++;
    } else if (_inRanges(cp, BMP_EMOJI_DEFAULT)) {
        j = i + 1;
        if (next === VS15) return -1;
        if (next === VS16) j++;
    } else if (_inRanges(cp, BMP_EMOJI_TEXT)) {
        if (next === VS16) j = i + 2;
        else if (_isSkinTone(next) || next === ZWJ) j = i + 1;
        else return -1;
    } else {
        return -1;
    }
    if (_isSkinTone(cps[j])) j++;
    if (_isTag(cps[j])) {
        while (_isTag(cps[j])) j++;
        if (cps[j] !== 0xE007F) return -1;
        j++;
    }
    return j;
}

// One grapheme cluster at cps[i], returning the index past it, or -1 when
// what starts there is not an emoji.
function _cluster(cps, i) {
    var cp = cps[i];
    if (_isRegional(cp))
        return _isRegional(cps[i + 1]) ? i + 2 : -1;
    if (_isKeycapBase(cp)) {
        var k = i + 1;
        if (cps[k] === VS16) k++;
        return cps[k] === KEYCAP ? k + 1 : -1;
    }
    var j = _element(cps, i);
    while (j > 0 && cps[j] === ZWJ) {
        if (j + 1 >= cps.length) return -1;
        j = _element(cps, j + 1);
    }
    return j;
}

// The number of emoji clusters `text` is made of, whitespace between them
// allowed, or 0 when anything else is in it or it runs to MAX_CLUSTERS.
function emojiCount(text) {
    if (typeof text !== "string") return 0;
    var cps = _codePoints(text);
    var count = 0;
    var i = 0;
    while (i < cps.length) {
        var cp = cps[i];
        if (cp === 0x20 || cp === 0x09 || cp === 0x0A || cp === 0x0D) {
            i++;
            continue;
        }
        var end = _cluster(cps, i);
        if (end < 0) return 0;
        count++;
        if (count >= MAX_CLUSTERS) return 0;
        i = end;
    }
    return count;
}

function isEmojiOnly(text) {
    return emojiCount(text) > 0;
}
