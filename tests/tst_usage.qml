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
                refreshToken: "ref456",
                expiresAt: 1700000000000,
                subscriptionType: "pro",
                rateLimitTier: "max_20x"
            }
        }));
        compare(r.ok, true);
        compare(r.accessToken, "tok123");
        compare(r.hasRefreshToken, true);
        compare(r.expiresAtMs, 1700000000000);
        compare(r.subscriptionType, "pro");
        compare(r.rateLimitTier, "max_20x");
    }

    // The refresh token is what separates "logged out" from "logged in,
    // access token needs a claude run to refresh" — its value never leaves
    // the parser, only its presence.
    function test_parse_credentials_never_returns_the_refresh_token_itself() {
        var r = Usage.parseCredentials(JSON.stringify({
            claudeAiOauth: { accessToken: "tok", refreshToken: "ref456" }
        }));
        compare(r.hasRefreshToken, true);
        compare(r.refreshToken, undefined);
    }

    function test_parse_credentials_absent_refresh_token() {
        var r = Usage.parseCredentials(JSON.stringify({ claudeAiOauth: { accessToken: "tok" } }));
        compare(r.ok, true);
        compare(r.hasRefreshToken, false);
    }

    function test_parse_credentials_empty_refresh_token_counts_as_absent() {
        var r = Usage.parseCredentials(JSON.stringify({
            claudeAiOauth: { accessToken: "tok", refreshToken: "" }
        }));
        compare(r.hasRefreshToken, false);
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

    function test_parse_usage_enumerates_dynamic_buckets_in_stable_order() {
        var r = Usage.parseUsage(JSON.stringify({
            seven_day_sonnet: { utilization: 8.0, resets_at: "2026-08-05T00:00:00Z" },
            experimental_window: { utilization: 3.0, resets_at: "2026-08-05T00:00:00Z" },
            five_hour: { utilization: 42.0, resets_at: "2026-08-02T10:00:00Z" },
            seven_day_opus: { utilization: 15.0, resets_at: "2026-08-05T00:00:00Z" },
            seven_day: { utilization: 10.0, resets_at: "2026-08-05T00:00:00Z" }
        }));
        compare(r.ok, true);
        compare(r.rows.length, 5);
        compare(r.rows[0].label, "5-HOUR");
        compare(r.rows[1].label, "WEEKLY");
        compare(r.rows[2].label, "EXPERIMENTAL WINDOW");
        compare(r.rows[3].label, "WEEKLY OPUS");
        compare(r.rows[4].label, "WEEKLY SONNET");
        compare(r.rows[3].percent, 0.15);
        compare(r.rows[4].percent, 0.08);
    }

    function test_parse_usage_skips_null_utilization_bucket_without_dropping_others() {
        var r = Usage.parseUsage(JSON.stringify({
            five_hour: { utilization: 42.0, resets_at: "2026-08-02T10:00:00Z" },
            seven_day_opus: { utilization: null, resets_at: "2026-08-05T00:00:00Z" }
        }));
        compare(r.ok, true);
        compare(r.rows.length, 1);
        compare(r.rows[0].label, "5-HOUR");
    }

    function test_parse_usage_all_buckets_null_utilization_is_missing_fields() {
        var r = Usage.parseUsage(JSON.stringify({
            seven_day_opus: { utilization: null, resets_at: "2026-08-05T00:00:00Z" }
        }));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
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

    // sentenceLabel

    function test_sentence_label_lowercases_a_bucket_label() {
        compare(Usage.sentenceLabel("5-HOUR"), "5-hour");
        compare(Usage.sentenceLabel("WEEKLY"), "Weekly");
        compare(Usage.sentenceLabel("WEEKLY OPUS"), "Weekly opus");
    }

    function test_sentence_label_empty_for_nothing_to_say() {
        compare(Usage.sentenceLabel(""), "");
        compare(Usage.sentenceLabel(null), "");
        compare(Usage.sentenceLabel(undefined), "");
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

    // refreshStateForExit / refreshHint

    function test_refresh_state_for_exit_separates_a_missing_cli_from_a_failure() {
        compare(Usage.refreshStateForExit(0), "ok");
        compare(Usage.refreshStateForExit(127), "nocli");
        compare(Usage.refreshStateForExit(1), "failed");
        compare(Usage.refreshStateForExit(2), "failed");
    }

    function test_refresh_hint_names_the_step_left_to_the_owner() {
        compare(Usage.refreshHint("running"), "REFRESHING");
        compare(Usage.refreshHint("nocli"), "NO CLAUDE CLI");
        compare(Usage.refreshHint("failed"), "RUN CLAUDE AUTH LOGIN");
        compare(Usage.refreshHint("idle"), "RUN CLAUDE TO REFRESH");
    }

    // A clean helper run that left the token stale is not a refresh problem,
    // so it reads as the pre-refresh ask rather than as a success.
    function test_refresh_hint_treats_a_clean_run_that_changed_nothing_as_idle() {
        compare(Usage.refreshHint("ok"), "RUN CLAUDE TO REFRESH");
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
