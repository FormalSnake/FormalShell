//! A panel's keyboard cursor as pure functions: the arithmetic behind the
//! first-key reveal, grid stepping, tab sections, scroll-follow and the
//! ring. The panel holds the state; this keeps it testable without a surface.

pub fn clamp(index: i64, count: i64) -> i64 {
    if count <= 0 {
        return 0;
    }
    index.min(count - 1).max(0)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Move {
    pub index: i64,
    pub active: bool,
}

/// The first navigation key only reveals the cursor where it already sits:
/// the highlight has to appear somewhere the eye can find it before anything
/// under it moves. Vertical wins over horizontal so one call covers both axes
/// of a single-column list.
///
/// `columns` above 1 makes the same index a grid position (the calendar's
/// month): vertical steps a whole row, and horizontal stops at the ends of
/// the row it is on rather than sliding into the neighbouring week. Omitted
/// or 1, every list behaves as a plain one.
pub fn step(index: i64, count: i64, active: bool, dx: i64, dy: i64, columns: i64) -> Move {
    if !active {
        return Move {
            index: clamp(index, count),
            active: true,
        };
    }
    let cols = columns.max(1);
    if dy != 0 {
        return Move {
            index: clamp(index + dy * cols, count),
            active: true,
        };
    }
    if cols == 1 {
        return Move {
            index: clamp(index + dx, count),
            active: true,
        };
    }
    let row_start = clamp(index, count) / cols * cols;
    let next = (index + dx).min(row_start + cols - 1).max(row_start);
    Move {
        index: clamp(next, count),
        active: true,
    }
}

/// What activating the cursor reports, or `None` for nothing to activate. A
/// section past the row list (a panel footer holding one button) carries no
/// rows of its own, so only section 0 is gated on the row count.
pub fn activation(index: i64, count: i64, active: bool, section: i64) -> Option<i64> {
    if !active {
        return None;
    }
    if section > 0 {
        return Some(clamp(index, count));
    }
    (count > 0).then(|| clamp(index, count))
}

/// Left/Right on a panel whose cursor row carries an adjustable value
/// (Audio's volume tracks) steps that value instead of walking the list.
/// Gated on `active` for the same reason [`step`] is: the first key reveals
/// the cursor, so nothing under it changes before the eye can find it.
pub fn is_step(dx: i64, dy: i64, steps: bool, active: bool) -> bool {
    steps && active && dy == 0 && dx != 0
}

/// Tab wraps through the panel's sections in either direction.
pub fn section(current: i64, count: i64, direction: i64) -> i64 {
    if count <= 1 {
        return 0;
    }
    ((current + direction) % count + count) % count
}

/// The smallest scroll that puts the cursor row inside the viewport, and the
/// position already held when it is in there. `top` and `content_height` are
/// in the flickable's content coordinates, `viewport` is its visible height,
/// and `pad` is the ring reservation a cursor row draws its halo into, so a
/// row scrolled hard against either edge keeps room for it.
pub fn follow(
    top: f64,
    height: f64,
    content_y: f64,
    viewport: f64,
    content_height: f64,
    pad: f64,
) -> f64 {
    let mut next = content_y;
    if top - pad < next {
        next = top - pad;
    } else if top + height + pad > next + viewport {
        next = top + height + pad - viewport;
    }
    next.min((content_height - viewport).max(0.0)).max(0.0)
}

/// The first ancestor (nearest first) that draws `owns` for the whole group
/// it sits in, in which case the item must not draw its own or there are two.
/// Three flags ride this walk: the travelling cursor halo, the travelling tab
/// fill and a framed surface animating its own height. Walked rather than
/// declared per item: a surface builds its rows in its own file and nests
/// several of them two or three items deep, so a flag spelled at every row
/// would be one new row away from drawing the thing twice.
pub fn owner_above<'a, T>(
    ancestors: impl IntoIterator<Item = &'a T>,
    owns: impl Fn(&T) -> bool,
) -> Option<&'a T> {
    ancestors.into_iter().find(|a| owns(a))
}

/// The panel's key catcher takes no keys at all while an inline editor holds
/// focus, nor while the panel is closed but still mapped, where a stray key
/// would drive a surface nobody can see.
pub fn catcher_blocked(is_open: bool, inline_editor_focused: bool) -> bool {
    !is_open || inline_editor_focused
}

/// The cursor's ring after one write to it. The ring is the keyboard's own
/// mark: `keyed` is set by the two paths a key reaches the cursor by, and
/// every other write to the index, the section or `cursor_active` is a panel
/// naming the row under the pointer. That row keeps the cursor, so Enter
/// still acts on it, and loses the ring, since its hover wash is already the
/// whole mark a pointer needs. A write that leaves no cursor showing decides
/// nothing and the mark survives to whatever puts one back.
pub fn ring_after(on: bool, keyed: bool, shown: bool) -> bool {
    if !shown { on } else { keyed }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mv(index: i64, count: i64, active: bool, dx: i64, dy: i64) -> i64 {
        step(index, count, active, dx, dy, 1).index
    }

    fn grid(index: i64, count: i64, dx: i64, dy: i64, columns: i64) -> i64 {
        step(index, count, true, dx, dy, columns).index
    }

    #[test]
    fn first_move_reveals_without_moving() {
        let next = step(2, 5, false, 0, 1, 1);
        assert_eq!(
            next,
            Move {
                index: 2,
                active: true
            }
        );
    }

    #[test]
    fn second_move_steps() {
        assert_eq!(mv(2, 5, true, 0, 1), 3);
        assert_eq!(mv(2, 5, true, 0, -1), 1);
    }

    #[test]
    fn horizontal_moves_when_there_is_no_vertical_delta() {
        assert_eq!(mv(0, 5, true, 1, 0), 1);
        assert_eq!(mv(3, 5, true, -1, 0), 2);
        // A diagonal is vertical: one call covers both axes of a list.
        assert_eq!(mv(0, 5, true, 1, 1), 1);
    }

    // Calendar's 7-column month: down from the first Monday lands on the
    // second Monday, not on Tuesday.
    #[test]
    fn a_grid_steps_a_whole_row_vertically() {
        assert_eq!(grid(0, 42, 0, 1, 7), 7);
        assert_eq!(grid(14, 42, 0, -1, 7), 7);
    }

    #[test]
    fn a_grid_stops_horizontally_at_the_ends_of_its_own_row() {
        assert_eq!(grid(7, 42, -1, 0, 7), 7);
        assert_eq!(grid(13, 42, 1, 0, 7), 13);
        assert_eq!(grid(8, 42, -1, 0, 7), 7);
    }

    #[test]
    fn a_grid_clamps_vertically_at_the_grid_edges() {
        assert_eq!(grid(3, 42, 0, -1, 7), 0);
        assert_eq!(grid(38, 42, 0, 1, 7), 41);
    }

    #[test]
    fn one_column_behaves_exactly_like_a_list() {
        assert_eq!(grid(2, 5, 0, 1, 1), 3);
        assert_eq!(grid(2, 5, 1, 0, 1), 3);
    }

    #[test]
    fn move_clamps_at_both_ends() {
        assert_eq!(mv(0, 5, true, 0, -1), 0);
        assert_eq!(mv(4, 5, true, 0, 1), 4);
    }

    #[test]
    fn move_on_an_empty_list_stays_at_zero() {
        assert_eq!(mv(3, 0, true, 0, 1), 0);
        assert_eq!(mv(0, 0, false, 0, 1), 0);
    }

    #[test]
    fn clamp_pulls_a_stale_index_back_into_range() {
        assert_eq!(clamp(9, 5), 4);
        assert_eq!(clamp(-3, 5), 0);
        assert_eq!(clamp(2, 0), 0);
    }

    #[test]
    fn activation_reports_the_row_under_the_cursor() {
        assert_eq!(activation(2, 5, true, 0), Some(2));
        assert_eq!(activation(9, 5, true, 0), Some(4));
    }

    #[test]
    fn activation_is_nothing_before_the_cursor_is_revealed() {
        assert_eq!(activation(2, 5, false, 0), None);
    }

    #[test]
    fn activation_is_nothing_on_an_empty_row_list() {
        assert_eq!(activation(0, 0, true, 0), None);
    }

    #[test]
    fn a_section_past_the_row_list_activates_with_no_rows() {
        assert_eq!(activation(0, 0, true, 1), Some(0));
    }

    #[test]
    fn section_wraps_both_ways() {
        assert_eq!(section(0, 2, 1), 1);
        assert_eq!(section(1, 2, 1), 0);
        assert_eq!(section(0, 2, -1), 1);
    }

    #[test]
    fn a_single_section_never_moves() {
        assert_eq!(section(0, 1, 1), 0);
        assert_eq!(section(0, 0, -1), 0);
    }

    #[test]
    fn horizontal_is_a_step_only_on_a_panel_that_asked_for_one() {
        assert!(is_step(1, 0, true, true));
        assert!(is_step(-1, 0, true, true));
        assert!(!is_step(1, 0, false, true));
    }

    #[test]
    fn a_step_never_fires_before_the_cursor_is_revealed() {
        assert!(!is_step(1, 0, true, false));
    }

    #[test]
    fn vertical_is_never_a_step() {
        assert!(!is_step(0, 1, true, true));
        assert!(!is_step(1, 1, true, true));
    }

    #[test]
    fn the_catcher_is_blocked_while_an_inline_editor_has_focus() {
        assert!(catcher_blocked(true, true));
        assert!(!catcher_blocked(true, false));
    }

    #[test]
    fn the_catcher_is_blocked_on_a_closed_panel() {
        assert!(catcher_blocked(false, false));
    }

    // The sequence the ring rule exists for: a hovered row drew the ring and
    // the hover wash at once, which reads as a web focus ring. `keyed` is set
    // by the cursor's key paths alone; every other write is a pointer naming
    // a row.
    #[test]
    fn a_key_lights_the_ring_and_the_pointer_takes_it_off() {
        let mut on = ring_after(false, true, true);
        assert!(on);
        on = ring_after(on, false, true);
        assert!(!on);
        on = ring_after(on, true, true);
        assert!(on);
    }

    #[test]
    fn a_write_with_no_cursor_showing_decides_nothing() {
        assert!(ring_after(true, false, false));
        assert!(!ring_after(false, false, false));
    }

    // A tree of items, nearest ancestor first: a row under a list that owns the ring, and a
    // row under nothing.
    struct Item {
        cursor_from_keys: bool,
    }

    #[test]
    fn a_row_reads_the_nearest_list_above_it() {
        let list = Item {
            cursor_from_keys: true,
        };
        let row = Item {
            cursor_from_keys: false,
        };
        // A control nested inside the row (Audio's tracks) walks past the row
        // to the same list.
        let owner = owner_above([&row, &list], |i| i.cursor_from_keys);
        assert!(std::ptr::eq(owner.unwrap(), &list));
    }

    #[test]
    fn a_row_under_no_list_at_all_draws_the_ring() {
        let row = Item {
            cursor_from_keys: false,
        };
        assert!(owner_above([&row], |i| i.cursor_from_keys).is_none());
    }

    // Scroll-follow. A 400px viewport over 1200px of rows, 40px rows, a 2px
    // ring.

    #[test]
    fn a_row_already_in_view_does_not_scroll() {
        assert_eq!(follow(200.0, 40.0, 100.0, 400.0, 1200.0, 2.0), 100.0);
    }

    #[test]
    fn a_row_below_the_viewport_scrolls_just_far_enough() {
        assert_eq!(follow(520.0, 40.0, 100.0, 400.0, 1200.0, 2.0), 162.0);
    }

    #[test]
    fn a_row_above_the_viewport_scrolls_back_to_it() {
        assert_eq!(follow(80.0, 40.0, 200.0, 400.0, 1200.0, 2.0), 78.0);
    }

    #[test]
    fn the_first_row_never_scrolls_past_the_top() {
        assert_eq!(follow(0.0, 40.0, 200.0, 400.0, 1200.0, 2.0), 0.0);
    }

    #[test]
    fn the_last_row_stops_at_the_end_of_the_content() {
        assert_eq!(follow(1160.0, 40.0, 0.0, 400.0, 1200.0, 2.0), 800.0);
    }

    #[test]
    fn content_shorter_than_the_viewport_never_scrolls() {
        assert_eq!(follow(200.0, 40.0, 0.0, 400.0, 300.0, 2.0), 0.0);
    }
}
