use futures_lite::{Stream, StreamExt, stream};
use zbus::message::Type;
use zbus::zvariant::OwnedValue;
use zbus::{Connection, MatchRule, MessageStream, proxy};

use crate::device::get;

const SERVICE: &str = "org.freedesktop.UPower.PowerProfiles";

#[proxy(
    interface = "org.freedesktop.UPower.PowerProfiles",
    default_service = "org.freedesktop.UPower.PowerProfiles",
    default_path = "/org/freedesktop/UPower/PowerProfiles",
    gen_blocking = false
)]
trait Daemon {
    #[zbus(property)]
    fn active_profile(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn set_active_profile(&self, profile: &str) -> zbus::Result<()>;
    #[zbus(property)]
    fn profiles(&self) -> zbus::Result<Vec<std::collections::HashMap<String, OwnedValue>>>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Profile {
    PowerSaver,
    Balanced,
    Performance,
}

impl Profile {
    pub fn from_wire(wire: &str) -> Option<Self> {
        match wire {
            "power-saver" => Some(Self::PowerSaver),
            "balanced" => Some(Self::Balanced),
            "performance" => Some(Self::Performance),
            _ => None,
        }
    }

    pub fn to_wire(self) -> &'static str {
        match self {
            Self::PowerSaver => "power-saver",
            Self::Balanced => "balanced",
            Self::Performance => "performance",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProfilesState {
    pub active: Profile,
    /// In the order the daemon lists them. `Performance` is absent on
    /// hardware that does not offer it.
    pub available: Vec<Profile>,
}

impl ProfilesState {
    pub fn has_performance(&self) -> bool {
        self.available.contains(&Profile::Performance)
    }
}

#[derive(Clone)]
pub struct PowerProfiles {
    conn: Connection,
    daemon: DaemonProxy<'static>,
}

impl PowerProfiles {
    /// Bus-activates power-profiles-daemon when it is not running yet.
    pub async fn connect(conn: &Connection) -> zbus::Result<Self> {
        Ok(Self {
            conn: conn.clone(),
            daemon: DaemonProxy::new(conn).await?,
        })
    }

    pub async fn state(&self) -> zbus::Result<ProfilesState> {
        read_state(&self.daemon).await
    }

    /// Refuses `Performance` locally when the daemon does not list it, instead
    /// of surfacing the bus error.
    pub async fn set_active(&self, profile: Profile) -> zbus::Result<()> {
        if profile == Profile::Performance && !self.state().await?.has_performance() {
            return Err(zbus::Error::Failure(
                "the daemon does not offer the performance profile".into(),
            ));
        }
        self.daemon.set_active_profile(profile.to_wire()).await
    }

    /// The current state, then the new one after every change of
    /// `ActiveProfile` or `Profiles`. The match rule is installed before the
    /// first read, so no change slips between the two.
    pub async fn changes(&self) -> zbus::Result<impl Stream<Item = ProfilesState> + use<>> {
        let rule = MatchRule::builder()
            .msg_type(Type::Signal)
            .sender(SERVICE)?
            .interface("org.freedesktop.DBus.Properties")?
            .member("PropertiesChanged")?
            .build();
        let messages = MessageStream::for_match_rule(rule, &self.conn, None).await?;
        let first = read_state(&self.daemon).await?;
        let state = (self.daemon.clone(), messages, first.clone());
        let later = stream::unfold(state, |(daemon, mut messages, mut last)| async move {
            loop {
                messages.next().await?.ok()?;
                let Ok(now) = read_state(&daemon).await else {
                    continue;
                };
                if now != last {
                    last = now.clone();
                    return Some((now, (daemon, messages, last)));
                }
            }
        });
        Ok(stream::once(first).chain(later))
    }
}

async fn read_state(daemon: &DaemonProxy<'_>) -> zbus::Result<ProfilesState> {
    let active = daemon.active_profile().await?;
    let active = Profile::from_wire(&active)
        .ok_or_else(|| zbus::Error::Failure(format!("unknown power profile {active:?}")))?;
    let available = daemon
        .profiles()
        .await?
        .iter()
        .filter_map(|entry| get::<String>(entry, "Profile"))
        .filter_map(|name| Profile::from_wire(&name))
        .collect();
    Ok(ProfilesState { active, available })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_names_round_trip() {
        for p in [Profile::PowerSaver, Profile::Balanced, Profile::Performance] {
            assert_eq!(Profile::from_wire(p.to_wire()), Some(p));
        }
        assert_eq!(Profile::from_wire("turbo"), None);
    }

    #[test]
    fn performance_is_only_there_when_listed() {
        let s = ProfilesState {
            active: Profile::Balanced,
            available: vec![Profile::PowerSaver, Profile::Balanced],
        };
        assert!(!s.has_performance());
    }
}
