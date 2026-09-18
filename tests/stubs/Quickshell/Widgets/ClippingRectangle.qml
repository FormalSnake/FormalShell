import QtQuick

// Test-only stand-in for `Quickshell.Widgets.ClippingRectangle`, which is
// native. The clip itself is a ShaderEffect there and a plain rectangular
// `clip` here: what a test can assert about a `Cover` is its geometry and
// its border, and nothing measures the rounding of the picture's corners.
// primitive-exempt: this IS the primitive's stand-in, and the radius and
// border it carries are the ones the real type declares.
Rectangle {
    id: root

    property bool contentInsideBorder: false

    clip: true
}
