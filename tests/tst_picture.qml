import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Picture's contract (M49 D3, shell/Components/Picture.qml): a plain `Image`
// with the dither layer loaded only while `theme.dither` is on, so a surface
// reaches for this instead of branching on the knob itself. The stub Theme
// carries the metamorphosis preset's own table, where `dither` is off,
// which is the case asserted here: the Loader stays inactive, nothing
// constructs a DitherImage, and the image renders exactly as a bare
// `Image` would. The on path needs a real Theme reading a settings file,
// so it is proven in the
// rig's `--retro` runs rather than here.
TestCase {
    id: testCase
    name: "Picture"
    width: 200
    height: 200
    visible: true
    when: windowShown

    // 4x4 solid white, inline so the test needs no external file.
    readonly property string whiteSource: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQAAAACBiqPTAAAADElEQVQI12P4wACGAA8IA8FeW+PBAAAAAElFTkSuQmCC"

    Component {
        id: pictureComponent

        Picture {
            width: 40
            height: 40
        }
    }

    function make(props) {
        var picture = createTemporaryObject(pictureComponent, testCase, props);
        verify(picture);
        waitForRendering(picture);
        return picture;
    }

    // The Loader is the one child carrying `sourceComponent`; the Image does
    // not.
    function loaderOf(picture) {
        for (var i = 0; i < picture.children.length; i++) {
            if (picture.children[i].sourceComponent !== undefined)
                return picture.children[i];
        }
        return null;
    }

    function imageOf(picture) {
        for (var i = 0; i < picture.children.length; i++) {
            var child = picture.children[i];
            if (child.sourceComponent === undefined && child.fillMode !== undefined)
                return child;
        }
        return null;
    }

    function test_the_dither_layer_is_absent_while_the_knob_is_off() {
        compare(Theme.dither, false);
        var picture = make({ source: testCase.whiteSource });
        var loader = loaderOf(picture);
        verify(loader);
        compare(loader.active, false);
        verify(!loader.item);

        // Nothing under the component is a DitherImage: `painted` is the
        // member only that component carries.
        for (var i = 0; i < picture.children.length; i++)
            verify(picture.children[i].painted === undefined);
    }

    // With no dither layer to hand over to, the plain image is what draws.
    function test_the_image_draws_while_the_knob_is_off() {
        var picture = make({ source: testCase.whiteSource });
        var img = imageOf(picture);
        verify(img);
        verify(img.visible);
        compare(String(img.source), String(picture.source));
    }

    function test_the_defaults_are_a_plain_fitted_image() {
        var picture = make({});
        var img = imageOf(picture);
        compare(picture.fillMode, Image.PreserveAspectFit);
        compare(img.fillMode, Image.PreserveAspectFit);
        compare(img.cache, true);
        compare(img.asynchronous, true);
        compare(img.smooth, true);
    }

    // The decode cap every caller sets reaches the Image itself, or a
    // multi-MB source would decode at full resolution for an icon slot.
    function test_source_size_round_trips_to_the_image() {
        var picture = make({ source: testCase.whiteSource });
        var slot = Theme.space.controlHeight;
        picture.sourceSize = Qt.size(slot, slot);
        var img = imageOf(picture);
        compare(img.sourceSize.width, slot);
        compare(img.sourceSize.height, slot);
        compare(picture.sourceSize.width, slot);
        compare(picture.sourceSize.height, slot);
    }

    // The Image starts its load inside its own setSource, so a themed icon
    // is only kept off the pixmap reader thread if `asynchronous` has
    // already gone false by the time the Image emits sourceChanged. Checked
    // on each way into a themed source a bar cell takes: from nothing, from
    // a file, and from one themed icon to another.
    function test_a_themed_source_is_synchronous_before_it_loads() {
        var picture = make({});
        var img = imageOf(picture);
        var seen = [];
        img.sourceChanged.connect(function () {
            seen.push(String(img.source) + " " + img.asynchronous);
        });
        var steps = [
            "image://icon/firefox",
            testCase.whiteSource,
            "image://icon/kitty",
            "",
            "image://icon/org.gnome.Nautilus",
            "image://icon/firefox"
        ];
        for (var i = 0; i < steps.length; i++)
            picture.source = steps[i];
        compare(seen, [
            "image://icon/firefox false",
            testCase.whiteSource + " true",
            "image://icon/kitty false",
            " true",
            "image://icon/org.gnome.Nautilus false",
            "image://icon/firefox false"
        ]);
    }

    // The runner registers no `icon` provider, so a synchronous request for
    // one fails inside the assignment itself, while one handed to the pixmap
    // reader thread still reads Loading on the next line.
    function test_a_themed_source_never_reaches_the_reader_thread() {
        var steps = [
            ["", "image://icon/firefox"],
            [testCase.whiteSource, "image://icon/kitty"],
            ["image://icon/kitty", "image://icon/org.gnome.Nautilus"]
        ];
        for (var i = 0; i < steps.length; i++) {
            var picture = make({ source: steps[i][0] });
            var img = imageOf(picture);
            if (steps[i][0] === testCase.whiteSource)
                tryVerify(function () { return img.status === Image.Ready; }, 2000);
            picture.source = steps[i][1];
            compare(img.status, Image.Error, steps[i][0] + " -> " + steps[i][1]);
        }
    }

    // NotificationCard hides its whole art frame on the status the frame
    // reads off this alias, so it has to answer for the Image underneath at
    // every step rather than only once loaded.
    function test_status_reads_the_image_status() {
        var picture = make({});
        var img = imageOf(picture);
        compare(picture.status, Image.Null);
        compare(picture.status, img.status);

        picture.source = testCase.whiteSource;
        tryVerify(function () { return picture.status === Image.Ready; }, 2000);
        compare(picture.status, img.status);
    }
}
