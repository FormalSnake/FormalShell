//! Where the quake console lands. Pure, so the placement is testable without a
//! compositor.
//!
//! Resolved on every show rather than once at spawn: a window rule sized at
//! first map freezes the console at whatever the screen measured that day, and
//! an output rescaled afterwards leaves a console that is no longer half of
//! anything (omarchy hit this and worked around it with a gap rule).

use crate::js;

pub const SHARE_MIN: f64 = 0.2;
pub const SHARE_MAX: f64 = 1.0;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Insets {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

pub fn clamp_share(share: f64) -> f64 {
    if !share.is_finite() {
        return 0.5;
    }
    SHARE_MAX.min(SHARE_MIN.max(share))
}

/// `screen` is the output's LOGICAL box (the same space windows' rects and the
/// placement dispatchers use, never the output mode's physical pixels).
/// `insets` is the exclusive zone the bar already took off its own edge; the
/// console drops from the top of what is left and covers `share` of its height,
/// full width less one margin either side.
pub fn console_geometry(screen: Option<Rect>, insets: Option<Insets>, share: f64, margin: f64) -> Option<Rect> {
    let screen = screen.filter(|s| s.width > 0.0 && s.height > 0.0)?;
    let bar = insets.unwrap_or_default();
    let (top_inset, bottom_inset) = (0.0_f64.max(bar.top), 0.0_f64.max(bar.bottom));
    let (left_inset, right_inset) = (0.0_f64.max(bar.left), 0.0_f64.max(bar.right));
    let gap = 0.0_f64.max(js::round(if margin.is_nan() { 0.0 } else { margin }));
    let top = js::round(screen.y + top_inset + gap);
    let usable = screen.height - top_inset - bottom_inset - gap;
    // A margin wider than the screen is a config mistake, not a reason to hand
    // the compositor a negative box.
    let width = 1.0_f64.max(js::round(screen.width - left_inset - right_inset - gap * 2.0));
    let height = 1.0_f64.max(js::round(usable * clamp_share(share)) - gap);
    Some(Rect { x: js::round(screen.x + left_inset + gap), y: top, width, height })
}

/// The argv for a one-off drop-down: the console's own command with its app id
/// swapped for `run_app_id` and `-e <script>` appended. Every emulator spells
/// the class flag differently, so the id is substituted inside the argv the user
/// already wrote rather than appended as a flag this function would have to
/// guess. `None` when that argv never names `app_id`: the one-off would then
/// answer to the console's own id and the console's toggle could pick it up
/// instead of the console, which is worse than not running it.
pub fn one_off_argv(command: Option<&[String]>, app_id: &str, run_app_id: &str, script: &str) -> Option<Vec<String>> {
    let command = command.filter(|c| !c.is_empty())?;
    if app_id.is_empty() || run_app_id.is_empty() || app_id == run_app_id {
        return None;
    }
    let mut named = false;
    let mut out: Vec<String> = Vec::with_capacity(command.len() + 4);
    for arg in command {
        if arg.contains(app_id) {
            named = true;
            out.push(arg.replace(app_id, run_app_id));
        } else {
            out.push(arg.clone());
        }
    }
    if !named {
        return None;
    }
    out.extend(["-e", "sh", "-c", script].map(String::from));
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCREEN: Rect = Rect { x: 0.0, y: 0.0, width: 1920.0, height: 1080.0 };
    const TOP_BAR: Insets = Insets { top: 40.0, bottom: 0.0, left: 0.0, right: 0.0 };
    const NO_BAR: Insets = Insets { top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 };

    fn geo(screen: Rect, insets: Insets, share: f64, margin: f64) -> Rect {
        console_geometry(Some(screen), Some(insets), share, margin).unwrap()
    }

    #[test]
    fn half_of_the_area_under_the_bar() {
        let g = geo(SCREEN, TOP_BAR, 0.5, 10.0);
        assert_eq!((g.x, g.y, g.width, g.height), (10.0, 50.0, 1900.0, 505.0));
    }

    #[test]
    fn second_output_keeps_its_own_origin() {
        let g = geo(Rect { x: 1920.0, y: -200.0, width: 1280.0, height: 720.0 }, TOP_BAR, 0.5, 10.0);
        assert_eq!((g.x, g.y, g.width), (1930.0, -150.0, 1260.0));
    }

    /// A bottom bar takes its band off the bottom: the console drops from the
    /// top edge and covers half of what is left above the bar.
    #[test]
    fn a_bottom_bar_shortens_the_area_from_below() {
        let g = geo(SCREEN, Insets { bottom: 40.0, ..Default::default() }, 0.5, 10.0);
        assert_eq!((g.y, g.height), (10.0, 505.0));
    }

    /// A left bar takes its band off the left: the console starts past it and is
    /// that much narrower, at full height under no top bar.
    #[test]
    fn a_left_bar_narrows_the_console_from_the_left() {
        let g = geo(SCREEN, Insets { left: 40.0, ..Default::default() }, 0.5, 10.0);
        assert_eq!((g.x, g.y, g.width, g.height), (50.0, 10.0, 1860.0, 525.0));
    }

    #[test]
    fn share_is_clamped_at_both_ends() {
        assert_eq!(geo(SCREEN, NO_BAR, 3.0, 0.0).height, 1080.0);
        assert_eq!(geo(SCREEN, NO_BAR, 0.01, 0.0).height, 216.0);
    }

    #[test]
    fn unreadable_share_falls_back_to_half() {
        assert_eq!(geo(SCREEN, NO_BAR, f64::NAN, 0.0).height, geo(SCREEN, NO_BAR, 0.5, 0.0).height);
    }

    #[test]
    fn margin_wider_than_the_screen_never_goes_negative() {
        let g = geo(SCREEN, TOP_BAR, 0.5, 4000.0);
        assert!(g.width >= 1.0);
        assert!(g.height >= 1.0);
    }

    #[test]
    fn no_screen_is_no_geometry() {
        assert_eq!(console_geometry(None, Some(TOP_BAR), 0.5, 10.0), None);
        assert_eq!(console_geometry(Some(Rect::default()), Some(TOP_BAR), 0.5, 10.0), None);
    }

    fn s(items: &[&str]) -> Vec<String> {
        items.iter().map(|x| x.to_string()).collect()
    }

    /// The console's own command, its app id swapped so the standing console
    /// keeps its identity, and the command appended the one way every emulator
    /// the config note names accepts.
    #[test]
    fn one_off_argv_swaps_the_app_id_and_appends_the_command() {
        let argv = one_off_argv(
            Some(&s(&["ghostty", "--class=dev.formalshell.console"])),
            "dev.formalshell.console",
            "dev.formalshell.console.run",
            "nix run nixpkgs#hello; read",
        )
        .unwrap();
        assert_eq!(
            argv,
            s(&["ghostty", "--class=dev.formalshell.console.run", "-e", "sh", "-c", "nix run nixpkgs#hello; read"])
        );
    }

    #[test]
    fn one_off_argv_handles_the_id_in_its_own_argument() {
        let argv = one_off_argv(Some(&s(&["foot", "--app-id", "con"])), "con", "con.run", "true").unwrap();
        assert_eq!(argv.join(" "), "foot --app-id con.run -e sh -c true");
    }

    /// An argv that never names the app id would spawn a second window answering
    /// to the console's own id, which is worse than not running.
    #[test]
    fn one_off_argv_refuses_an_argv_that_never_names_the_app_id() {
        assert_eq!(one_off_argv(Some(&s(&["ghostty"])), "con", "con.run", "true"), None);
        assert_eq!(one_off_argv(Some(&[]), "con", "con.run", "true"), None);
        assert_eq!(one_off_argv(None, "con", "con.run", "true"), None);
        assert_eq!(one_off_argv(Some(&s(&["ghostty", "--class=con"])), "con", "con", "true"), None);
    }
}
