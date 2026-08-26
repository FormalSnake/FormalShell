import QtQuick

// The re-open tick every watch on a user-authored config file needs:
// `ConfigReopen { file: someFileView }`.
//
// A watch resolves the path once and then follows the inode, so a write that
// REPLACES the file rather than editing it in place goes unannounced and the
// file stops reaching the shell for the rest of the session. Home-manager
// does exactly that on every activation: `~/.config/formalshell/*` is a
// symlink into the store, the watch lands on the store file, which is
// immutable and never touched again, and retargeting the symlink beside it
// produces no event at all. (g815, 2026-08-26: a nixos-rebuild moved
// bar.position and the bar stayed where it was until the service was
// restarted by hand.) FileView's own directory watch does not cover it
// either: it reports a file that did not exist and now does, and a
// replacement is never that (quickshell src/io/fileview.cpp,
// onWatchedDirectoryChanged).
//
// A rename over the path is NOT this case and needs nothing: it unlinks the
// inode the watch is on, which inotify does report.
//
// reload() re-runs the whole open, so a tick reads through the new symlink
// AND re-attaches the watch to the new inode: one tick after a replacement,
// in-place edits are instant again and this is back to costing nothing. Five
// seconds is chosen against how config actually changes, which is a person
// saving a file or a rebuild finishing, so the pickup reads as immediate
// while the idle cost is one read of a few KB. What each consumer owes in
// return is publishing nothing when the bytes match: the tick fires whether
// or not anything changed, and a config object reassigned on every tick
// would re-evaluate every binding hanging off it.
//
// dev/smoke.d/config_reload.sh pins the whole thing against a real symlink
// retarget in a live session.
Timer {
    id: root

    required property var file

    interval: 5000
    running: true
    repeat: true
    onTriggered: root.file.reload()
}
