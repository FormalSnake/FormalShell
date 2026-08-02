import QtQuick
import QtTest
import "../shell/Usage/usage.js" as Usage

TestCase {
    name: "Usage"

    // parseCredentials

    function test_parse_credentials_extracts_oauth_fields() {
        var r = Usage.parseCredentials(JSON.stringify({
            claudeAiOauth: {
                accessToken: "tok123",
                expiresAt: 1700000000000,
                subscriptionType: "pro",
                rateLimitTier: "max_20x"
            }
        }));
        compare(r.ok, true);
        compare(r.accessToken, "tok123");
        compare(r.expiresAtMs, 1700000000000);
        compare(r.subscriptionType, "pro");
        compare(r.rateLimitTier, "max_20x");
    }

    function test_parse_credentials_malformed_json() {
        var r = Usage.parseCredentials("not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    function test_parse_credentials_missing_oauth_block() {
        var r = Usage.parseCredentials(JSON.stringify({ other: true }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_credentials_empty_access_token() {
        var r = Usage.parseCredentials(JSON.stringify({ claudeAiOauth: { accessToken: "" } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_credentials_missing_expiry_defaults_to_zero() {
        var r = Usage.parseCredentials(JSON.stringify({ claudeAiOauth: { accessToken: "tok" } }));
        compare(r.ok, true);
        compare(r.expiresAtMs, 0);
    }

    // credentialsExpired

    function test_credentials_expired_true_past_deadline() {
        compare(Usage.credentialsExpired(1000, 2000), true);
    }

    function test_credentials_expired_false_before_deadline() {
        compare(Usage.credentialsExpired(3000, 2000), false);
    }

    function test_credentials_expired_false_when_no_expiry_info() {
        compare(Usage.credentialsExpired(0, 2000), false);
    }

    // parseUsage

    function test_parse_usage_extracts_five_hour_and_seven_day_rows() {
        var r = Usage.parseUsage(JSON.stringify({
            five_hour: { utilization: 42.0, resets_at: "2026-08-02T10:00:00Z" },
            seven_day: { utilization: 10.0, resets_at: "2026-08-05T00:00:00Z" }
        }));
        compare(r.ok, true);
        compare(r.rows.length, 2);
        compare(r.rows[0].label, "5-HOUR");
        compare(r.rows[0].percent, 0.42);
        compare(r.rows[0].resetsAt, "2026-08-02T10:00:00Z");
        compare(r.rows[1].label, "WEEKLY");
        compare(r.rows[1].percent, 0.1);
    }

    function test_parse_usage_prefers_seven_day_oauth_apps_over_seven_day() {
        var r = Usage.parseUsage(JSON.stringify({
            five_hour: { utilization: 5.0 },
            seven_day: { utilization: 99.0 },
            seven_day_oauth_apps: { utilization: 20.0, resets_at: "2026-08-06T00:00:00Z" }
        }));
        compare(r.rows[1].percent, 0.2);
        compare(r.rows[1].resetsAt, "2026-08-06T00:00:00Z");
    }

    function test_parse_usage_treats_fraction_scale_when_nothing_is_percent() {
        var r = Usage.parseUsage(JSON.stringify({
            five_hour: { utilization: 0.37 },
            seven_day: { utilization: 0.05 }
        }));
        compare(r.rows[0].percent, 0.37);
        compare(r.rows[1].percent, 0.05);
    }

    function test_parse_usage_missing_both_buckets() {
        var r = Usage.parseUsage(JSON.stringify({ other: true }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_usage_malformed_json() {
        var r = Usage.parseUsage("not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    function test_parse_usage_negative_utilization_dropped() {
        var r = Usage.parseUsage(JSON.stringify({ five_hour: { utilization: -1 } }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    // tierLabel

    function test_tier_label_max_tier_wins_over_subscription() {
        compare(Usage.tierLabel("pro", "max_20x"), "Max 20x");
    }

    function test_tier_label_falls_back_to_capitalized_subscription() {
        compare(Usage.tierLabel("pro", ""), "Pro");
    }

    function test_tier_label_empty_when_both_absent() {
        compare(Usage.tierLabel("", ""), "");
    }

    // formatReset

    function test_format_reset_hours_and_minutes() {
        var now = Date.parse("2026-08-02T10:00:00Z");
        var resets = "2026-08-02T12:14:00Z";
        compare(Usage.formatReset(now, resets), "RESETS 2H 14M");
    }

    function test_format_reset_minutes_only_under_an_hour() {
        var now = Date.parse("2026-08-02T10:00:00Z");
        compare(Usage.formatReset(now, "2026-08-02T10:45:00Z"), "RESETS 45M");
    }

    function test_format_reset_days_and_hours_over_a_day() {
        var now = Date.parse("2026-08-02T10:00:00Z");
        compare(Usage.formatReset(now, "2026-08-04T13:00:00Z"), "RESETS 2D 3H");
    }

    function test_format_reset_now_when_already_past() {
        var now = Date.parse("2026-08-02T10:00:00Z");
        compare(Usage.formatReset(now, "2026-08-02T09:00:00Z"), "RESETS NOW");
    }

    function test_format_reset_empty_for_no_timestamp() {
        compare(Usage.formatReset(Date.now(), ""), "");
    }

    // parseCodexAccount

    function test_parse_codex_account_extracts_plan_type() {
        var r = Usage.parseCodexAccount(JSON.stringify({ id: 2, result: { account: { planType: "team" } } }));
        compare(r.ok, true);
        compare(r.planType, "team");
    }

    function test_parse_codex_account_falls_back_to_type_field() {
        var r = Usage.parseCodexAccount(JSON.stringify({ id: 2, result: { account: { type: "individual" } } }));
        compare(r.ok, true);
        compare(r.planType, "individual");
    }

    function test_parse_codex_account_missing_account() {
        var r = Usage.parseCodexAccount(JSON.stringify({ id: 2, result: {} }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_codex_account_malformed_json() {
        var r = Usage.parseCodexAccount("not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    // parseCodexRateLimits

    function test_parse_codex_rate_limits_extracts_primary_and_secondary() {
        var r = Usage.parseCodexRateLimits(JSON.stringify({
            id: 3,
            result: {
                rateLimits: {
                    planType: "team",
                    primary: { usedPercent: 12.5, windowDurationMins: 300, resetsAt: 1785700800 },
                    secondary: { usedPercent: 40, windowDurationMins: 10080, resetsAt: 1785700800 }
                }
            }
        }));
        compare(r.ok, true);
        compare(r.planType, "team");
        compare(r.rows.length, 2);
        compare(r.rows[0].label, "5H WINDOW");
        compare(r.rows[0].percent, 0.125);
        compare(r.rows[1].label, "WEEKLY");
        compare(r.rows[1].percent, 0.4);
    }

    function test_parse_codex_rate_limits_labels_non_hour_windows_in_minutes() {
        var r = Usage.parseCodexRateLimits(JSON.stringify({
            id: 3,
            result: { rateLimits: { primary: { usedPercent: 5, windowDurationMins: 90 } } }
        }));
        compare(r.rows[0].label, "90M WINDOW");
    }

    function test_parse_codex_rate_limits_missing_limits() {
        var r = Usage.parseCodexRateLimits(JSON.stringify({ id: 3, result: {} }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_codex_rate_limits_only_secondary_present() {
        var r = Usage.parseCodexRateLimits(JSON.stringify({
            id: 3,
            result: { rateLimits: { secondary: { usedPercent: 8, windowDurationMins: 10080 } } }
        }));
        compare(r.ok, true);
        compare(r.rows.length, 1);
        compare(r.rows[0].label, "WEEKLY");
    }
}
