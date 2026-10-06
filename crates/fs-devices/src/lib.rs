//! Pure logic behind the device panels: earbuds, iPhone, Bluetooth, LocalSend,
//! Wi-Fi and Tailscale. Plain data in, plain data out, no IO.
//!
//! Ported from `shell/{Earbuds,Iphone,Bluetooth,Localsend,Network,Tailscale}`.

pub mod bluetooth;
pub mod earbuds;
pub mod iphone;
pub mod localsend;
pub mod network;
pub mod tailscale;
