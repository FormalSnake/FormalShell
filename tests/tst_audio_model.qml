import QtQuick
import QtTest
import "../shell/Audio/model.js" as AudioModel

TestCase {
    name: "AudioModel"

    function node(extra) {
        var base = { isStream: false, isSink: false, type: "" };
        Object.keys(extra || {}).forEach(function (k) { base[k] = extra[k]; });
        return base;
    }

    // isPlaybackStream

    function test_is_playback_stream_false_for_null() {
        verify(!AudioModel.isPlaybackStream(null));
    }

    function test_is_playback_stream_false_for_non_stream_node() {
        verify(!AudioModel.isPlaybackStream(node({ isStream: false, isSink: true })));
    }

    function test_is_playback_stream_true_when_stream_and_sink() {
        verify(AudioModel.isPlaybackStream(node({ isStream: true, isSink: true, type: "" })));
    }

    function test_is_playback_stream_true_for_stream_output_audio_type() {
        verify(AudioModel.isPlaybackStream(node({ isStream: true, isSink: false, type: "Stream/Output/Audio" })));
    }

    function test_is_playback_stream_true_for_audio_out_stream_type() {
        verify(AudioModel.isPlaybackStream(node({ isStream: true, isSink: false, type: "AudioOutStream" })));
    }

    function test_is_playback_stream_true_for_generic_output_type() {
        verify(AudioModel.isPlaybackStream(node({ isStream: true, isSink: false, type: "Output" })));
    }

    function test_is_playback_stream_false_for_capture_input_stream() {
        verify(!AudioModel.isPlaybackStream(node({ isStream: true, isSink: false, type: "Stream/Input/Audio" })));
    }

    function test_is_playback_stream_never_reads_properties_field() {
        // A node whose `properties` getter would throw if touched pre-bind
        // (the omarchy destabilization the plan's research section
        // documents) must still classify correctly without accessing it.
        var n = node({ isStream: true, isSink: true });
        Object.defineProperty(n, "properties", {
            get: function () { throw new Error("properties read pre-bind"); }
        });
        verify(AudioModel.isPlaybackStream(n));
    }

    // streamLabel

    function test_stream_label_prefers_application_name() {
        var label = AudioModel.streamLabel({ "application.name": "Spotify", "media.name": "Track" }, "desc", "name");
        compare(label, "Spotify");
    }

    function test_stream_label_falls_back_to_description() {
        var label = AudioModel.streamLabel({}, "Firefox", "name");
        compare(label, "Firefox");
    }

    function test_stream_label_falls_back_to_media_name() {
        var label = AudioModel.streamLabel({ "media.name": "Track Title" }, "", "name");
        compare(label, "Track Title");
    }

    function test_stream_label_falls_back_to_node_name() {
        var label = AudioModel.streamLabel({}, "", "raw-node-name");
        compare(label, "raw-node-name");
    }

    function test_stream_label_empty_when_nothing_resolves() {
        compare(AudioModel.streamLabel({}, "", ""), "");
    }

    function test_stream_label_handles_null_props() {
        compare(AudioModel.streamLabel(null, "desc", "name"), "desc");
    }

    // clampDevice / clampStream

    function test_clamp_device_caps_at_one() {
        compare(AudioModel.clampDevice(1.5), 1);
    }

    function test_clamp_device_floors_at_zero() {
        compare(AudioModel.clampDevice(-0.2), 0);
    }

    function test_clamp_device_passes_through_mid_range() {
        compare(AudioModel.clampDevice(0.42), 0.42);
    }

    function test_clamp_stream_allows_overdrive_up_to_one_point_five() {
        compare(AudioModel.clampStream(1.5), 1.5);
        compare(AudioModel.clampStream(1.3), 1.3);
    }

    function test_clamp_stream_caps_above_one_point_five() {
        compare(AudioModel.clampStream(2), 1.5);
    }

    function test_clamp_stream_floors_at_zero() {
        compare(AudioModel.clampStream(-0.5), 0);
    }

    // sourceState

    function test_source_state_unavailable_without_input_device() {
        // A host with no capture device reports unavailable regardless of the
        // last-known mute flag, so the mic cell can never render a stale
        // muted/live answer for hardware that isn't there.
        compare(AudioModel.sourceState(false, false), "unavailable");
        compare(AudioModel.sourceState(false, true), "unavailable");
    }

    function test_source_state_muted_when_available_and_muted() {
        compare(AudioModel.sourceState(true, true), "muted");
    }

    function test_source_state_live_when_available_and_unmuted() {
        compare(AudioModel.sourceState(true, false), "live");
    }
}
