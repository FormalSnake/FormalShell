.pragma library

// Pure open-meteo glue (M6 Task 8, spec §Surfaces 2's weather panel):
// request URL construction and response→model parsing, including every
// failure shape WeatherPanel.qml needs to render an honest error cell
// instead of a hang or a silent blank. No Date.now()/XMLHttpRequest in
// here — the network side-effect and current-time formatting stay in
// WeatherPanel.qml, this file stays deterministic under test.

function buildUrl(latitude, longitude) {
    if (typeof latitude !== "number" || typeof longitude !== "number")
        return null;
    if (!isFinite(latitude) || !isFinite(longitude))
        return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180)
        return null;

    return "https://api.open-meteo.com/v1/forecast?"
        + "latitude=" + latitude
        + "&longitude=" + longitude
        + "&current=temperature_2m,weather_code"
        + "&daily=temperature_2m_max,temperature_2m_min,weather_code"
        + "&timezone=auto&forecast_days=5";
}

function _isNumber(v) {
    return typeof v === "number" && isFinite(v);
}

// status 0 is XMLHttpRequest's own signal for "never reached the server"
// (DNS failure, no route, timeout) — distinct from a real HTTP error status
// the server sent back, so the two get separate honest error labels.
function parseResponse(status, bodyText) {
    if (status === 0)
        return { ok: false, error: "network_error" };
    if (status !== 200)
        return { ok: false, error: "http_error" };

    var data;
    try {
        data = JSON.parse(bodyText);
    } catch (e) {
        return { ok: false, error: "malformed_json" };
    }

    if (!data || typeof data !== "object")
        return { ok: false, error: "missing_fields" };

    var current = data.current;
    if (!current || !_isNumber(current.temperature_2m) || !_isNumber(current.weather_code))
        return { ok: false, error: "missing_fields" };

    var daily = data.daily;
    if (!daily || !Array.isArray(daily.time) || !Array.isArray(daily.temperature_2m_max)
        || !Array.isArray(daily.temperature_2m_min) || !Array.isArray(daily.weather_code))
        return { ok: false, error: "missing_fields" };

    var forecast = [];
    for (var i = 0; i < daily.time.length; i++) {
        if (!_isNumber(daily.temperature_2m_max[i]) || !_isNumber(daily.temperature_2m_min[i]) || !_isNumber(daily.weather_code[i]))
            continue;
        forecast.push({
            date: daily.time[i],
            high: daily.temperature_2m_max[i],
            low: daily.temperature_2m_min[i],
            code: daily.weather_code[i]
        });
    }

    return {
        ok: true,
        current: { temperature: current.temperature_2m, code: current.weather_code },
        forecast: forecast
    };
}

// WMO weather_code (open-meteo's own scheme) grouped down to the handful of
// conditions the panel draws an icon for. The key is semantic, so both the
// label tables and the icon table below key off one grouping.
var _conditions = {
    0: "clear", 1: "clear",
    2: "partly-cloudy",
    3: "overcast",
    45: "fog", 48: "fog",
    51: "drizzle", 53: "drizzle", 55: "drizzle",
    56: "freezing-rain", 57: "freezing-rain", 66: "freezing-rain", 67: "freezing-rain",
    61: "rain", 63: "rain", 65: "rain",
    71: "snow", 73: "snow", 75: "snow", 77: "snow", 85: "snow", 86: "snow",
    80: "showers", 81: "showers", 82: "showers",
    95: "thunderstorm", 96: "thunderstorm", 99: "thunderstorm"
};

var _labels = {
    "clear": "CLEAR",
    "partly-cloudy": "PARTLY CLOUDY",
    "overcast": "OVERCAST",
    "fog": "FOG",
    "drizzle": "DRIZZLE",
    "freezing-rain": "FREEZING RAIN",
    "rain": "RAIN",
    "snow": "SNOW",
    "showers": "SHOWERS",
    "thunderstorm": "THUNDERSTORM",
    "unknown": "UNAVAILABLE"
};

function conditionKey(code) {
    return _conditions[code] || "unknown";
}

function conditionLabel(code) {
    return _labels[conditionKey(code)];
}

// The same condition as body text rather than a marker (DESIGN.md §5:
// uppercase belongs to section labels alone), for the panel hero's own
// line. Derived from the one table so a new condition never has to be
// written out twice.
function conditionText(code) {
    var label = conditionLabel(code);
    return label.charAt(0) + label.slice(1).toLowerCase();
}

// Three-letter weekday for a daily.time date-only string ("2026-07-28"),
// sentence case: a forecast row's day name is a word, so it reads in sans
// and is not uppercased. Date-only ISO strings parse as UTC midnight, so
// this reads the UTC day-of-week rather than the local one; the local
// getter would misdate the first and last forecast rows whenever the host's
// timezone sits west of UTC.
var _weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function weekdayLabel(dateStr) {
    return _weekdays[new Date(dateStr + "T00:00:00Z").getUTCDay()];
}

// Condition -> icon name (spec "Icons"): the panel and the bar cell both
// render these through Components/Icon.qml, so the active set decides the
// codepoint and no surface file carries one. Day and night differ only where
// the sky itself is the subject; a rain or snow icon draws the same either
// way in both sets. An unmapped code falls back to the thermometer, the same
// "no reading yet" icon the bar cell shows before the first fetch lands.
var _icons = {
    "clear": { day: "sun", night: "moon" },
    "partly-cloudy": { day: "cloud-sun", night: "cloud-moon" },
    "overcast": { day: "cloudy", night: "cloudy" },
    "fog": { day: "cloud-fog", night: "cloud-fog" },
    "drizzle": { day: "cloud-drizzle", night: "cloud-drizzle" },
    "freezing-rain": { day: "cloud-hail", night: "cloud-hail" },
    "rain": { day: "cloud-rain", night: "cloud-rain" },
    "snow": { day: "cloud-snow", night: "cloud-snow" },
    "showers": { day: "cloud-rain-wind", night: "cloud-rain-wind" },
    "thunderstorm": { day: "cloud-lightning", night: "cloud-lightning" }
};

var FALLBACK_ICON = "thermometer";

// isDay defaults true unless explicitly false: open-meteo's `current.is_day`
// is 0/1, WeatherPanel.qml converts to boolean before this ever runs, and a
// first-fetch caller with no day/night signal yet should read as day rather
// than guessing night.
function iconForCode(code, isDay) {
    var pair = _icons[conditionKey(code)];
    if (!pair) return FALLBACK_ICON;
    return isDay === false ? pair.night : pair.day;
}
