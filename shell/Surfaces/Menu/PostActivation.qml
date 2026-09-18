import QtQuick
import Quickshell.Io
import qs.Core as Core
import qs.Compositor
import qs.Notifications
import "../../Menu/providers.js" as Providers

// Two Enter-time side effects that outlive the row activation itself, both
// keyed off the launcher's own window rather than off the row: instant
// paste and launch feedback.
//
// Instant paste: an activated row carrying `pasteAfter` (the clipboard
// route's rows and the emoji route's, both gated on `clipboard.paste`)
// closes the menu like any action, then synthesizes the configured paste
// chord into whatever window focus returns to, on top of the copy that
// already ran. One wtype spawn, gated on the window's actual visible flip
// plus a short settle: synthesizing input while this keyboard-exclusive
// surface still holds focus would land it in the menu's own search field.
// That settle doubles as the write barrier, since the copy is exec'd at
// Enter, a close animation ahead of the keystroke.
//
// wtype missing from PATH (the sh wrapper's exit 127) or a compositor
// without the virtual-keyboard protocol degrade to the copy that already
// ran: one warning, no error surface. Re-opening before the settle fires
// drops whatever was pending (onWindowVisibleChanged below), better nothing
// than typed at the menu.
Item {
    id: root

    // Bound to Menu.qml's own window `visible`.
    property bool windowVisible: false
    property bool _pendingPaste: false

    function armPaste() {
        root._pendingPaste = true;
    }

    onWindowVisibleChanged: {
        if (root.windowVisible) {
            typeSettleTimer.stop();
            root._pendingPaste = false;
        } else if (root._pendingPaste) {
            typeSettleTimer.restart();
        }
    }

    Timer {
        id: typeSettleTimer
        interval: 150
        onTriggered: {
            var paste = root._pendingPaste;
            root._pendingPaste = false;
            if (!paste)
                return;
            var chord = Core.Config.get("clipboard.pasteChord", "ctrl+v");
            var argv = Providers.pasteArgv(chord);
            if (!argv) {
                console.warn("Menu: clipboard.pasteChord is not a wtype chord:", chord, "- copied but not pasted");
                return;
            }
            typeProc.command = ["sh", "-c", 'command -v wtype >/dev/null 2>&1 || exit 127; exec wtype "$@"', "sh"].concat(argv);
            typeProc.running = true;
        }
    }

    Process {
        id: typeProc
        onExited: exitCode => {
            if (exitCode === 127)
                console.warn("Menu: wtype not on PATH, copied but not pasted");
            else if (exitCode !== 0)
                console.warn("Menu: wtype failed (exit " + exitCode + "), copied but not pasted");
        }
    }

    // Launch feedback for app rows. DesktopEntry.execute() is
    // fire-and-forget, it hands the entry's Exec line off and reports
    // nothing back, so the only truthful confirmation a launch can ever
    // get is the app's own window turning up. CompositorService.windows is
    // the live toplevel list, so this watches instead of claiming: baseline
    // the window count (and the focused window id) the moment Enter lands,
    // and if something new arrives within `_graceMs`, THE WINDOW is the
    // feedback and no toast fires at all. omarchy's AppLibrary.qml
    // (launchSerial/launchToplevelCount/launchActiveToplevel, and its note
    // about the OSD outliving the launch that opened it) takes the same
    // position for the same reason. Only a grace period that passes with
    // nothing new gets a toast, and it says exactly what is known:
    // LAUNCHING, this app, nothing on screen yet.
    //
    // Success is never claimed, and neither is failure: a slow cold start,
    // a second instance handing its argv to an already-open window, and an
    // Exec line that died immediately are indistinguishable from out here,
    // so one honest in-progress wording covers all three. The one case that
    // fires immediately is a backend that isn't connected
    // (CompositorService.available false, e.g. a session that is not
    // Hyprland): there is nothing to observe at any point, so waiting out
    // the grace period would only delay the same sentence.
    //
    // One watch at a time, a second launch inside the grace period
    // supersedes the first, so a burst of Enters can't stack up toasts.
    readonly property int _graceMs: 2000
    property string _watchLabel: ""
    property int _baselineWindows: 0
    property string _baselineFocusedId: ""

    function beginLaunchWatch(label) {
        if (!CompositorService.available) {
            NotificationService.notify("LAUNCHING", label);
            return;
        }
        root._watchLabel = label;
        root._baselineWindows = (CompositorService.windows || []).length;
        root._baselineFocusedId = CompositorService.focusedWindowId;
        graceTimer.restart();
    }

    Timer {
        id: graceTimer
        interval: root._graceMs
        onTriggered: {
            var label = root._watchLabel;
            root._watchLabel = "";
            if (label === "")
                return;
            // A focus move is evidence alongside the count: an app that
            // raised an already-open window of its own never changes the
            // total. Either reading can also be the user's own doing, which
            // costs at worst one toast NOT shown, never a false claim.
            if ((CompositorService.windows || []).length > root._baselineWindows
                || CompositorService.focusedWindowId !== root._baselineFocusedId)
                return;
            NotificationService.notify("LAUNCHING", label);
        }
    }
}
