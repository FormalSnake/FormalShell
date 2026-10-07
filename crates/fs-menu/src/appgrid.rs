//! The launcher's app grid: how many cells fit across the card, and which
//! rows the grid owns. Where an arrow press lands is `nav`'s.

use crate::node::{Kind, Node};

/// How many cells fit across `width` at `min_cell`, at least one: a card
/// narrower than a single cell still draws a column rather than none. The
/// grid divides `width` by this, so every gutter comes out equal.
pub fn columns_for(width: f64, min_cell: f64) -> usize {
    if !(width > 0.0) || !(min_cell > 0.0) {
        return 1;
    }
    ((width / min_cell).floor() as usize).max(1)
}

/// `partition`'s result: app rows first, then the rest; `app_count` is the
/// index of the first row under the grid.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Partition {
    pub rows: Vec<Node>,
    pub app_count: usize,
}

/// App rows first, everything else after, each block in the order the
/// ranking gave it. A stable partition, not a sort: nothing is scored again,
/// so every cursor index stays an index into one list.
pub fn partition(rows: Vec<Node>) -> Partition {
    let (mut apps, rest): (Vec<Node>, Vec<Node>) = rows.into_iter().partition(|r| r.kind == Kind::App);
    let app_count = apps.len();
    apps.extend(rest);
    Partition { rows: apps, app_count }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, kind: Kind) -> Node {
        Node::new(id, id, kind)
    }

    #[test]
    fn columns() {
        assert_eq!(columns_for(560.0, 96.0), 5);
        assert_eq!(columns_for(50.0, 96.0), 1);
        assert_eq!(columns_for(0.0, 96.0), 1);
        assert_eq!(columns_for(500.0, 0.0), 1);
        assert_eq!(columns_for(f64::NAN, 10.0), 1);
    }

    #[test]
    fn apps_lead_in_ranked_order() {
        let p = partition(vec![
            row("a", Kind::Action),
            row("x", Kind::App),
            row("b", Kind::Submenu),
            row("y", Kind::App),
        ]);
        let ids: Vec<&str> = p.rows.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, ["x", "y", "a", "b"]);
        assert_eq!(p.app_count, 2);
        assert_eq!(partition(vec![row("a", Kind::Action)]).app_count, 0);
        assert_eq!(partition(Vec::new()), Partition::default());
    }
}
