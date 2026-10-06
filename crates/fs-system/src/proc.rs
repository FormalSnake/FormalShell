//! Long-lived children of the shell, wrapped so the kernel kills them when
//! the shell dies.
//!
//! `systemctl --user restart formalshell` kills the shell outright, and every
//! child it owned is reparented to systemd and left running. systemd does not
//! clean them up either, because the unit sets KillMode=process deliberately:
//! outside a uwsm session, apps launched from the launcher share the shell's
//! cgroup and have to survive a restart.
//!
//! PR_SET_PDEATHSIG closes every exit path. setpriv sets it and execs in
//! place, so the wrapped command is still the shell's own direct child and
//! its pid is the one a signal has to reach, which the night light's SIGUSR1
//! handshake depends on.
//!
//! Only for a child that outlives its own call: a one-shot exits long before
//! a restart can orphan it.

use regex::Regex;
use std::sync::LazyLock;

pub fn die_with_parent(argv: &[String]) -> Vec<String> {
    let mut out: Vec<String> = ["setpriv", "--pdeathsig", "TERM", "--"].map(String::from).to_vec();
    out.extend(argv.iter().cloned());
    out
}

/// The parts of a desktop entry `app_launch` reads.
#[derive(Debug, Clone, Default)]
pub struct Entry {
    pub id: String,
    pub command: Vec<String>,
    pub run_in_terminal: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Action {
    pub command: Vec<String>,
}

/// uwsm rejects an id outside this pattern with an error toast, and a file
/// named "Modrinth App.desktop" has a space in its id.
static UWSM_ENTRY_ID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$").unwrap());

/// argv that launches a desktop entry, or one of its actions, as its own scope
/// in app-graphical.slice rather than as a child in the shell's cgroup, so
/// systemd-oomd can kill that one app instead of the shell and everything it
/// launched. uwsm parses the entry itself, so Exec field codes and
/// Terminal=true behave as in any launcher. An action goes by its parsed
/// command: uwsm only resolves actions by id. An id uwsm rejects goes by its
/// parsed command too, with -T carrying Terminal=true.
///
/// `None` outside a uwsm session (the nested smoke rig has no app slice to
/// land in).
pub fn app_launch(uwsm_session: bool, entry: Option<&Entry>, action: Option<&Action>) -> Option<Vec<String>> {
    let entry = entry.filter(|_| uwsm_session)?;
    if action.is_none() && UWSM_ENTRY_ID.is_match(&entry.id) {
        return Some(vec!["uwsm".into(), "app".into(), "--".into(), format!("{}.desktop", entry.id)]);
    }
    let command = action.map_or(&entry.command, |a| &a.command);
    if command.is_empty() {
        return None;
    }
    let mut argv: Vec<String> = vec!["uwsm".into(), "app".into()];
    if action.is_none() && entry.run_in_terminal {
        argv.push("-T".into());
    }
    argv.push("--".into());
    argv.extend(command.iter().cloned());
    Some(argv)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    fn entry(id: &str, command: &[&str], term: bool) -> Entry {
        Entry { id: id.into(), command: s(command), run_in_terminal: term }
    }

    #[test]
    fn the_wrapped_command_survives_verbatim() {
        let argv = die_with_parent(&s(&["wl-paste", "--type", "text", "--watch", "sh", "-c", "cat"]));
        assert_eq!(argv[4..], s(&["wl-paste", "--type", "text", "--watch", "sh", "-c", "cat"])[..]);
    }

    #[test]
    fn setpriv_options_end_before_the_command() {
        let argv = die_with_parent(&s(&["cava", "-p", "/tmp/cfg"]));
        assert_eq!(argv[..4], s(&["setpriv", "--pdeathsig", "TERM", "--"])[..]);
        assert_eq!(argv.iter().position(|a| a == "--"), Some(3));
    }

    #[test]
    fn an_empty_command_is_not_an_error() {
        assert_eq!(die_with_parent(&[]), s(&["setpriv", "--pdeathsig", "TERM", "--"]));
    }

    #[test]
    fn the_callers_array_is_left_alone() {
        let argv = s(&["ttfx", "--effect", "rain"]);
        let _ = die_with_parent(&argv);
        assert_eq!(argv, s(&["ttfx", "--effect", "rain"]));
    }

    #[test]
    fn app_launch_goes_by_desktop_id_under_uwsm() {
        let e = entry("org.gnome.Nautilus", &[], false);
        assert_eq!(app_launch(true, Some(&e), None), Some(s(&["uwsm", "app", "--", "org.gnome.Nautilus.desktop"])));
    }

    #[test]
    fn an_action_launches_by_its_parsed_command() {
        let action = Action { command: s(&["firefox", "--private-window"]) };
        let e = entry("firefox", &[], false);
        assert_eq!(app_launch(true, Some(&e), Some(&action)), Some(s(&["uwsm", "app", "--", "firefox", "--private-window"])));
    }

    #[test]
    fn an_id_uwsm_rejects_launches_by_command() {
        let e = entry("Modrinth App", &["ModrinthApp"], false);
        assert_eq!(app_launch(true, Some(&e), None), Some(s(&["uwsm", "app", "--", "ModrinthApp"])));
    }

    #[test]
    fn a_terminal_entry_by_command_keeps_its_terminal() {
        let e = entry("My Tool", &["htop"], true);
        assert_eq!(app_launch(true, Some(&e), None), Some(s(&["uwsm", "app", "-T", "--", "htop"])));
    }

    #[test]
    fn no_uwsm_session_means_no_argv() {
        let e = entry("firefox", &[], false);
        assert_eq!(app_launch(false, Some(&e), None), None);
        assert_eq!(app_launch(true, Some(&e), Some(&Action::default())), None);
    }
}
