import QtQuick
import Quickshell.Io
import "../../Menu/providers.js" as Providers

// Nix package runner state (M12 Task 7; M13b Task 4 added the honest
// end states). `nix search` is seconds-slow and network-bound, so unlike
// calc/emoji the rows can't be computed in a binding: keystrokes arm a
// 500ms debounce (requestSearch, called from onTextChanged/query(), never
// from a binding), one Process runs at a time, and a result is only cached
// when it still answers the latest requested query, anything else is
// dropped and the search re-runs (_startSearch from onExited). Each cached
// answer carries its outcome (Providers.nixSearchOutcome) so rowsFor
// renders NO RESULTS and SEARCH FAILED distinctly instead of one
// ambiguous nothing. `nix` missing from PATH (the sh wrapper's `command -v`
// guard, exit 127) latches `available` false: every nix surface then
// renders the single dim NO NIX row and no further processes spawn.
Item {
    id: root

    property string _query: ""       // the query `_results` answers
    property var _results: []
    property string _outcome: "results"  // how `_query` ended: results|empty|failed
    property string _wantQuery: ""   // latest requested query
    property bool available: true
    property bool _warmed: false     // the eval cache has been paid for
    property bool _warming: false

    function requestSearch(q) {
        q = String(q || "").trim();
        if (q === "" || !root.available || q === root._query) return;
        root._wantQuery = q;
        debounce.restart();
    }

    // Entering a nix surface pays the eval cache off before the reader has
    // typed anything. `nix search` walks the whole nixpkgs attrset the first
    // time it sees a revision (~20s on a real host, measured on nixpkgs
    // 2026-08-31) and answers in about a second afterwards, so the cost lands
    // on the route opening, where a dim INDEXING NIXPKGS row states it,
    // rather than on the first query, where it read as a search that never
    // returned. The query is a token nothing matches: what costs the time is
    // the evaluation, not the term. Doubles as the availability probe, so
    // NO NIX now shows on entry instead of after a first query.
    function requestWarm() {
        if (!root.available || root._warmed || root._warming) return;
        if (searchProc.running) return;
        root._warming = true;
        searchProc._warming = true;
        searchProc._query = "";
        searchProc.command = root._command("__formalshell_warm__");
        searchProc.running = true;
    }

    function _command(q) {
        return ["sh", "-c", 'command -v nix >/dev/null 2>&1 || exit 127; exec nix search nixpkgs "$1" --json', "sh", q];
    }

    function _startSearch() {
        if (searchProc.running || root._wantQuery === "" || !root.available) return;
        searchProc._warming = false;
        searchProc._query = root._wantQuery;
        searchProc.command = root._command(root._wantQuery);
        searchProc.running = true;
    }

    // The rows a nix surface (route level or ":nix" trigger) shows for `q`
    // right now: the honest NO NIX row, a dim SEARCHING note while the
    // cached answer doesn't cover this exact query yet (the debounce +
    // Process round trip runs tens of seconds on a cold real-host eval
    // cache), or the cached end state, result rows, NO RESULTS, SEARCH
    // FAILED. Stale rows for a previous query never linger.
    function rowsFor(q) {
        if (!root.available) return [Providers.nixUnavailableRow()];
        q = String(q || "").trim();
        if (q === "") return root._warming ? [Providers.nixIndexingRow()] : [];
        if (q !== root._query) return [Providers.nixSearchingRow()];
        if (root._outcome === "failed") return [Providers.nixFailedRow()];
        if (root._outcome === "empty") return [Providers.nixNoResultsRow()];
        return Providers.nixRows(root._results);
    }

    Timer {
        id: debounce
        interval: 500
        onTriggered: root._startSearch()
    }

    Process {
        id: searchProc

        property string _query: ""
        property bool _warming: false

        stdout: StdioCollector {
            id: collector
        }
        onExited: exitCode => {
            var outcome = Providers.nixSearchOutcome(exitCode, collector.text);
            if (outcome.state === "unavailable") {
                root.available = false;
                root._warming = false;
                console.warn("Menu: nix not found on PATH, nix runner disabled");
                return;
            }
            // A warm run answers nothing: it exists to have evaluated. Any
            // query typed while it ran is still pending, so start it here.
            if (searchProc._warming) {
                searchProc._warming = false;
                root._warming = false;
                root._warmed = true;
                root._startSearch();
                return;
            }
            if (_query !== root._wantQuery) {
                root._startSearch();
                return;
            }
            root._query = _query;
            root._outcome = outcome.state;
            root._results = outcome.results;
        }
    }
}
