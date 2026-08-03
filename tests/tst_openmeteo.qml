import QtQuick
import QtTest
import "../shell/Weather/openmeteo.js" as Openmeteo

TestCase {
    name: "Openmeteo"

    function _currentJson(temp, code) {
        return JSON.stringify({
            current: { temperature_2m: temp, weather_code: code },
            daily: {
                time: ["2026-07-28", "2026-07-29"],
                temperature_2m_max: [24.1, 22.8],
                temperature_2m_min: [14.3, 13.9],
                weather_code: [code, 3]
            }
        });
    }

    // buildUrl

    function test_build_url_includes_latitude_and_longitude() {
        var url = Openmeteo.buildUrl(52.52, 13.41);
        verify(url.indexOf("latitude=52.52") >= 0);
        verify(url.indexOf("longitude=13.41") >= 0);
    }

    function test_build_url_targets_open_meteo_forecast_endpoint() {
        var url = Openmeteo.buildUrl(0, 0);
        verify(url.indexOf("https://api.open-meteo.com/v1/forecast?") === 0);
    }

    function test_build_url_requests_current_and_daily_variables() {
        var url = Openmeteo.buildUrl(0, 0);
        verify(url.indexOf("current=temperature_2m,weather_code") >= 0);
        verify(url.indexOf("daily=temperature_2m_max,temperature_2m_min,weather_code") >= 0);
    }

    function test_build_url_handles_negative_coordinates() {
        var url = Openmeteo.buildUrl(-33.87, -70.65);
        verify(url.indexOf("latitude=-33.87") >= 0);
        verify(url.indexOf("longitude=-70.65") >= 0);
    }

    function test_build_url_null_for_non_number_latitude() {
        compare(Openmeteo.buildUrl("52", 13.41), null);
    }

    function test_build_url_null_for_nan_longitude() {
        compare(Openmeteo.buildUrl(52.52, NaN), null);
    }

    function test_build_url_null_for_out_of_range_latitude() {
        compare(Openmeteo.buildUrl(91, 0), null);
    }

    function test_build_url_null_for_out_of_range_longitude() {
        compare(Openmeteo.buildUrl(0, 181), null);
    }

    // parseResponse — failure shapes

    function test_parse_response_network_error_on_zero_status() {
        var r = Openmeteo.parseResponse(0, "");
        compare(r.ok, false);
        compare(r.error, "network_error");
    }

    function test_parse_response_http_error_on_non_200_status() {
        var r = Openmeteo.parseResponse(400, '{"error":true,"reason":"bad request"}');
        compare(r.ok, false);
        compare(r.error, "http_error");
    }

    function test_parse_response_malformed_json() {
        var r = Openmeteo.parseResponse(200, "not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    function test_parse_response_missing_current_field() {
        var r = Openmeteo.parseResponse(200, JSON.stringify({ daily: { time: [], temperature_2m_max: [], temperature_2m_min: [], weather_code: [] } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_response_missing_daily_field() {
        var r = Openmeteo.parseResponse(200, JSON.stringify({ current: { temperature_2m: 10, weather_code: 0 } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_response_current_missing_temperature() {
        var r = Openmeteo.parseResponse(200, JSON.stringify({ current: { weather_code: 0 }, daily: { time: [], temperature_2m_max: [], temperature_2m_min: [], weather_code: [] } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_response_daily_missing_array() {
        var r = Openmeteo.parseResponse(200, JSON.stringify({ current: { temperature_2m: 10, weather_code: 0 }, daily: { time: [], temperature_2m_max: [], weather_code: [] } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    // parseResponse — success shape

    function test_parse_response_success_current_model() {
        var r = Openmeteo.parseResponse(200, _currentJson(18.5, 2));
        compare(r.ok, true);
        compare(r.current.temperature, 18.5);
        compare(r.current.code, 2);
    }

    function test_parse_response_success_forecast_rows() {
        var r = Openmeteo.parseResponse(200, _currentJson(18.5, 2));
        compare(r.forecast.length, 2);
        compare(r.forecast[0].date, "2026-07-28");
        compare(r.forecast[0].high, 24.1);
        compare(r.forecast[0].low, 14.3);
        compare(r.forecast[0].code, 2);
        compare(r.forecast[1].code, 3);
    }

    function test_parse_response_skips_malformed_forecast_row() {
        var body = JSON.stringify({
            current: { temperature_2m: 10, weather_code: 0 },
            daily: {
                time: ["2026-07-28", "2026-07-29"],
                temperature_2m_max: [20, "bad"],
                temperature_2m_min: [10, 9],
                weather_code: [0, 1]
            }
        });
        var r = Openmeteo.parseResponse(200, body);
        compare(r.ok, true);
        compare(r.forecast.length, 1);
        compare(r.forecast[0].date, "2026-07-28");
    }

    function test_parse_response_empty_forecast_arrays_still_ok() {
        var r = Openmeteo.parseResponse(200, JSON.stringify({ current: { temperature_2m: 10, weather_code: 0 }, daily: { time: [], temperature_2m_max: [], temperature_2m_min: [], weather_code: [] } }));
        compare(r.ok, true);
        compare(r.forecast.length, 0);
    }

    // conditionKey / conditionLabel

    function test_condition_key_clear_sky() {
        compare(Openmeteo.conditionKey(0), "clear");
    }

    function test_condition_key_partly_cloudy() {
        compare(Openmeteo.conditionKey(2), "partly-cloudy");
    }

    function test_condition_key_overcast() {
        compare(Openmeteo.conditionKey(3), "overcast");
    }

    function test_condition_key_fog() {
        compare(Openmeteo.conditionKey(45), "fog");
        compare(Openmeteo.conditionKey(48), "fog");
    }

    function test_condition_key_rain() {
        compare(Openmeteo.conditionKey(61), "rain");
        compare(Openmeteo.conditionKey(65), "rain");
    }

    function test_condition_key_freezing_rain() {
        compare(Openmeteo.conditionKey(56), "freezing-rain");
        compare(Openmeteo.conditionKey(67), "freezing-rain");
    }

    function test_condition_key_snow() {
        compare(Openmeteo.conditionKey(71), "snow");
        compare(Openmeteo.conditionKey(86), "snow");
    }

    function test_condition_key_showers() {
        compare(Openmeteo.conditionKey(80), "showers");
    }

    function test_condition_key_thunderstorm() {
        compare(Openmeteo.conditionKey(96), "thunderstorm");
    }

    function test_condition_key_unknown_code() {
        compare(Openmeteo.conditionKey(999), "unknown");
    }

    function test_condition_label_matches_key() {
        compare(Openmeteo.conditionLabel(0), "CLEAR");
        compare(Openmeteo.conditionLabel(999), "UNAVAILABLE");
    }

    // weekdayLabel

    function test_weekday_label_formats_uppercase_three_letters() {
        var label = Openmeteo.weekdayLabel("2026-07-28");
        compare(label.length, 3);
        compare(label, label.toUpperCase());
    }

    function test_weekday_label_matches_known_date() {
        // 2026-07-28 is a Tuesday (UTC).
        compare(Openmeteo.weekdayLabel("2026-07-28"), "TUE");
    }

    // glyphForCode — codepoints asserted by charCodeAt against the pinned
    // nerd-fonts-jetbrains-mono cmap (verified via fonttools ttx), never
    // against literal PUA characters typed into this test file.

    function test_glyph_for_code_clear_day_matches_pinned_codepoint() {
        compare(Openmeteo.glyphForCode(0, true).charCodeAt(0), 0xe30d); // weather-day_sunny
    }

    function test_glyph_for_code_clear_night_matches_pinned_codepoint() {
        compare(Openmeteo.glyphForCode(0, false).charCodeAt(0), 0xe32b); // weather-night_clear
    }

    function test_glyph_for_code_defaults_to_day_when_isday_omitted() {
        compare(Openmeteo.glyphForCode(0).charCodeAt(0), Openmeteo.glyphForCode(0, true).charCodeAt(0));
    }

    function test_glyph_for_code_overcast_same_glyph_day_and_night() {
        compare(Openmeteo.glyphForCode(3, true), Openmeteo.glyphForCode(3, false));
    }

    function test_glyph_for_code_day_and_night_differ_for_directional_conditions() {
        [0, 2, 45, 51, 56, 61, 71, 80, 95].forEach(function (code) {
            verify(Openmeteo.glyphForCode(code, true) !== Openmeteo.glyphForCode(code, false));
        });
    }

    function test_glyph_for_code_unknown_code_returns_fallback() {
        compare(Openmeteo.glyphForCode(999, true).charCodeAt(0), 0xe34e); // weather-thermometer_exterior
        compare(Openmeteo.glyphForCode(999, false).charCodeAt(0), 0xe34e);
    }

    function test_glyph_for_code_totality_every_documented_code_resolves() {
        // Every WMO code openmeteo.js's _conditions table maps, mirroring
        // the conditionKey coverage above — none of these may fall back.
        var codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 66, 67, 61, 63, 65,
            71, 73, 75, 77, 85, 86, 80, 81, 82, 95, 96, 99];
        var fallback = 0xe34e;
        codes.forEach(function (code) {
            verify(Openmeteo.glyphForCode(code, true).charCodeAt(0) !== fallback);
            verify(Openmeteo.glyphForCode(code, false).charCodeAt(0) !== fallback);
        });
    }
}
