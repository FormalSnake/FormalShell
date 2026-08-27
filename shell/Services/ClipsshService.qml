pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Notifications
import "../Menu/providers.js" as Providers

// Runs the menu's clipssh route and reports how it went.
//
// clipssh reads the clipboard image, pipes it over ssh, and wl-copy's the
// remote path back, so a transfer takes as long as the link does, and it can
// fail at either end. The shell runs it here rather than handing it to
// CompositorService.spawn (the path every other menu action takes) because a
// spawned command yields no exit code and no output: an in-flight transfer
// and one that died on the first line look identical from the bar.
//
// Three things say so: an indicator cell for as long as it is in flight
// (Indicators.qml, the row that means "something is happening right now"), a
// toast naming the remote path when it lands, and an urgent toast carrying
// clipssh's own error line when it doesn't.
//
// The alias goes through `sh -c` as an argument rather than spliced into the
// command, so a clipssh that isn't installed comes back as exit 127, which is
// an outcome to report, instead of a Process that never starts and so never
// exits.
//
// One transfer at a time, refused rather than queued: clipssh reads the
// clipboard at the moment it runs, and the clipboard is a single global, so a
// queued transfer would send whatever happened to be on it by then.
//
// This is also where clipssh's own alias store is read, rather than in the
// launcher route that used to own the FileView: the route is no longer the
// only caller. `clipssh.alias` and the auto-send below both need to resolve a
// name with no row under a cursor to read it off, and two watches on one
// small file would be two answers to the same question.
Singleton {
    id: root

    readonly property bool busy: proc.running

    // The alias in flight, for the indicator cell's tooltip. Empty whenever
    // `busy` is false.
    property string target: ""

    // clipssh's own `name=user@host` store, optional: absence just means zero
    // aliases (the route's NO ALIASES row), never a warning. Watched, and
    // reloaded on every launcher open, so an alias added mid-session shows
    // up without a watch ever having attached to a file that did not exist.
    readonly property var aliases: Providers.clipsshAliases(root._aliasesText)
    property string _aliasesText: ""

    function reloadAliases() {
        aliasFile.reload();
    }

    // The alias a caller with nothing to ask gets: `clipssh.alias` when it
    // names one, otherwise the only alias there is. "" means undecided, and
    // the two callers answer it differently on purpose: the launcher can ask
    // (it drills into the route), the auto-send cannot and says so. The
    // literal "ask" is how a one-alias store still gets a prompt.
    function resolveAlias() {
        var configured = String(Config.get("clipssh.alias", ""));
        if (configured === "ask")
            return "";
        if (configured !== "")
            return configured;
        return root.aliases.length === 1 ? root.aliases[0].name : "";
    }

    function send(alias) {
        root._run(alias, "");
    }

    // A history entry sent without it having to be the current selection:
    // clipssh reads the clipboard and nothing else, so the file goes on it
    // first, in the same child so the two cannot interleave with whatever
    // else is copying. A wl-copy that fails prints clipssh's own `Error:`
    // shape, which is what clipsshOutcome already reads, so a clipboard
    // failure reports as itself instead of as a bare exit code.
    function sendImage(alias, path) {
        if (String(path || "") === "")
            return;
        root._run(alias, path);
    }

    // The `clipssh.autoSendImages` path: every image landing in clipboard
    // history goes straight to the resolved alias. Silent where the
    // deliberate paths speak up, because this one fires on a copy the user
    // did not aim at clipssh: an in-flight transfer is skipped rather than
    // toasted BUSY (the copy that started it is usually this same image,
    // put on the clipboard by sendImage a moment earlier), and an
    // unresolvable alias is reported once per session rather than on every
    // screenshot.
    property bool _autoWarned: false

    function autoSendImage(path) {
        if (!Config.get("clipssh.autoSendImages", false))
            return;
        if (root.busy)
            return;
        var alias = root.resolveAlias();
        if (alias === "") {
            if (!root._autoWarned) {
                root._autoWarned = true;
                NotificationService.notify("CLIPSSH NOT SENDING",
                    root.aliases.length === 0
                        ? "clipssh.autoSendImages is on with no aliases saved"
                        : "clipssh.autoSendImages is on: set clipssh.alias to one of "
                            + root.aliases.length + " aliases", 2);
            }
            return;
        }
        root._run(alias, "");
    }

    // `path` empty sends whatever is on the clipboard already, which is what
    // the route's own rows mean by Enter.
    function _run(alias, path) {
        if (String(alias || "") === "")
            return;
        if (root.busy) {
            NotificationService.notify("CLIPSSH BUSY", "Still sending to " + root.target, 1);
            return;
        }
        root.target = alias;
        // The alias and the path ride argv rather than the script text, so a
        // path carrying a quote or a space cannot splice the command.
        proc.command = path === ""
            ? ["sh", "-c", 'exec clipssh "$1"', "sh", alias]
            : ["sh", "-c",
                'wl-copy --type image/png < "$2" || { printf "Error: could not put the image on the clipboard\\n" >&2; exit 1; }; '
                    + 'exec clipssh "$1"',
                "sh", alias, path];
        proc.running = true;
        NotificationService.notify("CLIPSSH SENDING", "Clipboard image to " + alias, 1);
    }

    FileView {
        id: aliasFile
        printErrors: false
        path: Quickshell.env("HOME") + "/.clipssh/aliases"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._aliasesText = aliasFile.text()
        onLoadFailed: root._aliasesText = ""
    }

    Process {
        id: proc

        stdout: StdioCollector {
            id: sendOut
        }
        stderr: StdioCollector {
            id: sendErr
        }

        onExited: exitCode => {
            var outcome = Providers.clipsshOutcome(exitCode, sendOut.text, sendErr.text);
            if (outcome.ok)
                NotificationService.notify("CLIPSSH COPIED",
                    outcome.path === ""
                        ? "Remote path is on the clipboard"
                        : outcome.path + " is on the clipboard", 1);
            else
                NotificationService.notify("CLIPSSH FAILED", root.target + ": " + outcome.error, 2);
            root.target = "";
        }
    }
}
