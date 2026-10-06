//! Pure logic behind the notification, reminder, calendar, weather,
//! location, herdr, usage and flake-update surfaces: plain data in, plain
//! data out, no IO.
//!
//! Months handed to and returned from this crate are 1-based (chrono's
//! convention), unlike the 0-based months of the QML-era JS.

pub mod calendar;
pub mod clock;
pub mod herdr;
mod js;
pub mod location;
pub mod notifications;
pub mod reminders;
pub mod system_update;
pub mod usage;
pub mod weather;
