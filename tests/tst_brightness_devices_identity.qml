import QtQuick
import QtTest

// Regression test for the DISPLAY-section drag bug: BrightnessService.devices
// used to be a `property var` computed fresh (new array, new objects) on
// every percent change, and Repeater does a full delegate destroy/recreate
// whenever a JS-array model's identity changes — which dropped the mouse
// grab mid-drag on the brightness slider. Fixed by making `devices` a
// ListModel mutated in place (setProperty/insert/remove). This file can't
// exercise the real BrightnessService (no backlight/DDC in the VM), so it
// proves the underlying Qt/QML mechanism directly: the old shape destroys
// delegates on every value change, the new shape does not.
TestCase {
    id: root
    name: "BrightnessDevicesIdentity"

    property int arrayDestructions: 0
    property int listModelDestructions: 0
    property var arr: [{ deviceId: "backlight", percent: 10 }]

    // Old shape: BrightnessService.devices as it was before the fix.
    Component {
        id: arrayDelegate
        Item {
            required property var modelData
            Component.onDestruction: root.arrayDestructions++
        }
    }

    Repeater {
        id: arrayRepeater
        model: root.arr
        delegate: arrayDelegate
    }

    // New shape: BrightnessService.devices as fixed.
    ListModel {
        id: lm
        ListElement { deviceId: "backlight"; percent: 10 }
    }

    Component {
        id: lmDelegate
        Item {
            required property string deviceId
            required property real percent
            Component.onDestruction: root.listModelDestructions++
        }
    }

    Repeater {
        id: lmRepeater
        model: lm
        delegate: lmDelegate
    }

    function test_plain_array_reassignment_destroys_delegates() {
        arrayDestructions = 0;
        // Reproduces the bug: a brand-new array on every percent change,
        // same as the old `devices: { var list = [...]; return list; }`.
        arr = [{ deviceId: "backlight", percent: 20 }];
        compare(arrayDestructions, 1);
    }

    function test_listmodel_setProperty_keeps_delegate_alive() {
        listModelDestructions = 0;
        lm.setProperty(0, "percent", 20);
        compare(listModelDestructions, 0);
        compare(lmRepeater.itemAt(0).percent, 20);
    }
}
