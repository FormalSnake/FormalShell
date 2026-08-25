.pragma library

// Which Icon name the OSD pill draws for the kind it is showing (DESIGN.md
// §3 "OSD"). Pure so tests can walk the volume ramp without a Quickshell
// engine; Osd.qml holds the live state.
//
// A muted sink keeps its pre-mute percentage on the readout but draws
// `volume-x`, since the icon answers "will I hear this" and the number
// answers "where is the slider".
function iconName(kind, volume, muted) {
    if (kind === "brightness")
        return "sun";
    if (kind === "media")
        return "music";
    if (muted || !(volume > 0))
        return "volume-x";
    return volume < 0.5 ? "volume-1" : "volume-2";
}
