import QtQuick
import QtTest
import "../shell/Menu/rowsync.js" as RowSync

// The keyed-list diff (M53 D6). Menu.qml and MonitorView.qml both hand it the
// ids their model holds and the ids it should hold, so what is tested here is
// that replaying the ops it returns really does walk one list to the other.
TestCase {
    name: "RowSync"

    // What a ListModel does with the ops, so a plan can be checked against
    // the list it claims to produce rather than against itself.
    function replay(ids, ops) {
        var work = ids.slice();
        for (var i = 0; i < ops.length; i++) {
            var op = ops[i];
            if (op.op === "remove")
                work.splice(op.index, 1);
            else if (op.op === "insert")
                work.splice(op.index, 0, op.id);
            else
                work.splice(op.to, 0, work.splice(op.from, 1)[0]);
        }
        return work;
    }

    function check(from, to) {
        var plan = RowSync.plan(from, to, 64);
        verify(!plan.reset);
        compare(replay(from, plan.ops).join(","), to.join(","));
        return plan;
    }

    function test_an_unchanged_list_needs_no_ops() {
        var plan = RowSync.plan(["a", "b", "c"], ["a", "b", "c"], 64);
        verify(!plan.reset);
        compare(plan.ops.length, 0);
    }

    function test_a_row_leaving_is_one_removal() {
        var plan = check(["a", "b", "c"], ["a", "c"]);
        compare(plan.ops.length, 1);
        compare(plan.ops[0].op, "remove");
        compare(plan.ops[0].index, 1);
    }

    function test_a_row_arriving_lands_at_its_own_place() {
        var plan = check(["a", "c"], ["a", "b", "c"]);
        compare(plan.ops.length, 1);
        compare(plan.ops[0].op, "insert");
        compare(plan.ops[0].index, 1);
        compare(plan.ops[0].id, "b");
    }

    function test_two_rows_swapping_rank_is_a_move() {
        var plan = check(["a", "b"], ["b", "a"]);
        compare(plan.ops.length, 1);
        compare(plan.ops[0].op, "move");
    }

    function test_removals_insertions_and_moves_together() {
        check(["a", "b", "c", "d", "e"], ["e", "c", "f", "a"]);
    }

    function test_a_whole_new_list_still_replays() {
        check(["a", "b", "c"], ["d", "a", "e", "b", "f"]);
    }

    function test_a_reordered_process_table_replays() {
        var from = [];
        var to = [];
        for (var i = 0; i < 40; i++)
            from.push("p" + i);
        for (i = 0; i < 40; i++)
            to.push("p" + i);
        // Four processes overtake their neighbours on one poll.
        to.splice(30, 1);
        to.splice(3, 0, "p30");
        to.splice(20, 1);
        to.splice(1, 0, "p19");
        check(from, to);
    }

    // The threshold (M53 D6): past it the change is a rebuild, and motion
    // explaining a rebuild is noise.
    function test_a_change_bigger_than_the_limit_resets() {
        var plan = RowSync.plan(["a", "b", "c"], ["d", "e", "f"], 4);
        verify(plan.reset);
    }

    function test_the_same_change_under_the_limit_does_not_reset() {
        verify(!RowSync.plan(["a", "b", "c"], ["d", "e", "f"], 64).reset);
    }

    function test_an_empty_list_on_either_side_resets() {
        verify(RowSync.plan([], ["a"], 64).reset);
        verify(RowSync.plan(["a"], [], 64).reset);
    }

    // Identity is the whole mechanism, so two rows claiming the same id are
    // not something to guess at.
    function test_duplicate_ids_reset() {
        verify(RowSync.plan(["a", "a"], ["a"], 64).reset);
        verify(RowSync.plan(["a", "b"], ["a", "a"], 64).reset);
    }

    function test_ids_are_read_off_the_rows_by_key() {
        var ids = RowSync.idsOf([{ pid: 7 }, { pid: 9 }], "pid");
        compare(ids.join(","), "7,9");
    }
}
