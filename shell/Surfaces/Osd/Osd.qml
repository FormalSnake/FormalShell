import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Compositor
import qs.Components
import qs.Services

// Bottom-centered volume/brightness/media OSD (DESIGN.md §OSD, spec §7, M5
// Task 6, M8b Task 5 card chrome): a single three-cell row (icon | label |
// value) sharing rules, no keyboard focus, auto-hides `_hideDelay` after the
// last trigger. Column
// widths are fixed constants measured once off the glyph/label sets below —
// never off the live value — so volume ticking 3% -> 97%, or a long media
// title swapping in, never reflows the card (plan-wide no-jitter contract).
// One instance, opened on the focused screen at trigger time (same
// reasoning as Menu/Center: summoned, not per-output).
PanelWindow {
    id: root

    readonly property int _hideDelay: 1600

    property string kind: ""          // "" | "volume" | "brightness" | "media"
    property string mediaText: ""

    function showVolume() {
        root.kind = "volume";
        hideTimer.restart();
    }

    function showBrightness() {
        root.kind = "brightness";
        hideTimer.restart();
    }

    function showMedia(text) {
        root.mediaText = text;
        root.kind = "media";
        hideTimer.restart();
    }

    function close() {
        hideTimer.stop();
        root.kind = "";
    }

    Timer {
        id: hideTimer
        interval: root._hideDelay
        onTriggered: root.kind = ""
    }

    // AudioService fires this on ANY volume/mute change, ours or external
    // (wpctl, pavucontrol, hardware keys routed through it) — the only
    // trigger wired automatically. Brightness/media only ever show via
    // OsdIpc: BrightnessService has no polling loop to hook a signal off
    // (see its own header), and there is no media-player service yet (M6).
    Connections {
        target: AudioService
        function onChanged() { root.showVolume(); }
    }

    readonly property var _screen: {
        var name = CompositorService.focusedOutputName;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    screen: root._screen
    // Held visible through the exit fade (DESIGN.md §4): the timer clears
    // `kind`, the frame's opacity Behavior runs to 0, then the window
    // unmaps. No input concerns — this surface never takes any.
    visible: root.kind !== "" || frame.opacity > 0
    color: "transparent"

    WlrLayershell.namespace: "formalshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Anchoring only the bottom edge (no left/right) is what centers the
    // surface horizontally under wlr-layer-shell's arrange rules — the same
    // technique swayosd uses for its own bottom-center card.
    anchors.bottom: true
    margins.bottom: Theme.space.panelGap

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    // Off-screen calibration set: every glyph/label this card can ever show,
    // rendered once at the real live font so implicitWidth reflects actual
    // metrics instead of a guessed constant. `_iconWidth`/`_labelWidth`
    // below take the max across these, fixing the column widths for good.
    Item {
        visible: false

        Text {
            id: _mIconVolume
            text: "󰕾"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.title
        }
        Text {
            id: _mIconMuted
            text: "󰝟"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.title
        }
        Text {
            id: _mIconBrightness
            text: "󰃟"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.title
        }
        Text {
            id: _mIconMedia
            text: "󰝚"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.title
        }
        MetaLabel { id: _mLabelVolume; text: "VOLUME" }
        MetaLabel { id: _mLabelBrightness; text: "BRIGHTNESS" }
        MetaLabel { id: _mLabelMuted; text: "MUTED" }
        Text {
            id: _mValuePercent
            text: "100%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize.body
        }
    }

    readonly property int _iconWidth: Math.max(_mIconVolume.implicitWidth, _mIconMuted.implicitWidth, _mIconBrightness.implicitWidth, _mIconMedia.implicitWidth)

    // +4: the live label below renders with `elide: Text.ElideRight` set
    // (needed for the media kind's arbitrary track title), and Qt's elide
    // layout measures a hair narrower than these unconstrained calibration
    // Texts' own implicitWidth — without slack, "BRIGHTNESS" (the widest of
    // the three) clips to "BRIGHTNES…" despite the column being sized to
    // fit it exactly (observed on the mac VM rig, 2026-07-28).
    readonly property int _labelWidth: Math.max(_mLabelVolume.implicitWidth, _mLabelBrightness.implicitWidth, _mLabelMuted.implicitWidth) + 4
    readonly property int _mediaLabelWidth: 220
    readonly property int _valueWidth: _mValuePercent.implicitWidth

    // Every cell measures to its own content's natural height (icon at
    // Theme.fontSize.title vs. the value column's stacked percent+bar), so the
    // shared row height is the tallest of the three regardless of which
    // kind is currently showing — keeps the card's height fixed too.
    readonly property int _rowHeight: Math.max(iconCell.implicitHeight, labelCell.implicitHeight, valueCell.implicitHeight)

    Item {
        id: frame
        implicitWidth: row.implicitWidth + Theme.borderWidth
        implicitHeight: row.implicitHeight + Theme.borderWidth
        width: implicitWidth
        height: implicitHeight

        // Enter/exit (DESIGN.md §4): fade plus a rise from the bottom edge,
        // one animated scalar so a retrigger mid-exit reverses in place.
        // Kind-to-kind swaps while already showing (volume -> brightness)
        // stay instant: opacity never leaves 1.
        opacity: root.kind !== "" ? 1 : 0
        transform: Translate { y: (1 - frame.opacity) * Theme.motion.slide }

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.standard; easing.type: Theme.motion.easing }
        }

        // Opaque card backing (DESIGN.md's omarchy card chrome — "a single
        // bordered rectangle", M8b Task 5): without it the card was only
        // ever as opaque as whatever color happened to sit behind the
        // matugen-picked background, i.e. see-through over a real wallpaper.
        Rectangle {
            anchors.fill: parent
            color: Theme.color.background
        }

        // Outer top/left rule — Cell.qml's shared-rule contract makes every
        // cell draw its own bottom+right rule, so the frame only needs to
        // close off the top and left of the whole row.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.borderWidth
            color: Theme.color.border
        }
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Theme.borderWidth
            color: Theme.color.border
        }

        Row {
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: Theme.borderWidth
            anchors.leftMargin: Theme.borderWidth
            spacing: 0

            Cell {
                id: iconCell
                width: root._iconWidth + Theme.space.lg * 2 + Theme.borderWidth
                height: root._rowHeight

                Text {
                    anchors.centerIn: parent
                    text: root.kind === "brightness" ? "󰃟"
                        : root.kind === "media" ? "󰝚"
                        : (AudioService.muted ? "󰝟" : "󰕾")
                    color: iconCell.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize.title
                }
            }

            Cell {
                id: labelCell
                width: (root.kind === "media" ? root._mediaLabelWidth : root._labelWidth) + Theme.space.lg * 2 + Theme.borderWidth
                height: root._rowHeight

                MetaLabel {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    elide: Text.ElideRight
                    color: labelCell.dimForeground
                    text: root.kind === "brightness" ? "BRIGHTNESS"
                        : root.kind === "media" ? root.mediaText
                        : (AudioService.muted ? "MUTED" : "VOLUME")
                }
            }

            Cell {
                id: valueCell
                visible: root.kind !== "media"
                width: visible ? (root._valueWidth + Theme.space.lg * 2 + Theme.borderWidth) : 0
                height: root._rowHeight

                // Muted keeps showing the pre-mute volume number (still
                // informative) but drops the fill to 0 — the bar is the
                // "how much sound you'll actually hear" signal.
                readonly property real _fraction: root.kind === "brightness"
                    ? BrightnessService.percent / 100
                    : (AudioService.muted ? 0 : AudioService.volume)
                readonly property int _percent: root.kind === "brightness"
                    ? Math.round(BrightnessService.percent)
                    : Math.round(AudioService.volume * 100)

                Column {
                    width: parent.width
                    spacing: Theme.space.xxs

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: valueCell._percent + "%"
                        color: valueCell.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize.body
                    }

                    // Flat accent fill, no thumb, no radius — DESIGN.md's
                    // "sliders are full-width cells whose fill level is a
                    // flat accent block" rule, sized by fraction only. The
                    // remainder dithers per §2.8 instead of a flat rule wash.
                    DitherFill {
                        width: parent.width
                        height: Theme.space.trackThickness

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, valueCell._fraction))
                            height: parent.height
                            color: Theme.color.primary
                        }
                    }
                }
            }
        }

        // Dog-ear fold mark (DESIGN.md §2 item 7).
        DogEar {}
    }
}
