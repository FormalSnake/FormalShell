import QtQuick
import QtTest
import qs.Core
import "../shell/Components"

// Picture's contract (M49 D3, shell/Components/Picture.qml): a plain `Image`
// with the dither layer loaded only while `theme.dither` is on, so a surface
// reaches for this instead of branching on the knob itself. The stub Theme
// carries the shadcn preset's own table, where `dither` is off, which is the
// case asserted here: the Loader stays inactive, nothing constructs a
// DitherImage, and the image renders exactly as a bare `Image` would. The on
// path needs a real Theme reading a settings file, so it is proven in the
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
