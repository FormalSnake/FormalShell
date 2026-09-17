pragma Singleton
import QtQuick

// The join half of Core/PanelRegistry.qml, for Components/Joint.qml under
// test: the same list and the same three calls, with no Quickshell types
// behind them.
QtObject {
    id: root

    property var joins: []

    function setJoin(owner, join) {
        if (!owner || !join)
            return;
        root.joins = root.joins.filter(function (j) {
            return j.owner !== owner || j.edge !== join.edge;
        }).concat([{
            owner: owner,
            edge: join.edge,
            x: join.x,
            width: join.width,
            reach: join.reach,
            screen: join.screen,
            target: join.target === undefined ? null : join.target
        }]);
    }

    function clearJoin(owner, edge) {
        var all = edge === undefined || edge === null;
        function mine(j) { return j.owner === owner && (all || j.edge === edge); }
        if (root.joins.some(mine))
            root.joins = root.joins.filter(function (j) { return !mine(j); });
    }

    function joinOn(edge, screen, target) {
        var t = target === undefined ? null : target;
        var joins = root.joins;
        for (var i = 0; i < joins.length; i++)
            if (joins[i].edge === edge && joins[i].screen === screen && joins[i].target === t)
                return joins[i];
        return null;
    }
}
