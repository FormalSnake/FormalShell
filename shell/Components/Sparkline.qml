import QtQuick
import QtQuick.Shapes
import qs.Core
import "../Monitor/history.js" as History

// A small history line: `values` in `primary` over a wash of itself, and an
// optional `secondary` series in the muted ink. Both are drawn against the
// same `ceiling` (a 0..1 fraction series passes 1). The hairline along the
// bottom is always there, so a series with no samples yet reads as empty
// rather than as a missing widget.
Item {
    id: root

    property var values: []
    property var secondary: []
    property real ceiling: 1
    property int capacity: History.CAPACITY

    implicitHeight: Theme.space.controlHeight

    // PathPolyline takes points, not the plain objects history.js returns.
    function _line(series) {
        return History.points(series, root.width, root.height, root.ceiling, root.capacity)
            .map(function (p) { return Qt.point(p.x, p.y); });
    }

    readonly property var _main: root._line(root.values)
    readonly property var _second: root._line(root.secondary)

    // A closed polygon down to the floor for the wash under the line.
    readonly property var _area: {
        var pts = root._main;
        if (pts.length < 2)
            return [];
        var out = pts.slice();
        out.push(Qt.point(pts[pts.length - 1].x, root.height));
        out.push(Qt.point(pts[0].x, root.height));
        return out;
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.borderWidth
        color: Theme.color.border
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.color.primary, 0.15)
            PathPolyline { path: root._area }
        }

        ShapePath {
            strokeWidth: Theme.space.xxs
            strokeColor: Theme.color.mutedForeground
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._second.length > 1 ? root._second : [] }
        }

        ShapePath {
            strokeWidth: Theme.space.xxs
            strokeColor: Theme.color.primary
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._main.length > 1 ? root._main : [] }
        }
    }
}
