use fs_menu::clipboard::emoji::{MAX_CLUSTERS, emoji_count, is_emoji_only};

#[test]
fn single_emoji() {
    let cases = [
        ("face", "\u{1F602}"),
        ("vs16 heart", "\u{2764}\u{FE0F}"),
        ("rose", "\u{1F339}"),
        ("default emoji bmp", "\u{2705}"),
        ("skin tone", "\u{1F44D}\u{1F3FD}"),
        ("zwj family", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"),
        ("zwj couple with vs16 heart", "\u{1F469}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F468}"),
        ("zwj skin toned", "\u{1F9D1}\u{1F3FF}\u{200D}\u{1F4BB}"),
        ("rainbow flag", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"),
        ("country flag", "\u{1F1E7}\u{1F1EA}"),
        ("subdivision flag", "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"),
        ("keycap", "1\u{FE0F}\u{20E3}"),
        ("keycap without vs16", "#\u{20E3}"),
        ("surrounding whitespace", "  \u{1F602}\n"),
    ];
    for (tag, text) in cases {
        assert_eq!(emoji_count(text), 1, "{tag}");
        assert!(is_emoji_only(text), "{tag}");
    }
}

#[test]
fn runs_count_clusters() {
    assert_eq!(emoji_count("\u{1F602}\u{1F602}"), 2);
    assert_eq!(emoji_count("\u{1F1E7}\u{1F1EA}\u{1F1F3}\u{1F1F1}"), 2);
    assert_eq!(emoji_count("\u{2764}\u{FE0F} \u{1F339} \u{1F44D}\u{1F3FD}"), 3);
    assert_eq!(
        emoji_count("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}\u{1F44D}\u{1F3FD}"),
        2
    );
}

#[test]
fn not_emoji_only() {
    let cases = [
        ("empty", ""),
        ("whitespace", "   "),
        ("letter then emoji", "a\u{1F602}"),
        ("emoji then word", "\u{1F602} lol"),
        ("plain digits", "123"),
        ("one digit", "7"),
        ("hash", "#"),
        ("text heart", "\u{2764}"),
        ("copyright", "\u{A9}"),
        ("text presentation", "\u{1F602}\u{FE0E}"),
        ("lone regional indicator", "\u{1F1E7}"),
        ("dangling zwj", "\u{1F468}\u{200D}"),
        ("bare vs16", "\u{FE0F}"),
        ("cjk", "\u{6F22}\u{5B57}"),
        ("url", "https://example.com/\u{1F602}"),
    ];
    for (tag, text) in cases {
        assert_eq!(emoji_count(text), 0, "{tag}");
        assert!(!is_emoji_only(text), "{tag}");
    }
}

#[test]
fn long_runs_read_as_text() {
    let run = "\u{1F602}".repeat(MAX_CLUSTERS - 1);
    assert_eq!(emoji_count(&run), MAX_CLUSTERS - 1);
    assert_eq!(emoji_count(&format!("{run}\u{1F602}")), 0);
}
