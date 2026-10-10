//! A scroll area under the pointer: what one axis event asks of it, and the
//! touchpad's rubber band past either end.

use std::time::Instant;

use smithay_client_toolkit::reexports::client::protocol::wl_pointer::AxisSource;
use smithay_client_toolkit::seat::pointer::AxisScroll;

use crate::motion::{Animated, Kind};

/// Content pixels a touchpad's pixel of travel moves. A wheel's notches
/// keep their own step.
pub const FINGER_GAIN: f64 = 1.12;

/// UIKit's rubber band constant: the share of the pull the content follows
/// at the very start of a stretch.
const PULL: f64 = 0.55;

/// The stretch's asymptote, a share of the viewport capped in pixels: it
/// can never get past this however far the fingers travel.
const REACH: f64 = 0.1;
const REACH_MAX: f64 = 40.0;

/// What one axis frame asks of a scroll area.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Travel {
    /// Wheel notches: value120 over 120, an older seat's discrete steps,
    /// or a sourceless smooth value at 15 a notch.
    Notches(f64),
    /// Content pixels off a touchpad. `finger` is the one source that
    /// promises an axis_stop on lift, so the only one that may stretch.
    Pixels { px: f64, finger: bool },
    /// The fingers left the pad.
    Lift,
    None,
}

/// A wheel carries a continuous value too, so only one of them is ever read.
pub fn travel(axis: &AxisScroll, source: Option<AxisSource>) -> Travel {
    let finger = source == Some(AxisSource::Finger);
    if axis.value120 != 0 {
        Travel::Notches(f64::from(axis.value120) / 120.0)
    } else if axis.discrete != 0 {
        Travel::Notches(f64::from(axis.discrete))
    } else if axis.absolute != 0.0 && (finger || source == Some(AxisSource::Continuous)) {
        Travel::Pixels { px: axis.absolute * FINGER_GAIN, finger }
    } else if axis.absolute != 0.0 {
        Travel::Notches(axis.absolute / 15.0)
    } else if axis.stop && finger {
        Travel::Lift
    } else {
        Travel::None
    }
}

fn reach(view: f64) -> f64 {
    (view * REACH).clamp(1.0, REACH_MAX)
}

/// `(1 - 1/(x*c/d + 1)) * d`: the drawn stretch for `pull` px of finger
/// travel past an end, each pixel giving less than the one before.
pub fn rubber(pull: f64, view: f64) -> f64 {
    let d = reach(view);
    pull.signum() * (1.0 - 1.0 / (pull.abs() * PULL / d + 1.0)) * d
}

fn unrubber(stretch: f64, view: f64) -> f64 {
    let d = reach(view);
    let s = stretch.abs().min(d * 0.999);
    stretch.signum() * (d / PULL) * (1.0 / (1.0 - s / d) - 1.0)
}

/// The stretch a touchpad pulls past either end of a scroll area while the
/// fingers are down, springing back on the spatial clock once they lift.
/// The offset itself never leaves `0..=max`: the stretch is drawn on top.
pub struct Stretch {
    /// The fingers' travel past the end, negative past the top.
    pull: f64,
    view: f64,
    shown: Animated,
}

impl Stretch {
    pub fn new() -> Self {
        Self { pull: 0.0, view: 0.0, shown: Animated::new(0.0, Kind::SpatialFast.curve()) }
    }

    /// `offset` moved by `px` of finger travel. Whatever lands past an end
    /// pulls the stretch, and travel back toward the content unwinds the
    /// pull before it moves the offset. Returns the new offset.
    pub fn drag(&mut self, now: Instant, offset: f64, max: f64, px: f64, view: f64) -> f64 {
        self.view = view;
        // Fingers back on the pad mid spring take it from where it is.
        if self.pull == 0.0 {
            let shown = self.shown.value(now);
            if shown != 0.0 {
                self.pull = unrubber(shown, view);
            }
        }
        let mut px = px;
        if self.pull != 0.0 && px.signum() != self.pull.signum() {
            let left = self.pull + px;
            if left.signum() == self.pull.signum() && left != 0.0 {
                self.pull = left;
                self.shown.jump(rubber(self.pull, view));
                return offset;
            }
            self.pull = 0.0;
            px = left;
        }
        let next = offset + px;
        let (offset, over) = if max <= 0.0 {
            (0.0, 0.0)
        } else if next > max {
            (max, next - max)
        } else if next < 0.0 {
            (0.0, next)
        } else {
            (next, 0.0)
        };
        self.pull += over;
        self.shown.jump(rubber(self.pull, view));
        offset
    }

    /// The fingers lifted: back to the end on `spatialFast`.
    pub fn release(&mut self, now: Instant, ms: f64) {
        self.pull = 0.0;
        if self.shown.target() != 0.0 {
            self.shown.set_on(now, 0.0, ms, Kind::SpatialFast.curve());
        }
    }

    /// A wheel, a key or a new view takes over: no stretch at all.
    pub fn settle(&mut self) {
        self.pull = 0.0;
        self.shown.jump(0.0);
    }

    pub fn value(&self, now: Instant) -> f64 {
        self.shown.value(now)
    }

    pub fn running(&self, now: Instant) -> bool {
        self.shown.running(now)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_stretch_resists_harder_the_further_it_goes_and_never_reaches_its_cap() {
        let view = 600.0;
        let (a, b, c) = (rubber(40.0, view), rubber(80.0, view), rubber(10_000.0, view));
        assert!(a > 0.0 && b > a && c > b);
        assert!(b - a < a, "the second 40px gave {} against the first's {a}", b - a);
        assert!(c < REACH_MAX);
        assert!(rubber(-40.0, view) == -a);
        assert!((unrubber(a, view) - 40.0).abs() < 1e-6);
    }

    #[test]
    fn travel_inside_the_area_moves_the_offset_and_past_it_only_stretches() {
        let now = Instant::now();
        let mut s = Stretch::new();
        assert_eq!(s.drag(now, 100.0, 200.0, 50.0, 400.0), 150.0);
        assert_eq!(s.value(now), 0.0);
        // The end is reached at once, the rest pulls.
        assert_eq!(s.drag(now, 150.0, 200.0, 80.0, 400.0), 200.0);
        let pulled = s.value(now);
        assert!(pulled > 0.0 && pulled < 30.0, "{pulled}");
        // Back toward the content unwinds the pull before the offset moves.
        assert_eq!(s.drag(now, 200.0, 200.0, -10.0, 400.0), 200.0);
        assert!(s.value(now) < pulled && s.value(now) > 0.0);
        assert_eq!(s.drag(now, 200.0, 200.0, -40.0, 400.0), 180.0);
        assert_eq!(s.value(now), 0.0);
        // Past the top too.
        assert_eq!(s.drag(now, 180.0, 200.0, -400.0, 400.0), 0.0);
        assert!(s.value(now) < 0.0);
    }

    #[test]
    fn a_lift_springs_back_onto_the_end() {
        let now = Instant::now();
        let mut s = Stretch::new();
        s.drag(now, 200.0, 200.0, 120.0, 400.0);
        s.release(now, 350.0);
        assert!(s.running(now));
        let later = now + std::time::Duration::from_millis(351);
        assert!(!s.running(later));
        assert_eq!(s.value(later), 0.0);
    }

    #[test]
    fn an_area_with_nothing_to_scroll_does_not_stretch() {
        let now = Instant::now();
        let mut s = Stretch::new();
        assert_eq!(s.drag(now, 0.0, 0.0, 120.0, 400.0), 0.0);
        assert_eq!(s.value(now), 0.0);
    }

    #[test]
    fn a_wheel_never_reads_as_a_finger() {
        let axis = |absolute: f64, value120: i32, stop: bool| AxisScroll { absolute, discrete: 0, value120, relative_direction: None, stop };
        assert_eq!(travel(&axis(15.0, 120, false), Some(AxisSource::Wheel)), Travel::Notches(1.0));
        assert_eq!(travel(&axis(15.0, 0, false), None), Travel::Notches(1.0));
        assert_eq!(travel(&axis(10.0, 0, false), Some(AxisSource::Finger)), Travel::Pixels { px: 10.0 * FINGER_GAIN, finger: true });
        assert_eq!(travel(&axis(0.0, 0, true), Some(AxisSource::Finger)), Travel::Lift);
        assert_eq!(travel(&axis(0.0, 0, true), Some(AxisSource::Wheel)), Travel::None);
    }
}
