import QtQuick
import QtTest
import "../shell/Compositor/appicon.js" as AppIcon

// The chain a window takes to its app's icon (Compositor/appicon.js), against
// fixture entries shaped like DesktopEntries.applications.values: `command`
// is a list, `icon` a theme name or an absolute path. `themed` stands in for
// Quickshell.iconPath(name, true), which answers "" for a name the theme
// lacks.
TestCase {
    name: "AppIcon"

    readonly property var themeIcons: ["foot", "firefox", "discord", "org.wezfurlong.wezterm"]

    function themed(name) {
        return themeIcons.indexOf(name) >= 0 ? "image://icon/" + name : "";
    }

    function entry(id, fields) {
        var out = { id: id, name: id, startupClass: "", icon: id, command: [id] };
        for (var key in fields)
            out[key] = fields[key];
        return out;
    }

    // Messages as it is on the owner's host: a native Wayland app with no
    // app id at all, launched from a script in ~/.local/bin, whose entry
    // names an absolute .svg and carries no StartupWMClass.
    readonly property var messages: entry("messages", {
        name: "Messages",
        icon: "/home/kyandesutter/.local/share/icons/messages.svg",
        command: ["/home/kyandesutter/.local/bin/messages"]
    })

    readonly property var entries: [
        entry("foot", { name: "Foot", command: ["foot"] }),
        entry("firefox", { name: "Firefox", startupClass: "firefox", command: ["firefox", "--name", "firefox"] }),
        entry("com.discordapp.Discord", { name: "Discord", icon: "discord",
            command: ["/usr/bin/flatpak", "run", "com.discordapp.Discord"] }),
        entry("org.wezfurlong.wezterm", { name: "WezTerm", command: ["wezterm", "start"] }),
        entry("Alacritty", { name: "Alacritty", startupClass: "Alacritty" }),
        entry("shell-script", { name: "Some Script", command: ["sh", "-c", "echo"] }),
        messages
    ]

    function win(fields) {
        var out = { id: "0x1", title: "", appId: "", initialClass: "", initialTitle: "", pid: 0 };
        for (var key in fields)
            out[key] = fields[key];
        return out;
    }

    function idOf(found) {
        return found ? found.id : null;
    }

    // --- tier 1: the class ------------------------------------------------

    function test_the_class_matches_an_entry_id() {
        compare(idOf(AppIcon.entryFor(win({ appId: "foot" }), entries, null)), "foot");
    }

    function test_the_class_matches_an_id_case_folded() {
        compare(idOf(AppIcon.entryFor(win({ appId: "FOOT" }), entries, null)), "foot");
    }

    function test_the_class_matches_startup_wm_class() {
        compare(idOf(AppIcon.entryFor(win({ appId: "alacritty" }), entries, null)), "Alacritty");
    }

    function test_the_initial_class_answers_when_the_class_is_empty() {
        compare(idOf(AppIcon.entryFor(win({ initialClass: "firefox" }), entries, null)), "firefox");
    }

    function test_a_reverse_dns_entry_takes_its_last_segment() {
        compare(idOf(AppIcon.entryFor(win({ appId: "discord" }), entries, null)),
            "com.discordapp.Discord");
    }

    function test_a_reverse_dns_class_takes_its_last_segment() {
        var entriesPlain = [entry("wezterm", { name: "WezTerm" })];
        compare(idOf(AppIcon.entryFor(win({ appId: "org.wezfurlong.wezterm" }), entriesPlain, null)),
            "wezterm");
    }

    function test_an_exact_id_wins_over_a_tail_match() {
        compare(idOf(AppIcon.entryFor(win({ appId: "org.wezfurlong.wezterm" }), entries, null)),
            "org.wezfurlong.wezterm");
    }

    // --- tier 2: the process ----------------------------------------------

    function test_an_empty_class_resolves_through_the_launching_script() {
        // The window's own process is whatever the script started; the script
        // itself is its parent, run through an interpreter.
        var procs = [
            { exe: "/nix/store/abc-webkitgtk/bin/MiniBrowser", argv: ["MiniBrowser", "https://messages"] },
            { exe: "/nix/store/xyz-bash/bin/bash", argv: ["bash", "/home/kyandesutter/.local/bin/messages"] }
        ];
        compare(idOf(AppIcon.entryFor(win({ pid: 4242, title: "Messages" }), entries, procs)), "messages");
    }

    function test_an_empty_class_resolves_through_the_exe_itself() {
        var procs = [{ exe: "/home/kyandesutter/.local/bin/messages", argv: ["messages"] }];
        compare(idOf(AppIcon.entryFor(win({ pid: 7 }), entries, procs)), "messages");
    }

    function test_a_nix_wrapper_reads_as_its_program() {
        var procs = [{ exe: "/nix/store/q-foot/bin/.foot-wrapped", argv: ["/run/current-system/sw/bin/foot"] }];
        compare(idOf(AppIcon.entryFor(win({ pid: 9 }), entries, procs)), "foot");
    }

    // An ancestor only matches by absolute path: a class-less app launched
    // from a terminal must not take the terminal's icon.
    function test_an_ancestor_never_matches_by_basename() {
        var procs = [
            { exe: "/opt/thing/thing", argv: ["thing"] },
            { exe: "/usr/bin/fish", argv: ["fish"] },
            { exe: "/usr/bin/foot", argv: ["foot"] }
        ];
        compare(AppIcon.entryFor(win({ pid: 5 }), entries, procs), null);
    }

    function test_an_interpreter_basename_claims_nothing() {
        var procs = [{ exe: "/usr/bin/sh", argv: ["sh", "-c", "run"] }];
        compare(AppIcon.entryFor(win({ pid: 5 }), entries, procs), null);
    }

    // --- tier 3: the initial title ----------------------------------------

    function test_an_empty_class_and_no_process_falls_to_the_initial_title() {
        compare(idOf(AppIcon.entryFor(win({ initialTitle: "Messages", title: "Messages" }), entries, null)),
            "messages");
    }

    function test_the_current_title_alone_matches_nothing() {
        compare(AppIcon.entryFor(win({ title: "Messages" }), entries, null), null);
    }

    function test_nothing_at_all_is_null() {
        compare(AppIcon.entryFor(win({}), entries, null), null);
        compare(AppIcon.entryFor(null, entries, null), null);
        compare(AppIcon.entryFor(win({ appId: "foot" }), [], null), null);
    }

    // --- the picture --------------------------------------------------------

    function test_an_absolute_icon_path_is_a_file_url() {
        compare(AppIcon.source(messages.icon, themed),
            "file:///home/kyandesutter/.local/share/icons/messages.svg");
    }

    function test_a_theme_name_goes_through_the_theme() {
        compare(AppIcon.source("foot", themed), "image://icon/foot");
        compare(AppIcon.source("no-such-icon", themed), "");
        compare(AppIcon.source("", themed), "");
        compare(AppIcon.source("file:///x.png", themed), "file:///x.png");
    }

    // --- the /proc read -----------------------------------------------------

    function test_the_proc_read_parses_into_depth_order() {
        var text = "4242\t1\t/usr/bin/bash\tbash\x1f/home/k/.local/bin/messages\x1f\n"
            + "4242\t0\t/opt/app/app\tapp\x1f--flag\x1f\n"
            + "garbage line\n"
            + "17\t0\t\t\n";
        var read = AppIcon.parseProcs(text);
        compare(read["4242"].length, 2);
        compare(read["4242"][0].exe, "/opt/app/app");
        compare(read["4242"][0].argv.length, 2);
        compare(read["4242"][1].argv[1], "/home/k/.local/bin/messages");
        compare(read["17"].length, 1);
        compare(read["17"][0].argv.length, 0);
    }

    function test_the_proc_command_passes_pids_as_arguments() {
        var argv = AppIcon.procCommand([4242, "17"]);
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        compare(argv.slice(-2), ["4242", "17"]);
    }
}
