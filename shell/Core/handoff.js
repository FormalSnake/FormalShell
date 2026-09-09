.pragma library

// PanelRegistry's handoff bookkeeping (M53 D5), as a pure function so it is
// testable without the Quickshell types the registry pulls in, the same
// split cursor.js and geometry.js already use.
//
// Opening B while A is open is one card changing shape rather than two
// surfaces crossing: A's frame travels to B's rect while their contents
// crossfade, and since both are a `card` fill with the same border and
// radius, two frames on one trajectory read as one card moving and
// resizing. That reading only holds where the two frames really are
// interchangeable, which is what the four refusals below are.
//
// `from` and `to` are { isOpen, handingOver, owned, screenName, rect }
// descriptors the registry builds off the two Panel instances. `rect` is
// the outgoing frame's { x, y, width, height } in the output's own
// coordinates, which both windows share since each covers the whole output.
// The answer is that rect, or null for an open that keeps the ordinary
// enter/exit recipe.
function outgoingRect(from, to) {
    if (!from || !to)
        return null;
    // A popout hanging off another one (the tray's menu over its second bar,
    // a chevron widget's own panel) is a second card by design, and the tray
    // menu takes the `popover` fill at `radiusMd` rather than the panel's:
    // there was never one card here to hand over.
    if (from.owned || to.owned)
        return null;
    // Gone already, or already handing its card to someone else.
    if (!from.isOpen || from.handingOver)
        return null;
    // Two outputs are two cards. Wayland hands clients no cross-window
    // global coordinates either, so a rect off another output would not mean
    // anything on this one.
    if (!from.screenName || !to.screenName || from.screenName !== to.screenName)
        return null;
    var rect = from.rect;
    if (!rect || !(rect.width > 0) || !(rect.height > 0))
        return null;
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
}
