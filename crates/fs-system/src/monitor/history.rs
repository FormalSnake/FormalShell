//! Rolling samples behind the monitor's sparklines. A sample that could not
//! be taken (the first tick of a delta, a card with no counter) is left out
//! rather than stored as a zero, so a line only ever draws measured points.

/// Two minutes at the default 2s poll.
pub const CAPACITY: usize = 60;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

pub fn push(series: &[f64], value: Option<f64>, capacity: Option<usize>) -> Vec<f64> {
    let mut out = series.to_vec();
    let Some(value) = value.filter(|v| v.is_finite()) else {
        return out;
    };
    out.push(value);
    let cap = capacity.filter(|c| *c > 0).unwrap_or(CAPACITY);
    if out.len() > cap {
        out.drain(..out.len() - cap);
    }
    out
}

/// The scale a byte-rate series is drawn against: its own peak, but never
/// below `floor`, so an idle link's noise does not fill the box.
pub fn ceiling(series: &[f64], floor: f64) -> f64 {
    series.iter().fold(floor, |top, v| if *v > top { *v } else { top })
}

/// Polyline points for a series in a width x height box, y up from the
/// bottom. A series shorter than `capacity` is spread across the whole box
/// rather than crowded against the right edge; once the series is full the
/// newest sample sits on the right edge and the rest step left.
pub fn points(series: &[f64], width: f64, height: f64, top: f64, capacity: Option<usize>) -> Vec<Point> {
    let cap = capacity.filter(|c| *c > 0).unwrap_or(CAPACITY);
    if top.is_nan() || top <= 0.0 || cap < 2 {
        return Vec::new();
    }
    let slots = series.len().min(cap);
    series
        .iter()
        .enumerate()
        .map(|(i, v)| {
            let fraction = (v / top).clamp(0.0, 1.0);
            let x = if slots > 1 { i as f64 / (slots - 1) as f64 * width } else { width };
            Point { x, y: height - fraction * height }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn push_skips_unmeasured_samples() {
        assert_eq!(push(&[], None, None), Vec::<f64>::new());
        assert_eq!(push(&[0.1], Some(f64::NAN), None), vec![0.1]);
        assert_eq!(push(&[0.1], Some(0.2), None), vec![0.1, 0.2]);
    }

    #[test]
    fn push_keeps_the_newest_capacity_samples() {
        let mut s = Vec::new();
        for i in 0..5 {
            s = push(&s, Some(i as f64), Some(3));
        }
        assert_eq!(s, vec![2.0, 3.0, 4.0]);
    }

    #[test]
    fn push_does_not_mutate_its_input() {
        let before = vec![0.1];
        let _ = push(&before, Some(0.2), None);
        assert_eq!(before, vec![0.1]);
    }

    #[test]
    fn ceiling_has_a_floor() {
        assert_eq!(ceiling(&[], 1024.0), 1024.0);
        assert_eq!(ceiling(&[10.0, 20.0], 1024.0), 1024.0);
        assert_eq!(ceiling(&[10.0, 5000.0], 1024.0), 5000.0);
    }

    #[test]
    fn points_spread_across_the_box_until_the_series_is_full() {
        let pts = points(&[0.5], 100.0, 20.0, 1.0, Some(11));
        assert_eq!(pts.len(), 1);
        assert_eq!(pts[0].x, 100.0);
        assert_eq!(pts[0].y, 10.0);
        let pts = points(&[0.0, 1.0], 100.0, 20.0, 1.0, Some(11));
        assert_eq!((pts[0].x, pts[0].y), (0.0, 20.0));
        assert_eq!((pts[1].x, pts[1].y), (100.0, 0.0));
        let pts = points(&[0.0, 0.5, 1.0], 100.0, 20.0, 1.0, Some(11));
        assert_eq!(pts[1].x, 50.0);
    }

    #[test]
    fn points_clamp_to_the_box_and_refuse_a_zero_scale() {
        assert_eq!(points(&[2.0], 100.0, 20.0, 1.0, Some(11))[0].y, 0.0);
        assert!(points(&[1.0], 100.0, 20.0, 0.0, Some(11)).is_empty());
    }
}
