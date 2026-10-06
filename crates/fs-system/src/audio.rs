//! Model groundwork for the audio panel's mixer: stream filtering, the label
//! fallback chain, and the two volume clamps (device vs per-app overdrive).

use icu_collator::Collator;
use icu_collator::options::CollatorOptions;
use std::collections::HashMap;

/// The pre-bind-safe fields of a PipeWire node.
#[derive(Debug, Clone, Default)]
pub struct PwNode {
    pub name: String,
    pub description: String,
    pub is_stream: bool,
    pub is_sink: bool,
    pub node_type: String,
    /// The node has an audio interface (`audio` is non-null).
    pub has_audio: bool,
}

/// Ported from omarchy's audio Model.js (MIT, Copyright (c) David Heinemeier
/// Hansson): identifies true playback streams using only pre-bind-safe fields
/// (is_stream, is_sink, type). A node's property bag is invalid until the node
/// is bound, and reading it while streams churn (a capture app starting, say)
/// destabilized quickshell's Pipewire service in omarchy's own history, so
/// this never touches properties.
pub fn is_playback_stream(node: Option<&PwNode>) -> bool {
    let Some(node) = node.filter(|n| n.is_stream) else {
        return false;
    };
    node.is_sink
        || node.node_type.contains("Stream/Output/Audio")
        || node.node_type.contains("AudioOutStream")
        || node.node_type.contains("Output")
}

/// application.name -> node.description -> media.name -> node.name, the same
/// order omarchy's rawStreamLabel reads. `props` must only be passed once the
/// caller has confirmed the node is ready (properties is invalid pre-bind);
/// this function itself takes the already-read values so it stays free of that
/// timing concern.
pub fn stream_label(props: Option<&HashMap<String, String>>, description: &str, name: &str) -> String {
    let prop = |k: &str| props.and_then(|p| p.get(k)).map_or("", String::as_str);
    [prop("application.name"), description, prop("media.name"), name]
        .into_iter()
        .find(|s| !s.is_empty())
        .unwrap_or("")
        .to_string()
}

fn clamp(v: f64, lo: f64, hi: f64) -> f64 {
    if v.is_nan() { v } else { lo.max(hi.min(v)) }
}

/// Master output/input sliders clamp to 1.0 (a flat track never overdrives past
/// full); per-app streams allow 0..1.5 overdrive, per omarchy's mixer behavior.
pub fn clamp_device(v: f64) -> f64 {
    clamp(v, 0.0, 1.0)
}

pub fn clamp_stream(v: f64) -> f64 {
    clamp(v, 0.0, 1.5)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceState {
    Unavailable,
    Muted,
    Live,
}

impl SourceState {
    pub fn as_str(self) -> &'static str {
        match self {
            SourceState::Unavailable => "unavailable",
            SourceState::Muted => "muted",
            SourceState::Live => "live",
        }
    }
}

/// The single place the mic cell's honest-unavailable branch is decided, so the
/// widget carries no state logic of its own. `available` is whether the default
/// audio source has an audio interface; "unavailable" is a real answer on any
/// host with no capture device, never a stubbed 0%.
pub fn source_state(available: bool, muted: bool) -> SourceState {
    if !available {
        SourceState::Unavailable
    } else if muted {
        SourceState::Muted
    } else {
        SourceState::Live
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeviceRow {
    pub name: String,
    pub label: String,
    pub is_sink: bool,
}

/// Launcher rows: real devices only, outputs first, each half by label. Reads
/// pre-bind-safe fields only, same constraint as `is_playback_stream`. Labels
/// compare by the Unicode root collation, which is what a locale-aware compare
/// gives.
pub fn device_rows(nodes: &[PwNode]) -> Vec<DeviceRow> {
    let mut out: Vec<DeviceRow> = nodes
        .iter()
        .filter(|n| n.has_audio && !n.is_stream)
        .map(|n| DeviceRow {
            name: n.name.clone(),
            label: if !n.description.is_empty() { n.description.clone() } else { n.name.clone() },
            is_sink: n.is_sink,
        })
        .collect();
    let collator = Collator::try_new(Default::default(), CollatorOptions::default()).ok();
    out.sort_by(|a, b| {
        b.is_sink.cmp(&a.is_sink).then_with(|| match &collator {
            Some(c) => c.compare(&a.label, &b.label),
            None => a.label.cmp(&b.label),
        })
    });
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(f: impl FnOnce(&mut PwNode)) -> PwNode {
        let mut n = PwNode::default();
        f(&mut n);
        n
    }

    fn stream(is_sink: bool, ty: &str) -> PwNode {
        node(|n| {
            n.is_stream = true;
            n.is_sink = is_sink;
            n.node_type = ty.into();
        })
    }

    // isPlaybackStream

    #[test]
    fn is_playback_stream_false_for_none() {
        assert!(!is_playback_stream(None));
    }

    #[test]
    fn is_playback_stream_false_for_non_stream_node() {
        assert!(!is_playback_stream(Some(&node(|n| n.is_sink = true))));
    }

    #[test]
    fn is_playback_stream_true_when_stream_and_sink() {
        assert!(is_playback_stream(Some(&stream(true, ""))));
    }

    #[test]
    fn is_playback_stream_true_for_stream_output_audio_type() {
        assert!(is_playback_stream(Some(&stream(false, "Stream/Output/Audio"))));
    }

    #[test]
    fn is_playback_stream_true_for_audio_out_stream_type() {
        assert!(is_playback_stream(Some(&stream(false, "AudioOutStream"))));
    }

    #[test]
    fn is_playback_stream_true_for_generic_output_type() {
        assert!(is_playback_stream(Some(&stream(false, "Output"))));
    }

    #[test]
    fn is_playback_stream_false_for_capture_input_stream() {
        assert!(!is_playback_stream(Some(&stream(false, "Stream/Input/Audio"))));
    }

    // streamLabel

    fn props(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn stream_label_prefers_application_name() {
        let p = props(&[("application.name", "Spotify"), ("media.name", "Track")]);
        assert_eq!(stream_label(Some(&p), "desc", "name"), "Spotify");
    }

    #[test]
    fn stream_label_falls_back_to_description() {
        assert_eq!(stream_label(Some(&props(&[])), "Firefox", "name"), "Firefox");
    }

    #[test]
    fn stream_label_falls_back_to_media_name() {
        let p = props(&[("media.name", "Track Title")]);
        assert_eq!(stream_label(Some(&p), "", "name"), "Track Title");
    }

    #[test]
    fn stream_label_falls_back_to_node_name() {
        assert_eq!(stream_label(Some(&props(&[])), "", "raw-node-name"), "raw-node-name");
    }

    #[test]
    fn stream_label_empty_when_nothing_resolves() {
        assert_eq!(stream_label(Some(&props(&[])), "", ""), "");
    }

    #[test]
    fn stream_label_handles_null_props() {
        assert_eq!(stream_label(None, "desc", "name"), "desc");
    }

    // clampDevice / clampStream

    #[test]
    fn clamp_device_caps_at_one() {
        assert_eq!(clamp_device(1.5), 1.0);
    }

    #[test]
    fn clamp_device_floors_at_zero() {
        assert_eq!(clamp_device(-0.2), 0.0);
    }

    #[test]
    fn clamp_device_passes_through_mid_range() {
        assert_eq!(clamp_device(0.42), 0.42);
    }

    #[test]
    fn clamp_stream_allows_overdrive_up_to_one_point_five() {
        assert_eq!(clamp_stream(1.5), 1.5);
        assert_eq!(clamp_stream(1.3), 1.3);
    }

    #[test]
    fn clamp_stream_caps_above_one_point_five() {
        assert_eq!(clamp_stream(2.0), 1.5);
    }

    #[test]
    fn clamp_stream_floors_at_zero() {
        assert_eq!(clamp_stream(-0.5), 0.0);
    }

    // sourceState

    #[test]
    fn source_state_unavailable_without_input_device() {
        assert_eq!(source_state(false, false).as_str(), "unavailable");
        assert_eq!(source_state(false, true).as_str(), "unavailable");
    }

    #[test]
    fn source_state_muted_when_available_and_muted() {
        assert_eq!(source_state(true, true).as_str(), "muted");
    }

    #[test]
    fn source_state_live_when_available_and_unmuted() {
        assert_eq!(source_state(true, false).as_str(), "live");
    }

    // deviceRows

    fn dev(name: &str, desc: &str, sink: bool) -> PwNode {
        node(|n| {
            n.name = name.into();
            n.description = desc.into();
            n.has_audio = true;
            n.is_sink = sink;
        })
    }

    #[test]
    fn device_rows_drops_streams_and_audioless_nodes() {
        let rows = device_rows(&[
            node(|n| {
                n.name = "s".into();
                n.has_audio = true;
                n.is_stream = true;
                n.is_sink = true;
            }),
            node(|n| {
                n.name = "n".into();
                n.is_sink = true;
            }),
            dev("ok", "Ok", true),
        ]);
        assert_eq!(rows.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(), ["ok"]);
    }

    #[test]
    fn device_rows_label_falls_back_to_name() {
        let rows = device_rows(&[dev("raw", "", false)]);
        assert_eq!(rows[0].label, "raw");
    }

    #[test]
    fn device_rows_outputs_first_each_half_by_label() {
        let rows = device_rows(&[
            dev("i2", "Zmic", false),
            dev("o2", "Zspk", true),
            dev("i1", "Amic", false),
            dev("o1", "Aspk", true),
        ]);
        assert_eq!(rows.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(), ["o1", "o2", "i1", "i2"]);
    }

    #[test]
    fn device_rows_compare_case_insensitively_first() {
        let rows = device_rows(&[dev("b", "banana", true), dev("a", "Apple", true), dev("c", "cherry", true)]);
        assert_eq!(rows.iter().map(|r| r.name.as_str()).collect::<Vec<_>>(), ["a", "b", "c"]);
    }
}
