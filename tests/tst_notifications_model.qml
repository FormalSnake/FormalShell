import QtQuick
import QtTest
import "../shell/Notifications/model.js" as M

TestCase {
    name: "NotificationsModel"

    function notif(id, urgency, extra) {
        var base = {
            id: id,
            appName: "TestApp",
            appIcon: "",
            summary: "Summary " + id,
            body: "Body " + id,
            urgency: urgency,
            actions: [],
            image: "",
            senderIsNotifySend: false,
            local: false
        };
        Object.keys(extra || {}).forEach(function (k) { base[k] = extra[k]; });
        return base;
    }

    function test_initial_state_shape() {
        var s = M.initialState();
        compare(s.popups.length, 0);
        compare(s.pending.length, 0);
        compare(s.past.length, 0);
        compare(s.dnd, false);
        compare(s.nextExpiry, null);
    }

    function test_bypasses_dnd_true_only_for_critical_notify_send() {
        verify(M.bypassesDnd(notif("a", 2, { senderIsNotifySend: true })));
    }

    function test_bypasses_dnd_false_for_critical_chat_app() {
        // A chat app abusing urgency=critical must NOT bypass DND.
        verify(!M.bypassesDnd(notif("a", 2, { senderIsNotifySend: false })));
    }

    function test_bypasses_dnd_false_for_notify_send_at_normal_urgency() {
        verify(!M.bypassesDnd(notif("a", 1, { senderIsNotifySend: true })));
    }

    function test_bypasses_dnd_true_for_critical_local() {
        verify(M.bypassesDnd(notif("a", 2, { local: true })));
    }

    function test_bypasses_dnd_false_for_local_at_normal_urgency() {
        verify(!M.bypassesDnd(notif("a", 1, { local: true })));
    }

    function test_add_dnd_on_non_bypassing_routes_to_pending() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 1), 1000, {});
        compare(s.popups.length, 0);
        compare(s.pending.length, 1);
        compare(s.pending[0].id, "a");
        compare(s.pending[0].seenAt, null);
    }

    function test_add_dnd_on_bypassing_critical_routes_to_popup() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 2, { senderIsNotifySend: true }), 1000, {});
        compare(s.popups.length, 1);
        compare(s.pending.length, 0);
    }

    function test_add_normal_urgency_gets_default_timeout_expiry() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        compare(s.popups[0].expiresAt, 7000); // 1000 + 6000ms default
    }

    function test_add_critical_urgency_is_sticky() {
        var s = M.initialState();
        s = M.add(s, notif("a", 2, { senderIsNotifySend: true }), 1000, {});
        compare(s.popups[0].expiresAt, 0);
    }

    function test_add_custom_timeout_via_opts() {
        var s = M.initialState();
        s = M.add(s, notif("a", 0), 1000, { timeoutMs: 2000 });
        compare(s.popups[0].expiresAt, 3000);
    }

    function test_add_entry_shape_carries_arrival_time_and_null_seen() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1234, {});
        var e = s.popups[0];
        compare(e.appName, "TestApp");
        compare(e.summary, "Summary a");
        compare(e.arrivedAt, 1234);
        compare(e.seenAt, null);
    }

    function test_popup_cap_overflow_pushes_oldest_to_pending() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.add(s, notif("b", 1), 1001, {});
        s = M.add(s, notif("c", 1), 1002, {});
        s = M.add(s, notif("d", 1), 1003, {});
        compare(s.popups.length, 4);
        compare(s.pending.length, 0);

        s = M.add(s, notif("e", 1), 1004, {});
        compare(s.popups.length, 4);
        compare(s.pending.length, 1);
        compare(s.pending[0].id, "a"); // oldest evicted
        var ids = s.popups.map(function (p) { return p.id; });
        compare(ids.join(","), "b,c,d,e");
    }

    function test_expire_moves_timed_out_popups_to_pending_unseen() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, { timeoutMs: 500 }); // expires 1500
        s = M.add(s, notif("b", 1), 1000, { timeoutMs: 5000 }); // expires 6000
        s = M.expire(s, 2000);
        compare(s.popups.length, 1);
        compare(s.popups[0].id, "b");
        compare(s.pending.length, 1);
        compare(s.pending[0].id, "a");
        compare(s.pending[0].seenAt, null);
    }

    function test_expire_never_times_out_sticky_critical_popups() {
        var s = M.initialState();
        s = M.add(s, notif("a", 2, { senderIsNotifySend: true }), 1000, {});
        s = M.expire(s, 999999999);
        compare(s.popups.length, 1);
        compare(s.pending.length, 0);
    }

    function test_update_patches_popup_content_in_place_without_moving_tier() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.update(s, "a", { summary: "Song B" }, 5000);
        compare(s.popups.length, 1);
        compare(s.pending.length, 0);
        compare(s.popups[0].summary, "Song B");
        compare(s.popups[0].arrivedAt, 1000); // unchanged by a replace
    }

    function test_update_refreshes_expiry_for_still_popped_up_entry() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {}); // expires 7000
        s = M.update(s, "a", { summary: "Song B" }, 6500); // past the original clock
        compare(s.popups[0].expiresAt, 12500); // 6500 + 6000ms default, not expired
    }

    function test_update_keeps_sticky_expiry_for_critical_popup() {
        var s = M.initialState();
        s = M.add(s, notif("a", 2, { senderIsNotifySend: true }), 1000, {});
        s = M.update(s, "a", { summary: "Song B" }, 5000);
        compare(s.popups[0].expiresAt, 0);
    }

    function test_update_patches_pending_entry_without_touching_expiry() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.update(s, "a", { summary: "Song B" }, 5000);
        compare(s.pending.length, 1);
        compare(s.pending[0].summary, "Song B");
        compare(s.pending[0].expiresAt, null);
    }

    function test_update_unknown_id_is_noop() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        var updated = M.update(s, "missing", { summary: "Song B" }, 5000);
        compare(updated, s);
    }

    function test_purity_update_does_not_mutate_input_state() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        var before = JSON.stringify(s);
        M.update(s, "a", { summary: "Song B" }, 5000);
        compare(JSON.stringify(s), before);
    }

    function test_dismiss_popup_moves_to_past_marked_seen() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.dismissPopup(s, "a", 5000);
        compare(s.popups.length, 0);
        compare(s.past.length, 1);
        compare(s.past[0].id, "a");
        compare(s.past[0].seenAt, 5000);
    }

    function test_mark_all_seen_drains_pending_to_past() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.add(s, notif("b", 1), 1001, {});
        s = M.markAllSeen(s, 9000);
        compare(s.pending.length, 0);
        compare(s.past.length, 2);
        compare(s.past[0].seenAt, 9000);
        compare(s.past[1].seenAt, 9000);
    }

    function test_prune_past_drops_entries_older_than_15_minutes() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 0, {});
        s = M.dismissPopup(s, "a", 1000); // seenAt 1000
        s = M.add(s, notif("b", 1), 0, {});
        s = M.dismissPopup(s, "b", 900000); // seenAt exactly 15min after "now" below

        var fifteenMin = 15 * 60 * 1000;
        var now = 1000 + fifteenMin + 1;
        s = M.prunePast(s, now);
        var ids = s.past.map(function (p) { return p.id; });
        verify(ids.indexOf("a") < 0);
        verify(ids.indexOf("b") >= 0);
    }

    function test_invoke_target_returns_most_recently_arrived_across_popups_and_pending() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("old", 1), 1000, {}); // -> pending (dnd on)
        s = M.setDnd(s, false);
        s = M.add(s, notif("newer", 1), 2000, {}); // -> popups
        var target = M.invokeTarget(s);
        verify(target);
        compare(target.id, "newer");
    }

    function test_invoke_target_null_when_nothing_pending_or_popup() {
        var s = M.initialState();
        compare(M.invokeTarget(s), null);
    }

    function test_dismiss_one_removes_from_any_tier() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.dismissPopup(s, "a", 2000); // now in past
        s = M.dismissOne(s, "a");
        compare(s.past.length, 0);
    }

    function test_dismiss_all_clears_popups_only() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 1), 1000, {}); // pending
        s = M.setDnd(s, false);
        s = M.add(s, notif("b", 1), 1001, {}); // popup
        s = M.dismissAll(s);
        compare(s.popups.length, 0);
        compare(s.pending.length, 1);
    }

    function test_clear_pending_empties_pending_only() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.clearPending(s);
        compare(s.pending.length, 0);
    }

    function test_set_dnd_toggles_flag() {
        var s = M.initialState();
        s = M.setDnd(s, true);
        compare(s.dnd, true);
        s = M.setDnd(s, false);
        compare(s.dnd, false);
    }

    function test_purity_add_does_not_mutate_input_state() {
        var s = M.initialState();
        var before = JSON.stringify(s);
        M.add(s, notif("a", 1), 1000, {});
        compare(JSON.stringify(s), before);
    }

    function test_purity_expire_dismiss_prune_do_not_mutate_input_state() {
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, { timeoutMs: 100 });
        var before = JSON.stringify(s);
        M.expire(s, 5000);
        M.dismissPopup(s, "a", 5000);
        M.prunePast(s, 5000);
        compare(JSON.stringify(s), before);
    }

    function test_replace_by_id_never_creates_a_second_popup_entry() {
        // Proves the freedesktop replaces_id contract: NotificationService.qml
        // resyncs an existing id via update() on every property change
        // instead of calling add() again, so the reducer must never grow a
        // second entry for the same id.
        var s = M.initialState();
        s = M.add(s, notif("a", 1), 1000, {});
        s = M.update(s, "a", { summary: "Song B" }, 2000);
        s = M.update(s, "a", { summary: "Song C" }, 3000);
        compare(s.popups.length, 1);
        compare(s.popups[0].summary, "Song C");
    }

    // isChromiumDerived / sanitizeBody / styledBody

    function test_is_chromium_derived_matches_known_browsers_by_app_name() {
        verify(M.isChromiumDerived("Google Chrome", ""));
        verify(M.isChromiumDerived("Brave Browser", ""));
        verify(M.isChromiumDerived("Vivaldi", ""));
        // Edge's Linux sender reports its binary name, not the title-case
        // brand string, and the marker list matches that literally.
        verify(M.isChromiumDerived("microsoft-edge", ""));
        verify(M.isChromiumDerived("Opera", ""));
    }

    function test_is_chromium_derived_matches_via_app_icon_too() {
        verify(M.isChromiumDerived("Unknown", "google-chrome"));
    }

    function test_is_chromium_derived_false_for_unrelated_sender() {
        verify(!M.isChromiumDerived("Slack", "slack"));
    }

    function test_sanitize_body_strips_img_tag_regardless_of_sender() {
        var out = M.sanitizeBody('<img src="x.png">Hello', "Slack", "");
        compare(out, "Hello");
    }

    function test_sanitize_body_leaves_non_chromium_url_prefix_untouched() {
        var body = "https://example.com/x Something happened";
        compare(M.sanitizeBody(body, "Slack", ""), body);
    }

    function test_sanitize_body_strips_chromium_link_prefix_github_fixture() {
        // The exact "GH notifs are ugly" shape: Chrome glues a
        // URL-as-link line to the front of the body.
        var body = '<a href="https://github.com/notifications">github.com</a> '
            + 'New comment on issue #42: "Fix the thing"';
        var out = M.sanitizeBody(body, "Google Chrome", "");
        compare(out, 'New comment on issue #42: "Fix the thing"');
    }

    function test_sanitize_body_strips_chromium_bare_url_prefix() {
        var body = "github.com/owner/repo/pull/7 Review requested";
        var out = M.sanitizeBody(body, "Google Chrome", "");
        compare(out, "Review requested");
    }

    function test_sanitize_body_chromium_sender_still_strips_img() {
        var out = M.sanitizeBody('<img src="x.png">Plain text', "Brave Browser", "");
        compare(out, "Plain text");
    }

    function test_styled_body_converts_all_newline_forms_to_br() {
        compare(M.styledBody("a\nb\r\nc\rd", "Slack", ""), "a<br/>b<br/>c<br/>d");
    }

    function test_styled_body_applies_sanitize_before_newline_conversion() {
        var body = '<a href="https://github.com/x">github.com</a> line one\nline two';
        var out = M.styledBody(body, "Google Chrome", "");
        compare(out, "line one<br/>line two");
    }

    // Regression: the server never advertises body-markup support
    // (NotificationService.qml's bodyMarkupSupported: false), so a bare
    // `<`/`&`/`>` in a sender's plain text is incidental, not markup —
    // styledBody() must escape it rather than hand it to Text.StyledText's
    // parser, which otherwise drops everything after an unterminated tag.

    function test_styled_body_escapes_bare_angle_brackets_instead_of_dropping_text() {
        var out = M.styledBody("5 < 10 && 3 > 1", "Slack", "");
        compare(out, "5 &lt; 10 &amp;&amp; 3 &gt; 1");
    }

    function test_styled_body_escapes_unterminated_tag_without_losing_the_tail() {
        var body = "unterminated <b tag swallows this whole tail";
        var out = M.styledBody(body, "Slack", "");
        compare(out, "unterminated &lt;b tag swallows this whole tail");
    }

    function test_styled_body_escapes_comparison_text_without_losing_the_tail() {
        var out = M.styledBody("disk usage a < b and more text after", "Slack", "");
        compare(out, "disk usage a &lt; b and more text after");
    }

    // relTime

    function test_rel_time_under_a_minute_is_now() {
        compare(M.relTime(1000, 1000), "now");
        compare(M.relTime(60999, 1000), "now");
    }

    function test_rel_time_minute_boundary() {
        compare(M.relTime(61000, 1000), "1m ago");
    }

    function test_rel_time_minutes_just_under_an_hour() {
        compare(M.relTime(1000 + 59 * 60 * 1000, 1000), "59m ago");
    }

    function test_rel_time_hour_boundary_reads_hours_not_sixty_minutes() {
        compare(M.relTime(1000 + 60 * 60 * 1000, 1000), "1h ago");
    }

    function test_rel_time_hours_just_under_a_day() {
        compare(M.relTime(1000 + 23 * 60 * 60 * 1000, 1000), "23h ago");
    }

    function test_rel_time_day_boundary_reads_days_not_twentyfour_hours() {
        compare(M.relTime(1000 + 24 * 60 * 60 * 1000, 1000), "1d ago");
    }

    function test_rel_time_multiple_days() {
        compare(M.relTime(1000 + 3 * 24 * 60 * 60 * 1000, 1000), "3d ago");
    }

    function test_rel_time_clamps_future_arrival_to_now() {
        compare(M.relTime(1000, 5000), "now");
    }
}
