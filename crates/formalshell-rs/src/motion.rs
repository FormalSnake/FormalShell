//! The two clock families as `Anim` runs them (tokens.js `MOTION_BASE`,
//! `MOTION_CURVES`), a `Behavior`'s retarget, and the velocity deform
//! (Components/Deform.qml) with its spring.

use std::time::{Duration, Instant};

/// One cubic bezier through (0,0) and (1,1), Qt's `BezierSpline` with a
/// single segment: the two control points.
#[derive(Clone, Copy, Debug)]
pub struct Curve(pub [f64; 4]);

pub const SPATIAL_FAST: Curve = Curve([0.42, 1.67, 0.21, 0.9]);
pub const SPATIAL: Curve = Curve([0.38, 1.21, 0.22, 1.0]);

pub const SPATIAL_FAST_MS: f64 = 350.0;
pub const SPATIAL_MS: f64 = 500.0;
pub const PULSE_MS: f64 = 900.0;

/// metamorphosis's `emerge`: `{ duration: "spatial", curve: "spatial" }`.
pub const EMERGE: (f64, Curve) = (SPATIAL_MS, SPATIAL);

impl Curve {
    /// y at a given x. x(t) is monotonic for control x in [0, 1], so a
    /// bisection lands t to f64 precision.
    pub fn ease(&self, x: f64) -> f64 {
        if x <= 0.0 {
            return 0.0;
        }
        if x >= 1.0 {
            return 1.0;
        }
        let [x1, y1, x2, y2] = self.0;
        let bez = |a: f64, b: f64, t: f64| {
            let u = 1.0 - t;
            3.0 * u * u * t * a + 3.0 * u * t * t * b + t * t * t
        };
        let (mut lo, mut hi) = (0.0, 1.0);
        for _ in 0..60 {
            let mid = (lo + hi) / 2.0;
            if bez(x1, x2, mid) < x { lo = mid } else { hi = mid }
        }
        bez(y1, y2, (lo + hi) / 2.0)
    }
}

/// A number under `Behavior on x { Anim {} }`: a new target starts a fresh
/// animation from wherever the value is, on the full duration.
pub struct Animated {
    target: f64,
    from: f64,
    start: Instant,
    duration: Duration,
    curve: Curve,
}

impl Animated {
    pub fn new(value: f64, curve: Curve) -> Self {
        Self { target: value, from: value, start: Instant::now(), duration: Duration::ZERO, curve }
    }

    pub fn value(&self, now: Instant) -> f64 {
        if self.duration.is_zero() {
            return self.target;
        }
        let x = now.saturating_duration_since(self.start).as_secs_f64() / self.duration.as_secs_f64();
        self.from + (self.target - self.from) * self.curve.ease(x)
    }

    pub fn running(&self, now: Instant) -> bool {
        !self.duration.is_zero() && now < self.start + self.duration
    }

    pub fn set(&mut self, now: Instant, target: f64, duration_ms: f64) {
        if target == self.target {
            return;
        }
        self.from = self.value(now);
        self.target = target;
        self.start = now;
        self.duration = Duration::from_secs_f64(duration_ms.max(0.0) / 1000.0);
    }

    /// The `Behavior` disabled: the value lands at once.
    pub fn jump(&mut self, target: f64) {
        self.target = target;
        self.from = target;
        self.duration = Duration::ZERO;
    }
}

/// tokens.js `DEFORM`.
const MAX_STRETCH: f64 = 0.35;
const DEAD_BAND: f64 = 5.0;
const STIFFNESS: f64 = 200.0;
const DAMPING: f64 = 16.0;
const EPSILON: f64 = 0.002;

/// Deform.qml for a top-edge drawer: the symmetric 2x2 the three springs
/// carry, sampled off the frame's live position and height.
pub struct Deform {
    pub m00: f64,
    pub m01: f64,
    pub m11: f64,
    v00: f64,
    v01: f64,
    v11: f64,
    pub at_rest: bool,
    sampled: Option<(f64, f64, f64)>,
}

impl Deform {
    pub fn new() -> Self {
        Self { m00: 1.0, m01: 0.0, m11: 1.0, v00: 0.0, v01: 0.0, v11: 0.0, at_rest: true, sampled: None }
    }

    /// The frame loop stopped: the next step has nothing to subtract.
    pub fn unsample(&mut self) {
        self.sampled = None;
    }

    /// One frame: `x`, `y` the frame's scene position, `h` its height.
    pub fn step(&mut self, dt: f64, x: f64, y: f64, h: f64, amount: f64) {
        let Some((px, py, ph)) = self.sampled.filter(|_| (0.001..=0.1).contains(&dt)) else {
            self.sampled = Some((x, y, h));
            self.settle(0.0);
            return;
        };
        let vx = (x - px) / dt;
        let vy = (y - py) / dt + (h - ph) / dt;
        self.sampled = Some((x, y, h));

        let speed = (vx * vx + vy * vy).sqrt();
        if self.at_rest && speed < DEAD_BAND {
            return;
        }
        self.at_rest = false;

        let (mut t00, mut t01, mut t11) = (1.0, 0.0, 1.0);
        if speed > DEAD_BAND {
            let stretch = 1.0 + (speed * amount / 10000.0).min(MAX_STRETCH);
            let compress = 1.0 / stretch;
            let (cos, sin) = (vx / speed, vy / speed);
            t00 = stretch * cos * cos + compress * sin * sin;
            t01 = (stretch - compress) * cos * sin;
            t11 = stretch * sin * sin + compress * cos * cos;
        }

        // Damping integrated implicitly, as Deform.qml does: an explicit
        // term flips sign once DAMPING * dt passes 1.
        let inv = 1.0 / (1.0 + DAMPING * dt);
        self.v00 = (self.v00 - STIFFNESS * (self.m00 - t00) * dt) * inv;
        self.v01 = (self.v01 - STIFFNESS * (self.m01 - t01) * dt) * inv;
        self.v11 = (self.v11 - STIFFNESS * (self.m11 - t11) * dt) * inv;
        self.m00 += self.v00 * dt;
        self.m01 += self.v01 * dt;
        self.m11 += self.v11 * dt;
        self.settle(speed);
    }

    fn settle(&mut self, speed: f64) {
        if self.at_rest {
            return;
        }
        let e = EPSILON;
        let settled = (self.m00 - 1.0).abs() < e
            && self.m01.abs() < e
            && (self.m11 - 1.0).abs() < e
            && self.v00.abs() < e
            && self.v01.abs() < e
            && self.v11.abs() < e
            && speed < DEAD_BAND;
        if settled {
            *self = Self { sampled: self.sampled, ..Self::new() };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spatial_overshoots_and_lands() {
        let peak = (1..100).map(|i| SPATIAL.ease(i as f64 / 100.0)).fold(0.0, f64::max);
        assert!(peak > 1.0 && peak < 1.1, "{peak}");
        assert_eq!(SPATIAL.ease(1.0), 1.0);
        assert_eq!(SPATIAL.ease(0.0), 0.0);
    }
}
