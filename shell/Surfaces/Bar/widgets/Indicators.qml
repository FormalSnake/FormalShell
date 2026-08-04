import QtQuick
import qs.Core
import qs.Components
import qs.Services

// Bar region for transient session-state glyphs (DESIGN.md §3 Bar's
// "indicators slot", spec §Surfaces-1, M10 Task 2): a stay-awake glyph
// bound ONLY to the explicit IdleService.stayAwake toggle (M-polish batch
// item B, omarchy's StayAwake indicator semantics — read-only reference at
// omarchy/shell/plugins/bar/indicators/StayAwake.qml: binds to the toggle
// itself, same md-coffee glyph, click turns it off) and night light off
// NightLightService.active (M16 Task 6). IdleService's own media-playback
// guard still holds the screensaver/lock chain exactly as before, but no
// longer surfaces a glyph here — stayAwake is the only thing this cell
// reflects now, so a track playing in the background never shows as an
// idle-inhibit the user didn't ask for. The DND bell-off glyph this slot
// carried since M10 moved to BellWidget.qml (M13b Task 2) — that cell is
// always visible and owns both DND display and its toggle, so a second
// DND glyph here would just double up. Each glyph is its own standalone
// Cell, shown only while its condition holds; the whole row disappears
// when none does — never an empty box. Glyph codepoints taken from the
// pinned nerd-fonts-jetbrains-mono cmap (nix/testvm.nix) via fonttools
// ttx, not memory: md-coffee U+F0176, md-lightbulb_night U+F1A4C — both
// audited for optical centering (fonttools glyf bbox: xMin 0/xMax 600
// exactly filling the 600-unit advance width, ink vertically centered on
// the font's own ascent/descent midpoint for both) — no asymmetry found,
// the cell's own symmetric Theme.space.lg/sm padding already centers them.
// This `Row` is also what wakes NightLightService up at shell startup (a
// live binding on a QML singleton is what forces its lazy construction —
// see PolkitDialog.qml's own `PolkitService.flow` binding for the
// established precedent), so `nightlight.startOn` in settings.json
// actually takes effect even on a session where the indicator itself
// never renders.
Row {
    id: root

    readonly property bool _stayAwakeActive: IdleService.stayAwake
    readonly property bool _nightLightActive: NightLightService.active
    // Read by Bar.qml's regionDelegate instead of `visible` directly — see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: root._stayAwakeActive || root._nightLightActive

    spacing: Theme.space.sm
    visible: root.shown

    Cell {
        id: stayAwakeCell
        visible: root._stayAwakeActive
        standalone: true
        hovered: stayAwakeArea.containsMouse

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅶"
            color: stayAwakeCell.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }

        MouseArea {
            id: stayAwakeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: IdleService.toggleStayAwake()
        }
    }

    Cell {
        id: nightLightCell
        visible: root._nightLightActive
        standalone: true

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󱩌"
            color: nightLightCell.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.fontSize.body
        }
    }
}
