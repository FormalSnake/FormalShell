import QtQuick
import qs.Core
import "../Theme/tokens.js" as Tokens

// The velocity deform (DESIGN.md §1 "Motion", M54 D7): a card that arrives
// squashes into its rest and springs back, the way caelestia's panels do
// (mechanics and constants read at ce84c7b, written here in QML).
//
// The consumer holds one of these beside the item it owns, binds `active`
// for as long as something is moving (a Behavior's `running`, Presence's
// `!settled`) and hands the matrix to the item drawing both the frame and
// the contents:
//
//     Deform { id: deform; target: card; active: presence.running }
//     ...
//     transform: Matrix4x4 { matrix: deform.matrix }
//
// Every frame the target's scene position and size are sampled, the
// velocity taken from the delta, and the matrix targets a stretch along the
// direction of travel with a compress across it. Each of its three
// components rides an underdamped spring, so the card keeps deforming for a
// beat after the travel has stopped and unwinds through its rest rather
// than snapping back to it.
//
// The matrix is centred on the anchored edge's midpoint, not the item's
// own centre: a drawer hanging off the bar has to squash into the bar,
// and a matrix about the centre would pull its top edge off the line it
// hangs from.
QtObject {
    id: root

    property Item target: null

    // Runs the frame loop. Dropping it does not cut the deform off: the
    // springs keep integrating until they reach rest, then the loop stops
    // on its own (M54 D12, idle cost stays zero).
    property bool active: false

    // Per consumer, not a constant: 0.1 for the launcher, 0.15 for a
    // popout, 0.25 for the OSD. It reads as px/s per 10000 of stretch,
    // capped at `DEFORM.maxStretch`.
    property real amount: 0.15

    // The edge the target hangs off, whose midpoint the matrix is centred
    // on. Anything else (the default of a centred surface) takes the item's
    // own centre.
    property string edge: "top"

    readonly property matrix4x4 matrix: {
        const item = root.target;
        if (!Theme.motionEnabled || item === null || root._atRest)
            return Qt.matrix4x4();

        const w = item.width;
        const h = item.height;
        const cx = root.edge === "left" ? 0 : root.edge === "right" ? w : w / 2;
        const cy = root.edge === "top" ? 0 : root.edge === "bottom" ? h : h / 2;
        const s = root._spring;
        const m = Qt.matrix4x4(s.m00, s.m01, 0, 0, s.m01, s.m11, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        return Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1)
            .times(m)
            .times(Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1));
    }

    // The 2x2 linear part, symmetric, so three numbers describe it. One
    // object rather than three properties: the matrix above re-evaluates
    // once per frame instead of three times.
    property var _spring: ({ m00: 1, m01: 0, m11: 1 })
    property real _v00: 0
    property real _v01: 0
    property real _v11: 0
    property bool _atRest: true

    property bool _sampled: false
    property real _prevX: 0
    property real _prevY: 0
    property real _prevW: 0
    property real _prevH: 0

    property FrameAnimation _clock: FrameAnimation {
        running: Theme.motionEnabled && root.target !== null && (root.active || !root._atRest)
        // A restart has no previous sample to subtract, and the sample it
        // would inherit is however long ago the loop last stopped.
        onRunningChanged: root._sampled = false
        onTriggered: root._step(frameTime)
    }

    function _sample(x, y, w, h) {
        root._prevX = x;
        root._prevY = y;
        root._prevW = w;
        root._prevH = h;
        root._sampled = true;
    }

    function _step(dt) {
        const item = root.target;
        if (item === null)
            return;

        const p = item.mapToItem(null, 0, 0);
        const w = item.width;
        const h = item.height;

        // A frame this long or this short says nothing about how fast the
        // card is going: a stall would read as a kick and a repeated frame
        // as a divide by nearly zero.
        if (!root._sampled || dt > 0.1 || dt < 0.001) {
            root._sample(p.x, p.y, w, h);
            root._settle(0);
            return;
        }

        let vx = (p.x - root._prevX) / dt;
        let vy = (p.y - root._prevY) / dt;

        // An edge-anchored card grows away from the edge it hangs off, so
        // its own top left holds still while its free edge travels the
        // whole size delta. Without this an opening drawer deforms not at
        // all, which is the one open the deform exists for.
        const dw = (w - root._prevW) / dt;
        const dh = (h - root._prevH) / dt;
        if (root.edge === "top")
            vy += dh;
        else if (root.edge === "bottom")
            vy -= dh;
        else if (root.edge === "left")
            vx += dw;
        else if (root.edge === "right")
            vx -= dw;
        else {
            vx += dw / 2;
            vy += dh / 2;
        }

        root._sample(p.x, p.y, w, h);

        const speed = Math.sqrt(vx * vx + vy * vy);
        if (root._atRest && speed < Tokens.DEFORM.deadBand)
            return;
        root._atRest = false;

        let t00 = 1;
        let t01 = 0;
        let t11 = 1;
        if (speed > Tokens.DEFORM.deadBand) {
            // R(θ)·diag(stretch, 1/stretch)·Rᵀ written out: stretched along
            // the direction of travel, compressed across it, so the card
            // keeps its area.
            const stretch = 1 + Math.min(speed * root.amount / 10000, Tokens.DEFORM.maxStretch);
            const compress = 1 / stretch;
            const cos = vx / speed;
            const sin = vy / speed;
            t00 = stretch * cos * cos + compress * sin * sin;
            t01 = (stretch - compress) * cos * sin;
            t11 = stretch * sin * sin + compress * cos * cos;
        }

        // Damping integrated implicitly, the friction term reading the new
        // velocity: 1/(1 + c·dt) stays inside (0, 1) for any dt, where an
        // explicit -c·v·dt term flips sign once c·dt passes 1 (dt ~62ms
        // here) and pumps energy into the spring instead of taking it out.
        const s = root._spring;
        const k = Tokens.DEFORM.stiffness;
        const invDamp = 1 / (1 + Tokens.DEFORM.damping * dt);
        root._v00 = (root._v00 - k * (s.m00 - t00) * dt) * invDamp;
        root._v01 = (root._v01 - k * (s.m01 - t01) * dt) * invDamp;
        root._v11 = (root._v11 - k * (s.m11 - t11) * dt) * invDamp;
        root._spring = {
            m00: s.m00 + root._v00 * dt,
            m01: s.m01 + root._v01 * dt,
            m11: s.m11 + root._v11 * dt
        };

        root._settle(speed);
    }

    // Identity is a state, not a value the springs drift toward: without
    // the snap the loop would keep running on a deform nobody can see.
    function _settle(speed) {
        if (root._atRest)
            return;

        const e = Tokens.DEFORM.epsilon;
        const s = root._spring;
        const settled = Math.abs(s.m00 - 1) < e && Math.abs(s.m01) < e && Math.abs(s.m11 - 1) < e
            && Math.abs(root._v00) < e && Math.abs(root._v01) < e && Math.abs(root._v11) < e
            && speed < Tokens.DEFORM.deadBand;
        if (!settled)
            return;

        root._spring = { m00: 1, m01: 0, m11: 1 };
        root._v00 = 0;
        root._v01 = 0;
        root._v11 = 0;
        root._atRest = true;
    }
}
