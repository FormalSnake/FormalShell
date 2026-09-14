import QtQuick
import QtTest
import "../shell/Lyrics/model.js" as Lyrics

TestCase {
    name: "LyricsModel"

    // cacheKey

    function test_cache_key_lowercases_and_dashes() {
        compare(Lyrics.cacheKey("The Beatles", "Let It Be", "Let It Be", 243), "the-beatles-let-it-be-let-it-be-243");
    }

    function test_cache_key_strips_punctuation() {
        compare(Lyrics.cacheKey("Sigur Rós", "( )", "Takk...", 10), "sigur-r-s-takk-10");
    }

    function test_cache_key_rounds_the_duration() {
        compare(Lyrics.cacheKey("a", "b", "c", 10.6), "a-b-c-11");
    }

    function test_cache_key_of_a_missing_duration_is_zero() {
        compare(Lyrics.cacheKey("a", "b", "c", undefined), "a-b-c-0");
    }

    // getUrl

    function test_get_url_targets_lrclib_get() {
        var url = Lyrics.getUrl("Air", "La Femme d'Argent", "Moon Safari", 429);
        verify(url.indexOf("https://lrclib.net/api/get?") === 0);
        verify(url.indexOf("track_name=La%20Femme%20d'Argent") >= 0 || url.indexOf("track_name=La%20Femme%20d%27Argent") >= 0);
        verify(url.indexOf("artist_name=Air") >= 0);
    }

    function test_get_url_includes_album_name_when_present() {
        var url = Lyrics.getUrl("Air", "Title", "Moon Safari", 429);
        verify(url.indexOf("album_name=Moon%20Safari") >= 0);
    }

    function test_get_url_omits_album_name_when_empty() {
        var url = Lyrics.getUrl("Air", "Title", "", 429);
        verify(url.indexOf("album_name=") === -1);
    }

    function test_get_url_includes_rounded_duration() {
        var url = Lyrics.getUrl("Air", "Title", "Moon Safari", 428.6);
        verify(url.indexOf("duration=429") >= 0);
    }

    function test_get_url_omits_duration_when_not_finite() {
        var url = Lyrics.getUrl("Air", "Title", "Moon Safari", NaN);
        verify(url.indexOf("duration=") === -1);
    }

    function test_get_url_omits_duration_when_zero_or_negative() {
        var url = Lyrics.getUrl("Air", "Title", "Moon Safari", 0);
        verify(url.indexOf("duration=") === -1);
        url = Lyrics.getUrl("Air", "Title", "Moon Safari", -5);
        verify(url.indexOf("duration=") === -1);
    }

    // searchUrl

    function test_search_url_targets_lrclib_search() {
        var url = Lyrics.searchUrl("Air", "Title");
        verify(url.indexOf("https://lrclib.net/api/search?") === 0);
        verify(url.indexOf("track_name=Title") >= 0);
        verify(url.indexOf("artist_name=Air") >= 0);
    }

    function test_search_url_percent_encodes() {
        var url = Lyrics.searchUrl("Sigur Rós", "Untitled #1");
        verify(url.indexOf("Sigur%20R%C3%B3s") >= 0);
        verify(url.indexOf("Untitled%20%231") >= 0);
    }

    // pickSynced — /api/get object shape

    function test_pick_synced_reads_a_get_hit() {
        var body = JSON.stringify({ syncedLyrics: "[00:01.00]Hello\n[00:02.00]World" });
        compare(Lyrics.pickSynced(body), "[00:01.00]Hello\n[00:02.00]World");
    }

    function test_pick_synced_of_a_plain_only_hit_is_empty() {
        var body = JSON.stringify({ plainLyrics: "Hello\nWorld", syncedLyrics: null });
        compare(Lyrics.pickSynced(body), "");
    }

    function test_pick_synced_of_an_instrumental_is_empty() {
        var body = JSON.stringify({ instrumental: true, syncedLyrics: null, plainLyrics: null });
        compare(Lyrics.pickSynced(body), "");
    }

    function test_pick_synced_of_a_synced_lyrics_with_no_usable_timing_is_empty() {
        // one stamp, one line: still usable on its own, so pin the
        // no-usable-timing case on an unparseable body instead.
        var body = JSON.stringify({ syncedLyrics: "no timestamps here" });
        compare(Lyrics.pickSynced(body), "");
    }

    // pickSynced — /api/search array shape

    function test_pick_synced_skips_a_plain_only_hit_for_a_synced_one() {
        var body = JSON.stringify([
            { plainLyrics: "Hello", syncedLyrics: null },
            { syncedLyrics: "[00:01.00]Hello\n[00:02.00]World" }
        ]);
        compare(Lyrics.pickSynced(body), "[00:01.00]Hello\n[00:02.00]World");
    }

    function test_pick_synced_of_an_empty_search_array_is_empty() {
        compare(Lyrics.pickSynced(JSON.stringify([])), "");
    }

    // pickSynced — malformed input

    function test_pick_synced_of_an_empty_body_is_empty() {
        compare(Lyrics.pickSynced(""), "");
    }

    function test_pick_synced_of_a_non_json_body_is_empty() {
        compare(Lyrics.pickSynced("not json{{{"), "");
    }

    // parseLrc

    function test_parse_lrc_reads_plain_stamps() {
        var lines = Lyrics.parseLrc("[00:01.00]One\n[00:02.50]Two");
        compare(lines.length, 2);
        compare(lines[0].time, 1);
        compare(lines[0].text, "One");
        compare(lines[1].time, 2.5);
        compare(lines[1].text, "Two");
    }

    function test_parse_lrc_reads_hundredths_and_thousandths() {
        var lines = Lyrics.parseLrc("[00:01.5]A\n[00:02.500]B\n[00:03.123]C");
        compare(lines[0].time, 1.5);
        compare(lines[1].time, 2.5);
        verify(Math.abs(lines[2].time - 3.123) < 1e-9);
    }

    function test_parse_lrc_reads_minutes() {
        var lines = Lyrics.parseLrc("[01:02.00]Late");
        compare(lines[0].time, 62);
    }

    function test_parse_lrc_several_stamps_on_one_line_are_one_entry_each() {
        var lines = Lyrics.parseLrc("[00:01.00][00:05.00]Repeat me");
        compare(lines.length, 2);
        compare(lines[0].time, 1);
        compare(lines[1].time, 5);
        compare(lines[0].text, "Repeat me");
        compare(lines[1].text, "Repeat me");
    }

    function test_parse_lrc_skips_metadata_tags() {
        var lines = Lyrics.parseLrc("[ar:Some Artist]\n[ti:Some Title]\n[offset:+500]\n[00:01.00]Real line");
        compare(lines.length, 1);
        compare(lines[0].text, "Real line");
    }

    function test_parse_lrc_skips_a_stampless_line() {
        var lines = Lyrics.parseLrc("[00:01.00]Real line\nno stamp here at all");
        compare(lines.length, 1);
    }

    function test_parse_lrc_merges_equal_times_as_a_translation() {
        var lines = Lyrics.parseLrc("[00:01.00]Hello\n[00:01.00]Bonjour");
        compare(lines.length, 1);
        compare(lines[0].text, "Hello\nBonjour");
    }

    function test_parse_lrc_sorts_out_of_order_lines() {
        var lines = Lyrics.parseLrc("[00:05.00]Second\n[00:01.00]First");
        compare(lines[0].text, "First");
        compare(lines[1].text, "Second");
    }

    function test_parse_lrc_reads_enhanced_word_stamps() {
        var lines = Lyrics.parseLrc("[00:01.00]<00:01.00>Hello <00:01.50>world");
        compare(lines.length, 1);
        compare(lines[0].text, "Hello world");
        compare(lines[0].words.length, 2);
        compare(lines[0].words[0], { time: 1, text: "Hello" });
        compare(lines[0].words[1], { time: 1.5, text: "world" });
    }

    function test_parse_lrc_of_empty_text_is_empty() {
        compare(Lyrics.parseLrc("").length, 0);
        compare(Lyrics.parseLrc(undefined).length, 0);
    }

    // hasUsableTiming

    function test_has_usable_timing_of_one_line_is_true() {
        verify(Lyrics.hasUsableTiming([{ time: 1, text: "A" }]));
    }

    function test_has_usable_timing_of_increasing_lines_is_true() {
        verify(Lyrics.hasUsableTiming([{ time: 1, text: "A" }, { time: 2, text: "B" }]));
    }

    function test_has_usable_timing_of_lines_stuck_on_one_time_is_false() {
        verify(!Lyrics.hasUsableTiming([{ time: 1, text: "A" }, { time: 1, text: "B" }, { time: 1, text: "C" }]));
    }

    function test_has_usable_timing_of_nothing_is_false() {
        verify(!Lyrics.hasUsableTiming([]));
        verify(!Lyrics.hasUsableTiming(null));
    }

    // indexForTime

    function test_index_for_time_before_the_first_line_is_negative_one() {
        var lines = [{ time: 5, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.indexForTime(lines, 0), -1);
    }

    function test_index_for_time_on_a_line_is_its_index() {
        var lines = [{ time: 5, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.indexForTime(lines, 10), 1);
    }

    function test_index_for_time_between_lines_is_the_earlier_one() {
        var lines = [{ time: 5, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.indexForTime(lines, 7), 0);
    }

    function test_index_for_time_honors_the_fudge() {
        var lines = [{ time: 10, text: "A" }];
        compare(Lyrics.indexForTime(lines, 10 - Lyrics.FUDGE_SECONDS), 0);
        compare(Lyrics.indexForTime(lines, 10 - Lyrics.FUDGE_SECONDS - 0.01), -1);
    }

    function test_index_for_time_after_the_last_line_is_the_last_index() {
        var lines = [{ time: 5, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.indexForTime(lines, 999), 1);
    }

    // wordIndexForTime

    function test_word_index_for_time_walks_a_line_s_words() {
        var words = [{ time: 1, text: "Hello" }, { time: 1.5, text: "world" }];
        compare(Lyrics.wordIndexForTime(words, 0), -1);
        compare(Lyrics.wordIndexForTime(words, 1.2), 0);
        compare(Lyrics.wordIndexForTime(words, 1.5), 1);
    }

    // displayLines

    function test_display_lines_opens_with_an_interlude_when_the_first_line_is_late() {
        var lines = [{ time: 6, text: "First", words: [] }];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 2);
        compare(out[0], { interlude: true, time: 0, end: 6 });
        compare(out[1], lines[0]);
    }

    function test_display_lines_has_no_leading_interlude_for_an_early_first_line() {
        var lines = [{ time: 2, text: "First", words: [] }];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 1);
    }

    function test_display_lines_inserts_an_interlude_over_a_wide_gap() {
        var lines = [
            { time: 1, text: "First", words: [] },
            { time: 20, text: "Second", words: [] }
        ];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 3);
        compare(out[1], { interlude: true, time: 1 + Lyrics.LINE_ASSUMED_SECONDS, end: 20 });
    }

    function test_display_lines_estimates_the_end_off_the_last_word() {
        var lines = [
            { time: 1, text: "First", words: [{ time: 1, text: "First" }, { time: 2, text: "line" }] },
            { time: 10, text: "Second", words: [] }
        ];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 3);
        compare(out[1].time, 2 + Lyrics.WORD_FALLBACK_SECONDS);
    }

    function test_display_lines_has_no_interlude_over_a_short_gap() {
        var lines = [
            { time: 1, text: "First", words: [] },
            { time: 3, text: "Second", words: [] }
        ];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 2);
    }

    function test_display_lines_clamps_the_estimated_end_to_the_next_line() {
        // LINE_ASSUMED_SECONDS (7s) alone would land past "Second",
        // only 2s later; the clamp keeps that pair a non-event instead
        // of a bogus negative gap, and the next pair still gets its own
        // interlude on its own terms.
        var lines = [
            { time: 1, text: "First", words: [] },
            { time: 3, text: "Second", words: [] },
            { time: 20, text: "Third", words: [] }
        ];
        var out = Lyrics.displayLines(lines);
        compare(out.length, 4);
        compare(out[0], lines[0]);
        compare(out[1], lines[1]);
        compare(out[2], { interlude: true, time: 3 + Lyrics.LINE_ASSUMED_SECONDS, end: 20 });
        compare(out[3], lines[2]);
    }

    function test_display_lines_of_nothing_is_empty() {
        compare(Lyrics.displayLines([]).length, 0);
    }

    // depthOpacity

    function test_depth_opacity_of_the_active_line_is_full() {
        compare(Lyrics.depthOpacity(0), 1);
    }

    function test_depth_opacity_falls_with_distance() {
        compare(Lyrics.depthOpacity(1), 0.7);
        compare(Lyrics.depthOpacity(-1), 0.7);
        compare(Lyrics.depthOpacity(2), 0.45);
        compare(Lyrics.depthOpacity(3), 0.25);
    }

    function test_depth_opacity_floors_at_three_lines_away() {
        compare(Lyrics.depthOpacity(4), 0.25);
        compare(Lyrics.depthOpacity(-10), 0.25);
    }
}
