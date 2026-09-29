import QtQuick
import QtMultimedia
import qs.Core as Core
import qs.Components
import qs.Services
import "../../../Menu/actions.js" as Actions

// The launcher's camera mirror. Registered in Menu/appviews.js against the
// "mirror" route: a live feed in the card, flipped left to right like a
// mirror, with one key (Tab, Enter or the footer's button) stepping through
// every camera the machine lists, IR sensors last.
//
// Qt's own V4L2 backend captures (QtMultimedia, already on the wrapper's
// import path for AnimatedAlbumArt). It enumerates a grey-only device as a
// camera of its own, so an IR sensor needs no second capture path.
//
// The device is open only while the launcher is: `live` is bound by
// Menu.qml to `isOpen`, which drops the moment a close starts, well ahead of
// the exit fade that keeps this item alive, and leaving the route destroys
// the item. Both end with the Camera inactive and the descriptor closed.
//
// The IR emitter is not touched. It is a UVC extension-unit control that
// differs per model, and V4L2 streaming alone leaves it however the firmware
// wants it, so an IR feed can come up dark on a laptop whose emitter has not
// been enabled system-wide.
Item {
    id: root

    property bool live: false

    // QVideoFrameFormat::PixelFormat is not exposed to QML, so Y8 and Y16
    // are the enum's own values (qvideoframeformat.h, Format_Y8 = 24).
    readonly property int _pixelY8: 24
    readonly property int _pixelY16: 25

    readonly property bool _multiple: MirrorService.cameras.length > 1
    readonly property var _device: root._find(MirrorService.currentId)

    Component.onCompleted: {
        MirrorService.open = true;
        MirrorService.feedItem = frame;
        root._publish();
    }
    Component.onDestruction: MirrorService.reset()

    MediaDevices {
        id: devices
        onVideoInputsChanged: root._publish()
    }

    // QCameraDevice.id is a QByteArray, which QML hands over as an
    // ArrayBuffer rather than a string.
    function _idString(id) {
        if (typeof id === "string")
            return id;
        var bytes = new Uint8Array(id);
        var text = "";
        for (var i = 0; i < bytes.length; i++)
            text += String.fromCharCode(bytes[i]);
        return text;
    }

    function _greyOnly(device) {
        var formats = device.videoFormats;
        if (formats.length === 0)
            return false;
        for (var i = 0; i < formats.length; i++) {
            var pixel = formats[i].pixelFormat;
            if (pixel !== root._pixelY8 && pixel !== root._pixelY16)
                return false;
        }
        return true;
    }

    function _publish() {
        var list = [];
        var inputs = devices.videoInputs;
        for (var i = 0; i < inputs.length; i++)
            list.push({ id: root._idString(inputs[i].id), description: inputs[i].description, greyOnly: root._greyOnly(inputs[i]) });
        MirrorService.publish(list);
    }

    function _find(id) {
        var inputs = devices.videoInputs;
        for (var i = 0; i < inputs.length; i++) {
            if (root._idString(inputs[i].id) === id)
                return inputs[i];
        }
        return null;
    }

    CaptureSession {
        camera: camera
        videoOutput: feed
    }

    Camera {
        id: camera
        cameraDevice: root._device ? root._device : devices.defaultVideoInput
        active: root.live && root._device !== null
        onErrorOccurred: (error, errorString) => MirrorService.error = errorString
    }

    Binding {
        target: MirrorService
        property: "streaming"
        value: camera.active
    }

    // Per camera: the first frame after a switch is what turns "Starting"
    // into a picture.
    Connections {
        target: feed.videoSink
        function onVideoFrameChanged() {
            MirrorService.hasFrame = true;
        }
    }

    Connections {
        target: MirrorService
        function onCurrentIdChanged() {
            MirrorService.hasFrame = false;
        }
    }

    readonly property var viewActions: {
        var hints = [{ keys: Actions.KEY_ESC, label: "Back" }];
        if (!root._multiple)
            return { primary: null, hints: hints };
        return { primary: { keys: Actions.KEY_TAB, label: "Next camera" }, hints: hints };
    }

    function viewActivate(index) {
        MirrorService.cycle(1);
        return true;
    }

    function viewKey(key, modifiers) {
        switch (key) {
        case Qt.Key_Tab:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            MirrorService.cycle(1);
            return true;
        case Qt.Key_Backtab:
            MirrorService.cycle(-1);
            return true;
        }
        return false;
    }

    Box {
        id: frame
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: caption.top
        anchors.leftMargin: Core.Theme.space.sm
        anchors.rightMargin: Core.Theme.space.sm
        anchors.bottomMargin: Core.Theme.space.sm
        role: "cell"

        VideoOutput {
            id: feed
            anchors.fill: parent
            anchors.margins: Core.Theme.borderWidth
            fillMode: VideoOutput.PreserveAspectFit
            visible: MirrorService.hasFrame && MirrorService.error === ""
            transform: Scale {
                origin.x: feed.width / 2
                xScale: -1
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: Core.Theme.space.sm
            visible: !feed.visible

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "camera"
                size: Core.Theme.fontSize.title
                color: Core.Theme.color.mutedForeground
            }

            SectionLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: MirrorService.error !== "" ? MirrorService.error
                    : (MirrorService.cameras.length === 0 ? "No camera" : "Starting camera")
                color: MirrorService.error !== "" ? Core.Theme.color.destructive : Core.Theme.color.mutedForeground
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: Math.min(implicitWidth, frame.width - Core.Theme.space.lg * 2)
            }
        }
    }

    Item {
        id: caption
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Core.Theme.space.sm + Core.Theme.space.controlPaddingX
        anchors.rightMargin: Core.Theme.space.sm + Core.Theme.space.controlPaddingX
        height: Core.Theme.space.controlHeight
        visible: MirrorService.cameras.length > 0

        Text {
            anchors.left: parent.left
            anchors.right: position.left
            anchors.rightMargin: Core.Theme.space.sm
            anchors.verticalCenter: parent.verticalCenter
            text: MirrorService.current ? MirrorService.current.label : ""
            elide: Text.ElideRight
            color: Core.Theme.color.foreground
            font.family: Core.Theme.fontFamilyMono
            font.pixelSize: Core.Theme.fontSize.bodySmall
        }

        Text {
            id: position
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root._multiple
            text: (MirrorService.cameras.indexOf(MirrorService.current) + 1) + " of " + MirrorService.cameras.length
            color: Core.Theme.color.mutedForeground
            font.family: Core.Theme.fontFamilyMono
            font.pixelSize: Core.Theme.fontSize.bodySmall
        }
    }
}
