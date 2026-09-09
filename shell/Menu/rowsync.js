.pragma library

// The keyed-list diff behind M53 D6 ("lists never reset"): given the row ids
// a ListModel currently holds and the ids it should hold, the ops that walk
// one to the other, in the order a ListModel has to be given them.
//
// Why a diff at all: a JS array handed to a ListView is a model reset on
// every keystroke, so no row survives a re-rank and nothing can move. A
// ListModel synced by id keeps the row that was already there, which is what
// lets the view's add/displaced/move transitions say what actually changed.
//
// `limit` is the point past which motion stops explaining anything: a diff
// touching more rows than that is a rebuild, and the caller resets instead.
// Duplicate ids on either side mean identity is not a thing here at all
// (nothing in the launcher produces them, the process table cannot), so
// those reset too rather than guessing which of two rows is which.

function plan(currentIds, nextIds, limit) {
    var reset = { reset: true, ops: [] };
    var i, j;
    var n = nextIds.length;
    if (currentIds.length === 0 || n === 0)
        return reset;

    var nextAt = {};
    for (i = 0; i < n; i++) {
        if (nextAt[nextIds[i]] !== undefined)
            return reset;
        nextAt[nextIds[i]] = i;
    }
    var currentAt = {};
    for (j = 0; j < currentIds.length; j++) {
        if (currentAt[currentIds[j]] !== undefined)
            return reset;
        currentAt[currentIds[j]] = j;
    }

    // What the change costs, counted before any of it is applied: rows
    // leaving, rows arriving, and rows that stay but no longer sit in the
    // same order relative to each other. The last term is a positional
    // comparison rather than a longest-common-subsequence, which is O(n)
    // instead of O(n²) and only ever over-counts, so the threshold errs
    // toward resetting.
    var touched = 0;
    var survivors = [];
    for (j = 0; j < currentIds.length; j++) {
        if (nextAt[currentIds[j]] === undefined)
            touched++;
        else
            survivors.push(currentIds[j]);
    }
    var wanted = [];
    for (i = 0; i < n; i++) {
        if (currentAt[nextIds[i]] === undefined)
            touched++;
        else
            wanted.push(nextIds[i]);
    }
    for (i = 0; i < survivors.length; i++) {
        if (survivors[i] !== wanted[i])
            touched++;
    }
    if (touched > limit)
        return reset;
    if (touched === 0)
        return { reset: false, ops: [] };

    var ops = [];
    var work = currentIds.slice();
    // Removals back to front, so every index still ahead of the cursor is
    // the index the model will see when its turn comes.
    for (j = work.length - 1; j >= 0; j--) {
        if (nextAt[work[j]] === undefined) {
            work.splice(j, 1);
            ops.push({ op: "remove", index: j });
        }
    }
    var at = {};
    for (j = 0; j < work.length; j++)
        at[work[j]] = j;
    for (i = 0; i < n; i++) {
        var id = nextIds[i];
        if (work[i] === id)
            continue;
        var from = at[id];
        if (from === undefined) {
            work.splice(i, 0, id);
            ops.push({ op: "insert", index: i, id: id });
        } else {
            work.splice(from, 1);
            work.splice(i, 0, id);
            ops.push({ op: "move", from: from, to: i });
        }
        for (j = i; j < work.length; j++)
            at[work[j]] = j;
    }
    return { reset: false, ops: ops };
}

// The ids a model holds, for the caller that keeps them nowhere else.
function idsOf(rows, key) {
    var ids = [];
    for (var i = 0; i < rows.length; i++)
        ids.push(rows[i][key]);
    return ids;
}
