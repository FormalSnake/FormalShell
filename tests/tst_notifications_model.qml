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
            senderIsNotifySend: false
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
}
