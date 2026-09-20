import QtQuick
import QtTest
import "../shell/Clipboard/urilist.js" as U
import "../shell/Clipboard/history.js" as H

TestCase {
    name: "ClipboardUriList"

    function test_one_local_png() {
        var f = U.imageFile("file:///home/k/Pictures/shot.png\r\n");
        compare(f.path, "/home/k/Pictures/shot.png");
        compare(f.uri, "file:///home/k/Pictures/shot.png");
        compare(f.png, true);
    }

    function test_percent_escapes_and_case() {
        var f = U.imageFile("file:///home/k/My%20Pictures/caf%C3%A9.JPG");
        compare(f.path, "/home/k/My Pictures/café.JPG");
        compare(f.png, false);
    }

    function test_host_and_comment_lines() {
        var f = U.imageFile("# copied\r\nfile://macbook/tmp/a.webp\r\n");
        compare(f.path, "/tmp/a.webp");
    }

    function test_leaked_nul_is_stripped() {
        compare(U.imageFile("\u0000file:///tmp/a.png").path, "/tmp/a.png");
    }

    function test_rejects_everything_else() {
        compare(U.imageFile("file:///tmp/a.png\r\nfile:///tmp/b.png\r\n"), null);
        compare(U.imageFile("https://example.com/a.png"), null);
        compare(U.imageFile("file:///tmp/notes.txt"), null);
        compare(U.imageFile("file:///tmp/noext"), null);
        compare(U.imageFile("file:///tmp/bad%ZZ.png"), null);
        compare(U.imageFile(""), null);
        compare(U.imageFile(undefined), null);
    }

    function test_drop_echo_takes_the_fresh_path_row() {
        var s = H.add(H.initialState(), { id: "a", text: "older" }, 1000).state;
        s = H.add(s, { id: "b", text: "/tmp/a.png\n" }, 2000).state;
        s = H.dropEcho(s, ["/tmp/a.png", "file:///tmp/a.png"], 2500, 5000);
        compare(s.items.length, 1);
        compare(s.items[0].text, "older");
    }

    function test_drop_echo_leaves_other_rows() {
        var s = H.add(H.initialState(), { id: "a", text: "/tmp/a.png" }, 1000).state;
        compare(H.dropEcho(s, ["/tmp/a.png"], 9000, 5000), s);
        s = H.add(s, { id: "b", text: "newer" }, 2000).state;
        compare(H.dropEcho(s, ["/tmp/a.png"], 2500, 5000), s);
        compare(H.dropEcho(H.initialState(), ["/tmp/a.png"], 0, 5000).items.length, 0);
    }
}
