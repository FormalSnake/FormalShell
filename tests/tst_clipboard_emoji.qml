import QtQuick
import QtTest
import "../shell/Clipboard/emoji.js" as E

TestCase {
    name: "ClipboardEmoji"

    function test_single_emoji_data() {
        return [
            { tag: "face", text: "😂" },
            { tag: "vs16 heart", text: "❤️" },
            { tag: "rose", text: "🌹" },
            { tag: "default emoji bmp", text: "✅" },
            { tag: "skin tone", text: "👍🏽" },
            { tag: "zwj family", text: "👨‍👩‍👧‍👦" },
            { tag: "zwj couple with vs16 heart", text: "👩‍❤️‍👨" },
            { tag: "zwj skin toned", text: "🧑🏿‍💻" },
            { tag: "rainbow flag", text: "🏳️‍🌈" },
            { tag: "country flag", text: "🇧🇪" },
            { tag: "subdivision flag", text: "🏴󠁧󠁢󠁳󠁣󠁴󠁿" },
            { tag: "keycap", text: "1️⃣" },
            { tag: "keycap without vs16", text: "#⃣" },
            { tag: "surrounding whitespace", text: "  😂\n" }
        ];
    }

    function test_single_emoji(data) {
        compare(E.emojiCount(data.text), 1);
        verify(E.isEmojiOnly(data.text));
    }

    function test_runs_count_clusters() {
        compare(E.emojiCount("😂😂"), 2);
        compare(E.emojiCount("🇧🇪🇳🇱"), 2);
        compare(E.emojiCount("❤️ 🌹 👍🏽"), 3);
        compare(E.emojiCount("👨‍👩‍👧‍👦👍🏽"), 2);
    }

    function test_not_emoji_only_data() {
        return [
            { tag: "empty", text: "" },
            { tag: "whitespace", text: "   " },
            { tag: "letter then emoji", text: "a😂" },
            { tag: "emoji then word", text: "😂 lol" },
            { tag: "plain digits", text: "123" },
            { tag: "one digit", text: "7" },
            { tag: "hash", text: "#" },
            { tag: "text heart", text: "❤" },
            { tag: "copyright", text: "©" },
            { tag: "text presentation", text: "😂︎" },
            { tag: "lone regional indicator", text: "🇧" },
            { tag: "dangling zwj", text: "👨‍" },
            { tag: "bare vs16", text: "️" },
            { tag: "cjk", text: "漢字" },
            { tag: "url", text: "https://example.com/😂" }
        ];
    }

    function test_not_emoji_only(data) {
        compare(E.emojiCount(data.text), 0);
        verify(!E.isEmojiOnly(data.text));
    }

    function test_long_runs_read_as_text() {
        var run = "";
        for (var i = 0; i < E.MAX_CLUSTERS - 1; i++) run += "😂";
        compare(E.emojiCount(run), E.MAX_CLUSTERS - 1);
        compare(E.emojiCount(run + "😂"), 0);
    }

    function test_non_string() {
        compare(E.emojiCount(undefined), 0);
        compare(E.emojiCount(null), 0);
    }
}
