import QtQuick
import QtTest
import "../shell/Iphone/model.js" as IM
import "../shell/Notifications/model.js" as NM

TestCase {
    name: "IphoneModel"

    // Lines in the exact shape omarchy-iphone-bridge's cmd_listen emits
    // (bin/omarchy-iphone-bridge @ 586f37d).
    property string lineSms: "{\"type\": \"notification\", \"id\": 4012, \"appId\": \"com.apple.MobileSMS\", \"appName\": \"Messages\", \"title\": \"Alex\", \"subtitle\": \"\", \"body\": \"Still on for Friday?\", \"deviceName\": \"Kyan's iPhone\", \"deviceHandle\": \"/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6\", \"positiveAction\": null, \"negativeAction\": \"Clear\", \"category\": 4, \"categoryCount\": 2, \"silent\": false, \"important\": false, \"preexisting\": false, \"session\": 77, \"ts\": 1790000000.0}"
    property string lineCall: "{\"type\": \"notification\", \"id\": 4013, \"appId\": \"com.apple.mobilephone\", \"appName\": \"Phone\", \"title\": \"Mum\", \"subtitle\": \"\", \"body\": \"mobile\", \"deviceName\": \"Kyan's iPhone\", \"deviceHandle\": \"/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6\", \"positiveAction\": \"Answer\", \"negativeAction\": \"Decline\", \"category\": 1, \"categoryCount\": 1, \"silent\": false, \"important\": true, \"preexisting\": false, \"session\": 77, \"ts\": 1790000001.0}"

    readonly property var rules: IM.dedupeRules(IM.DEFAULT_DEDUPE)

    function phone(fields) {
        var base = IM.parseEvent(lineSms);
        Object.keys(fields || {}).forEach(function (k) { base[k] = fields[k]; });
        return base;
    }

    function local(id, summary, body, arrivedAt, extra) {
        var e = {
            id: id, appName: "Messages", desktopEntry: "", summary: summary, body: body,
            urgency: 1, actions: [], image: "", local: false, source: "", phone: null,
            arrivedAt: arrivedAt
        };
        Object.keys(extra || {}).forEach(function (k) { e[k] = extra[k]; });
        return e;
    }

    // A notifications-model entry for a phone arrival, as notifyPhone adds it.
    function phoneEntry(record, arrivedAt) {
        var m = IM.toNotification(record);
        return {
            id: "iphone-" + record.session + "-" + record.id, appName: m.appName, appIcon: "",
            summary: m.summary, body: m.body, urgency: m.urgency, actions: m.actions,
            image: "", senderIsNotifySend: false, source: "iphone", phone: m.phone,
            arrivedAt: arrivedAt
        };
    }

    // --- parseEvent ------------------------------------------------------

    function test_parse_notification() {
        var e = IM.parseEvent(lineSms);
        compare(e.type, "notification");
        compare(e.id, 4012);
        compare(e.bundleId, "com.apple.MobileSMS");
        compare(e.appName, "Messages");
        compare(e.title, "Alex");
        compare(e.body, "Still on for Friday?");
        compare(e.deviceHandle, "/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6");
        compare(e.positiveAction, "");
        compare(e.negativeAction, "Clear");
        compare(e.category, 4);
        compare(e.silent, false);
        compare(e.session, 77);
        compare(e.ts, 1790000000);
    }

    function test_parse_notification_defaults_missing_fields() {
        var e = IM.parseEvent("{\"type\":\"notification\",\"id\":5}");
        compare(e.bundleId, "");
        compare(e.appName, "iPhone");
        compare(e.title, "");
        compare(e.negativeAction, "");
        compare(e.silent, false);
        compare(e.session, 0);
    }

    function test_parse_history_drops_non_objects() {
        var e = IM.parseEvent("{\"type\":\"history\",\"items\":[" + lineSms + ", 3, null]}");
        compare(e.type, "history");
        compare(e.items.length, 1);
        compare(e.items[0].id, 4012);
    }

    function test_parse_status_ignores_installed() {
        var e = IM.parseEvent("{\"type\":\"status\",\"observer\":true,\"connected\":true,\"deviceName\":\"Kyan's iPhone\",\"battery\":64,\"installed\":false}");
        compare(e.observer, true);
        compare(e.connected, true);
        compare(e.deviceName, "Kyan's iPhone");
        compare(e.battery, 64);
        verify(e.installed === undefined);
        compare(IM.parseEvent("{\"type\":\"status\",\"battery\":-1}").battery, -1);
    }

    function test_parse_small_events() {
        compare(IM.parseEvent("{\"type\":\"dismiss\",\"id\":4012}").id, 4012);
        compare(IM.parseEvent("{\"type\":\"pairingCode\",\"code\":\"123456\"}").code, "123456");
        compare(IM.parseEvent("{\"type\":\"advertising\",\"hci\":\"hci0\",\"name\":\"FormalShell\"}").name, "FormalShell");
        compare(IM.parseEvent("{\"type\":\"error\",\"message\":\"The phone rejected the command\"}").message, "The phone rejected the command");
    }

    function test_parse_garbage_is_null() {
        compare(IM.parseEvent(""), null);
        compare(IM.parseEvent("   "), null);
        compare(IM.parseEvent("not json"), null);
        compare(IM.parseEvent("[1,2]"), null);
        compare(IM.parseEvent("{\"type\":\"hci\",\"adapters\":[]}"), null);
    }

    // --- AMS now-playing (M75 Task 4) -------------------------------------
    //
    // Lines in the exact shape omarchy-iphone-ams's cmd_listen/cmd_command
    // emit (bin/omarchy-iphone-ams @ 586f37d): `nowplaying` always carries
    // the player's whole known state, not a diff.

    function test_parse_ams_status() {
        compare(IM.parseAmsLine("{\"type\": \"status\", \"available\": true}").available, true);
        compare(IM.parseAmsLine("{\"type\": \"status\", \"available\": false}").available, false);
    }

    function test_parse_ams_nowplaying() {
        var e = IM.parseAmsLine("{\"type\": \"nowplaying\", \"title\": \"Talk\", \"artist\": \"Kraftwerk\", \"album\": \"The Man-Machine\", \"duration\": 220.5, \"player\": \"Music\", \"playback\": \"playing\", \"elapsed\": 41.2, \"volume\": 0.6}");
        compare(e.type, "nowplaying");
        compare(e.title, "Talk");
        compare(e.artist, "Kraftwerk");
        compare(e.album, "The Man-Machine");
        compare(e.duration, 220.5);
        compare(e.elapsed, 41.2);
        compare(e.playback, "playing");
        compare(e.volume, 0.6);
    }

    function test_parse_ams_nowplaying_defaults() {
        var e = IM.parseAmsLine("{\"type\": \"nowplaying\", \"title\": \"\", \"artist\": \"\", \"album\": \"\", \"duration\": 0.0, \"player\": \"\", \"playback\": \"\", \"elapsed\": 0.0, \"volume\": -1.0}");
        compare(e.title, "");
        compare(e.duration, 0);
        compare(e.playback, "");
        compare(e.volume, -1);
    }

    function test_parse_ams_error_and_garbage() {
        compare(IM.parseAmsLine("{\"type\": \"error\", \"message\": \"AMS not available (phone connected?)\"}").message, "AMS not available (phone connected?)");
        compare(IM.parseAmsLine(""), null);
        compare(IM.parseAmsLine("not json"), null);
        compare(IM.parseAmsLine("{\"type\":\"hci\"}"), null);
    }

    // --- recent list -----------------------------------------------------

    function test_upsert_replaces_a_modified_resend() {
        var a = phone({ id: 1 });
        var b = phone({ id: 2 });
        var list = IM.upsert(IM.upsert([], a, 10), b, 10);
        list = IM.upsert(list, phone({ id: 1, body: "edited" }), 10);
        compare(list.length, 2);
        compare(list[0].id, 1);
        compare(list[0].body, "edited");
        compare(IM.upsert(list, phone({ id: 3 }), 2).length, 2);
        compare(IM.removeById(list, 2).length, 1);
    }

    // --- Focus -----------------------------------------------------------

    function test_focus_verdict_modes() {
        var loud = phone({ silent: false });
        var quiet = phone({ silent: true });
        compare(IM.focusVerdict(loud, "respect"), "toast");
        compare(IM.focusVerdict(quiet, "respect"), "quiet");
        compare(IM.focusVerdict(quiet, "hide"), "drop");
        compare(IM.focusVerdict(loud, "hide"), "toast");
        compare(IM.focusVerdict(quiet, "ignore"), "toast");
        compare(IM.focusVerdict(quiet, "bogus"), "quiet");
    }

    function test_route_gates() {
        var cfg = { enable: true, block: ["COM.apple.mobilesms"], focus: "respect" };
        compare(IM.route(phone(), cfg), "drop");
        cfg.block = [];
        compare(IM.route(phone(), cfg), "toast");
        compare(IM.route(phone({ preexisting: true }), cfg), "drop");
        compare(IM.route(phone({ silent: true }), cfg), "quiet");
        cfg.enable = false;
        compare(IM.route(phone(), cfg), "drop");
    }

    function test_in_focus_heuristic() {
        var now = 1000000;
        compare(IM.inFocus([], now, 900), false);
        compare(IM.inFocus([{ at: now - 1000, silent: true }], now, 900), true);
        // An audible arrival after the silent one ends it.
        compare(IM.inFocus([{ at: now - 5000, silent: true }, { at: now - 1000, silent: false }], now, 900), false);
        // And a silent one after an audible one starts it again.
        compare(IM.inFocus([{ at: now - 5000, silent: false }, { at: now - 1000, silent: true }], now, 900), true);
        // Aged out of the window.
        compare(IM.inFocus([{ at: now - 901000, silent: true }], now, 900), false);
        compare(IM.inFocus([{ at: now - 901000, silent: false }, { at: now - 1000, silent: true }], now, 900), true);
    }

    function test_sync_dnd_turns_on_and_off_its_own() {
        var s = { owned: false, focus: false };
        var r = IM.syncDndStep(s, true, false, true);
        compare(r.set, true);
        compare(r.owned, true);
        // The write lands back as a DND change: nothing further.
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, true, true, true);
        compare(r.set, null);
        compare(r.owned, true);
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, false, true, true);
        compare(r.set, false);
        compare(r.owned, false);
    }

    function test_sync_dnd_never_clears_a_hand_set_dnd() {
        // DND already on when Focus starts: not ours.
        var r = IM.syncDndStep({ owned: false, focus: false }, true, true, true);
        compare(r.set, null);
        compare(r.owned, false);
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, false, true, true);
        compare(r.set, null);
    }

    function test_sync_dnd_hand_clear_mid_focus_sticks() {
        var r = IM.syncDndStep({ owned: false, focus: false }, true, false, true);
        compare(r.set, true);
        // Owner turns DND off by hand while Focus still reads on.
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, true, false, true);
        compare(r.set, null);
        compare(r.owned, false);
        // ...and back on by hand: that one is theirs, so Focus ending leaves it.
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, true, true, true);
        compare(r.owned, false);
        r = IM.syncDndStep({ owned: r.owned, focus: r.focus }, false, true, true);
        compare(r.set, null);
    }

    function test_sync_dnd_disabled() {
        var r = IM.syncDndStep({ owned: false, focus: false }, true, false, false);
        compare(r.set, null);
        // Turning the key off while it owns DND hands it back.
        r = IM.syncDndStep({ owned: true, focus: true }, true, true, false);
        compare(r.set, false);
        compare(r.owned, false);
    }

    // --- dedupe ----------------------------------------------------------

    function test_normalise() {
        compare(IM.normalise("⁨Alex⁩", "It’s   late "), IM.normalise("alex", "it's late"));
        verify(IM.normalise("Alex", "hi") !== IM.normalise("Alex", "hi!"));
        verify(IM.normalise("ab", "c") !== IM.normalise("a", "bc"));
    }

    function test_dedupe_rules_parse() {
        compare(rules.length, 1);
        compare(rules[0].phone, "com.apple.mobilesms");
        compare(rules[0].windowMs, 30000);
        compare(IM.dedupeRules([]).length, 0);
        compare(IM.dedupeRules("nope").length, 0);
        compare(IM.dedupeRules([{ phone: "x" }, { phone: "y", local: ["Y"], window: -3 }])[0].windowMs, 30000);
    }

    function test_phone_arrival_dropped_for_live_local() {
        var now = 100000;
        var hit = IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now - 2000)], now);
        verify(hit !== null);
        compare(hit.id, 9);
    }

    function test_phone_arrival_kept_outside_window_or_mismatch() {
        var now = 100000;
        compare(IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now - 31000)], now), null);
        compare(IM.dedupe(rules, phone(), [local(9, "Alex", "Something else", now)], now), null);
        compare(IM.dedupe(rules, phone(), [local(9, "Sam", "Still on for Friday?", now)], now), null);
        compare(IM.dedupe(rules, phone({ bundleId: "net.whatsapp.WhatsApp" }),
            [local(9, "Alex", "Still on for Friday?", now)], now), null);
        compare(IM.dedupe([], phone(), [local(9, "Alex", "Still on for Friday?", now)], now), null);
    }

    function test_dedupe_matches_desktop_entry_and_skips_other_sources() {
        var now = 100000;
        verify(IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now,
            { appName: "whatever", desktopEntry: "es.canarycoders.messages" })], now) !== null);
        compare(IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now,
            { appName: "Slack" })], now), null);
        // Shell-authored and other phone entries never count as the local copy.
        compare(IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now,
            { local: true })], now), null);
        compare(IM.dedupe(rules, phone(), [local(9, "Alex", "Still on for Friday?", now,
            { source: "iphone" })], now), null);
    }

    function test_dedupe_group_chat_readings() {
        var now = 100000;
        // The desktop client: the group as summary, "Sender: text" as body.
        var group = local(9, "Weekend", "Alex: Still on for Friday?", now);
        // The phone with the sender as title and the group as subtitle.
        verify(IM.dedupe(rules, phone({ subtitle: "Weekend" }), [group], now) !== null);
        // The phone with the group as title and the prefixed body.
        verify(IM.dedupe(rules, phone({ title: "Weekend", body: "Alex: Still on for Friday?" }), [group], now) !== null);
        // The phone with the group as title and the sender as subtitle.
        verify(IM.dedupe(rules, phone({ title: "Weekend", subtitle: "Alex" }), [group], now) !== null);
    }

    // The replace path end to end through the notification reducer: a
    // phone card on screen, then the desktop client raising the same
    // message, leaves one card, the local one.
    function test_local_arrival_replaces_phone_card() {
        var now = 100000;
        var s = NM.initialState();
        s = NM.add(s, phoneEntry(phone(), now), now, {});
        s = NM.add(s, local(9, "Alex", "Still on for Friday?", now + 3000), now + 3000, {});
        compare(s.popups.length, 2);
        var incoming = s.popups.filter(function (p) { return p.id === 9; })[0];
        var all = s.popups.concat(s.pending, s.past);
        var stale = IM.superseded(rules, incoming, all, now + 3000);
        compare(stale.length, 1);
        compare(stale[0], "iphone-77-4012");
        s = NM.dismissMany(s, stale);
        compare(s.popups.length, 1);
        compare(s.popups[0].id, 9);
        compare(s.pending.length + s.past.length, 0);
    }

    function test_local_arrival_replaces_quiet_phone_entry_in_history() {
        var now = 100000;
        var s = NM.add(NM.initialState(), phoneEntry(phone({ silent: true }), now), now, { quiet: true });
        compare(s.popups.length, 0);
        compare(s.pending.length, 1);
        var incoming = local(9, "Alex", "Still on for Friday?", now + 1000);
        var stale = IM.superseded(rules, incoming, s.popups.concat(s.pending, s.past), now + 1000);
        compare(stale.length, 1);
        s = NM.dismissMany(s, stale);
        compare(s.pending.length, 0);
    }

    function test_superseded_leaves_unrelated_phone_entries() {
        var now = 100000;
        var entries = [
            phoneEntry(phone(), now - 40000),
            phoneEntry(phone({ id: 2, body: "Other" }), now),
            phoneEntry(phone({ id: 3, bundleId: "net.whatsapp.WhatsApp" }), now),
            local(8, "Alex", "Still on for Friday?", now)
        ];
        compare(IM.superseded(rules, local(9, "Alex", "Still on for Friday?", now), entries, now).length, 0);
        compare(IM.superseded(rules, local(9, "Alex", "Still on for Friday?", now, { appName: "Slack" }),
            [phoneEntry(phone(), now)], now).length, 0);
    }

    // --- notification model hooks ----------------------------------------

    function test_quiet_add_goes_to_pending_without_dnd() {
        var s = NM.add(NM.initialState(), phoneEntry(phone(), 1000), 1000, { quiet: true });
        compare(s.popups.length, 0);
        compare(s.pending.length, 1);
        compare(s.pending[0].source, "iphone");
        compare(s.pending[0].phone.id, 4012);
    }

    function test_phone_and_local_cards_never_group() {
        var a = phoneEntry(phone(), 1000);
        var b = local(9, "Alex", "different", 1000);
        verify(NM.groupKey(a) !== NM.groupKey(b));
        compare(NM.groupEntries([a, b]).length, 2);
    }

    function test_critical_phone_entry_still_waits_behind_dnd() {
        var call = IM.parseEvent(lineCall);
        var s = NM.setDnd(NM.initialState(), true);
        s = NM.add(s, phoneEntry(call, 1000), 1000, {});
        compare(s.popups.length, 0);
        compare(s.pending.length, 1);
    }

    // --- mapping ---------------------------------------------------------

    function test_to_notification() {
        var m = IM.toNotification(phone({ subtitle: "Weekend" }));
        compare(m.summary, "Alex");
        compare(m.body, "Weekend\nStill on for Friday?");
        compare(m.urgency, 1);
        compare(m.category, "im.received");
        compare(m.actions.length, 1);
        compare(m.actions[0].key, "negative");
        compare(m.actions[0].label, "Clear");
        compare(m.phone.body, "Still on for Friday?");
        compare(m.phone.icon, "message-circle");
        compare(m.phone.negativeAction, "Clear");

        var call = IM.toNotification(IM.parseEvent(lineCall));
        compare(call.urgency, 2);
        compare(call.actions.map(function (a) { return a.key; }).join(","), "positive,negative");
        compare(call.phone.icon, "phone-incoming");

        compare(IM.toNotification(phone({ title: "", category: 2 })).summary, "Missed call");
        compare(IM.toNotification(phone({ title: "", category: 0 })).summary, "Messages");
    }

    function test_app_icon() {
        compare(IM.appIcon("com.apple.MobileSMS"), "message-circle");
        compare(IM.appIcon("com.apple.mobilephone", 2), "phone-missed");
        compare(IM.appIcon("com.apple.mobilephone", 3), "voicemail");
        compare(IM.appIcon("com.example.unknown"), "smartphone");
        compare(IM.appIcon(""), "smartphone");
    }

    function test_extract_code() {
        compare(IM.extractCode("Your verification code is 482913"), "482913");
        compare(IM.extractCode("123-456 is your Apple ID code"), "123456");
        compare(IM.extractCode("Order 482913 has shipped"), "");
        compare(IM.extractCode("Security alert since 2019"), "");
        compare(IM.extractCode(""), "");
    }

    function test_device_matching() {
        compare(IM.addressFromHandle("/org/bluez/hci0/dev_a1_B2_C3_D4_E5_F6"), "A1:B2:C3:D4:E5:F6");
        compare(IM.addressFromHandle(""), "");
        var byPath = { dbusPath: "/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6", address: "x", name: "a", connected: true };
        var byAddr = { dbusPath: "", address: "a1:b2:c3:d4:e5:f6", name: "b", connected: true };
        var byName = { dbusPath: "", address: "", name: "Kyan's iPhone", connected: true };
        compare(IM.matchDevice([byAddr, byPath], "/org/bluez/hci0/dev_A1_B2_C3_D4_E5_F6", ""), byPath);
        compare(IM.matchDevice([byName, byAddr], "/org/bluez/hci1/dev_A1_B2_C3_D4_E5_F6", ""), byAddr);
        compare(IM.matchDevice([byName], "", "Kyan's iPhone"), byName);
        compare(IM.matchDevice([{ name: "Kyan's iPhone", connected: false }], "", "Kyan's iPhone"), null);
        compare(IM.matchDevice([], "", ""), null);
    }

    function test_actionable_only_in_its_session() {
        var e = phone();
        compare(IM.isActionable(e, 0), true);
        compare(IM.isActionable(e, 77), true);
        compare(IM.isActionable(e, 78), false);
        compare(IM.isActionable(phone({ deviceHandle: "" }), 77), false);
        compare(IM.isActionable(null, 77), false);
    }

    function test_artwork_search_url_puts_title_first() {
        compare(IM.artworkSearchUrl("Daft Punk", "Get Lucky"),
            "https://itunes.apple.com/search?term=Get%20Lucky%20Daft%20Punk&entity=song&limit=10");
    }

    function test_pick_artwork_prefers_the_album_and_upsizes() {
        var body = JSON.stringify({ results: [
            { artistName: "Someone Else", collectionName: "RAM", artworkUrl100: "https://x/a.jpg/100x100bb.jpg" },
            { artistName: "Daft Punk", collectionName: "Get Lucky (Remix)", artworkUrl100: "https://x/b.jpg/100x100bb.jpg" },
            { artistName: "Daft Punk, Pharrell Williams", collectionName: "Random Access Memories", artworkUrl100: "https://x/c.jpg/100x100bb.jpg" }
        ] });
        compare(IM.pickArtwork(body, "Daft Punk", "Random Access Memories"), "https://x/c.jpg/600x600bb.jpg");
        compare(IM.pickArtwork(body, "Daft Punk", "Unknown"), "https://x/b.jpg/600x600bb.jpg");
    }

    function test_pick_artwork_needs_the_same_artist() {
        var body = JSON.stringify({ results: [{ artistName: "Other", artworkUrl100: "https://x/a.jpg/100x100bb.jpg" }] });
        compare(IM.pickArtwork(body, "Fixture Band", "Fixture Album"), "");
        compare(IM.pickArtwork("nope", "Fixture Band", ""), "");
        compare(IM.pickArtwork(body, "", ""), "");
    }
}
