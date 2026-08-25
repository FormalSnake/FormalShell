import QtQuick
import QtTest
import "../shell/Surfaces/Osd/icon.js" as OsdIcon

// M44 D5: which Icon the OSD pill draws. The names all have to exist in
// both sets, which tst_icons.qml asserts separately.
TestCase {
    name: "OsdIcon"

    function test_brightness_is_the_sun_whatever_the_sink_is_doing() {
        compare(OsdIcon.iconName("brightness", 0.9, false), "sun");
        compare(OsdIcon.iconName("brightness", 0, true), "sun");
    }

    function test_media_is_the_note() {
        compare(OsdIcon.iconName("media", 0.5, false), "music");
    }

    function test_volume_steps_at_half() {
        compare(OsdIcon.iconName("volume", 0.49, false), "volume-1");
        compare(OsdIcon.iconName("volume", 0.5, false), "volume-2");
        compare(OsdIcon.iconName("volume", 1, false), "volume-2");
    }

    function test_silence_and_mute_both_draw_the_crossed_speaker() {
        compare(OsdIcon.iconName("volume", 0, false), "volume-x");
        compare(OsdIcon.iconName("volume", 0.8, true), "volume-x");
    }

    // AudioService reports no sink as volume 0 with muted false, and an
    // unbound node can answer undefined; neither may fall through to a
    // speaker icon that claims sound is coming out.
    function test_an_absent_sink_is_not_drawn_as_audible() {
        compare(OsdIcon.iconName("volume", undefined, false), "volume-x");
        compare(OsdIcon.iconName("", 0, false), "volume-x");
    }
}
