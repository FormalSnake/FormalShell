import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Width-cap regression guard for the shared marquee
// (shell/Components/MarqueeText.qml) and for the composed active-window
// cell that embeds it (shell/Surfaces/Bar/widgets/ActiveWindow.qml).
//
// The real Theme singleton is a Quickshell Singleton, so these run against
// tests/stubs/qs/Core/Theme.qml (same palette.js/tokens.js values) via
// qmltestrunner's -import, wired up in the justfile/flake test calls.
// Expected widths come from a reference Text measured with the same font,
// never from literal pixel counts: monospace resolves to a different face
// per host, and only the arithmetic around the measurement is under test.
TestCase {
    id: testCase
    name: "MarqueeText"
    width: 600
    height: 200
    visible: true
    when: windowShown

    readonly property string shortText: "kitty"
    readonly property string longText: "MarqueeText Overflow Verification Window Title That Does Not Fit"

    Component {
        id: marqueeComponent

        Item {
            id: wrapper

            property string label: ""
            property real cap: 200
            property real inset: 0

            readonly property Item probeMarquee: marquee
            readonly property Item probeRef: reference

            MarqueeText {
                id: marquee
                text: wrapper.label
                maxWidth: wrapper.cap
                leftPadding: wrapper.inset
            }

            Text {
                id: reference
                visible: false
                text: wrapper.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize.body
            }
        }
    }

    // ActiveWindow.qml's Row, structurally verbatim: a glyph-sized icon, the
    // app name, and the title marquee handed whatever budget the first two
    // leave. The widget caps its own implicitWidth at maxWidth and clips, so
    // any overshoot here is a silently cut label on the real bar.
    Component {
        id: activeWindowRowComponent

        Item {
            id: cell

            property real maxWidth: 260
            property string appName: ""
            property string title: ""

            readonly property Item probeRow: row
            readonly property Item probeName: primaryText
            readonly property Item probeTitle: titleText

            implicitWidth: Math.min(row.implicitWidth, cell.maxWidth)
            implicitHeight: row.implicitHeight
            clip: true

            Row {
                id: row
                spacing: Theme.space.xxs

                Rectangle {
                    id: appIcon
                    width: primaryText.implicitHeight
                    height: primaryText.implicitHeight
                    color: "#808080"
                }

                Text {
                    id: primaryText
                    text: cell.appName
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.body
                    width: Math.min(implicitWidth, cell.maxWidth * 0.5)
                    elide: Text.ElideRight
                }

                MarqueeText {
                    id: titleText
                    text: cell.title
                    leftPadding: Theme.space.md
                    maxWidth: {
                        var used = 0;
                        if (appIcon.visible)
                            used += appIcon.width + row.spacing;
                        if (primaryText.visible)
                            used += primaryText.width + row.spacing;
                        return Math.max(0, cell.maxWidth - used);
                    }
                }
            }
        }
    }

    function settle(item) {
        waitForRendering(item);
        wait(50);
    }

    function test_marquee_hugs_text_that_fits() {
        failOnWarning(/Binding loop/);
        var w = createTemporaryObject(marqueeComponent, testCase, {
            label: testCase.shortText,
            cap: 400,
            inset: 6
        });
        verify(w);
        settle(w);

        // Under the cap the item is exactly its inset plus its text, so the
        // bar's other widgets sit right against it instead of a padded slot.
        verify(w.probeRef.implicitWidth + 6 < 400);
        compare(w.probeMarquee.width, 6 + w.probeRef.implicitWidth);
        compare(w.probeMarquee.height, w.probeRef.implicitHeight);
    }

    function test_marquee_counts_its_left_padding_inside_the_cap() {
        failOnWarning(/Binding loop/);
        var w = createTemporaryObject(marqueeComponent, testCase, {
            label: testCase.longText,
            cap: 180,
            inset: 6
        });
        verify(w);
        settle(w);

        // The bug this pins: leftPadding used to be added on top of maxWidth,
        // so an overflowing title reported maxWidth + leftPadding and lost
        // its trailing pixels (the ellipsis itself, motion disabled) to the
        // embedding cell's clip.
        verify(w.probeRef.implicitWidth > 180);
        compare(w.probeMarquee.width, 180);
    }

    function test_marquee_cap_holds_without_left_padding() {
        failOnWarning(/Binding loop/);
        var w = createTemporaryObject(marqueeComponent, testCase, {
            label: testCase.longText,
            cap: 220
        });
        verify(w);
        settle(w);

        compare(w.probeMarquee.width, 220);
    }

    function test_active_window_row_stays_inside_its_budget() {
        failOnWarning(/Binding loop/);
        var cell = createTemporaryObject(activeWindowRowComponent, testCase, {
            appName: "Ghostty",
            title: testCase.longText
        });
        verify(cell);
        settle(cell);

        // Icon, name and title together fill the budget exactly. Anything
        // over it is drawn and then clipped away, which is what the widget's
        // own `clip: true` was quietly hiding.
        compare(cell.probeRow.implicitWidth, 260);
        compare(cell.implicitWidth, 260);
        verify(cell.probeTitle.width > 0);
    }

    function test_active_window_row_elides_a_long_app_name() {
        failOnWarning(/Binding loop/);
        var cell = createTemporaryObject(activeWindowRowComponent, testCase, {
            appName: "An Application Whose Desktop Entry Name Runs Very Long Indeed",
            title: testCase.longText
        });
        verify(cell);
        settle(cell);

        // The name gives up at half the cell rather than consuming the whole
        // budget, so the title still has room to scroll in and the name
        // itself ends in an ellipsis instead of a cut glyph.
        compare(cell.probeName.width, 130);
        verify(cell.probeName.truncated);
        verify(cell.probeTitle.width > 0);
        compare(cell.probeRow.implicitWidth, 260);
    }
}
