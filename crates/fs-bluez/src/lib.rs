//! BlueZ client for the shell: adapters, devices, discovery, pairing and an
//! optional pairing agent, over zbus on a caller-owned connection.

pub mod agent;
mod client;
mod proxies;
pub mod state;

pub use client::{Bluez, Error, Monitor, Result, SMOKE_ENV};
