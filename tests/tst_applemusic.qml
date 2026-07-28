import QtQuick
import QtTest
import "../shell/Media/applemusic.js" as AppleMusic

TestCase {
    name: "AppleMusic"

    // cacheKey / cachePath

    function test_cache_key_lowercases_and_dashes() {
        compare(AppleMusic.cacheKey("The Beatles", "Abbey Road"), "the-beatles-abbey-road");
    }

    function test_cache_key_strips_punctuation() {
        compare(AppleMusic.cacheKey("Sigur Rós", "( )"), "sigur-r-s");
    }

    function test_cache_path_appends_mp4_under_dir() {
        compare(AppleMusic.cachePath("/cache/applemusic-art", "Air", "Moon Safari"), "/cache/applemusic-art/air-moon-safari.mp4");
    }

    // searchUrl

    function test_search_url_targets_itunes_album_search() {
        var url = AppleMusic.searchUrl("Air", "Moon Safari");
        verify(url.indexOf("https://itunes.apple.com/search?") === 0);
        verify(url.indexOf("media=music") >= 0);
        verify(url.indexOf("entity=album") >= 0);
        verify(url.indexOf("term=Air%20Moon%20Safari") >= 0);
    }

    function test_search_url_null_without_artist() {
        compare(AppleMusic.searchUrl("", "Moon Safari"), null);
    }

    function test_search_url_null_without_album() {
        compare(AppleMusic.searchUrl("Air", ""), null);
    }

    // parseSearchResult — a hit, a miss, malformed, http error

    function test_parse_search_result_hit_returns_collection_id() {
        var r = AppleMusic.parseSearchResult(0, JSON.stringify({ results: [{ collectionId: 1440833449 }] }));
        compare(r.ok, true);
        compare(r.collectionId, 1440833449);
    }

    function test_parse_search_result_miss_no_results() {
        var r = AppleMusic.parseSearchResult(0, JSON.stringify({ results: [] }));
        compare(r.ok, true);
        compare(r.collectionId, null);
    }

    function test_parse_search_result_malformed_json() {
        var r = AppleMusic.parseSearchResult(0, "not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    function test_parse_search_result_http_error_on_nonzero_exit() {
        var r = AppleMusic.parseSearchResult(1, "");
        compare(r.ok, false);
        compare(r.error, "http_error");
    }

    // albumPageUrl / extractAssetPath / extractToken

    function test_album_page_url() {
        compare(AppleMusic.albumPageUrl(1440833449), "https://music.apple.com/us/album/1440833449");
    }

    function test_extract_asset_path_finds_hashed_bundle() {
        var html = '<script src="/assets/index~a1B2c3.js" defer></script>';
        compare(AppleMusic.extractAssetPath(html), "/assets/index~a1B2c3.js");
    }

    function test_extract_asset_path_null_when_absent() {
        compare(AppleMusic.extractAssetPath("<html></html>"), null);
    }

    function test_extract_token_finds_jwt_looking_string() {
        var js = 'const t="eyJhbGciOiJFUzI1NiJ9.abc-def_123.sig";';
        compare(AppleMusic.extractToken(js), "eyJhbGciOiJFUzI1NiJ9.abc-def_123.sig");
    }

    function test_extract_token_null_when_absent() {
        compare(AppleMusic.extractToken("const t=1;"), null);
    }

    // ampApiUrl

    function test_amp_api_url_requests_editorial_video_extension() {
        var url = AppleMusic.ampApiUrl(1440833449);
        compare(url, "https://amp-api.music.apple.com/v1/catalog/us/albums/1440833449?extend=editorialVideo");
    }

    // parseEditorialVideo — a hit, a miss, malformed, http error

    function test_parse_editorial_video_hit_prefers_motion_detail_square() {
        var body = JSON.stringify({ data: [{ attributes: { editorialVideo: {
            motionDetailSquare: { video: "https://a.example/detail.m3u8" },
            motionSquareVideo1x1: { video: "https://a.example/square.m3u8" }
        } } }] });
        var r = AppleMusic.parseEditorialVideo(0, body);
        compare(r.ok, true);
        compare(r.videoUrl, "https://a.example/detail.m3u8");
    }

    function test_parse_editorial_video_hit_falls_back_to_square_1x1() {
        var body = JSON.stringify({ data: [{ attributes: { editorialVideo: {
            motionSquareVideo1x1: { video: "https://a.example/square.m3u8" }
        } } }] });
        var r = AppleMusic.parseEditorialVideo(0, body);
        compare(r.ok, true);
        compare(r.videoUrl, "https://a.example/square.m3u8");
    }

    function test_parse_editorial_video_miss_no_editorial_video_field() {
        var body = JSON.stringify({ data: [{ attributes: {} }] });
        var r = AppleMusic.parseEditorialVideo(0, body);
        compare(r.ok, true);
        compare(r.videoUrl, "");
    }

    function test_parse_editorial_video_miss_empty_video_fields() {
        var body = JSON.stringify({ data: [{ attributes: { editorialVideo: {} } }] });
        var r = AppleMusic.parseEditorialVideo(0, body);
        compare(r.ok, true);
        compare(r.videoUrl, "");
    }

    function test_parse_editorial_video_malformed_json() {
        var r = AppleMusic.parseEditorialVideo(0, "not json{{{");
        compare(r.ok, false);
        compare(r.error, "malformed_json");
    }

    function test_parse_editorial_video_missing_data_array() {
        var r = AppleMusic.parseEditorialVideo(0, JSON.stringify({}));
        compare(r.ok, false);
        compare(r.error, "missing_fields");
    }

    function test_parse_editorial_video_http_error_on_nonzero_exit() {
        var r = AppleMusic.parseEditorialVideo(1, "");
        compare(r.ok, false);
        compare(r.error, "http_error");
    }

    // resolveUrl

    function test_resolve_url_passes_through_absolute() {
        compare(AppleMusic.resolveUrl("https://a.example/x.mp4", "https://a.example/base/master.m3u8"), "https://a.example/x.mp4");
    }

    function test_resolve_url_joins_relative_to_base_directory() {
        compare(AppleMusic.resolveUrl("hi/rendition.m3u8", "https://a.example/base/master.m3u8"), "https://a.example/base/hi/rendition.m3u8");
    }

    // pickVariant

    function _master(lines) {
        return lines.join("\n");
    }

    function test_pick_variant_selects_highest_bandwidth_avc1_under_768() {
        var master = _master([
            "#EXTM3U",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=500000,RESOLUTION=320x320,CODECS=\"avc1.640015\"",
            "low/index.m3u8",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2000000,RESOLUTION=640x640,CODECS=\"avc1.640028\"",
            "high/index.m3u8"
        ]);
        compare(AppleMusic.pickVariant(master), "high/index.m3u8");
    }

    function test_pick_variant_skips_resolutions_above_768() {
        var master = _master([
            "#EXTM3U",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=500000,RESOLUTION=320x320,CODECS=\"avc1.640015\"",
            "low/index.m3u8",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=9000000,RESOLUTION=1080x1080,CODECS=\"avc1.640028\"",
            "huge/index.m3u8"
        ]);
        compare(AppleMusic.pickVariant(master), "low/index.m3u8");
    }

    function test_pick_variant_skips_non_avc1_codecs() {
        var master = _master([
            "#EXTM3U",
            "#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2000000,RESOLUTION=640x640,CODECS=\"hvc1.1.6.L93.90\"",
            "hevc/index.m3u8"
        ]);
        compare(AppleMusic.pickVariant(master), null);
    }

    function test_pick_variant_null_on_empty_master() {
        compare(AppleMusic.pickVariant(""), null);
    }

    // extractMp4Url

    function test_extract_mp4_url_resolves_relative_map_uri() {
        var rendition = _master([
            "#EXTM3U",
            "#EXT-X-MAP:URI=\"segment0.mp4\",BYTERANGE=\"800@0\"",
            "#EXT-X-BYTERANGE:200000@800",
            "seg.mp4"
        ]);
        compare(AppleMusic.extractMp4Url(rendition, "https://a.example/base/hi/index.m3u8"), "https://a.example/base/hi/segment0.mp4");
    }

    function test_extract_mp4_url_null_without_map_tag() {
        compare(AppleMusic.extractMp4Url("#EXTM3U\nseg.mp4", "https://a.example/base/hi/index.m3u8"), null);
    }

    // isStale / parsePruneListing — prune boundary conditions

    function test_is_stale_false_at_exact_boundary() {
        var now = Date.UTC(2026, 6, 28);
        var mtime = now - 30 * 24 * 60 * 60 * 1000;
        compare(AppleMusic.isStale(mtime, now, 30), false);
    }

    function test_is_stale_true_one_ms_past_boundary() {
        var now = Date.UTC(2026, 6, 28);
        var mtime = now - 30 * 24 * 60 * 60 * 1000 - 1;
        compare(AppleMusic.isStale(mtime, now, 30), true);
    }

    function test_is_stale_false_for_fresh_file() {
        var now = Date.UTC(2026, 6, 28);
        compare(AppleMusic.isStale(now - 60000, now, 30), false);
    }

    function test_is_stale_false_for_non_numeric_mtime() {
        compare(AppleMusic.isStale(undefined, Date.now(), 30), false);
    }

    function test_parse_prune_listing_returns_only_stale_paths() {
        var now = Date.UTC(2026, 6, 28) / 1000;
        var fresh = now - 60;
        var stale = now - 31 * 24 * 60 * 60;
        var listing = fresh + " /cache/applemusic-art/fresh-album.mp4\n"
            + stale + " /cache/applemusic-art/stale-album.mp4\n";
        var result = AppleMusic.parsePruneListing(listing, now * 1000, 30);
        compare(result.length, 1);
        compare(result[0], "/cache/applemusic-art/stale-album.mp4");
    }

    function test_parse_prune_listing_skips_malformed_lines() {
        var result = AppleMusic.parsePruneListing("not-a-valid-line\n\nabc /bad/epoch.mp4\n", Date.now(), 30);
        compare(result.length, 0);
    }

    function test_parse_prune_listing_empty_for_empty_text() {
        compare(AppleMusic.parsePruneListing("", Date.now(), 30).length, 0);
    }
}
