import QtQuick
import QtTest
import "../shell/Lyrics/model.js" as Lyrics

TestCase {
    name: "LyricsModel"

    // -- fixtures (kopuz's own `line`/`background_line` helpers, ported) --

    function _line(time, end, text) {
        return { time: time, end: end === undefined ? null : end,
            text: text === undefined ? "la" : text, words: [],
            parent: null, background: false, oppositeTurn: false, estimated: false };
    }

    function _backgroundLine(time, end, parent) {
        var l = _line(time, end);
        l.background = true;
        l.parent = parent;
        return l;
    }

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

    // getUrl / searchUrl (lrclib)

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

    // itunesSearchUrl / paxsenixAppleLyricsUrl / paxsenixYoutubeSearchUrl / paxsenixYoutubeLyricsUrl

    function test_itunes_search_url_orders_title_then_artist() {
        var url = Lyrics.itunesSearchUrl("Example Artist", "Ninety Two Ten");
        verify(url.indexOf("https://itunes.apple.com/search?term=") === 0);
        verify(url.indexOf(encodeURIComponent("Ninety Two Ten Example Artist")) >= 0);
        verify(url.indexOf("entity=song") >= 0);
        verify(url.indexOf("limit=8") >= 0);
        verify(url.indexOf("country=US") >= 0);
    }

    function test_paxsenix_apple_lyrics_url_carries_the_track_id() {
        compare(Lyrics.paxsenixAppleLyricsUrl(12345), "https://lyrics.paxsenix.org/apple-music/lyrics?id=12345");
    }

    function test_paxsenix_youtube_search_url_orders_title_then_artist() {
        var url = Lyrics.paxsenixYoutubeSearchUrl("Example Artist", "Ninety Two Ten");
        verify(url.indexOf("https://lyrics.paxsenix.org/youtube/search?q=") === 0);
        verify(url.indexOf(encodeURIComponent("Ninety Two Ten Example Artist")) >= 0);
    }

    function test_paxsenix_youtube_lyrics_url_carries_the_video_id() {
        compare(Lyrics.paxsenixYoutubeLyricsUrl("abc123"), "https://lyrics.paxsenix.org/youtube/lyrics?id=abc123");
    }

    // pickSynced: /api/get object shape

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

    // pickSynced: /api/search array shape

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

    // pickSynced: malformed input

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

    function test_parse_lrc_merges_equal_times_as_a_parenthesised_translation() {
        var lines = Lyrics.parseLrc("[00:01.00]Hello\n[00:01.00]Bonjour");
        compare(lines.length, 1);
        compare(lines[0].text, "Hello\n(Bonjour)");
    }

    function test_parse_lrc_keeps_an_already_parenthesised_translation() {
        var lines = Lyrics.parseLrc("[00:01.00]Hello\n[00:01.00](Bonjour)");
        compare(lines[0].text, "Hello\n(Bonjour)");
    }

    function test_parse_lrc_a_blank_translation_line_adds_nothing() {
        var lines = Lyrics.parseLrc("[00:01.00]Hello\n[00:01.00] ");
        compare(lines[0].text, "Hello");
    }

    function test_parse_lrc_sorts_out_of_order_lines() {
        var lines = Lyrics.parseLrc("[00:05.00]Second\n[00:01.00]First");
        compare(lines[0].text, "First");
        compare(lines[1].text, "Second");
    }

    function test_parse_lrc_fills_the_new_p1_fields() {
        var lines = Lyrics.parseLrc("[00:01.00]La");
        compare(lines[0].end, null);
        compare(lines[0].parent, null);
        compare(lines[0].background, false);
        compare(lines[0].oppositeTurn, false);
        compare(lines[0].estimated, false);
    }

    function test_parse_lrc_reads_enhanced_word_stamps() {
        var lines = Lyrics.parseLrc("[00:01.00]<00:01.00>Hello <00:01.50>world");
        compare(lines.length, 1);
        compare(lines[0].text, "Hello world");
        compare(lines[0].words.length, 2);
        compare(lines[0].words[0], { time: 1, text: "Hello", joinsNext: false });
        compare(lines[0].words[1], { time: 1.5, text: "world", joinsNext: false });
    }

    function test_parse_lrc_groups_syllable_stamps_as_one_word() {
        var lines = Lyrics.parseLrc("[00:01.00]<00:01.00>Hel<00:01.20>lo <00:01.50>world");
        compare(lines[0].text, "Hello world");
        compare(lines[0].words[0], { time: 1, text: "Hel", joinsNext: true });
        compare(lines[0].words[1], { time: 1.2, text: "lo", joinsNext: false });
        compare(lines[0].words[2], { time: 1.5, text: "world", joinsNext: false });
        var groups = Lyrics.chunkWords(lines[0].words);
        compare(groups.length, 2);
        compare(groups[0].map(function (c) { return c.text; }), ["Hel", "lo"]);
        compare(groups[1].map(function (c) { return c.text; }), ["world"]);
    }

    function test_parse_lrc_a_stray_stamp_with_no_text_still_separates() {
        // The middle stamp owns nothing (immediately followed by the next
        // stamp), so it is dropped from `words`, but the chunk before it
        // still doesn't join across it: there was no text there to join to.
        var lines = Lyrics.parseLrc("[00:01.00]<00:01.00>One<00:01.10><00:01.20>Two");
        compare(lines[0].words.length, 2);
        compare(lines[0].words[0], { time: 1, text: "One", joinsNext: false });
        compare(lines[0].words[1], { time: 1.2, text: "Two", joinsNext: false });
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

    // fromPaxsenixApple: spaces, punctuation, part joins

    function test_from_paxsenix_apple_joins_syllable_parts_with_no_space() {
        var body = JSON.stringify({
            content: [{
                text: [
                    { text: "La", timestamp: 10100, part: true },
                    { text: "la", timestamp: 10300, part: false },
                    { text: "loo", timestamp: 10600, part: false }
                ],
                backgroundText: [],
                timestamp: 10000,
                endtime: 11000,
                background: false,
                oppositeTurn: false
            }]
        });
        var lines = Lyrics.fromPaxsenixApple(body);
        compare(lines.length, 1);
        compare(lines[0].time, 10);
        compare(lines[0].end, 11);
        compare(lines[0].text, "Lala loo");
        compare(lines[0].words.length, 3);
        compare(lines[0].words[0], { time: 10.1, text: "La", joinsNext: true });
        compare(lines[0].words[1], { time: 10.3, text: "la", joinsNext: false });
        compare(lines[0].words[2], { time: 10.6, text: "loo", joinsNext: false });
        var groups = Lyrics.chunkWords(lines[0].words);
        compare(groups.length, 2);
    }

    function test_from_paxsenix_apple_never_spaces_before_punctuation() {
        var body = JSON.stringify({
            content: [{
                text: [
                    { text: "La", timestamp: 1000, part: false },
                    { text: ",", timestamp: 1200, part: false },
                    { text: "la", timestamp: 1400, part: false }
                ],
                backgroundText: [],
                timestamp: 1000,
                endtime: 2000,
                background: false,
                oppositeTurn: false
            }]
        });
        var lines = Lyrics.fromPaxsenixApple(body);
        compare(lines[0].text, "La, la");
    }

    function test_from_paxsenix_apple_splits_background_text_with_its_own_parent() {
        var body = JSON.stringify({
            content: [
                {
                    text: [
                        { text: "La", timestamp: 10000, part: false },
                        { text: "la", timestamp: 10500, part: false }
                    ],
                    backgroundText: [{ text: "Echo", timestamp: 10800, part: false }],
                    timestamp: 10000,
                    endtime: 12000,
                    background: true,
                    oppositeTurn: true
                },
                {
                    text: [{ text: "Next", timestamp: 10600, part: false }],
                    backgroundText: [],
                    timestamp: 10600,
                    endtime: 13000,
                    background: false,
                    oppositeTurn: true
                }
            ]
        });
        var lines = Lyrics.fromPaxsenixApple(body);
        compare(lines.length, 3);
        compare(lines[0].text, "La la");
        verify(!lines[0].background);
        verify(lines[0].oppositeTurn);
        compare(lines[0].parent, null);
        compare(lines[1].text, "Echo");
        verify(lines[1].background);
        verify(lines[1].oppositeTurn);
        compare(lines[1].parent, 0);
        compare(lines[1].time, 10.8);
        compare(lines[2].text, "Next");
        compare(lines[2].parent, null);
    }

    function test_from_paxsenix_apple_a_background_row_with_no_background_text_is_itself_background() {
        var body = JSON.stringify({
            content: [{
                text: [{ text: "Mm", timestamp: 5000, part: false }],
                backgroundText: [],
                timestamp: 5000,
                endtime: 5500,
                background: true,
                oppositeTurn: false
            }]
        });
        var lines = Lyrics.fromPaxsenixApple(body);
        compare(lines.length, 1);
        verify(lines[0].background);
        compare(lines[0].text, "Mm");
        compare(lines[0].parent, null);
    }

    function test_from_paxsenix_apple_falls_back_to_lrc_when_content_has_no_timing() {
        var body = JSON.stringify({
            content: [{
                text: [{ text: "Untimed", part: false }],
                backgroundText: [],
                timestamp: 0,
                endtime: 0,
                background: false,
                oppositeTurn: false
            }],
            lrc: "[00:01.00]One\n[00:02.00]Two",
            plain: "Untimed"
        });
        var lines = Lyrics.fromPaxsenixApple(body);
        compare(lines.length, 2);
        compare(lines[0].text, "One");
        compare(lines[1].text, "Two");
    }

    function test_from_paxsenix_apple_of_nothing_usable_is_empty() {
        compare(Lyrics.fromPaxsenixApple(JSON.stringify({ content: [], lrc: "", plain: "x" })).length, 0);
    }

    function test_from_paxsenix_apple_of_non_json_is_empty() {
        compare(Lyrics.fromPaxsenixApple("not json{{{").length, 0);
    }

    // matchScore / bestItunesSong / bestYoutubeResult / parseColonDuration

    function test_match_score_of_identical_token_sets_is_one_hundred() {
        compare(Lyrics.matchScore("Ninety Two Ten Example Artist", "Ninety Two Ten Example Artist"), 100);
    }

    function test_match_score_of_disjoint_text_is_zero() {
        compare(Lyrics.matchScore("Completely Different Words", "Nothing Alike Here"), 0);
    }

    function test_match_score_strips_the_feat_marker_without_dropping_the_name() {
        compare(
            Lyrics.matchScore("Song (feat. Other) Artist", "Song Artist"),
            Lyrics.matchScore("Song Other Artist", "Song Artist")
        );
    }

    function test_best_itunes_song_drops_candidates_below_the_floor() {
        var songs = [{ trackId: 1, trackName: "Nothing Alike", artistName: "Unrelated" }];
        compare(Lyrics.bestItunesSong(songs, "Ninety Two Ten Example Artist", 0), null);
    }

    function test_best_itunes_song_prefers_the_duration_match_within_the_window() {
        var songs = [
            { trackId: 1, trackName: "Ninety Two Ten", artistName: "Example Artist", trackTimeMillis: 230000 },
            { trackId: 2, trackName: "Ninety Two Ten", artistName: "Example Artist", trackTimeMillis: 197200 }
        ];
        var best = Lyrics.bestItunesSong(songs, "Ninety Two Ten Example Artist", 198);
        compare(best.trackId, 2);
    }

    function test_best_itunes_song_rejects_a_candidate_past_the_duration_window() {
        var songs = [{ trackId: 1, trackName: "Ninety Two Ten", artistName: "Example Artist", trackTimeMillis: 400000 }];
        compare(Lyrics.bestItunesSong(songs, "Ninety Two Ten Example Artist", 198), null);
    }

    function test_best_youtube_result_checks_the_duration_window() {
        var results = [
            { videoId: "wrong-duration", title: "Ninety Two Ten", author: "Example Artist", duration: "5:40" },
            { videoId: "right-duration", title: "Ninety Two Ten", author: "Example Artist", duration: "3:28" }
        ];
        var best = Lyrics.bestYoutubeResult(results, "Ninety Two Ten Example Artist", 208);
        compare(best.videoId, "right-duration");
    }

    function test_parse_colon_duration_reads_minutes_and_seconds() {
        compare(Lyrics.parseColonDuration("3:28"), 208);
    }

    function test_parse_colon_duration_reads_hours() {
        compare(Lyrics.parseColonDuration("1:02:03"), 3723);
    }

    function test_parse_colon_duration_of_empty_is_null() {
        compare(Lyrics.parseColonDuration(""), null);
    }

    function test_parse_colon_duration_of_non_numeric_is_null() {
        compare(Lyrics.parseColonDuration("nope"), null);
    }

    // quality / pickBest / isDefinitive

    function test_quality_of_nothing_is_zero() {
        compare(Lyrics.quality([]), 0);
        compare(Lyrics.quality(null), 0);
    }

    function test_quality_of_line_timing_only_is_one() {
        compare(Lyrics.quality([{ time: 1, words: [] }]), 1);
    }

    function test_quality_of_word_timing_is_two() {
        var lines = [{ time: 1, words: [{ time: 1, text: "a", joinsNext: false }, { time: 1.5, text: "b", joinsNext: false }] }];
        compare(Lyrics.quality(lines), 2);
    }

    function test_is_definitive_matches_quality_two() {
        verify(Lyrics.isDefinitive([{ time: 1, words: [{ time: 1, text: "a" }, { time: 1.5, text: "b" }] }]));
        verify(!Lyrics.isDefinitive([{ time: 1, words: [] }]));
    }

    function test_pick_best_prefers_the_highest_quality() {
        var results = [
            { source: "lrclib", lines: [{ time: 1, words: [] }] },
            { source: "apple", lines: [{ time: 1, words: [{ time: 1, text: "a" }, { time: 1.5, text: "b" }] }] }
        ];
        compare(Lyrics.pickBest(results).source, "apple");
    }

    function test_pick_best_ties_go_to_the_earlier_entry() {
        var results = [
            { source: "apple", lines: [{ time: 1, words: [] }] },
            { source: "youtube", lines: [{ time: 1, words: [] }] }
        ];
        compare(Lyrics.pickBest(results).source, "apple");
    }

    function test_pick_best_of_all_quality_zero_is_null() {
        var results = [{ source: "apple", lines: [] }, { source: "lrclib", lines: [] }];
        compare(Lyrics.pickBest(results), null);
    }

    // chunkGlow

    function test_chunk_glow_is_full_while_the_chunk_is_being_sung() {
        var words = [
            { time: 1, text: "Hel", joinsNext: true },
            { time: 2, text: "lo", joinsNext: false }
        ];
        compare(Lyrics.chunkGlow(words, 0, 3, 0.5), 0);
        compare(Lyrics.chunkGlow(words, 0, 3, 1.5), 1);
        compare(Lyrics.chunkGlow(words, 0, 3, 2), 1);
    }

    function test_chunk_glow_decays_linearly_once_the_chunk_is_over() {
        var words = [
            { time: 1, text: "Hel", joinsNext: true },
            { time: 2, text: "lo", joinsNext: false }
        ];
        compare(Lyrics.chunkGlow(words, 0, 3, 2 + Lyrics.GLOW_DECAY_SECONDS / 2), 0.5);
        compare(Lyrics.chunkGlow(words, 0, 3, 2 + Lyrics.GLOW_DECAY_SECONDS), 0);
        compare(Lyrics.chunkGlow(words, 0, 3, 10), 0);
    }

    // chunkWords

    function test_chunk_words_one_chunk_per_word_for_a_word_stamped_line() {
        var words = [
            { time: 1, text: "Hello", joinsNext: false },
            { time: 1.5, text: "world", joinsNext: false }
        ];
        var groups = Lyrics.chunkWords(words);
        compare(groups.length, 2);
        compare(groups[0].length, 1);
        compare(groups[1].length, 1);
    }

    function test_chunk_words_of_nothing_is_empty() {
        compare(Lyrics.chunkWords([]).length, 0);
        compare(Lyrics.chunkWords(null).length, 0);
    }

    // chunkEnd / chunkProgress

    function test_chunk_end_runs_to_the_next_chunk() {
        var words = [{ time: 1, text: "A" }, { time: 2, text: "B" }];
        compare(Lyrics.chunkEnd(words, 0, 10), 2);
    }

    function test_chunk_end_of_the_last_chunk_runs_to_the_line_end() {
        var words = [{ time: 1, text: "A" }];
        compare(Lyrics.chunkEnd(words, 0, 4), 4);
    }

    function test_chunk_end_of_the_last_chunk_with_no_line_end_falls_back() {
        var words = [{ time: 1, text: "A" }];
        compare(Lyrics.chunkEnd(words, 0, undefined), 1 + Lyrics.WORD_FALLBACK_SECONDS);
    }

    function test_chunk_progress_before_its_stamp_is_zero() {
        var words = [{ time: 5, text: "A" }, { time: 6, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, 4), 0);
    }

    function test_chunk_progress_partway_through_its_span() {
        var words = [{ time: 5, text: "A" }, { time: 6, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, 5.5), 0.5);
    }

    function test_chunk_progress_after_its_span_is_one() {
        var words = [{ time: 5, text: "A" }, { time: 6, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, 100), 1);
    }

    function test_chunk_progress_caps_the_span_at_wipe_max_seconds() {
        // The next chunk is 10s out; the wipe still finishes at the cap
        // rather than creeping toward it.
        var words = [{ time: 0, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, Lyrics.WIPE_MAX_SECONDS), 1);
        verify(Lyrics.chunkProgress(words, 0, undefined, Lyrics.WIPE_MAX_SECONDS / 2) < 1);
    }

    function test_chunk_progress_of_the_last_chunk_runs_to_the_line_end() {
        var words = [{ time: 0, text: "A" }];
        compare(Lyrics.chunkProgress(words, 0, 0.5, 0.5), 1);
        compare(Lyrics.chunkProgress(words, 0, 0.5, 0.25), 0.5);
    }

    // The cap is a provider's own stamp held over a pause. A synthesised
    // chunk has no pause in it, so it keeps its whole share of the line.
    function test_chunk_progress_of_a_synthesised_chunk_is_not_capped() {
        var words = [{ time: 0, text: "A" }, { time: 10, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, 5, true), 0.5);
        compare(Lyrics.chunkProgress(words, 0, undefined, 10, true), 1);
    }

    // The owner's report: two line-synced lines of the same words held for
    // different lengths wipe at their own rates, each reaching the end of
    // its text as the next line lights, rather than both running at one
    // fixed rate (owner, 2026-09-18).
    function _estimatedWipe(lineTime, nextTime, t) {
        var lines = Lyrics.synthesiseWords([
            _line(lineTime, null, "one two"),
            _line(nextTime)
        ]);
        var words = lines[0].words;
        var sum = 0;
        for (var i = 0; i < words.length; i++)
            sum += Lyrics.chunkProgress(words, i, nextTime, t, true);
        return sum / words.length;
    }

    function test_an_estimated_wipe_tracks_the_line_it_is_held_for() {
        // Held 2s and held 6s, each sampled at half its own span.
        fuzzyCompare(_estimatedWipe(0, 2, 1), 0.5, 0.06);
        fuzzyCompare(_estimatedWipe(0, 6, 3), 0.5, 0.06);
        // At one wall-clock second the short line is half sung and the long
        // one has barely started, which is the difference a fixed rate
        // cannot draw.
        verify(_estimatedWipe(0, 2, 1) > _estimatedWipe(0, 6, 1) + 0.25);
        // And three quarters through the long line it is still travelling,
        // where a capped chunk would have finished and be waiting.
        verify(_estimatedWipe(0, 6, 4.5) < 0.9);
    }

    function test_an_estimated_wipe_lands_as_the_next_line_lights() {
        compare(_estimatedWipe(0, 2, 2), 1);
        compare(_estimatedWipe(0, 6, 6), 1);
    }

    // synthesiseWords

    function test_synthesise_words_shares_the_span_by_character_count() {
        var lines = [{ time: 0, end: 11, text: "one two three", words: [], parent: null, background: false, oppositeTurn: false, estimated: false }];
        var out = Lyrics.synthesiseWords(lines);
        compare(out[0].estimated, true);
        compare(out[0].words.length, 3);
        compare(out[0].words[0], { time: 0, text: "one", joinsNext: false });
        compare(out[0].words[1], { time: 3, text: "two", joinsNext: false });
        compare(out[0].words[2], { time: 6, text: "three", joinsNext: false });
    }

    function test_synthesise_words_spans_to_the_next_main_line_when_untimed() {
        var lines = [
            { time: 0, end: null, text: "la la", words: [], parent: null, background: false, oppositeTurn: false, estimated: false },
            { time: 4, end: null, text: "la", words: [], parent: null, background: false, oppositeTurn: false, estimated: false }
        ];
        var out = Lyrics.synthesiseWords(lines);
        compare(out[0].words[0].time, 0);
        compare(out[0].words[1].time, 2);
    }

    function test_synthesise_words_leaves_a_provider_timed_line_alone() {
        var lines = [{ time: 0, end: 2, text: "la", words: [{ time: 0, text: "la", joinsNext: false }],
            parent: null, background: false, oppositeTurn: false, estimated: false }];
        var out = Lyrics.synthesiseWords(lines);
        compare(out[0], lines[0]);
    }

    function test_synthesise_words_skips_an_interlude() {
        var lines = [{ interlude: true, time: 0, end: 5, text: "", words: [], parent: null, background: false, oppositeTurn: false, estimated: false }];
        var out = Lyrics.synthesiseWords(lines);
        compare(out[0].words.length, 0);
        compare(out[0].estimated, false);
    }

    function test_synthesise_words_skips_a_merged_translation() {
        var lines = [{ time: 0, end: 3, text: "la\n(la)", words: [], parent: null, background: false, oppositeTurn: false, estimated: false }];
        var out = Lyrics.synthesiseWords(lines);
        compare(out[0].words.length, 0);
    }

    // mainLineIndices / nextMainLineStart / lineEndEstimate

    function test_main_line_indices_are_every_line_when_none_are_background() {
        var lines = [_line(1), _line(2)];
        compare(Lyrics.mainLineIndices(lines), [0, 1]);
    }

    function test_main_line_indices_skip_background_lines() {
        var lines = [_line(1), _backgroundLine(1.5, 2, 0), _line(3)];
        compare(Lyrics.mainLineIndices(lines), [0, 2]);
    }

    function test_main_line_indices_fall_back_to_every_line_when_all_are_background() {
        var lines = [_backgroundLine(1, 2, null), _backgroundLine(3, 4, null)];
        compare(Lyrics.mainLineIndices(lines), [0, 1]);
    }

    function test_next_main_line_start_of_the_last_main_line_is_undefined() {
        var lines = [_line(1), _line(2)];
        compare(Lyrics.nextMainLineStart(lines, Lyrics.mainLineIndices(lines), 1), undefined);
    }

    // A track switch republishes `lines` while a caller still holds a
    // `mainIndices` built from the longer, previous array (LyricsPane's
    // `_mainIndices` and `_activeIndex` are separate property bindings on
    // the same `lines`, observed going out of step for one evaluation
    // against a real MPRIS player in the VM rig). An index past the
    // current array is a stale read, not a corrupt one, so every one of
    // these skips it rather than indexing into `undefined`.
    function test_active_main_line_index_ignores_a_mainIndices_entry_past_the_current_lines() {
        var lines = [_line(1), _line(2)];
        var staleMain = [0, 1, 2, 5];
        compare(Lyrics.activeMainLineIndex(lines, staleMain, 2.5), 1);
    }

    function test_next_main_line_start_of_a_mainIndices_entry_past_the_current_lines_is_undefined() {
        var lines = [_line(1), _line(2)];
        compare(Lyrics.nextMainLineStart(lines, [0, 5], 0), undefined);
    }

    function test_background_line_bound_ignores_a_mainIndices_entry_past_the_current_lines() {
        var lines = [_line(1), _backgroundLine(1.5, null, 0)];
        compare(Lyrics.backgroundLineBound(lines, [0, 5], lines[1]), undefined);
    }

    function test_line_end_estimate_prefers_its_own_end() {
        compare(Lyrics.lineEndEstimate(_line(1, 4)), 4);
    }

    function test_line_end_estimate_falls_back_to_the_last_word() {
        var line = _line(1);
        line.words = [{ time: 1, text: "la", joinsNext: false }, { time: 2, text: "la", joinsNext: false }];
        compare(Lyrics.lineEndEstimate(line), 2 + Lyrics.WORD_FALLBACK_SECONDS);
    }

    function test_line_end_estimate_falls_back_to_the_assumed_tail() {
        compare(Lyrics.lineEndEstimate(_line(1)), 1 + Lyrics.LINE_ASSUMED_SECONDS);
    }

    // ledPosition

    function test_led_position_reads_ahead_of_the_player() {
        fuzzyCompare(Lyrics.ledPosition(10, 0), 10 + Lyrics.POSITION_LEAD_SECONDS, 1e-9);
    }

    function test_led_position_stacks_the_offset_on_the_lead() {
        fuzzyCompare(Lyrics.ledPosition(10, 0.25), 10 + Lyrics.POSITION_LEAD_SECONDS - 0.25, 1e-9);
        fuzzyCompare(Lyrics.ledPosition(10, -0.25), 10 + Lyrics.POSITION_LEAD_SECONDS + 0.25, 1e-9);
    }

    function test_led_position_without_an_offset_is_the_lead_alone() {
        fuzzyCompare(Lyrics.ledPosition(10, undefined), 10 + Lyrics.POSITION_LEAD_SECONDS, 1e-9);
    }

    function test_a_line_lights_a_lead_before_its_own_stamp() {
        var lines = [_line(10, 14), _line(14, 18)];
        var main = Lyrics.mainLineIndices(lines);

        compare(Lyrics.activeMainLineIndex(lines, main, Lyrics.ledPosition(9.95, 0)), 0);
        compare(Lyrics.activeMainLineIndex(lines, main, Lyrics.ledPosition(9.85, 0)), -1);
    }

    function test_a_chunk_is_already_wiping_at_its_own_stamp() {
        var words = [{ time: 5, text: "A" }, { time: 6, text: "B" }];
        fuzzyCompare(Lyrics.chunkProgress(words, 0, undefined, Lyrics.ledPosition(5, 0)),
            Lyrics.POSITION_LEAD_SECONDS, 1e-9);
    }

    function test_the_offset_key_can_hold_a_chunk_back_past_its_stamp() {
        var words = [{ time: 5, text: "A" }, { time: 6, text: "B" }];
        compare(Lyrics.chunkProgress(words, 0, undefined, Lyrics.ledPosition(5, 0.3)), 0);
    }

    // lineActiveAt / activeMainLineIndex / backgroundLineBound / activeSecondaryLines
    // (kopuz's own test cases, ported by name)

    function test_background_line_stays_lit_when_the_next_main_line_starts() {
        // The next main line begins while the previous one's backing
        // vocal is still running.
        var lines = [
            _line(63.167, 67.299),
            _backgroundLine(65.48, 67.299, 0),
            _line(66.236, 70.567)
        ];
        var main = Lyrics.mainLineIndices(lines);

        compare(Lyrics.activeMainLineIndex(lines, main, 66.5), 2);
        compare(Lyrics.activeSecondaryLines(lines, main, 66.5, 2), [0, 1]);
        compare(Lyrics.activeSecondaryLines(lines, main, 67.5, 2), []);
    }

    function test_background_line_stays_lit_after_its_parent_ends_with_no_main_line_active() {
        var lines = [
            _line(1, 2),
            _backgroundLine(1.5, 5, 0),
            _line(10, 12)
        ];
        var main = Lyrics.mainLineIndices(lines);

        compare(Lyrics.activeMainLineIndex(lines, main, 3), -1);
        compare(Lyrics.activeSecondaryLines(lines, main, 3, -1), [1]);
        compare(Lyrics.activeSecondaryLines(lines, main, 5.5, -1), []);
    }

    function test_untimed_background_line_runs_until_the_next_main_line() {
        var lines = [
            _line(1, 2),
            _backgroundLine(1.5, null, 0),
            _line(4, 6)
        ];
        var main = Lyrics.mainLineIndices(lines);

        compare(Lyrics.activeSecondaryLines(lines, main, 3, -1), [1]);
        compare(Lyrics.activeSecondaryLines(lines, main, 4.5, 2), []);
    }

    // displayLines (kopuz's build_display_lines, ported by name)

    function test_marks_intro_and_instrumental_gaps() {
        var lines = [_line(12, 15), _line(40, 43), _line(45, 48)];
        var display = Lyrics.displayLines(lines);

        compare(display.length, 5);
        compare(display.map(function (l) { return l.interlude === true; }), [true, false, true, false, false]);
        compare(display[0].time, 0);
        compare(display[0].end, 12);
        compare(display[2].time, 15);
        compare(display[2].end, 40);
    }

    function test_gap_starts_after_a_background_line_outlasts_its_parent() {
        var lines = [_line(1, 4), _backgroundLine(3, 9, 0), _line(30, 33)];
        var display = Lyrics.displayLines(lines);

        compare(display.map(function (l) { return l.interlude === true; }), [false, false, true, false]);
        compare(display[2].time, 9);
        compare(display[3].parent, null);
        compare(display[1].parent, 0);
    }

    function test_leaves_lyrics_untouched_without_a_long_gap() {
        var lines = [_line(1, 4), _line(5, 8)];
        var display = Lyrics.displayLines(lines);

        compare(display, lines);
        compare(display.map(function (l) { return l.interlude === true; }), [false, false]);
    }

    function test_untimed_lines_fall_back_to_an_assumed_tail() {
        var lines = [_line(0), _line(60)];
        var display = Lyrics.displayLines(lines);

        compare(display.map(function (l) { return l.interlude === true; }), [false, true, false]);
        compare(display[1].time, Lyrics.LINE_ASSUMED_SECONDS);
        compare(display[1].end, 60);
    }

    function test_display_lines_of_nothing_is_empty() {
        compare(Lyrics.displayLines([]).length, 0);
    }

    // The dark rule (owner, 2026-09-18): a run that ends four seconds before
    // the next line goes dark, since the seamless carry only reaches three,
    // and a dark pane has to carry the note. kopuz's own five-second
    // threshold would leave this one drawing nothing at all.
    function test_marks_a_gap_the_seamless_carry_cannot_hold() {
        var lines = [_line(1, 5), _line(9, 13)];
        var display = Lyrics.displayLines(lines);

        compare(display.map(function (l) { return l.interlude === true; }), [false, true, false]);
        compare(display[1].time, 5);
        compare(display[1].end, 9);
    }

    function test_leaves_a_gap_the_seamless_carry_holds() {
        var lines = [_line(1, 5), _line(8, 12)];
        compare(Lyrics.displayLines(lines).length, 2);
    }

    // The note lights exactly where the line before it goes dark, which is
    // the whole point of the rule: the two answers can never disagree.
    function test_a_marked_gap_starts_where_the_line_stops_being_lit() {
        var display = Lyrics.displayLines([_line(1, 5), _line(9, 13)]);
        var main = Lyrics.mainLineIndices(display);

        compare(Lyrics.activeMainLineIndex(display, main, 4.9), 0);
        compare(Lyrics.activeMainLineIndex(display, main, 5.1), 1);
        compare(display[1].interlude, true);
    }

    // Nothing is lit before the first line either, so a run-in past the
    // carry takes the note too.
    function test_marks_a_run_in_past_the_seamless_carry() {
        var display = Lyrics.displayLines([_line(4, 8)]);
        compare(display.map(function (l) { return l.interlude === true; }), [true, false]);
        compare(display[0].end, 4);
        compare(Lyrics.displayLines([_line(3, 8)]).length, 1);
    }

    // A run with no end of its own never goes dark (`lineActiveAt` holds it
    // to the next main line), so the dark rule has nothing to mark and only
    // kopuz's own threshold speaks.
    function test_a_run_with_no_end_takes_only_the_assumed_rule() {
        compare(Lyrics.displayLines([_line(1), _line(5)]).length, 2);

        var wide = Lyrics.displayLines([_line(1), _line(21)]);
        compare(wide.map(function (l) { return l.interlude === true; }), [false, true, false]);
        compare(wide[1].time, 1 + Lyrics.LINE_ASSUMED_SECONDS);
    }

    // Synthesised words are spread over the very estimate this reads, so
    // taking them as the line's end would close every instrumental gap on a
    // line-synced track to nothing and the note would never appear.
    function test_synthesised_words_do_not_stand_in_for_a_line_end() {
        var lines = Lyrics.synthesiseWords([_line(1, null, "one two three"), _line(21)]);
        compare(lines[0].estimated, true);
        compare(Lyrics.lineEndEstimate(lines[0]), 1 + Lyrics.LINE_ASSUMED_SECONDS);

        var display = Lyrics.displayLines(lines);
        compare(display.map(function (l) { return l.interlude === true; }), [false, true, false]);
        compare(display[1].time, 1 + Lyrics.LINE_ASSUMED_SECONDS);
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

    // A pane with room for nine rows under the anchor spends the same four
    // table entries over those nine, so the sixth row down is still readable
    // instead of sitting on the floor with three rows of the pane to spare.
    function test_depth_opacity_spreads_over_the_rows_that_fit() {
        compare(Lyrics.depthOpacity(3, 9), 0.7);
        compare(Lyrics.depthOpacity(6, 9), 0.45);
        compare(Lyrics.depthOpacity(9, 9), 0.25);
    }

    function test_depth_opacity_floors_at_the_end_of_its_span() {
        compare(Lyrics.depthOpacity(12, 9), 0.25);
    }

    function test_depth_opacity_of_a_shallow_pane_falls_faster() {
        compare(Lyrics.depthOpacity(1, 1.5), 0.45);
    }

    // rowSpans

    function test_row_spans_split_the_viewport_at_the_comfort_offset() {
        var spans = Lyrics.rowSpans(400, 40);
        compare(spans.above, 4.2);
        compare(spans.below, 5.8);
    }

    function test_row_spans_never_fall_under_one_row() {
        var spans = Lyrics.rowSpans(40, 40);
        compare(spans.above, 1);
        compare(spans.below, 1);
    }

    function test_row_spans_of_an_unmeasured_pane_are_one() {
        var spans = Lyrics.rowSpans(0, 0);
        compare(spans.above, 1);
        compare(spans.below, 1);
    }

    // edgeFraction

    function test_edge_fraction_clear_of_both_ends_is_one() {
        compare(Lyrics.edgeFraction(30, 20, 100), 1);
    }

    function test_edge_fraction_half_a_row_from_the_top_is_half() {
        compare(Lyrics.edgeFraction(10, 20, 100), 0.5);
    }

    function test_edge_fraction_half_a_row_from_the_bottom_is_half() {
        compare(Lyrics.edgeFraction(70, 20, 100), 0.5);
    }

    // The row the clip would cut is already gone: the ramp runs out as the
    // end of the viewport reaches the row, not as it crosses it.
    function test_edge_fraction_touching_an_end_is_zero() {
        compare(Lyrics.edgeFraction(0, 20, 100), 0);
        compare(Lyrics.edgeFraction(80, 20, 100), 0);
    }

    function test_edge_fraction_fully_out_above_is_zero() {
        compare(Lyrics.edgeFraction(-30, 20, 100), 0);
    }

    function test_edge_fraction_fully_out_below_is_zero() {
        compare(Lyrics.edgeFraction(110, 20, 100), 0);
    }

    function test_edge_fraction_of_a_zero_height_item_is_zero() {
        compare(Lyrics.edgeFraction(10, 0, 100), 0);
    }

    // blurFor

    function test_blur_for_of_the_anchor_is_zero() {
        compare(Lyrics.blurFor(0, 100), 0);
    }

    function test_blur_for_scales_by_distance_and_quantises() {
        compare(Lyrics.blurFor(2, 100), 2);
    }

    function test_blur_for_caps_before_scaling_by_strength() {
        compare(Lyrics.blurFor(10, 100), 6);
    }

    function test_blur_for_scales_by_strength_percent() {
        compare(Lyrics.blurFor(5, 50), 3);
    }

    function test_blur_for_of_zero_strength_is_zero() {
        compare(Lyrics.blurFor(5, 0), 0);
    }

    function test_blur_for_caps_at_the_end_of_its_own_span() {
        compare(Lyrics.blurFor(10, 100, 10), 6);
        compare(Lyrics.blurFor(5, 100, 10), 3);
    }

    // chunkRowBands

    function test_chunk_row_bands_of_an_unmeasured_chunk_cover_the_box() {
        var bands = Lyrics.chunkRowBands([], 20, 120);
        compare(bands.length, 1);
        compare(bands[0].top, 0);
        compare(bands[0].height, 20);
        compare(bands[0].width, 120);
    }

    // The bands tile the box: the first starts at its top whatever the
    // font's own first baseline offset is, and the last runs to its floor,
    // so no sliver of a glyph is left outside the mask.
    function test_chunk_row_bands_tile_the_whole_box() {
        var bands = Lyrics.chunkRowBands([
            { y: 2, height: 18, width: 300 },
            { y: 20, height: 18, width: 140 }
        ], 40, 320);
        compare(bands.length, 2);
        compare(bands[0].top, 0);
        compare(bands[0].height, 20);
        compare(bands[0].width, 300);
        compare(bands[1].top, 20);
        compare(bands[1].height, 20);
        compare(bands[1].width, 140);
    }

    // rowWipe

    function test_row_wipe_of_a_single_row_is_the_chunk_progress() {
        compare(Lyrics.rowWipe([{ top: 0, height: 20, width: 120 }], 0, 0.4), 0.4);
    }

    // Reading order across a break: the first row is finishing while the
    // second has not started, which is the whole defect.
    function test_row_wipe_finishes_a_row_before_the_next_one_starts() {
        var bands = [{ top: 0, height: 20, width: 300 }, { top: 20, height: 20, width: 100 }];
        compare(Lyrics.rowWipe(bands, 0, 0.5), 2 / 3);
        compare(Lyrics.rowWipe(bands, 1, 0.5), 0);
    }

    function test_row_wipe_starts_the_second_row_once_the_first_is_full() {
        var bands = [{ top: 0, height: 20, width: 300 }, { top: 20, height: 20, width: 100 }];
        compare(Lyrics.rowWipe(bands, 0, 0.75), 1);
        compare(Lyrics.rowWipe(bands, 1, 0.75), 0);
        compare(Lyrics.rowWipe(bands, 1, 0.875), 0.5);
    }

    // The edge travels at one speed over the chunk's whole ink, so a short
    // last row takes proportionally less of the chunk's own span than a full
    // one rather than an equal share of it.
    function test_row_wipe_weights_a_row_by_its_own_ink_width() {
        var bands = [{ top: 0, height: 20, width: 300 }, { top: 20, height: 20, width: 100 }];
        compare(Lyrics.rowWipe(bands, 0, 1), 1);
        compare(Lyrics.rowWipe(bands, 1, 1), 1);
        compare(Lyrics.rowWipe(bands, 0, 0), 0);
        compare(Lyrics.rowWipe(bands, 1, 0), 0);
    }

    function test_row_wipe_of_a_row_that_is_not_there_is_zero() {
        compare(Lyrics.rowWipe([{ top: 0, height: 20, width: 120 }], 3, 1), 0);
        compare(Lyrics.rowWipe([], 0, 1), 0);
    }

    // comfortY

    function test_comfort_y_rests_the_item_top_at_the_comfort_fraction() {
        compare(Lyrics.comfortY(200, 50, 30), 34);
    }

    function test_comfort_y_of_an_item_already_there_is_zero() {
        compare(Lyrics.comfortY(100, 42, 20), 0);
    }
}
