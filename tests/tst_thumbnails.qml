import QtQuick
import QtTest
import "../shell/Services/thumbnails.js" as Thumbs
import "../shell/Menu/providers.js" as Providers

// The wallpaper picker's prerendered thumbnail cache (ThumbnailService).
// The service itself is side-effect orchestration around one ffmpeg fleet;
// everything that has to be right lives in thumbnails.js, because the same
// derivation runs in two places that never talk to each other — the service
// spawning the generator and the grid delegate reading the result — and a
// disagreement between them shows up as the wrong picture in a cell rather
// than as an error anywhere.
TestCase {
    name: "Thumbnails"

    readonly property string dir: "/home/u/.cache/formalshell/thumbnails"
    readonly property int size: 512

    function test_the_same_path_always_derives_the_same_name() {
        var a = Thumbs.cacheFileName("/pics/Dark/aurora.jpg", size);
        var b = Thumbs.cacheFileName("/pics/Dark/aurora.jpg", size);
        compare(a, b);
    }

    // Same basename under a different directory is the case the grid would
    // get visibly wrong: Dark/aurora.jpg and Light/aurora.jpg are two
    // different pictures.
    function test_same_basename_in_two_directories_derives_two_names() {
        var dark = Thumbs.cacheFileName("/pics/Dark/aurora.jpg", size);
        var light = Thumbs.cacheFileName("/pics/Light/aurora.jpg", size);
        verify(dark !== light);
    }

    function test_the_size_is_part_of_the_name() {
        verify(Thumbs.cacheFileName("/pics/a.jpg", 512) !== Thumbs.cacheFileName("/pics/a.jpg", 256));
    }

    // Two modes of one picture are two files. A caller asking for the
    // letterboxed copy must never be handed the square crop, which is the
    // one way this cache could show the wrong pixels rather than none.
    function test_the_mode_is_part_of_the_name() {
        var cover = Thumbs.cacheFileName("/pics/a.jpg", size, "cover");
        var fit = Thumbs.cacheFileName("/pics/a.jpg", size, "fit");
        verify(cover !== fit);
        verify(cover.indexOf("cover") >= 0);
        verify(fit.indexOf("fit") >= 0);
    }

    // Anything that is not "fit" is the square crop the picker has always
    // used, so an old call site that passes no mode keeps its files.
    function test_an_absent_or_unknown_mode_is_cover() {
        var plain = Thumbs.cacheFileName("/pics/a.jpg", size);
        compare(plain, Thumbs.cacheFileName("/pics/a.jpg", size, "cover"));
        compare(plain, Thumbs.cacheFileName("/pics/a.jpg", size, "nonsense"));
        compare(Thumbs.normalizeMode(undefined), "cover");
        compare(Thumbs.normalizeMode("fit"), "fit");
    }

    // The key is what a fanned-out directory actually stresses: hundreds of
    // paths sharing a long prefix and differing late.
    function test_no_collisions_across_a_fanned_out_directory() {
        var seen = {};
        for (var i = 0; i < 2000; i++) {
            var key = Thumbs.pathKey("/home/u/Pictures/Wallpapers/Dark/wallpaper-" + i + ".jpg");
            verify(seen[key] === undefined, "collision at " + i);
            seen[key] = true;
        }
    }

    function test_the_key_is_64_bits_of_lowercase_hex() {
        var key = Thumbs.pathKey("/pics/a.jpg");
        compare(key.length, 16);
        verify(/^[0-9a-f]{16}$/.test(key));
    }

    // A cache filename is one path component: anything that could open a
    // second directory level, escape the cache dir, or overrun a filesystem's
    // per-component limit has to be gone by the time it is written.
    function test_the_name_is_a_single_safe_path_component() {
        var name = Thumbs.cacheFileName("/pics/../../etc/we ird/na:me*with?junk.png", size);
        verify(name.indexOf("/") < 0);
        verify(name.indexOf(" ") < 0);
        verify(name.indexOf("..") < 0);
        verify(name.length < 100);
        verify(/\.jpg$/.test(name));
    }

    function test_a_pathological_basename_is_capped() {
        var long = "";
        for (var i = 0; i < 400; i++)
            long += "x";
        verify(Thumbs.cacheFileName("/pics/" + long + ".jpg", size).length < 100);
    }

    function test_a_dotfile_keeps_its_whole_name_as_the_stem() {
        verify(Thumbs.cacheFileName("/pics/.hidden", size).indexOf(".hidden") === 0);
    }

    function test_cache_path_joins_without_doubling_the_separator() {
        var a = Thumbs.cachePath("/cache/", "/pics/a.jpg", size);
        var b = Thumbs.cachePath("/cache", "/pics/a.jpg", size);
        compare(a, b);
        verify(a.indexOf("/cache/") === 0);
        verify(a.indexOf("//") < 0);
    }

    // The generator walks argv two at a time, so the flattening and the path
    // the grid reads back have to be the same function.
    function test_warm_args_flatten_src_dst_pairs() {
        var args = Thumbs.warmArgs(dir, ["/pics/a.jpg", "/pics/b.png"], size, "fit");
        compare(args.length, 4);
        compare(args[0], "/pics/a.jpg");
        compare(args[1], Thumbs.cachePath(dir, "/pics/a.jpg", size, "fit"));
        compare(args[2], "/pics/b.png");
        compare(args[3], Thumbs.cachePath(dir, "/pics/b.png", size, "fit"));
        verify(args[1].indexOf("fit") >= 0);
    }

    function test_warm_args_of_nothing_is_nothing() {
        compare(Thumbs.warmArgs(dir, [], size).length, 0);
        compare(Thumbs.warmArgs(dir, null, size).length, 0);
    }

    // Not a shell test — it can't be, from here — but the four properties
    // the script's whole design rests on are cheap to assert and expensive
    // to lose in an edit: it never blocks on stdin, it culls its own leftover
    // part files, it rebuilds only what the source outdates, and it swallows
    // a missing ffmpeg instead of failing the warm.
    function test_the_generator_keeps_its_contract() {
        var script = Thumbs.warmScript(4);
        verify(script.indexOf("-nostdin") >= 0);
        verify(script.indexOf('-name "*.part.jpg"') >= 0);
        verify(script.indexOf('-nt "$dst"') >= 0);
        verify(script.indexOf("|| { rm -f \"$tmp\"; exit 0; }") >= 0);
        verify(script.indexOf("-P 4") >= 0);
        // Both crops, picked by $mode rather than by two scripts.
        verify(script.indexOf("force_original_aspect_ratio=increase") >= 0);
        verify(script.indexOf("force_original_aspect_ratio=decrease") >= 0);
        // fit must not enlarge a source already smaller than the box.
        verify(script.indexOf("min(iw,$size)") >= 0);
        // An empty listing must not reach ffmpeg with unset positionals.
        verify(script.indexOf("xargs -0 -r") >= 0);
    }

    function test_concurrency_never_reaches_xargs_as_zero() {
        verify(Thumbs.warmScript(0).indexOf("-P 1") >= 0);
    }

    // The scan the picker route runs on entry and the scan the cache warms
    // off at startup are the same command, which is the only reason the two
    // can't disagree about what is in the directory.
    function test_the_picker_scan_is_one_shared_command() {
        var cmd = Providers.pickerScanCommand("/pics");
        compare(cmd[0], "sh");
        compare(cmd[1], "-c");
        compare(cmd[cmd.length - 1], "/pics");
        verify(cmd[2].indexOf("-maxdepth 1") >= 0);
        verify(cmd[2].indexOf('"$1/Dark"') >= 0);
        verify(cmd[2].indexOf('"$1/light"') >= 0);
        verify(cmd[2].indexOf("sort -u") >= 0);
        ["png", "jpg", "jpeg", "webp", "bmp"].forEach(function (ext) {
            verify(cmd[2].indexOf('-iname "*.' + ext + '"') >= 0, ext + " missing");
        });
    }
}
