.pragma library

// The launcher's app-view registry (M38 plan decision D1). A menu route
// listed here renders as a whole view inside the menu card instead of a row
// list: Menu.qml loads the named QML file into one Loader sibling of its
// rowsView/gridView, at the card's own app-view width, and the route's
// chrome (breadcrumb, Escape/backspace-pop, the `menu` IPC) keeps working
// unchanged because all of it keys off currentNodeId, never off which view
// is live.
//
// A registry rather than a third hardcoded route boolean beside
// _isPickerRoute/_isSplitRoute: the ask was a CLASS of route (owner: "a
// system monitor ... should open a full one in the launcher, similar to
// raycast apps"), so adding the next one is one line here plus one file
// under Surfaces/Menu/views/, with no Menu.qml edit at all.
//
// Paths are relative to Surfaces/Menu/, which is where Menu.qml resolves
// them from. This module stays pure (no Qt.resolvedUrl, no imports) so it
// is testable head-on by qmltestrunner.
//
// A view MAY declare `property string query`; Menu.qml binds the live
// search text into it when it does. A view that declares none simply has an
// inert search field, which is the honest state for a view with nothing to
// filter.
var VIEWS = {
    monitor: "views/MonitorView.qml"
};

// hasOwnProperty rather than a bare lookup: "constructor"/"toString"/
// "__proto__" are all truthy on any object literal, and each would
// otherwise resolve to a function and read as a registered route.
function viewFor(routeId) {
    if (typeof routeId !== "string" || routeId === "")
        return "";
    return Object.prototype.hasOwnProperty.call(VIEWS, routeId) ? VIEWS[routeId] : "";
}

function isAppView(routeId) {
    return viewFor(routeId) !== "";
}
