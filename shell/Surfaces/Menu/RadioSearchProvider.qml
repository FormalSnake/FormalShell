import QtQuick
import qs.Services
import "../../Menu/providers.js" as Providers

// Radio Browser search behind the "Search Stations" level and the ":r"
// trigger. Same shape as NixSearchProvider: keystrokes arm a 500ms debounce
// through requestSearch (called from onTextChanged/query(), never from a
// binding), one request runs at a time, and an answer is only kept while it
// still answers the latest query.
Item {
    id: root

    readonly property int maxRows: 50
    readonly property int minChars: 2

    property string _query: ""       // the query `results` answers
    property var results: []
    property string _outcome: "results"  // how `_query` ended: results|empty|failed
    property string _wantQuery: ""
    property bool _busy: false

    function requestSearch(q) {
        q = String(q || "").trim();
        if (q.length < root.minChars || q === root._query) return;
        root._wantQuery = q;
        debounce.restart();
    }

    function _start() {
        if (root._busy || root._wantQuery === "") return;
        var q = root._wantQuery;
        root._busy = true;
        RadioService.search(q, function (found) {
            root._busy = false;
            if (q !== root._wantQuery) {
                root._start();
                return;
            }
            root._query = q;
            root._outcome = found === null ? "failed" : (found.length === 0 ? "empty" : "results");
            root.results = found === null ? [] : found.slice(0, root.maxRows);
        });
    }

    function rowsFor(q) {
        q = String(q || "").trim();
        if (q.length < root.minChars) return [];
        if (q !== root._query) return [Providers.radioSearchingRow()];
        if (root._outcome === "failed") return [Providers.radioFailedRow()];
        if (root._outcome === "empty") return [Providers.radioNoResultsRow()];
        var favs = {};
        RadioService.favorites.forEach(function (s) { favs[s.uuid] = true; });
        return Providers.radioResultRows(root.results, favs);
    }

    function findStation(uuid) {
        var lists = [RadioService.favorites, root.results];
        for (var l = 0; l < lists.length; l++)
            for (var i = 0; i < lists[l].length; i++)
                if (lists[l][i].uuid === uuid) return lists[l][i];
        return null;
    }

    Timer {
        id: debounce
        interval: 500
        onTriggered: root._start()
    }
}
