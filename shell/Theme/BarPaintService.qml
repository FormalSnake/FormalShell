pragma Singleton
import QtQuick
import Quickshell

// The band's one reading of the wallpaper (owner, 2026-09-18). wingpanel
// samples per monitor, which on a two-output desk shows one bar with dark
// ink and the other with white; here the wallpaper is one picture for the
// session, so it is read once, on the main display
// (Services/MainOutputService.qml), and every band and frame ring wears that
// answer. A window covering an output is still that output's own business
// and never reaches this (barpaint.js's `decideFor`).
//
// The sampler is a Canvas and a Canvas paints only inside a window
// (BarPaint.qml), so it lives in the main output's own bar and hands its
// numbers here; every other bar reads them back. Which output they came off
// is reported beside the paint by `bar paint`.
Singleton {
    id: root

    // Written by the main display's band alone (Surfaces/Bar/BarWingpanel.qml),
    // never bound. Empty and unsampled until it has read once, which is the
    // bare light-ink band.
    property string source: ""
    property var stats: ({ mean: 0, std: 0, acutance: 0, sampled: false })
}
