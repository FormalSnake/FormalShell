pragma Singleton
import Quickshell
import QtQuick
import "handoff.js" as Handoff

// Cross-panel mutual exclusion (M6 Task 1 follow-up): every Panel.qml
// instance is a standalone top-level PanelWindow (AudioPanel, CalendarPanel,
// ...) with no knowledge of its siblings, and panels open from two
// unrelated entry points, a bar widget's click handler calling
// panel.toggle() directly, and PanelIpc's `panel open <name>` calling
// panel.open(), neither of which knows what else is open. This singleton
// is the one thing both paths share: Panel.qml's open() closes whatever
// `current` still points at before taking the slot itself, so at most one
// panel is ever open regardless of how it was opened.
Singleton {
    id: root

    property var current: null

    // Every mapped bar strip, in creation order. An open with no click
    // behind it (PanelIpc's `toggle`/`toggleAt`, a compositor keybind) still
    // has to find the cell its panel hangs off, and Bar.qml exists once per
    // output inside a Variants delegate that nothing outside can address,
    // while PanelIpc answers for the whole shell: this singleton is again
    // the one thing both ends already share. Reassigned rather than mutated
    // in place, so a consumer binding to it re-evaluates.
    property var bars: []

    function addBar(bar) {
        if (root.bars.indexOf(bar) < 0)
            root.bars = root.bars.concat([bar]);
    }

    function removeBar(bar) {
        root.bars = root.bars.filter(function (other) { return other !== bar; });
    }

    // The card in flight between two panels (M53 D5): `from` is the panel
    // giving its card up, `to` the one taking it, `rect` where the shared
    // trajectory starts. Null whenever the last open was a plain one, which
    // is what leaves Panel's ordinary enter/exit recipe in charge.
    property var handoff: null

    // Whether replacing `current` with `next` is one card changing shape,
    // and the rect that card is at right now. Panel.open() asks before it
    // closes what it is replacing, since the outgoing frame is only where it
    // was until then.
    function beginHandoff(from, next) {
        // A handoff still in flight when a third panel opens: its outgoing
        // half is an emptied card travelling to a rect nobody is going to
        // occupy any more, so it goes now rather than trailing the new pair.
        if (root.handoff && root.handoff.from && root.handoff.from !== from)
            root.handoff.from.endHandoff();
        var rect = (from && next && from !== next)
            ? Handoff.outgoingRect(root._describe(from), root._describe(next))
            : null;
        root.handoff = rect ? { from: from, to: next, rect: rect } : null;
        return rect;
    }

    // Where a card is joined to the bar right now (M54 D6), or null while
    // nothing hangs off it: `edge` the bar's edge, `x` and `width` the
    // card's own rect along that bar in the bar's coordinates on `screen`
    // (a screen name), the fillets outside it not counted. Bar.qml reads it
    // to open the gap in its inward line, and it is the one thing the bar
    // and the surface hanging off it share: two windows, one silhouette.
    //
    // Reassigned rather than mutated, like `bars` above, so a consumer
    // binding to it re-evaluates. `owner` rides along so a surface can only
    // ever clear its own join: a panel handing its card over to another one
    // closes after the card it gave up has already been republished, and a
    // clear that ignored the owner would take the new one down with it.
    property var join: null

    function setJoin(owner, join) {
        if (!owner || !join)
            return;
        root.join = {
            owner: owner,
            edge: join.edge,
            x: join.x,
            width: join.width,
            screen: join.screen
        };
    }

    function clearJoin(owner) {
        if (root.join && root.join.owner === owner)
            root.join = null;
    }

    // PluginOverlay joins the mutual-exclusion set above without being a
    // Panel, so the descriptor is built off what a Panel actually carries
    // rather than assumed of whatever holds the slot.
    function _describe(panel) {
        if (!panel || panel.frameRect === undefined)
            return null;
        return {
            isOpen: panel.isOpen === true,
            handingOver: panel.handingOver === true,
            owned: !!panel.owner,
            screenName: panel.screen ? panel.screen.name : "",
            rect: panel.frameRect
        };
    }
}
