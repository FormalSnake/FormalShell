use zbus::proxy;
use zbus::zvariant::ObjectPath;

pub(crate) const OBJECT_PATH: &str = "/org/mpris/MediaPlayer2";
pub(crate) const ROOT_IFACE: &str = "org.mpris.MediaPlayer2";
pub(crate) const PLAYER_IFACE: &str = "org.mpris.MediaPlayer2.Player";

#[proxy(
    interface = "org.mpris.MediaPlayer2",
    default_path = "/org/mpris/MediaPlayer2",
    gen_blocking = false
)]
pub(crate) trait Root {
    fn raise(&self) -> zbus::Result<()>;
}

#[proxy(
    interface = "org.mpris.MediaPlayer2.Player",
    default_path = "/org/mpris/MediaPlayer2",
    gen_blocking = false
)]
pub(crate) trait Player {
    fn next(&self) -> zbus::Result<()>;
    fn previous(&self) -> zbus::Result<()>;
    fn pause(&self) -> zbus::Result<()>;
    fn play_pause(&self) -> zbus::Result<()>;
    fn stop(&self) -> zbus::Result<()>;
    fn play(&self) -> zbus::Result<()>;
    fn seek(&self, offset: i64) -> zbus::Result<()>;
    fn set_position(&self, track_id: &ObjectPath<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(signal)]
    fn seeked(&self, position: i64) -> zbus::Result<()>;
}
