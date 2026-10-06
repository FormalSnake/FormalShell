//! MPRIS players on the session bus (fs-mpris), as far as the bar reads
//! them: who is playing what. The radio, AirPlay and iPhone sources and the
//! controls join here with the media panel.

use std::time::Instant;

use fs_mpris::{Mpris, PlayerState};
use serde_json::{Value, json};

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Player {
    pub id: String,
    pub identity: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub art_url: String,
    pub playing: bool,
    /// Seconds, as Quickshell reports them.
    pub position: f64,
    pub length: f64,
    pub can_seek: bool,
    pub can_raise: bool,
    pub shuffle: Option<bool>,
    pub loop_status: Option<&'static str>,
    pub volume: Option<f64>,
}

impl Player {
    fn from(state: &PlayerState, now: Instant) -> Self {
        Self {
            id: state.bus_name.clone(),
            identity: state.identity.clone(),
            title: state.metadata.title.clone(),
            artist: state.metadata.artist(),
            album: state.metadata.album.clone(),
            art_url: state.metadata.art_url.clone(),
            playing: state.is_playing(),
            position: state.position(now).as_secs_f64(),
            length: state.length(now).as_secs_f64(),
            can_seek: state.can_seek_now(),
            can_raise: state.can_raise,
            shuffle: state.shuffle,
            loop_status: state.loop_status.map(|l| l.as_str()),
            volume: state.volume,
        }
    }
}

#[derive(Default)]
pub struct State {
    pub players: Vec<Player>,
    /// MediaModel.pickPlayerId with no selection: the first playing, else
    /// the first.
    pub active: Option<Player>,
}

pub struct Diff(pub Vec<Player>, pub Option<Player>);

impl State {
    pub fn apply(&mut self, Diff(players, active): Diff) -> bool {
        if self.players == players && self.active == active {
            return false;
        }
        self.players = players;
        self.active = active;
        true
    }

    /// The title the bar shows: the track, or the player's own name.
    pub fn title(&self) -> Option<String> {
        let p = self.active.as_ref()?;
        Some(if p.title.is_empty() { p.identity.clone() } else { p.title.clone() })
    }

    /// MediaIpc.qml's `status`, for an MPRIS source.
    pub fn status(&self) -> Value {
        let p = self.active.clone().unwrap_or_default();
        let available = self.active.is_some();
        json!({
            "available": available,
            "id": p.id,
            "kind": if available { "mpris" } else { "" },
            "selectedId": "",
            "output": "",
            "canRoute": false,
            "playerCount": self.players.len(),
            "identity": p.identity,
            "title": p.title,
            "artist": p.artist,
            "album": p.album,
            "artUrl": p.art_url,
            "isPlaying": p.playing,
            "position": p.position,
            "length": p.length,
            "canSeek": p.can_seek,
            "canRaise": p.can_raise,
            "shuffleSupported": p.shuffle.is_some(),
            "shuffle": p.shuffle.unwrap_or(false),
            "loopSupported": p.loop_status.is_some(),
            "loop": p.loop_status.unwrap_or("None"),
            "volumeSupported": p.volume.is_some(),
            "volume": p.volume.unwrap_or(0.0),
        })
    }
}

fn publish(ctx: &Ctx, mpris: &Mpris) {
    let now = Instant::now();
    let players: Vec<Player> = mpris.players().map(|p| Player::from(p, now)).collect();
    let active = mpris.active(None).map(|p| Player::from(p, now));
    ctx.publish(store::Diff::Media(Diff(players, active)));
}

pub async fn run(ctx: Ctx) {
    let conn = match zbus::Connection::session().await {
        Ok(conn) => conn,
        Err(err) => return eprintln!("media: no session bus: {err}"),
    };
    let mut mpris = match Mpris::connect(&conn).await {
        Ok(mpris) => mpris,
        Err(err) => return eprintln!("media: {err}"),
    };
    publish(&ctx, &mpris);
    while mpris.next().await.is_some() {
        publish(&ctx, &mpris);
    }
}
