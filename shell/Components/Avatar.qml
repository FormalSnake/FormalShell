import QtQuick
import qs.Core

// The user's profile picture: a `Cover` rounded all the way to a circle
// (square under `theme.radius: 0`, the same rule every pill follows). The
// caller hands it a path; a missing or unreadable file hides the whole slot
// rather than drawing an empty well.
Cover {
    id: root

    property string path: ""
    property real size: Theme.space.xxl * 2

    width: root.size
    height: root.size
    radius: Theme.pillRadius(root.size)
    visible: root.path !== "" && root.status === Image.Ready
    source: root.path !== "" ? "file://" + root.path : ""
    sourceSize.width: Math.ceil(root.size * 2)
    sourceSize.height: Math.ceil(root.size * 2)
    // ~/.face is a symlink home-manager retargets; a cached decode would keep
    // the old picture until the shell restarts.
    cache: false
}
