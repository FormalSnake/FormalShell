pragma Singleton
import QtQuick
import Quickshell
import "../Camera/model.js" as Camera

// State of the launcher's Mirror view (Surfaces/Menu/views/MirrorView.qml):
// which cameras exist, which one is showing, whether the view holds the
// device open and what the device last complained about. The view owns the
// QtMultimedia objects (a MediaDevices, a Camera, a CaptureSession) and
// publishes into this; the service exists so the `mirror` IPC target and
// the rig can read and steer the view without reaching into a Loader.
//
// Nothing here opens a camera. `open` follows the view's lifetime and
// `streaming` follows the Camera object's own `active`, so a value read at
// any moment says whether the webcam LED is on.
Singleton {
    id: root

    // Camera/model.js rows, colour first, IR last.
    property var cameras: []
    property string currentId: ""
    property bool open: false
    property bool streaming: false
    property bool hasFrame: false
    property string error: ""

    // The box the feed is drawn in, for `mirror status` to report its rect.
    property Item feedItem: null

    readonly property var current: {
        var at = Camera.indexOf(root.cameras, root.currentId);
        return at >= 0 ? root.cameras[at] : null;
    }

    // `devices` is { id, description, greyOnly } per QCameraDevice.
    function publish(devices) {
        root.cameras = Camera.rows(devices);
        root.currentId = Camera.pick(root.cameras, root.currentId);
    }

    function cycle(delta) {
        var next = Camera.step(root.cameras, root.currentId, delta);
        if (next === root.currentId)
            return false;
        root.error = "";
        root.currentId = next;
        return true;
    }

    function reset() {
        root.cameras = [];
        root.currentId = "";
        root.open = false;
        root.streaming = false;
        root.hasFrame = false;
        root.error = "";
        root.feedItem = null;
    }
}
