import QtQuick
import QtTest

// A closed surface has to cost nothing. shell/Surfaces/Menu/Menu.qml builds
// its whole tree in one binding: the JSONC merge, every provider, the frecency
// sort and a Quickshell.iconPath call per installed app. A provider that read
// CompositorService.windows straight out of that binding subscribed the tree
// to it, so QML rebuilt the lot on every window open, close AND title change
// with the launcher closed and nobody looking. Switching a browser tab did it
// (shipped, found by hand 2026-08-26).
//
// The fix is the live read, `isOpen ? Service.thing : []`, on Menu.qml's
// _liveWindows and _liveClipboardItems. What this file pins is the engine
// behaviour that idiom rests on, not the two properties that use it today, so
// it still guards the next surface that grows one: the untaken branch of a
// ternary must not register a dependency, and taking it again must resubscribe.
// The ungated control at the bottom is what makes the gated cases mean
// anything. It rides the same churn and proves the tracker really does
// subscribe without the gate, so a rig that had quietly stopped churning would
// fail there instead of passing everywhere.
TestCase {
    id: testCase
    name: "ClosedSurfaceIdle"
    width: 200
    height: 200
    visible: true
    when: windowShown

    Component {
        id: rigComponent

        Item {
            id: rig

            property alias service: svc
            property alias gated: gatedSurface
            property alias ungated: ungatedSurface

            // Stands in for a shell service singleton. Quickshell is not
            // importable on the dev machine, and it does not need to be: the
            // subscription is the QML engine's, and a plain QtObject property
            // is tracked exactly the way CompositorService.windows is.
            QtObject {
                id: svc

                property var windows: []
                property int changes: 0

                // One window whose title moves, which is the cheapest event
                // the real service emits and the one that fired the bug.
                function churn() {
                    svc.changes++;
                    svc.windows = [{ id: "0x1", title: "tab " + svc.changes }];
                }
            }

            QtObject {
                id: gatedSurface

                property bool isOpen: false

                // The build counter stands in for the tree build's real cost.
                // It lives inside a var the binding only ever reads, and is
                // bumped by mutating that object in place, so counting cannot
                // notify anything and cannot become a dependency of the thing
                // it is measuring.
                property var stats: ({ builds: 0 })

                readonly property var liveWindows: gatedSurface.isOpen ? (svc.windows || []) : []
                readonly property var tree: gatedSurface.build(gatedSurface.liveWindows)

                function build(windows) {
                    gatedSurface.stats.builds++;
                    return {
                        rows: windows.length,
                        mark: windows.length ? windows[0].title : ""
                    };
                }
            }

            // The same shape with the gate taken out, driven by the same churn.
            QtObject {
                id: ungatedSurface

                property bool isOpen: false
                property var stats: ({ builds: 0 })

                readonly property var liveWindows: svc.windows || []
                readonly property var tree: ungatedSurface.build(ungatedSurface.liveWindows)

                function build(windows) {
                    ungatedSurface.stats.builds++;
                    return {
                        rows: windows.length,
                        mark: windows.length ? windows[0].title : ""
                    };
                }
            }
        }
    }

    function newRig() {
        var rig = createTemporaryObject(rigComponent, testCase);
        verify(rig !== null);
        // Both trees are built once at completion, so every case below counts
        // rebuilds from a settled surface rather than from zero.
        compare(rig.gated.stats.builds, 1);
        compare(rig.ungated.stats.builds, 1);
        return rig;
    }

    function churn(rig, times) {
        for (var i = 0; i < times; i++)
            rig.service.churn();
    }

    function test_a_closed_surface_ignores_the_service() {
        var rig = newRig();
        churn(rig, 20);
        compare(rig.gated.stats.builds, 1, "closed surface rebuilt on service churn");
        compare(rig.gated.tree.rows, 0);
    }

    // The gate buys idleness, not staleness: opening has to re-read and
    // resubscribe, or the launcher would show window state from whenever it
    // last closed.
    function test_opening_re_reads_and_resubscribes() {
        var rig = newRig();
        churn(rig, 20);
        rig.gated.isOpen = true;
        compare(rig.gated.stats.builds, 2);
        compare(rig.gated.tree.rows, 1);
        compare(rig.gated.tree.mark, "tab 20");
    }

    // The other half of the same contract. A gate that froze the value while
    // the surface was up would be worse than the bug it fixes.
    function test_an_open_surface_follows_the_service() {
        var rig = newRig();
        rig.gated.isOpen = true;
        compare(rig.gated.stats.builds, 2);
        churn(rig, 3);
        compare(rig.gated.stats.builds, 5);
        compare(rig.gated.tree.mark, "tab 3");
    }

    // Closing costs one rebuild, for the empty branch, and then nothing.
    function test_closing_drops_the_subscription_again() {
        var rig = newRig();
        rig.gated.isOpen = true;
        churn(rig, 3);
        var settled = rig.gated.stats.builds;
        rig.gated.isOpen = false;
        compare(rig.gated.stats.builds, settled + 1);
        churn(rig, 20);
        compare(rig.gated.stats.builds, settled + 1, "closed surface stayed subscribed");
        compare(rig.gated.tree.rows, 0);
    }

    // The control. Same churn, same shape, no ternary: this MUST rebuild every
    // time, or the cases above are passing on a rig that never churns.
    function test_an_ungated_read_rebuilds_while_closed() {
        var rig = newRig();
        compare(rig.ungated.isOpen, false);
        churn(rig, 20);
        compare(rig.ungated.stats.builds, 21, "ungated read did not subscribe to the service");
        compare(rig.ungated.tree.mark, "tab 20");
        compare(rig.gated.stats.builds, 1);
    }
}
