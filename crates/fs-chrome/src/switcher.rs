//! The window switcher's list and its cursor, pure so the order, the wrap and
//! the empty state are testable without a compositor.

use std::collections::HashSet;

use fs_js as js;
use crate::types::Rect;

/// What the switcher needs to know about a window to offer it.
pub trait SwitcherWindow {
    fn id(&self) -> &str;
    fn workspace_id(&self) -> &str;
}

/// What the switcher offers, in Gala's order: the most recently focused
/// window first, the one before it second, and so on, which is what makes a
/// single Alt+Tab land on the window you just came from. `history` is the ids
/// the surface has watched take focus, newest first; a window nothing has
/// focused this session has no place in it and keeps the compositor's own
/// order behind the ones that have.
///
/// `workspace_id` is the one being looked at, and windows anywhere else are
/// not offered. Gala's own list is the active workspace's, and offering the
/// rest is what made a quick Alt+Tab land on another workspace and take the
/// compositor there with it. Empty means no filter.
///
/// Special workspaces (ids starting with `-`) are dropped ahead of that, the
/// same rule the workspace model carries: they are overlays rather than
/// places, and the quake console lives on one permanently, so offering them
/// would offer a window the user cannot see and never put there.
pub fn entries<'a, W: SwitcherWindow>(
    windows: &'a [W],
    history: &[String],
    workspace_id: &str,
) -> Vec<&'a W> {
    let offered: Vec<&W> = windows
        .iter()
        .filter(|w| !w.id().is_empty())
        .filter(|w| !w.workspace_id().starts_with('-'))
        .filter(|w| workspace_id.is_empty() || w.workspace_id() == workspace_id)
        .collect();

    let mut out = Vec::new();
    let mut taken: HashSet<&str> = HashSet::new();
    for seen in history {
        for window in &offered {
            if window.id() != seen || taken.contains(seen.as_str()) {
                continue;
            }
            taken.insert(seen);
            out.push(*window);
        }
    }
    out.extend(offered.iter().filter(|w| !taken.contains(w.id())));
    out
}

/// Where the cursor lands after a step, wrapping both ways. An empty list has
/// no cursor at all, which is the index the caller holds while nothing is
/// offered.
pub fn advance(index: i64, count: i64, step: i64) -> i64 {
    if count <= 0 {
        return 0;
    }
    let next = (index + step) % count;
    if next < 0 { next + count } else { next }
}

/// One cell's thumbnail width at a fixed height, from the window's own rect so
/// the picture keeps its aspect. A window with no rect yet reads as 16:9, and
/// the ratio is held between `min_width` and `max_width` so a sliver of a
/// window or a very wide one still leaves a cell that can carry its caption.
pub fn thumb_width(rect: Option<Rect>, height: f64, min_width: f64, max_width: f64) -> f64 {
    let ratio = match rect {
        Some(r) if r.width > 0.0 && r.height > 0.0 => r.width / r.height,
        _ => 16.0 / 9.0,
    };
    let width = js::round(height * ratio);
    min_width.max(max_width.min(width))
}

#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub first: usize,
    pub count: usize,
    pub width: f64,
    pub widths: Vec<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Grid {
    pub rows: Vec<Row>,
    pub width: f64,
    pub gap: f64,
}

fn pack(widths: &[f64], gap: f64, limit: f64) -> Vec<Row> {
    let mut rows = Vec::new();
    let mut first = 0;
    let mut used = 0.0;
    for (i, &w) in widths.iter().enumerate() {
        let mut next = if i == first { w } else { used + gap + w };
        if i > first && next > limit {
            rows.push(Row {
                first,
                count: i - first,
                width: used,
                widths: widths[first..i].to_vec(),
            });
            first = i;
            next = w;
        }
        used = next;
    }
    if !widths.is_empty() {
        rows.push(Row {
            first,
            count: widths.len() - first,
            width: used,
            widths: widths[first..].to_vec(),
        });
    }
    rows
}

/// The cells wrapped into rows no wider than `max_width`, in order. A row
/// count is taken from a plain greedy fill, then the limit is pulled in as far
/// as that count allows, so eleven windows over two rows read as 6 and 5
/// rather than as a full row and a stub. `width` is the widest row, which is
/// what the card is as wide as, and each row carries its cells' widths. A cell
/// wider than `max_width` still gets a row of its own.
pub fn layout(widths: &[f64], gap: f64, max_width: f64) -> Grid {
    if widths.is_empty() {
        return Grid {
            rows: Vec::new(),
            width: 0.0,
            gap,
        };
    }
    let widest = widths.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let limit = widest.max(max_width.floor());
    let count = pack(widths, gap, limit).len();
    let mut low = widest;
    let mut high = limit;
    while low < high {
        let mid = ((low + high) / 2.0).floor();
        if pack(widths, gap, mid).len() <= count {
            high = mid;
        } else {
            low = mid + 1.0;
        }
    }
    let rows = pack(widths, gap, high);
    let width = rows.iter().fold(0.0_f64, |w, r| w.max(r.width));
    Grid { rows, width, gap }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Cell {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub row: usize,
}

/// Where each cell sits in the grid, from the top left: rows stacked at
/// `cell_height`, each centred on the widest one.
pub fn cells(grid: &Grid, cell_height: f64) -> Vec<Cell> {
    let mut out = Vec::new();
    for (r, row) in grid.rows.iter().enumerate() {
        let mut x = (grid.width - row.width) / 2.0;
        for &width in &row.widths[..row.count] {
            out.push(Cell {
                x,
                y: r as f64 * cell_height,
                width,
                height: cell_height,
                row: r,
            });
            x += width + grid.gap;
        }
    }
    out
}

/// Which row holds entry `index`, if any.
pub fn row_of(rows: &[Row], index: usize) -> Option<usize> {
    rows.iter()
        .position(|r| index >= r.first && index < r.first + r.count)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Ordinal {
    pub n: usize,
    pub of: usize,
}

/// Which of its app's windows each tile is, `n` counting from 1 in row order.
/// An empty key is a window nothing could name, which is never grouped with
/// another, so it reads `1 of 1`.
pub fn ordinals(keys: &[&str]) -> Vec<Ordinal> {
    let mut totals = std::collections::HashMap::new();
    for key in keys.iter().filter(|k| !k.is_empty()) {
        *totals.entry(*key).or_insert(0usize) += 1;
    }
    let mut seen = std::collections::HashMap::new();
    keys.iter()
        .map(|key| {
            if key.is_empty() {
                return Ordinal { n: 1, of: 1 };
            }
            let n = seen.entry(*key).or_insert(0usize);
            *n += 1;
            Ordinal {
                n: *n,
                of: totals[key],
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Win {
        id: String,
        workspace_id: String,
    }

    impl SwitcherWindow for Win {
        fn id(&self) -> &str {
            &self.id
        }

        fn workspace_id(&self) -> &str {
            &self.workspace_id
        }
    }

    fn win(id: &str, workspace_id: &str) -> Win {
        Win {
            id: id.into(),
            workspace_id: workspace_id.into(),
        }
    }

    fn three() -> Vec<Win> {
        vec![win("0xa", "1"), win("0xb", "1"), win("0xc", "1")]
    }

    fn hist(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|s| s.to_string()).collect()
    }

    fn ids(out: &[&Win]) -> Vec<String> {
        out.iter().map(|w| w.id.clone()).collect()
    }

    // The compositor lists windows in its own order; the switcher lists the
    // most recently focused first, so one Alt+Tab lands on the window before
    // the current one.
    #[test]
    fn the_most_recently_focused_comes_first() {
        let w = three();
        let out = entries(&w, &hist(&["0xc", "0xa"]), "");
        assert_eq!(ids(&out), ["0xc", "0xa", "0xb"]);
    }

    // A window nothing has focused this session keeps the compositor's own
    // order behind the ones that have, rather than being dropped.
    #[test]
    fn an_unfocused_window_keeps_its_place_at_the_back() {
        let w = three();
        let out = entries(&w, &[], "");
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].id, "0xa");
        assert_eq!(out[2].id, "0xc");
    }

    // A history carrying an id that has since closed names nothing, and the
    // rest of the order survives it.
    #[test]
    fn a_closed_window_in_the_history_is_skipped() {
        let w = three();
        let out = entries(&w, &hist(&["0xdead", "0xb"]), "");
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].id, "0xb");
    }

    // Special workspaces are overlays rather than places, and the quake
    // console lives on one permanently: offering it would offer a window the
    // user never put there.
    #[test]
    fn a_window_on_a_special_workspace_is_not_offered() {
        let w = vec![win("0xa", "1"), win("0xconsole", "-99"), win("0xb", "1")];
        let out = entries(&w, &[], "");
        assert_eq!(ids(&out), ["0xa", "0xb"]);
    }

    // Gala lists the active workspace's windows and no others, which is what
    // stops a quick Alt+Tab committing to a window somewhere else and taking
    // the compositor there.
    #[test]
    fn only_the_workspace_being_looked_at_is_offered() {
        let w = vec![win("0xa", "1"), win("0xelsewhere", "2"), win("0xb", "1")];
        let out = entries(&w, &hist(&["0xelsewhere", "0xb"]), "1");
        assert_eq!(ids(&out), ["0xb", "0xa"]);
    }

    // The history is the session's, not one workspace's, so an id on it that
    // names a window elsewhere names nothing here rather than pulling that
    // window onto the card.
    #[test]
    fn a_history_entry_from_another_workspace_offers_nothing() {
        let w = vec![win("0xa", "1"), win("0xelsewhere", "2")];
        let out = entries(&w, &hist(&["0xelsewhere"]), "1");
        assert_eq!(ids(&out), ["0xa"]);
    }

    // One window on the workspace is still a card: the cursor's single step
    // wraps onto it, so a tap leaves focus put.
    #[test]
    fn one_window_on_the_workspace_is_the_only_entry() {
        let w = vec![win("0xa", "1"), win("0xelsewhere", "2")];
        let out = entries(&w, &[], "1");
        assert_eq!(out.len(), 1);
        assert_eq!(advance(0, out.len() as i64, 1), 0);
    }

    // A workspace whose windows have all gone offers none, which is the cell
    // saying so rather than the rest of the session.
    #[test]
    fn an_empty_workspace_offers_none_of_the_others() {
        let w = vec![win("0xelsewhere", "2"), win("0xalso", "3")];
        assert_eq!(entries(&w, &hist(&["0xelsewhere"]), "1").len(), 0);
    }

    // No workspace named is no filter at all.
    #[test]
    fn an_empty_workspace_id_filters_nothing() {
        let w = vec![win("0xa", "1"), win("0xelsewhere", "2")];
        assert_eq!(entries(&w, &[], "").len(), 2);
    }

    #[test]
    fn the_empty_case_is_an_empty_list() {
        let none: Vec<Win> = Vec::new();
        assert_eq!(entries(&none, &hist(&["0xa"]), "").len(), 0);
    }

    // The cursor wraps both ways, and a list with nothing in it has no cursor
    // to move.
    #[test]
    fn the_cursor_wraps_at_either_end() {
        assert_eq!(advance(0, 3, 1), 1);
        assert_eq!(advance(2, 3, 1), 0);
        assert_eq!(advance(0, 3, -1), 2);
        assert_eq!(advance(1, 3, -1), 0);
        assert_eq!(advance(0, 0, 1), 0);
        assert_eq!(advance(4, 0, -1), 0);
    }

    // A thumbnail keeps its window's aspect at the cell's fixed height, held
    // between a floor and a ceiling so no cell collapses or sprawls.
    #[test]
    fn a_thumbnail_keeps_its_window_aspect() {
        let r = |w, h| Some(Rect::new(0.0, 0.0, w, h));
        assert_eq!(thumb_width(r(1600.0, 900.0), 100.0, 60.0, 300.0), 178.0);
        assert_eq!(thumb_width(r(900.0, 900.0), 100.0, 60.0, 300.0), 100.0);
        assert_eq!(thumb_width(r(300.0, 900.0), 100.0, 60.0, 300.0), 60.0);
        assert_eq!(thumb_width(r(3840.0, 400.0), 100.0, 60.0, 300.0), 300.0);
    }

    // A window whose rect the compositor has not reported reads as 16:9.
    #[test]
    fn a_window_with_no_rect_reads_as_sixteen_by_nine() {
        assert_eq!(thumb_width(None, 90.0, 40.0, 400.0), 160.0);
        assert_eq!(
            thumb_width(Some(Rect::new(0.0, 0.0, 0.0, 0.0)), 90.0, 40.0, 400.0),
            160.0
        );
    }

    #[test]
    fn cells_that_fit_stay_on_one_row() {
        let out = layout(&[100.0, 150.0, 100.0], 0.0, 400.0);
        assert_eq!(out.rows.len(), 1);
        assert_eq!(out.rows[0].count, 3);
        assert_eq!(out.width, 350.0);
    }

    // Eleven equal cells over a row holding seven read as 6 and 5.
    #[test]
    fn a_row_too_long_for_the_output_wraps_balanced() {
        let out = layout(&[100.0; 11], 0.0, 700.0);
        assert_eq!(out.rows.len(), 2);
        assert_eq!(out.rows[0].first, 0);
        assert_eq!(out.rows[0].count, 6);
        assert_eq!(out.rows[1].first, 6);
        assert_eq!(out.rows[1].count, 5);
        assert_eq!(out.width, 600.0);
    }

    // Different widths pack by their sum, and the gap counts between cells.
    #[test]
    fn mixed_widths_wrap_by_their_sum() {
        let out = layout(&[300.0, 300.0, 300.0], 10.0, 620.0);
        assert_eq!(out.rows.len(), 2);
        assert_eq!(out.rows[0].count, 2);
        assert_eq!(out.rows[0].width, 610.0);
        assert_eq!(out.rows[1].count, 1);
        assert_eq!(out.width, 610.0);
    }

    // A cell wider than the output still gets a row, cramped and never empty.
    #[test]
    fn a_cell_wider_than_the_output_still_draws() {
        let out = layout(&[500.0, 100.0], 0.0, 300.0);
        assert_eq!(out.rows.len(), 2);
        assert_eq!(out.rows[0].count, 1);
        assert_eq!(out.width, 500.0);
    }

    #[test]
    fn no_windows_is_no_grid_at_all() {
        assert_eq!(layout(&[], 0.0, 700.0).rows.len(), 0);
        assert_eq!(layout(&[], 0.0, 700.0).width, 0.0);
    }

    // Rows stack at the cell height and each is centred on the widest; the
    // balanced wrap here is 200 over 200 and 100.
    #[test]
    fn cells_sit_in_centred_rows() {
        let grid = layout(&[200.0, 200.0, 100.0], 0.0, 400.0);
        assert_eq!(grid.width, 300.0);
        let out = cells(&grid, 50.0);
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].x, 50.0);
        assert_eq!(out[0].y, 0.0);
        assert_eq!(out[1].x, 0.0);
        assert_eq!(out[1].y, 50.0);
        assert_eq!(out[2].x, 200.0);
        assert_eq!(out[2].width, 100.0);
        assert_eq!(out[2].row, 1);
    }

    #[test]
    fn the_row_holding_an_entry_is_found() {
        let out = layout(&[100.0; 4], 0.0, 200.0);
        assert_eq!(row_of(&out.rows, 0), Some(0));
        assert_eq!(row_of(&out.rows, 1), Some(0));
        assert_eq!(row_of(&out.rows, 2), Some(1));
        assert_eq!(row_of(&out.rows, 3), Some(1));
        assert_eq!(row_of(&out.rows, 4), None);
    }

    // Several windows of one app count off in row order; an app with one
    // window, and a window nothing could name, carry no count at all.
    #[test]
    fn windows_of_one_app_count_off_in_row_order() {
        let marks = ordinals(&[
            "entry:foot",
            "entry:mpv",
            "entry:foot",
            "",
            "",
            "entry:foot",
        ]);
        assert_eq!(marks.len(), 6);
        assert_eq!((marks[0].n, marks[0].of), (1, 3));
        assert_eq!(marks[2].n, 2);
        assert_eq!(marks[5].n, 3);
        assert_eq!(marks[1].of, 1);
        assert_eq!(marks[3].of, 1);
        assert_eq!(marks[4].of, 1);
        assert_eq!(ordinals(&[]).len(), 0);
    }
}
