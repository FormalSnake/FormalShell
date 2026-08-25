import QtQuick
import qs.Core
import qs.Components
import qs.Reminders
import qs.Services
import "../../../Capture/model.js" as Capture

// Bar region for transient session-state glyphs (DESIGN.md §3 Bar's
// "indicators slot", spec §Surfaces-1, M10 Task 2): a stay-awake glyph
// bound ONLY to the explicit IdleService.stayAwake toggle (M-polish batch
// item B, omarchy's StayAwake indicator semantics, read-only reference at
// omarchy/shell/plugins/bar/indicators/StayAwake.qml: binds to the toggle
// itself, same md-coffee glyph, click turns it off) and night light off
// NightLightService.active (M16 Task 6). IdleService's own media-playback
// guard still holds the screensaver/lock chain exactly as before, but no
// longer surfaces a glyph here, stayAwake is the only thing this cell
// reflects now, so a track playing in the background never shows as an
// idle-inhibit the user didn't ask for. The DND bell-off glyph this slot
// carried since M10 moved to BellWidget.qml (M13b Task 2), that cell is
// always visible and owns both DND display and its toggle, so a second
// DND glyph here would just double up. Each glyph is its own standalone
// Cell, shown only while its condition holds; the whole row disappears
// when none does, never an empty box.
//
// Three more cells joined the row and all carry more weight than a passive
// session flag, so they lead it, loudest first: a live screen recording
// (M22, the only destructive cell here, so its border and ink carry the
// colour while every neighbour stays plain), a clipssh transfer in flight
// (ClipsshService, whose whole point
// is that an ssh takes as long as it takes), and a pending reminder
// (countdown in the cell, message in the tooltip; DESIGN.md §2 item 5 names
// countdown as a numeric display that must not jitter, which only means
// anything if it is on screen). The recording cell's own elapsed clock stays
// in its tooltip: a per-second label on a glyph-only cell would relayout the
// bar every tick.
//
// This `Row` is also what wakes NightLightService up at shell startup (a
// live binding on a QML singleton is what forces its lazy construction,
// see PolkitDialog.qml's own `PolkitService.flow` binding for the
// established precedent), so `nightlight.startOn` in settings.json
// actually takes effect even on a session where the indicator itself
// never renders.
Row {
    id: root

    readonly property bool _stayAwakeActive: IdleService.stayAwake
    readonly property bool _nightLightActive: NightLightService.active
    // Live bindings on two more lazily-constructed singletons, same
    // construction-site mechanism the header documents for NightLightService.
    readonly property bool _recordingActive: RecordingService.active
    readonly property bool _clipsshSending: ClipsshService.busy
    readonly property bool _reminderPending: ReminderService.count > 0
    // Read by Bar.qml's regionDelegate instead of `visible` directly, see
    // that file's own header comment for why crossing the Loader boundary
    // through the built-in `visible` property specifically breaks its own
    // future reactivity.
    readonly property bool shown: root._recordingActive || root._clipsshSending || root._reminderPending || root._stayAwakeActive || root._nightLightActive

    // Bar.qml sets this on the widget it loads; this row is not a Cell
    // itself, so it hands it to each cell it holds (DESIGN.md §3 Bar).
    property bool ghost: false

    spacing: Theme.space.sm
    visible: root.shown

    Cell {
        id: recordingCell
        ghost: root.ghost
        height: root.height
        visible: root._recordingActive
        destructive: true
        tooltipText: "RECORDING " + Capture.elapsedLabel(RecordingService.elapsedMs)

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "circle-dot"
            color: recordingCell.foreground
        }

        interactive: true
        onClicked: RecordingService.stop()
    }

    // A clipssh transfer in flight (ClipsshService), up for as long as the
    // ssh takes. The toast that fires when the transfer lands expires in
    // seconds, so it can only answer "did it land", never "is it still
    // going"; this cell is the second half of that. No click action: clipssh
    // has no cancel, and killing the ssh mid-pipe would leave a truncated
    // file on the far end.
    Cell {
        id: clipsshCell
        ghost: root.ghost
        height: root.height
        visible: root._clipsshSending
        // The alias is the user's own word for a host, so it goes through
        // verbatim, same as the reminder message below.
        tooltipVerbatim: true
        tooltipText: ClipsshService.busy ? "SENDING CLIPBOARD IMAGE TO " + ClipsshService.target : ""

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "terminal"
            color: clipsshCell.foreground
        }
    }

    Cell {
        id: reminderCell
        ghost: root.ghost
        height: root.height
        visible: root._reminderPending
        // The message is the user's own typed words, so it goes through
        // verbatim rather than Tooltip's uppercasing (Tray.qml sets the same
        // flag for foreign strings).
        tooltipVerbatim: true
        tooltipText: ReminderService.count > 0
            ? ReminderService.pending[0].message + " / " + ReminderService.barLabel
            : ""

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.xxs

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "alarm-clock"
                color: reminderCell.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ReminderService.barLabel
                color: reminderCell.dimForeground
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize.body
                font.weight: Theme.weight.medium
            }
        }

        // Clearing deliberately lives in the menu and `reminder clear`, not
        // on an 18px cell with no confirm.
        interactive: true
        onClicked: ReminderService.showSummary()
    }

    Cell {
        id: stayAwakeCell
        ghost: root.ghost
        // Same Row-only-manages-x gap Workspaces.qml/Tray.qml fix
        // identically: `root` here IS the Row Bar.qml's regionDelegate
        // stretches to the bar's shared content height, so binding to it
        // (not `Theme.barHeight`, which routes back through the same
        // implicitHeight chain Bar.qml measures this Row by) gives every
        // glyph cell the same hover-fill extent as a directly-hosted widget.
        height: root.height
        visible: root._stayAwakeActive
        // This cell and the night-light one below say nothing but their
        // glyph, and both appear out of nowhere the moment their state turns
        // on, exactly the case a tooltip earns its place on. Both read "ON"
        // because neither cell exists in the off state at all.
        tooltipText: "STAY AWAKE ON"

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "coffee"
            color: stayAwakeCell.foreground
        }

        interactive: true
        onClicked: IdleService.toggleStayAwake()
    }

    Cell {
        id: nightLightCell
        ghost: root.ghost
        height: root.height
        visible: root._nightLightActive
        tooltipText: "NIGHT LIGHT ON"

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "lightbulb"
            color: nightLightCell.foreground
        }

        // Hover only, this cell has no action of its own (night light is
        // toggled from the menu, not here), so it takes no buttons and
        // leaves the cursor alone; all it does is give the tooltip above
        // something to trigger on, and pick up the bar's usual hover
        // inversion while it's there.
        interactive: true
        acceptedButtons: Qt.NoButton
    }
}
