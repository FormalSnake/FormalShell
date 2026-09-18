.pragma library

// Sunrise and sunset, and the mode the clock resolves to between them
// (M61, the 2026-09-17 spec's Part 2 "Dark schedule"). The formula is the
// NOAA solar-position spreadsheet, which is the path elementary's
// settings-daemon takes to the same pair (`Utils/SunriseSunsetCalculator`,
// itself ported from gnome-settings-daemon's gsd-night-light-common.c).
// Both of those are GPL: the recipe and its constants are read here, no
// line of either is ported.
//
// Every function takes the clock as an argument, so this file has no
// Date.now() in it and stays deterministic under test (openmeteo.js's own
// contract). ThemeEngine.qml owns the timer, the location and the writes.

// The zenith the pair is measured at: 90 degrees plus 50 arcminutes for the
// sun's own radius and the standard refraction allowance. It is what makes
// these times land on a published table rather than on the geometric
// horizon crossing, and it is the value both references use.
var DARK_ZENITH_DEG = 90.833;

// The window with no location to compute one from, elementary's own
// fallback for a machine geoclue cannot place.
var FALLBACK_DARK_HOUR = 20;
var FALLBACK_LIGHT_HOUR = 6;

var MS_PER_DAY = 86400000;
var MINUTES_PER_DAY = 1440;

function _deg2rad(degrees) {
    return Math.PI * degrees / 180;
}

function _rad2deg(radians) {
    return radians * 180 / Math.PI;
}

// The spreadsheet's serial date: whole days from 1900-01-01 to `date`'s own
// UTC day, plus the two days its 1900 leap-year quirk carries. Read off the
// UTC day rather than the local one, which is what the reference does; a
// zone far enough from UTC that the two disagree at the hour of the call
// gets the adjacent day's pair, about a minute out either way.
function _dateSerial(date) {
    var utcMidnight = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
    return Math.round((utcMidnight - Date.UTC(1900, 0, 1)) / MS_PER_DAY) + 2;
}

// Minutes since local midnight, the unit both times below are in.
function localMinutes(date) {
    return date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60;
}

// `tzOffsetHours` is the offset the times come back in, hours east of UTC;
// left out it is `date`'s own local offset, which is what the shell wants
// and what makes the pair read as wall clock. Returns null for coordinates
// outside the globe, and `polar` set for a day with no crossing at all:
// "night" where the sun never climbs to the zenith above, "day" where it
// never drops to it. sunriseMinutes/sunsetMinutes can fall outside 0..1440
// where solar noon sits near the edge of the zone's own day.
function sunTimes(date, latitude, longitude, tzOffsetHours) {
    if (typeof latitude !== "number" || typeof longitude !== "number")
        return null;
    if (!isFinite(latitude) || !isFinite(longitude))
        return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180)
        return null;

    var tzOffset = typeof tzOffsetHours === "number" ? tzOffsetHours : -date.getTimezoneOffset() / 60;
    var julianDay = _dateSerial(date) + 2415018.5 - tzOffset / 24;
    var century = (julianDay - 2451545) / 36525;
    var meanLong = (280.46646 + century * (36000.76983 + century * 0.0003032)) % 360;
    var meanAnom = 357.52911 + century * (35999.05029 - 0.0001537 * century);
    var eccentricity = 0.016708634 - century * (0.000042037 + 0.0000001267 * century);
    var centre = Math.sin(_deg2rad(meanAnom)) * (1.914602 - century * (0.004817 + 0.000014 * century))
        + Math.sin(_deg2rad(2 * meanAnom)) * (0.019993 - 0.000101 * century)
        + Math.sin(_deg2rad(3 * meanAnom)) * 0.000289;
    var appLong = meanLong + centre - 0.00569
        - 0.00478 * Math.sin(_deg2rad(125.04 - 1934.136 * century));
    var meanObliquity = 23 + (26 + (21.448 - century
        * (46.815 + century * (0.00059 - century * 0.001813))) / 60) / 60;
    var obliquity = meanObliquity + 0.00256 * Math.cos(_deg2rad(125.04 - 1934.136 * century));
    var declination = _rad2deg(Math.asin(Math.sin(_deg2rad(obliquity)) * Math.sin(_deg2rad(appLong))));
    var varY = Math.tan(_deg2rad(obliquity / 2)) * Math.tan(_deg2rad(obliquity / 2));
    var equationOfTime = 4 * _rad2deg(varY * Math.sin(2 * _deg2rad(meanLong))
        - 2 * eccentricity * Math.sin(_deg2rad(meanAnom))
        + 4 * eccentricity * varY * Math.sin(_deg2rad(meanAnom)) * Math.cos(2 * _deg2rad(meanLong))
        - 0.5 * varY * varY * Math.sin(4 * _deg2rad(meanLong))
        - 1.25 * eccentricity * eccentricity * Math.sin(2 * _deg2rad(meanAnom)));
    var cosHourAngle = Math.cos(_deg2rad(DARK_ZENITH_DEG))
        / (Math.cos(_deg2rad(latitude)) * Math.cos(_deg2rad(declination)))
        - Math.tan(_deg2rad(latitude)) * Math.tan(_deg2rad(declination));
    var solarNoon = 720 - 4 * longitude - equationOfTime + tzOffset * 60;

    var times = {
        latitude: latitude,
        longitude: longitude,
        tzOffsetHours: tzOffset,
        polar: "",
        sunriseMinutes: null,
        sunsetMinutes: null
    };
    // acos has no answer here, and which side it ran off says which way the
    // whole day went: the reference returns a NaN pair instead, which every
    // caller would have to re-derive.
    if (cosHourAngle > 1 || cosHourAngle < -1) {
        times.polar = cosHourAngle > 1 ? "night" : "day";
        return times;
    }
    var hourAngle = _rad2deg(Math.acos(cosHourAngle));
    times.sunriseMinutes = solarNoon - hourAngle * 4;
    times.sunsetMinutes = solarNoon + hourAngle * 4;
    return times;
}

// The window a machine with no location falls back on.
function fallbackDark(now) {
    var hour = now.getHours();
    return hour >= FALLBACK_DARK_HOUR || hour < FALLBACK_LIGHT_HOUR;
}

// `times` null means no location, so the fallback window answers instead.
function isDark(now, times) {
    if (!times)
        return fallbackDark(now);
    if (times.polar === "night")
        return true;
    if (times.polar === "day")
        return false;
    var minutes = localMinutes(now);
    return minutes < times.sunriseMinutes || minutes >= times.sunsetMinutes;
}

function _atMinutes(now, minutes) {
    var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    return new Date(midnight.getTime() + Math.round(minutes * 60000));
}

function _nextLocalMidnight(now) {
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
}

function _fallbackNextChange(now) {
    var hour = now.getHours();
    if (hour < FALLBACK_LIGHT_HOUR)
        return _atMinutes(now, FALLBACK_LIGHT_HOUR * 60);
    if (hour < FALLBACK_DARK_HOUR)
        return _atMinutes(now, FALLBACK_DARK_HOUR * 60);
    return new Date(_nextLocalMidnight(now).getTime() + FALLBACK_LIGHT_HOUR * 3600000);
}

// When the mode this schedule resolves to changes next, as a Date. `times`
// must be the pair for `now`'s own day; past today's sunset that means
// tomorrow's sunrise, which is recomputed off the coordinates the pair
// carries. A polar day answers local midnight: nothing flips before the
// calculation itself does.
function nextChange(now, times) {
    if (!times)
        return _fallbackNextChange(now);
    if (times.polar !== "")
        return _nextLocalMidnight(now);
    var minutes = localMinutes(now);
    if (minutes < times.sunriseMinutes)
        return _atMinutes(now, times.sunriseMinutes);
    if (minutes < times.sunsetMinutes)
        return _atMinutes(now, times.sunsetMinutes);
    // Noon tomorrow rather than now plus 24 hours: a DST jump would land
    // the latter back on today.
    var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 12);
    var next = sunTimes(tomorrow, times.latitude, times.longitude, times.tzOffsetHours);
    if (!next || next.polar !== "")
        return _nextLocalMidnight(now);
    return _atMinutes(tomorrow, next.sunriseMinutes);
}

// The mode `theme.mode` resolves to, or null for a key that leaves the mode
// to state.json alone. "dark" and "light" pin it; "auto" reads the
// schedule, unless an override is still snoozing it (`{ mode, untilMs }`,
// one cycle, elementary's own reading of a manual flip under a schedule).
function effectiveMode(key, now, times, override) {
    if (key === "dark" || key === "light")
        return key;
    if (key !== "auto")
        return null;
    if (override && override.untilMs > now.getTime())
        return override.mode === "light" ? "light" : "dark";
    return isDark(now, times) ? "dark" : "light";
}

// Minutes since local midnight as wall clock, for `theme status`. Wraps a
// pair whose solar noon put it outside the day.
function hhmm(minutes) {
    if (typeof minutes !== "number" || !isFinite(minutes))
        return "";
    var total = Math.round(minutes) % MINUTES_PER_DAY;
    if (total < 0)
        total += MINUTES_PER_DAY;
    var hours = Math.floor(total / 60);
    var rest = total % 60;
    return (hours < 10 ? "0" : "") + hours + ":" + (rest < 10 ? "0" : "") + rest;
}
