import QtQuick
import QtTest
import "../shell/Herdr/model.js" as HerdrModel

TestCase {
    name: "HerdrModel"

    // parsePsRows: `ps -eo pid=,ppid=,args=` shaped text.

    function test_parse_ps_rows_basic() {
        var rows = HerdrModel.parsePsRows("  123   1 /usr/bin/foo --bar\n  456 123 herdr --remote mac\n");
        compare(rows.length, 2);
        compare(rows[0], { pid: 123, ppid: 1, args: "/usr/bin/foo --bar" });
        compare(rows[1], { pid: 456, ppid: 123, args: "herdr --remote mac" });
    }

    function test_parse_ps_rows_skips_unmatched_lines() {
        var rows = HerdrModel.parsePsRows("garbage\n\n  789 1 sh\n");
        compare(rows.length, 1);
        compare(rows[0].pid, 789);
    }

    function test_parse_ps_rows_empty_input() {
        compare(HerdrModel.parsePsRows("").length, 0);
        compare(HerdrModel.parsePsRows(null).length, 0);
    }

    // parseClient.

    function test_parse_client_bare() {
        var c = HerdrModel.parseClient("herdr");
        compare(c, { key: "local", remote: "", session: "" });
    }

    function test_parse_client_nix_store_path() {
        var c = HerdrModel.parseClient("/nix/store/xxxx-herdr-0.9.1/bin/herdr");
        compare(c, { key: "local", remote: "", session: "" });
    }

    function test_parse_client_session() {
        var c = HerdrModel.parseClient("herdr --session work");
        compare(c, { key: "local:work", remote: "", session: "work" });
    }

    function test_parse_client_remote() {
        var c = HerdrModel.parseClient("herdr --remote mac");
        compare(c, { key: "remote:mac", remote: "mac", session: "" });
    }

    function test_parse_client_remote_and_session() {
        var c = HerdrModel.parseClient("herdr --remote mac --session work");
        compare(c, { key: "remote:mac:work", remote: "mac", session: "work" });
    }

    function test_parse_client_rejects_client_subcommand() {
        compare(HerdrModel.parseClient("herdr client"), null);
    }

    function test_parse_client_rejects_server_subcommand() {
        compare(HerdrModel.parseClient("herdr server"), null);
    }

    function test_parse_client_rejects_agent_subcommand() {
        compare(HerdrModel.parseClient("herdr agent list"), null);
    }

    function test_parse_client_rejects_non_herdr_binary() {
        compare(HerdrModel.parseClient("fish --login"), null);
    }

    function test_parse_client_rejects_dangling_flag() {
        compare(HerdrModel.parseClient("herdr --remote"), null);
    }

    function test_parse_client_rejects_unknown_flag() {
        compare(HerdrModel.parseClient("herdr --verbose"), null);
    }

    function test_parse_client_empty_and_non_string() {
        compare(HerdrModel.parseClient(""), null);
        compare(HerdrModel.parseClient(null), null);
    }

    // clientsByWindow.

    function test_clients_by_window_finds_descendant() {
        var rows = [
            { pid: 100, ppid: 1, args: "foot" },       // the window pid (terminal)
            { pid: 101, ppid: 100, args: "fish" },      // login shell
            { pid: 102, ppid: 101, args: "herdr" }      // the client, two levels down
        ];
        var result = HerdrModel.clientsByWindow(rows, [100]);
        compare(result.byWindow, { 100: ["local"] });
        compare(result.clients, { local: { remote: "", session: "" } });
    }

    function test_clients_by_window_shallowest_match_wins() {
        var rows = [
            { pid: 100, ppid: 1, args: "foot" },
            { pid: 101, ppid: 100, args: "herdr --session outer" },
            { pid: 102, ppid: 101, args: "herdr --session inner" }
        ];
        var result = HerdrModel.clientsByWindow(rows, [100]);
        compare(result.byWindow, { 100: ["local:outer"] });
    }

    function test_clients_by_window_no_client_in_subtree() {
        var rows = [
            { pid: 100, ppid: 1, args: "foot" },
            { pid: 101, ppid: 100, args: "vim" }
        ];
        var result = HerdrModel.clientsByWindow(rows, [100]);
        compare(result.byWindow, {});
        compare(result.clients, {});
    }

    function test_clients_by_window_multiple_windows_share_a_key() {
        var rows = [
            { pid: 100, ppid: 1, args: "foot" },
            { pid: 101, ppid: 100, args: "herdr --remote mac" },
            { pid: 200, ppid: 1, args: "foot" },
            { pid: 201, ppid: 200, args: "herdr --remote mac" }
        ];
        var result = HerdrModel.clientsByWindow(rows, [100, 200]);
        compare(result.byWindow, { 100: ["remote:mac"], 200: ["remote:mac"] });
        compare(Object.keys(result.clients).length, 1);
    }

    function test_clients_by_window_skips_zero_and_invalid_pids() {
        var result = HerdrModel.clientsByWindow([], [0, -1, NaN]);
        compare(result.byWindow, {});
    }

    function test_clients_by_window_does_not_match_client_subcommand() {
        var rows = [
            { pid: 100, ppid: 1, args: "foot" },
            { pid: 101, ppid: 100, args: "herdr --remote mac" },
            { pid: 102, ppid: 101, args: "herdr client" }
        ];
        var result = HerdrModel.clientsByWindow(rows, [100]);
        compare(result.byWindow, { 100: ["remote:mac"] });
    }

    function test_clients_by_window_collects_every_client_under_a_shared_pid() {
        // A ghostty server: every window's shell is a child of the one pid.
        var rows = [
            { pid: 100, ppid: 1, args: "ghostty" },
            { pid: 101, ppid: 100, args: "fish" },
            { pid: 102, ppid: 101, args: "herdr --remote mac" },
            { pid: 103, ppid: 102, args: "herdr client" },
            { pid: 111, ppid: 100, args: "fish" },
            { pid: 112, ppid: 111, args: "herdr" }
        ];
        var result = HerdrModel.clientsByWindow(rows, [100, 100]);
        compare(result.byWindow, { 100: ["remote:mac", "local"] });
        compare(Object.keys(result.clients).sort(), ["local", "remote:mac"]);
    }

    // defaultTitles / windowKeys: which of a pid's windows a key belongs to.

    function test_default_titles() {
        compare(HerdrModel.defaultTitles("MacBook-Pro-2.local", ["nativebrowser", "~", ""]),
            ["MacBook-Pro-2.local: nativebrowser", "MacBook-Pro-2.local: ~"]);
        compare(HerdrModel.defaultTitles("", ["a"]), []);
        compare(HerdrModel.defaultTitles("host", undefined), []);
    }

    function test_window_keys_lone_window_needs_no_title() {
        var keys = HerdrModel.windowKeys([{ id: "a", pid: 100, title: "anything" }], { 100: ["local"] }, {});
        compare(keys, { a: "local" });
    }

    function test_window_keys_shared_pid_takes_only_the_titled_window() {
        var windows = [
            { id: "herdr", pid: 100, title: "MacBook-Pro-2.local: nativebrowser" },
            { id: "shell", pid: 100, title: "~/Developer/FormalShell" }
        ];
        var titles = { "remote:mac": HerdrModel.defaultTitles("MacBook-Pro-2.local", ["nativebrowser", "nix"]) };
        compare(HerdrModel.windowKeys(windows, { 100: ["remote:mac"] }, titles), { herdr: "remote:mac" });
    }

    function test_window_keys_shared_pid_without_titles_badges_nothing() {
        var windows = [
            { id: "herdr", pid: 100, title: "MacBook-Pro-2.local: nativebrowser" },
            { id: "shell", pid: 100, title: "fish" }
        ];
        compare(HerdrModel.windowKeys(windows, { 100: ["remote:mac"] }, {}), {});
    }

    function test_window_keys_title_match_is_exact() {
        var windows = [
            { id: "a", pid: 100, title: "MacBook-Pro-2.local: nativebrowser (2)" },
            { id: "b", pid: 100, title: "macbook-pro-2.local: nativebrowser" },
            { id: "c", pid: 100, title: "MacBook-Pro-2: nativebrowser" }
        ];
        var titles = { "remote:mac": HerdrModel.defaultTitles("MacBook-Pro-2.local", ["nativebrowser"]) };
        compare(HerdrModel.windowKeys(windows, { 100: ["remote:mac"] }, titles), {});
    }

    function test_window_keys_two_clients_under_one_window_split_by_title() {
        var windows = [
            { id: "one", pid: 100, title: "e1504g: nix" },
            { id: "two", pid: 100, title: "mac: nix" }
        ];
        var titles = {
            local: HerdrModel.defaultTitles("e1504g", ["nix"]),
            "remote:mac": HerdrModel.defaultTitles("mac", ["nix"])
        };
        compare(HerdrModel.windowKeys(windows, { 100: ["local", "remote:mac"] }, titles),
            { one: "local", two: "remote:mac" });
    }

    function test_window_keys_title_both_candidates_render_is_ambiguous() {
        var windows = [{ id: "a", pid: 100, title: "mac: nix" }];
        var titles = {
            "remote:mac": HerdrModel.defaultTitles("mac", ["nix"]),
            "remote:mac:work": HerdrModel.defaultTitles("mac", ["nix"])
        };
        compare(HerdrModel.windowKeys(windows, { 100: ["remote:mac", "remote:mac:work"] }, titles), {});
    }

    // parsePollLine.

    function test_parse_poll_line_kinds() {
        compare(HerdrModel.parsePollLine("hostname MacBook-Pro-2.local"), { hostname: "MacBook-Pro-2.local" });
        compare(HerdrModel.parsePollLine('{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"label":"nix"},{"label":"~"}]}}'),
            { labels: ["nix", "~"] });
        compare(HerdrModel.parsePollLine('{"result":{"agents":[{"agent_status":"working"}]}}').agents.length, 1);
        compare(HerdrModel.parsePollLine("null"), { agents: null });
    }

    // parseList.

    function test_parse_list_ok() {
        var line = '{"id":1,"result":{"type":"agent_list","agents":[{"agent":"claude","agent_status":"working","pane_id":"w1:p1A","workspace_id":"w1"}]}}';
        var agents = HerdrModel.parseList(line);
        compare(agents.length, 1);
        compare(agents[0].agent_status, "working");
    }

    function test_parse_list_garbage_json() {
        compare(HerdrModel.parseList("not json"), null);
    }

    function test_parse_list_null_placeholder() {
        // the poll loop's own `echo null` stand-in for a failed call.
        compare(HerdrModel.parseList("null"), null);
    }

    function test_parse_list_missing_agents() {
        compare(HerdrModel.parseList('{"result":{"type":"agent_list"}}'), null);
    }

    function test_parse_list_empty_string() {
        compare(HerdrModel.parseList(""), null);
        compare(HerdrModel.parseList(undefined), null);
    }

    function test_parse_list_empty_agents_array() {
        var agents = HerdrModel.parseList('{"result":{"agents":[]}}');
        compare(agents, []);
    }

    // aggregate.

    function test_aggregate_blocked_wins_over_working() {
        compare(HerdrModel.aggregate([{ agent_status: "working" }, { agent_status: "blocked" }]), "blocked");
    }

    function test_aggregate_working_wins_over_done() {
        compare(HerdrModel.aggregate([{ agent_status: "done" }, { agent_status: "working" }]), "working");
    }

    function test_aggregate_done_alone() {
        compare(HerdrModel.aggregate([{ agent_status: "done" }]), "done");
    }

    function test_aggregate_idle_and_unknown_draw_nothing() {
        compare(HerdrModel.aggregate([{ agent_status: "idle" }, { agent_status: "unknown" }]), "");
    }

    function test_aggregate_empty_or_invalid() {
        compare(HerdrModel.aggregate([]), "");
        compare(HerdrModel.aggregate(null), "");
        compare(HerdrModel.aggregate("not an array"), "");
    }

    // shellQuote / fishQuote / pollCommand: the ssh + fish + bash nesting the
    // plan calls out as the risky part, checked byte-for-byte rather than by
    // eye. Every case here was cross-checked against a real fish 4.9.3
    // (`fish -c "bash -c '<fishQuote output>'"` round trip).

    function test_shell_quote_plain() {
        compare(HerdrModel.shellQuote("work"), "'work'");
    }

    function test_shell_quote_embedded_quote() {
        compare(HerdrModel.shellQuote("o'clock"), "'o'\\''clock'");
    }

    function test_fish_quote_plain() {
        compare(HerdrModel.fishQuote("hello world"), "'hello world'");
    }

    function test_fish_quote_escapes_backslash_and_quote() {
        // a shellQuote()'d session name nested inside the outer fishQuote()
        // carries both a literal backslash and a literal quote, exactly the
        // combination the two escaping rules have to survive together.
        var inner = "herdr --session " + HerdrModel.shellQuote("o'clock") + " agent list";
        compare(inner, "herdr --session 'o'\\''clock' agent list");
        var wrapped = HerdrModel.fishQuote(inner);
        compare(wrapped, "'herdr --session \\'o\\'\\\\\\'\\'clock\\' agent list'");
    }

    function test_poll_command_local_no_session() {
        var cmd = HerdrModel.pollCommand({ remote: "", session: "" });
        compare(cmd[0], "sh");
        compare(cmd[1], "-c");
        compare(cmd[2].indexOf("herdr --session") < 0, true);
        compare(cmd[2].indexOf("herdr agent list") >= 0, true);
    }

    function test_poll_command_local_with_session() {
        var cmd = HerdrModel.pollCommand({ remote: "", session: "work" });
        compare(cmd[2].indexOf("herdr --session 'work' agent list") >= 0, true);
    }

    function test_poll_command_remote_shape() {
        var cmd = HerdrModel.pollCommand({ remote: "mac", session: "" });
        compare(cmd[0], "ssh");
        compare(cmd[cmd.length - 2], "mac");
        var remoteCmd = cmd[cmd.length - 1];
        compare(remoteCmd.indexOf("bash --norc -c '") === 0, true);
        // fish's own escaping never leaves a bare, unescaped single quote
        // inside the wrapper: every `'` in the body is preceded by `\`.
        var body = remoteCmd.slice("bash --norc -c '".length, -1);
        var bareQuote = /(^|[^\\])'/.test(body);
        compare(bareQuote, false);
    }

    // Quickshell never closes a child's stdin, and bash under sshd sources
    // ~/.bashrc even for `-c`; one that starts fish there blocked the loop
    // on e1504g before it printed a single line.
    function test_poll_command_remote_never_waits_on_stdin_or_bashrc() {
        var cmd = HerdrModel.pollCommand({ remote: "mac", session: "" });
        compare(cmd.indexOf("-n") > 0 && cmd.indexOf("-n") < cmd.indexOf("mac"), true);
        compare(cmd[cmd.length - 1].indexOf("bash --norc -c ") === 0, true);
    }

    function test_poll_command_reports_hostname_and_workspaces() {
        var local = HerdrModel.pollCommand({ remote: "", session: "" })[2];
        compare(local.indexOf('echo "hostname $(uname -n)"') >= 0, true);
        compare(local.indexOf("herdr workspace list 2>/dev/null;") >= 0, true);
        var remote = HerdrModel.pollCommand({ remote: "mac", session: "work" });
        compare(remote[remote.length - 1].indexOf("workspace list") >= 0, true);
    }

    function test_poll_command_remote_resolves_herdr_three_ways() {
        var cmd = HerdrModel.pollCommand({ remote: "mac", session: "" });
        var remoteCmd = cmd[cmd.length - 1];
        compare(remoteCmd.indexOf("command -v herdr") >= 0, true);
        compare(remoteCmd.indexOf(".nix-profile/bin/herdr") >= 0, true);
        compare(remoteCmd.indexOf("/etc/profiles/per-user/") >= 0, true);
    }
}
