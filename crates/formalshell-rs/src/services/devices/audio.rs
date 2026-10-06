//! AudioService.qml over fs-audio's PipeWire thread: the default sink's
//! volume and mute, and whether a default source exists and is muted. The
//! graph lives on the service thread; writes go back as commands.

use std::cell::RefCell;

use fs_audio::{Command, Graph};

use crate::runtime::Ctx;
use crate::store;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Audio {
    /// None while there is no default sink with an audio interface.
    pub volume: Option<f64>,
    pub muted: bool,
    /// A default source with an audio interface exists.
    pub source: bool,
    pub source_muted: bool,
}

struct Client {
    handle: fs_audio::Audio,
    graph: Graph,
}

thread_local! {
    static CLIENT: RefCell<Option<Client>> = const { RefCell::new(None) };
}

fn snapshot(graph: &Graph) -> Audio {
    let sink = graph.default_sink().and_then(|n| n.audio.as_ref());
    let source = graph.default_source().and_then(|n| n.audio.as_ref());
    Audio {
        volume: sink.map(|a| a.volume() as f64),
        muted: sink.is_some_and(|a| a.muted),
        source: source.is_some(),
        source_muted: source.is_some_and(|a| a.muted),
    }
}

fn publish(ctx: &Ctx, audio: Audio) {
    ctx.publish(store::Diff::Devices(super::Diff::Audio(audio)));
}

pub async fn run(ctx: Ctx) {
    let (handle, events) = match fs_audio::spawn() {
        Ok(v) => v,
        Err(err) => {
            eprintln!("audio: {err}");
            return publish(&ctx, Audio::default());
        }
    };
    CLIENT.with_borrow_mut(|c| *c = Some(Client { handle, graph: Graph::default() }));
    while let Ok(event) = events.recv().await {
        let audio = CLIENT.with_borrow_mut(|c| {
            let c = c.as_mut()?;
            c.graph.apply(event);
            // One publish per burst: the initial sync is hundreds of events.
            while let Ok(more) = events.try_recv() {
                c.graph.apply(more);
            }
            Some(snapshot(&c.graph))
        });
        if let Some(audio) = audio {
            publish(&ctx, audio);
        }
    }
}

fn with_node(source: bool, f: impl FnOnce(&fs_audio::Audio, u32, &fs_audio::AudioState)) {
    CLIENT.with_borrow(|c| {
        let Some(c) = c else { return };
        let node = if source { c.graph.default_source() } else { c.graph.default_sink() };
        if let Some((id, audio)) = node.and_then(|n| Some((n.id, n.audio.as_ref()?))) {
            f(&c.handle, id, audio);
        }
    });
}

pub fn set_volume(_: &Ctx, volume: f64) {
    with_node(false, |h, node, _| h.send(Command::SetVolume { node, volume: volume.clamp(0.0, 1.0) as f32 }));
}

pub fn toggle_mute(_: &Ctx) {
    with_node(false, |h, node, a| h.send(Command::SetMuted { node, muted: !a.muted }));
}

pub fn toggle_source_mute(_: &Ctx) {
    with_node(true, |h, node, a| h.send(Command::SetMuted { node, muted: !a.muted }));
}
