//! A builtin whose service is not wired yet: it takes no room and shows
//! nothing until its own module replaces this one.

use crate::store::Topic;
use crate::surfaces::bar::cell::{Cell, Env, Look, View};

pub struct Absent;

impl Cell for Absent {
    fn reads(&self) -> &'static [Topic] {
        &[]
    }

    fn read(&mut self, _: &Env) -> bool {
        false
    }

    fn view(&self, _: &Look) -> View {
        View::hidden()
    }
}
