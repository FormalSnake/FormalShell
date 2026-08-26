import QtQuick
import QtTest
import "../shell/Notifications/icon.js" as NotificationIcon

// M48 D4: which picture a notification card shows, and in which order. Both
// lookups are injected here exactly as NotificationCard.qml injects the real
// ones: `themed` stands in for Quickshell.iconPath(name, true), which
// answers "" for a name the icon theme does not carry, and `entry` for the
// DesktopEntries lookup.
TestCase {
    name: "NotificationIcon"

    readonly property var themeIcons: ["firefox", "dialog-information", "signal-desktop"]
    readonly property var entries: ({
        "org.signal.Signal": { icon: "signal-desktop" },
        "Slack": { icon: "/opt/slack/icon.png" },
        "unthemed": { icon: "no-such-icon" }
    })

    function resolve(entry) {
        return NotificationIcon.resolve(entry, {
            themed: function (name) {
                return themeIcons.indexOf(name) >= 0 ? "image://icon/" + name : "";
            },
            entry: function (desktopId, appName) {
                return entries[desktopId] ?? entries[appName] ?? null;
            }
        });
    }

    function notif(fields) {
        var base = { appName: "", appIcon: "", desktopEntry: "", image: "" };
        for (var key in fields)
            base[key] = fields[key];
        return base;
    }

    // --- the order ---------------------------------------------------------

    function test_the_notifications_own_image_wins() {
        compare(resolve(notif({
            image: "image://qsimage/12", appIcon: "firefox", desktopEntry: "org.signal.Signal"
        })), "image://qsimage/12");
    }

    function test_the_app_icon_comes_next() {
        compare(resolve(notif({
            appIcon: "firefox", desktopEntry: "org.signal.Signal"
        })), "image://icon/firefox");
    }

    function test_the_named_desktop_entry_comes_third() {
        compare(resolve(notif({ desktopEntry: "org.signal.Signal" })), "image://icon/signal-desktop");
    }

    // The much more common sender: neither hint, only a name.
    function test_the_sender_name_finds_an_entry_when_no_hint_did() {
        compare(resolve(notif({ appName: "Slack" })), "file:///opt/slack/icon.png");
    }

    function test_nothing_resolving_leaves_the_card_its_bell() {
        compare(resolve(notif({ appName: "Some Daemon" })), "");
    }

    // --- what an app icon can be -------------------------------------------

    function test_an_absolute_path_becomes_a_file_url() {
        compare(resolve(notif({ appIcon: "/tmp/shot.png" })), "file:///tmp/shot.png");
    }

    function test_a_url_is_taken_as_given() {
        compare(resolve(notif({ appIcon: "file:///tmp/shot.png" })), "file:///tmp/shot.png");
        compare(resolve(notif({ appIcon: "image://icon/firefox" })), "image://icon/firefox");
    }

    // A themed name nothing carries must not stop the walk: the desktop
    // entry behind it still has a real icon.
    function test_an_unresolvable_app_icon_falls_through_to_the_entry() {
        compare(resolve(notif({
            appIcon: "no-such-icon", desktopEntry: "org.signal.Signal"
        })), "image://icon/signal-desktop");
    }

    function test_an_entry_whose_own_icon_is_unthemed_resolves_to_nothing() {
        compare(resolve(notif({ desktopEntry: "unthemed" })), "");
    }

    // --- the image-path hint -----------------------------------------------

    // The server hands an `image-path` naming a themed icon to the icon
    // provider unresolved, and the provider answers a magenta
    // missing-texture pixmap rather than failing, which renders as a
    // perfectly healthy Image in the card.
    function test_an_image_path_hint_naming_a_missing_icon_is_dropped() {
        compare(resolve(notif({ image: "image://icon/no-such-icon", appIcon: "firefox" })),
            "image://icon/firefox");
    }

    // An `image-path` hint carrying a plain path arrives wrapped the same
    // way, and QIcon has nothing to do with it.
    function test_an_image_path_hint_carrying_a_path_becomes_a_file_url() {
        compare(resolve(notif({ image: "image://icon//tmp/shot.png" })), "file:///tmp/shot.png");
    }

    function test_an_image_path_hint_naming_a_real_icon_is_kept() {
        compare(resolve(notif({ image: "image://icon/dialog-information" })),
            "image://icon/dialog-information");
    }

    // Only the plain provider url is second-guessed; one carrying the
    // provider's own query is passed through untouched.
    function test_a_provider_url_with_a_query_is_left_alone() {
        compare(resolve(notif({ image: "image://icon/a?fallback=b" })), "image://icon/a?fallback=b");
    }

    function test_a_missing_entry_is_no_entry_at_all() {
        compare(resolve({}), "");
    }
}
