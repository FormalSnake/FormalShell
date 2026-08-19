import QtQuick
import QtTest
import "../shell/Media/model.js" as MediaModel

TestCase {
    name: "MediaModel"

    function row(id, isPlaying, identity) {
        return { id: id, isPlaying: isPlaying === true, identity: identity || "" };
    }

    // pickPlayerId

    function test_pick_empty_for_no_players() {
        compare(MediaModel.pickPlayerId([], ""), "");
        compare(MediaModel.pickPlayerId(null, "org.mpris.MediaPlayer2.mpv"), "");
    }

    function test_pick_first_when_nothing_playing() {
        var rows = [row("a"), row("b")];
        compare(MediaModel.pickPlayerId(rows, ""), "a");
    }

    function test_pick_playing_over_first_registered() {
        var rows = [row("a"), row("b", true)];
        compare(MediaModel.pickPlayerId(rows, ""), "b");
    }

    function test_pick_first_playing_when_several_play() {
        var rows = [row("a"), row("b", true), row("c", true)];
        compare(MediaModel.pickPlayerId(rows, ""), "b");
    }

    function test_selection_wins_over_a_playing_player() {
        var rows = [row("a"), row("b", true)];
        compare(MediaModel.pickPlayerId(rows, "a"), "a");
    }

    function test_selection_that_quit_falls_back() {
        var rows = [row("a"), row("b", true)];
        compare(MediaModel.pickPlayerId(rows, "gone"), "b");
    }

    // playerLabel

    function test_label_prefers_identity() {
        compare(MediaModel.playerLabel(row("org.mpris.MediaPlayer2.mpv", false, "mpv Media Player")), "mpv Media Player");
    }

    function test_label_falls_back_to_bus_name_tail() {
        compare(MediaModel.playerLabel(row("org.mpris.MediaPlayer2.mpv")), "mpv");
    }

    function test_label_of_a_dotless_bus_name_is_the_name() {
        compare(MediaModel.playerLabel(row("mpv")), "mpv");
    }

    function test_label_of_nothing_is_empty() {
        compare(MediaModel.playerLabel(null), "");
    }

    // withLabels

    function test_labels_are_kept_when_they_are_already_distinct() {
        var rows = MediaModel.withLabels([
            row("org.mpris.MediaPlayer2.mpv", true, "mpv"),
            row("org.mpris.MediaPlayer2.firefox.instance-7", false, "Mozilla Firefox")
        ]);
        compare(rows[0].label, "mpv");
        compare(rows[1].label, "Mozilla Firefox");
        compare(rows[0].isPlaying, true);
        compare(rows[1].id, "org.mpris.MediaPlayer2.firefox.instance-7");
    }

    function test_colliding_labels_fall_back_to_the_bus_name() {
        var rows = MediaModel.withLabels([
            row("org.mpris.MediaPlayer2.mpv", false, "mpv"),
            row("org.mpris.MediaPlayer2.mpv.instance-abc", false, "mpv")
        ]);
        compare(rows[0].label, "mpv");
        compare(rows[1].label, "mpv.instance-abc");
    }

    function test_only_the_colliding_rows_lose_their_identity() {
        var rows = MediaModel.withLabels([
            row("org.mpris.MediaPlayer2.mpv", false, "mpv"),
            row("org.mpris.MediaPlayer2.mpv.instance-abc", false, "mpv"),
            row("org.mpris.MediaPlayer2.spotify", false, "Spotify")
        ]);
        compare(rows[2].label, "Spotify");
    }

    function test_labels_of_nothing_is_an_empty_list() {
        compare(MediaModel.withLabels(null).length, 0);
    }

    // loop names

    function test_loop_names_are_the_three_mpris_states() {
        verify(MediaModel.isLoopName("none"));
        verify(MediaModel.isLoopName("track"));
        verify(MediaModel.isLoopName("playlist"));
    }

    function test_unknown_loop_name_rejected() {
        verify(!MediaModel.isLoopName("all"));
        verify(!MediaModel.isLoopName(""));
        verify(!MediaModel.isLoopName("None"));
    }

    function test_loop_cycles_off_queue_track_off() {
        compare(MediaModel.nextLoop("none"), "playlist");
        compare(MediaModel.nextLoop("playlist"), "track");
        compare(MediaModel.nextLoop("track"), "none");
    }

    function test_loop_cycle_of_garbage_lands_on_none() {
        compare(MediaModel.nextLoop("nonsense"), "none");
    }

    // clamps

    function test_volume_clamped_to_the_flat_track() {
        compare(MediaModel.clampVolume(0.5), 0.5);
        compare(MediaModel.clampVolume(-1), 0);
        compare(MediaModel.clampVolume(1.4), 1);
    }

    function test_volume_of_nothing_is_zero() {
        compare(MediaModel.clampVolume(undefined), 0);
        compare(MediaModel.clampVolume("loud"), 0);
    }

    function test_seek_fraction_clamped_to_the_track() {
        compare(MediaModel.clampFraction(0.25), 0.25);
        compare(MediaModel.clampFraction(-0.3), 0);
        compare(MediaModel.clampFraction(2), 1);
        compare(MediaModel.clampFraction(NaN), 0);
    }
}
