use std::collections::{BTreeMap, HashMap};

use fs_info::herdr::*;
use serde_json::{Value, json};

fn row(pid: i64, ppid: i64, args: &str) -> PsRow {
    PsRow { pid, ppid, args: args.into() }
}

fn client(key: &str, remote: &str, session: &str) -> Option<ClientKey> {
    Some(ClientKey { key: key.into(), remote: remote.into(), session: session.into() })
}

fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| (*s).into()).collect()
}

fn by_window(pairs: &[(i64, &[&str])]) -> BTreeMap<i64, Vec<String>> {
    pairs.iter().map(|(pid, keys)| (*pid, strings(keys))).collect()
}

// parse_ps_rows: `ps -eo pid=,ppid=,args=` shaped text.

#[test]
fn parse_ps_rows_basic() {
    let rows = parse_ps_rows(Some("  123   1 /usr/bin/foo --bar\n  456 123 herdr --remote mac\n"));
    assert_eq!(
        rows,
        vec![row(123, 1, "/usr/bin/foo --bar"), row(456, 123, "herdr --remote mac")]
    );
}

#[test]
fn parse_ps_rows_skips_unmatched_lines() {
    let rows = parse_ps_rows(Some("garbage\n\n  789 1 sh\n"));
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].pid, 789);
}

#[test]
fn parse_ps_rows_empty_input() {
    assert_eq!(parse_ps_rows(Some("")).len(), 0);
    assert_eq!(parse_ps_rows(None).len(), 0);
}

// parse_client

#[test]
fn parse_client_bare() {
    assert_eq!(parse_client(Some("herdr")), client("local", "", ""));
}

#[test]
fn parse_client_nix_store_path() {
    assert_eq!(
        parse_client(Some("/nix/store/xxxx-herdr-0.9.1/bin/herdr")),
        client("local", "", "")
    );
}

#[test]
fn parse_client_session() {
    assert_eq!(parse_client(Some("herdr --session work")), client("local:work", "", "work"));
}

#[test]
fn parse_client_remote() {
    assert_eq!(parse_client(Some("herdr --remote mac")), client("remote:mac", "mac", ""));
}

#[test]
fn parse_client_remote_and_session() {
    assert_eq!(
        parse_client(Some("herdr --remote mac --session work")),
        client("remote:mac:work", "mac", "work")
    );
}

#[test]
fn parse_client_rejects_client_subcommand() {
    assert_eq!(parse_client(Some("herdr client")), None);
}

#[test]
fn parse_client_rejects_server_subcommand() {
    assert_eq!(parse_client(Some("herdr server")), None);
}

#[test]
fn parse_client_rejects_agent_subcommand() {
    assert_eq!(parse_client(Some("herdr agent list")), None);
}

#[test]
fn parse_client_rejects_non_herdr_binary() {
    assert_eq!(parse_client(Some("fish --login")), None);
}

#[test]
fn parse_client_rejects_dangling_flag() {
    assert_eq!(parse_client(Some("herdr --remote")), None);
}

#[test]
fn parse_client_rejects_unknown_flag() {
    assert_eq!(parse_client(Some("herdr --verbose")), None);
}

#[test]
fn parse_client_empty_and_non_string() {
    assert_eq!(parse_client(Some("")), None);
    assert_eq!(parse_client(None), None);
}

// clients_by_window

fn local_client() -> Client {
    Client { remote: "".into(), session: "".into() }
}

#[test]
fn clients_by_window_finds_descendant() {
    let rows = [
        row(100, 1, "foot"),    // the window pid (terminal)
        row(101, 100, "fish"),  // login shell
        row(102, 101, "herdr"), // the client, two levels down
    ];
    let result = clients_by_window(&rows, &[100.0]);
    assert_eq!(result.by_window, by_window(&[(100, &["local"])]));
    assert_eq!(result.clients, BTreeMap::from([("local".to_owned(), local_client())]));
}

#[test]
fn clients_by_window_shallowest_match_wins() {
    let rows = [
        row(100, 1, "foot"),
        row(101, 100, "herdr --session outer"),
        row(102, 101, "herdr --session inner"),
    ];
    let result = clients_by_window(&rows, &[100.0]);
    assert_eq!(result.by_window, by_window(&[(100, &["local:outer"])]));
}

#[test]
fn clients_by_window_no_client_in_subtree() {
    let rows = [row(100, 1, "foot"), row(101, 100, "vim")];
    let result = clients_by_window(&rows, &[100.0]);
    assert!(result.by_window.is_empty());
    assert!(result.clients.is_empty());
}

#[test]
fn clients_by_window_multiple_windows_share_a_key() {
    let rows = [
        row(100, 1, "foot"),
        row(101, 100, "herdr --remote mac"),
        row(200, 1, "foot"),
        row(201, 200, "herdr --remote mac"),
    ];
    let result = clients_by_window(&rows, &[100.0, 200.0]);
    assert_eq!(
        result.by_window,
        by_window(&[(100, &["remote:mac"]), (200, &["remote:mac"])])
    );
    assert_eq!(result.clients.len(), 1);
}

#[test]
fn clients_by_window_skips_zero_and_invalid_pids() {
    let result = clients_by_window(&[], &[0.0, -1.0, f64::NAN]);
    assert!(result.by_window.is_empty());
}

#[test]
fn clients_by_window_does_not_match_client_subcommand() {
    let rows = [
        row(100, 1, "foot"),
        row(101, 100, "herdr --remote mac"),
        row(102, 101, "herdr client"),
    ];
    let result = clients_by_window(&rows, &[100.0]);
    assert_eq!(result.by_window, by_window(&[(100, &["remote:mac"])]));
}

#[test]
fn clients_by_window_collects_every_client_under_a_shared_pid() {
    // A ghostty server: every window's shell is a child of the one pid.
    let rows = [
        row(100, 1, "ghostty"),
        row(101, 100, "fish"),
        row(102, 101, "herdr --remote mac"),
        row(103, 102, "herdr client"),
        row(111, 100, "fish"),
        row(112, 111, "herdr"),
    ];
    let result = clients_by_window(&rows, &[100.0, 100.0]);
    assert_eq!(result.by_window, by_window(&[(100, &["remote:mac", "local"])]));
    let keys: Vec<&str> = result.clients.keys().map(String::as_str).collect();
    assert_eq!(keys, ["local", "remote:mac"]);
}

// default_titles / window_keys: which of a pid's windows a key belongs to.

#[test]
fn default_titles_render_hostname_and_label() {
    assert_eq!(
        default_titles("MacBook-Pro-2.local", Some(&strings(&["nativebrowser", "~", ""]))),
        ["MacBook-Pro-2.local: nativebrowser", "MacBook-Pro-2.local: ~"]
    );
    assert_eq!(default_titles("", Some(&strings(&["a"]))), Vec::<String>::new());
    assert_eq!(default_titles("host", None), Vec::<String>::new());
}

fn window(id: &str, pid: i64, title: &str) -> Window {
    Window { id: id.into(), pid, title: title.into() }
}

fn titles(pairs: &[(&str, Vec<String>)]) -> HashMap<String, Vec<String>> {
    pairs.iter().map(|(k, v)| ((*k).into(), v.clone())).collect()
}

fn expected(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs.iter().map(|(k, v)| ((*k).into(), (*v).into())).collect()
}

#[test]
fn window_keys_lone_window_needs_no_title() {
    let keys = window_keys(
        &[window("a", 100, "anything")],
        &by_window(&[(100, &["local"])]),
        &HashMap::new(),
    );
    assert_eq!(keys, expected(&[("a", "local")]));
}

#[test]
fn window_keys_shared_pid_takes_only_the_titled_window() {
    let windows = [
        window("herdr", 100, "MacBook-Pro-2.local: nativebrowser"),
        window("shell", 100, "~/Developer/FormalShell"),
    ];
    let t = titles(&[(
        "remote:mac",
        default_titles("MacBook-Pro-2.local", Some(&strings(&["nativebrowser", "nix"]))),
    )]);
    assert_eq!(
        window_keys(&windows, &by_window(&[(100, &["remote:mac"])]), &t),
        expected(&[("herdr", "remote:mac")])
    );
}

#[test]
fn window_keys_shared_pid_without_titles_badges_nothing() {
    let windows = [
        window("herdr", 100, "MacBook-Pro-2.local: nativebrowser"),
        window("shell", 100, "fish"),
    ];
    assert!(window_keys(&windows, &by_window(&[(100, &["remote:mac"])]), &HashMap::new()).is_empty());
}

#[test]
fn window_keys_title_match_is_exact() {
    let windows = [
        window("a", 100, "MacBook-Pro-2.local: nativebrowser (2)"),
        window("b", 100, "macbook-pro-2.local: nativebrowser"),
        window("c", 100, "MacBook-Pro-2: nativebrowser"),
    ];
    let t = titles(&[(
        "remote:mac",
        default_titles("MacBook-Pro-2.local", Some(&strings(&["nativebrowser"]))),
    )]);
    assert!(window_keys(&windows, &by_window(&[(100, &["remote:mac"])]), &t).is_empty());
}

#[test]
fn window_keys_two_clients_under_one_window_split_by_title() {
    let windows = [window("one", 100, "e1504g: nix"), window("two", 100, "mac: nix")];
    let t = titles(&[
        ("local", default_titles("e1504g", Some(&strings(&["nix"])))),
        ("remote:mac", default_titles("mac", Some(&strings(&["nix"])))),
    ]);
    assert_eq!(
        window_keys(&windows, &by_window(&[(100, &["local", "remote:mac"])]), &t),
        expected(&[("one", "local"), ("two", "remote:mac")])
    );
}

#[test]
fn window_keys_title_both_candidates_render_is_ambiguous() {
    let windows = [window("a", 100, "mac: nix")];
    let t = titles(&[
        ("remote:mac", default_titles("mac", Some(&strings(&["nix"])))),
        ("remote:mac:work", default_titles("mac", Some(&strings(&["nix"])))),
    ]);
    assert!(window_keys(&windows, &by_window(&[(100, &["remote:mac", "remote:mac:work"])]), &t).is_empty());
}

// parse_poll_line

#[test]
fn parse_poll_line_kinds() {
    assert_eq!(
        parse_poll_line(Some("hostname MacBook-Pro-2.local")),
        PollLine::Hostname("MacBook-Pro-2.local".into())
    );
    assert_eq!(
        parse_poll_line(Some(
            r#"{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"label":"nix"},{"label":"~"}]}}"#
        )),
        PollLine::Labels(strings(&["nix", "~"]))
    );
    match parse_poll_line(Some(r#"{"result":{"agents":[{"agent_status":"working"}]}}"#)) {
        PollLine::Agents(Some(agents)) => assert_eq!(agents.len(), 1),
        other => panic!("{other:?}"),
    }
    assert_eq!(parse_poll_line(Some("null")), PollLine::Agents(None));
}

// parse_list

#[test]
fn parse_list_ok() {
    let line = r#"{"id":1,"result":{"type":"agent_list","agents":[{"agent":"claude","agent_status":"working","pane_id":"w1:p1A","workspace_id":"w1"}]}}"#;
    let agents = parse_list(Some(line)).unwrap();
    assert_eq!(agents.len(), 1);
    assert_eq!(agents[0]["agent_status"], "working");
}

#[test]
fn parse_list_garbage_json() {
    assert_eq!(parse_list(Some("not json")), None);
}

#[test]
fn parse_list_null_placeholder() {
    // the poll loop's own `echo null` stand-in for a failed call.
    assert_eq!(parse_list(Some("null")), None);
}

#[test]
fn parse_list_missing_agents() {
    assert_eq!(parse_list(Some(r#"{"result":{"type":"agent_list"}}"#)), None);
}

#[test]
fn parse_list_empty_string() {
    assert_eq!(parse_list(Some("")), None);
    assert_eq!(parse_list(None), None);
}

#[test]
fn parse_list_empty_agents_array() {
    assert_eq!(parse_list(Some(r#"{"result":{"agents":[]}}"#)), Some(vec![]));
}

// aggregate

fn status(s: &str) -> Value {
    json!({ "agent_status": s })
}

#[test]
fn aggregate_blocked_wins_over_working() {
    assert_eq!(aggregate(&[status("working"), status("blocked")]).as_str(), "blocked");
}

#[test]
fn aggregate_working_wins_over_done() {
    assert_eq!(aggregate(&[status("done"), status("working")]).as_str(), "working");
}

#[test]
fn aggregate_done_alone() {
    assert_eq!(aggregate(&[status("done")]).as_str(), "done");
}

#[test]
fn aggregate_idle_and_unknown_draw_nothing() {
    assert_eq!(aggregate(&[status("idle"), status("unknown")]).as_str(), "");
}

#[test]
fn aggregate_empty_or_invalid() {
    assert_eq!(aggregate(&[]).as_str(), "");
    assert_eq!(aggregate_value(&json!(null)).as_str(), "");
    assert_eq!(aggregate_value(&json!("not an array")).as_str(), "");
}

// shell_quote / fish_quote / poll_command: the ssh + fish + bash nesting the
// plan calls out as the risky part, checked byte-for-byte rather than by eye.
// Every case here was cross-checked against a real fish 4.9.3 (`fish -c "bash
// -c '<fish_quote output>'"` round trip).

#[test]
fn shell_quote_plain() {
    assert_eq!(shell_quote("work"), "'work'");
}

#[test]
fn shell_quote_embedded_quote() {
    assert_eq!(shell_quote("o'clock"), "'o'\\''clock'");
}

#[test]
fn fish_quote_plain() {
    assert_eq!(fish_quote("hello world"), "'hello world'");
}

#[test]
fn fish_quote_escapes_backslash_and_quote() {
    // a shell_quote()'d session name nested inside the outer fish_quote()
    // carries both a literal backslash and a literal quote, exactly the
    // combination the two escaping rules have to survive together.
    let inner = format!("herdr --session {} agent list", shell_quote("o'clock"));
    assert_eq!(inner, "herdr --session 'o'\\''clock' agent list");
    assert_eq!(fish_quote(&inner), "'herdr --session \\'o\\'\\\\\\'\\'clock\\' agent list'");
}

fn remote(remote: &str, session: &str) -> Client {
    Client { remote: remote.into(), session: session.into() }
}

#[test]
fn poll_command_local_no_session() {
    let cmd = poll_command(&remote("", ""));
    assert_eq!(cmd[0], "sh");
    assert_eq!(cmd[1], "-c");
    assert!(!cmd[2].contains("herdr --session"));
    assert!(cmd[2].contains("herdr agent list"));
}

#[test]
fn poll_command_local_with_session() {
    let cmd = poll_command(&remote("", "work"));
    assert!(cmd[2].contains("herdr --session 'work' agent list"));
}

#[test]
fn poll_command_remote_shape() {
    let cmd = poll_command(&remote("mac", ""));
    assert_eq!(cmd[0], "ssh");
    assert_eq!(cmd[cmd.len() - 2], "mac");
    let remote_cmd = &cmd[cmd.len() - 1];
    assert!(remote_cmd.starts_with("bash --norc -c '"));
    // fish's own escaping never leaves a bare, unescaped single quote inside
    // the wrapper: every `'` in the body is preceded by `\`.
    let body = &remote_cmd["bash --norc -c '".len()..remote_cmd.len() - 1];
    let bare_quote = body
        .char_indices()
        .any(|(i, c)| c == '\'' && (i == 0 || body.as_bytes()[i - 1] != b'\\'));
    assert!(!bare_quote);
}

// The service never closes a child's stdin, and bash under sshd sources
// ~/.bashrc even for `-c`; one that starts fish there blocked the loop on
// e1504g before it printed a single line.
#[test]
fn poll_command_remote_never_waits_on_stdin_or_bashrc() {
    let cmd = poll_command(&remote("mac", ""));
    let n = cmd.iter().position(|a| a == "-n").unwrap();
    let mac = cmd.iter().position(|a| a == "mac").unwrap();
    assert!(n > 0 && n < mac);
    assert!(cmd[cmd.len() - 1].starts_with("bash --norc -c "));
}

#[test]
fn poll_command_reports_hostname_and_workspaces() {
    let local = &poll_command(&remote("", ""))[2];
    assert!(local.contains("echo \"hostname $(uname -n)\""));
    assert!(local.contains("herdr workspace list 2>/dev/null;"));
    let remote_cmd = poll_command(&remote("mac", "work"));
    assert!(remote_cmd[remote_cmd.len() - 1].contains("workspace list"));
}

#[test]
fn poll_command_remote_resolves_herdr_three_ways() {
    let cmd = poll_command(&remote("mac", ""));
    let remote_cmd = &cmd[cmd.len() - 1];
    assert!(remote_cmd.contains("command -v herdr"));
    assert!(remote_cmd.contains(".nix-profile/bin/herdr"));
    assert!(remote_cmd.contains("/etc/profiles/per-user/"));
}
