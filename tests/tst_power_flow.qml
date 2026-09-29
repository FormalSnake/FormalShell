import QtQuick
import QtTest
import "../shell/Power/flow.js" as Flow

TestCase {
    name: "PowerFlow"

    // The g815 on AC with its charge limit at 80, both USB-C ports sourcing.
    readonly property string g815: [
        "@supply ADP0", "type=Mains", "online=1",
        "@supply BAT0", "type=Battery", "status=Not charging", "capacity=80", "power_now=0",
        "voltage_now=16659000", "charge_control_end_threshold=80",
        "@supply ucsi-source-psy-USBC000:001", "type=USB", "online=0", "voltage_now=0", "current_now=3000000",
        "@supply ucsi-source-psy-USBC000:002", "type=USB", "online=0", "voltage_now=0", "current_now=3000000",
        "@typec port0", "power_role=[source] sink", "power_operation_mode=usb_power_delivery", "partner=1", "product=iPhone",
        "@typec port1", "power_role=[source] sink", "power_operation_mode=usb_power_delivery", "partner=1",
        "@ucsi", "1 0x00000000000000011784b12c403b0000", "2 0x00000000000000011504b12c801b0000"
    ].join("\n")

    function _flow(text, extras) {
        return Flow.buildFlow(Flow.parseSnapshot(text), extras || {});
    }

    // decodeConnectorStatus

    function test_decode_g815_connector_one() {
        var c = Flow.decodeConnectorStatus("0x00000000000000011784b12c403b0000");
        compare(c.mode, "PD");
        compare(c.connected, true);
        compare(c.provider, true);
        compare(c.contract.position, 1);
        fuzzyCompare(c.contract.operatingA, 3.0, 0.001);
        fuzzyCompare(c.contract.maxA, 3.0, 0.001);
        compare(c.contract.watts, 15);
    }

    function test_decode_g815_connector_two() {
        var c = Flow.decodeConnectorStatus("0x00000000000000011504b12c801b0000");
        compare(c.connected, true);
        compare(c.provider, true);
        compare(c.contract.watts, 15);
    }

    function test_decode_empty_connector() {
        var c = Flow.decodeConnectorStatus("0x00000000000000000000000000000000");
        compare(c.connected, false);
        compare(c.provider, false);
        compare(c.contract, null);
    }

    function test_decode_higher_object_position_claims_no_watts() {
        // Position 2, 3.00 A: the voltage lives in source capabilities the
        // kernel does not expose, so no wattage.
        var c = Flow.decodeConnectorStatus("0x0000000000000000" + "2000c12c" + "00190000");
        compare(c.contract.position, 2);
        compare(c.contract.watts, null);
    }

    function test_decode_garbage_is_null() {
        compare(Flow.decodeConnectorStatus("0xzz"), null);
    }

    function test_parse_ucsi_lines_with_or_without_prefix() {
        var s = Flow.parseSnapshot("@ucsi\n1 0x00000000000000011784b12c403b0000\n2 00000000000000011504b12c801b0000\n");
        compare(s.ucsi["1"].connected, true);
        compare(s.ucsi["2"].contract.watts, 15);
    }

    // parseSnapshot units

    function test_parse_converts_micro_units() {
        var s = Flow.parseSnapshot("@supply BAT0\ntype=Battery\npower_now=12500000\nvoltage_now=16659000\ncurrent_now=750000\ncapacity=55");
        var b = s.supplies[0];
        compare(b.powerW, 12.5);
        compare(b.voltageV, 16.659);
        compare(b.currentA, 0.75);
        compare(b.capacity, 55);
    }

    function test_parse_missing_key_is_null() {
        var s = Flow.parseSnapshot("@supply ADP0\ntype=Mains\nonline=1");
        compare(s.supplies[0].powerW, null);
        compare(s.supplies[0].limit, null);
        compare(s.supplies[0].online, true);
    }

    function test_parse_role_brackets() {
        compare(Flow.parseBracketed("[source] sink"), "source");
        compare(Flow.parseBracketed("source [sink]"), "sink");
        compare(Flow.parseBracketed("source"), "");
    }

    function test_parse_product_keeps_equals() {
        var s = Flow.parseSnapshot("@typec port0\npartner=1\nproduct=A=B");
        compare(s.ports[0].product, "A=B");
    }

    // heldAtLimit

    function test_held_at_limit() {
        compare(Flow.heldAtLimit("Not charging", 80, 80, true), true);
        compare(Flow.heldAtLimit("Full", 79, 80, true), true);
    }

    function test_not_held_without_adapter_or_below_limit_or_no_limit() {
        compare(Flow.heldAtLimit("Not charging", 80, 80, false), false);
        compare(Flow.heldAtLimit("Not charging", 60, 80, true), false);
        compare(Flow.heldAtLimit("Not charging", 100, null, true), false);
        compare(Flow.heldAtLimit("Not charging", 100, 100, true), false);
        compare(Flow.heldAtLimit("Charging", 80, 80, true), false);
    }

    // buildFlow on the g815

    function test_g815_battery_is_held_with_no_flow() {
        var f = _flow(g815, { gpuW: 22.73 });
        compare(f.battery.state, "held");
        compare(f.battery.detail, "Held at 80%");
        compare(f.battery.value, "80%");
        compare(f.battery.link, "none");
        compare(f.links.battery, "none");
        compare(f.links.adapter, true);
    }

    function test_g815_adapter_has_no_watts() {
        var f = _flow(g815, {});
        compare(f.adapter.online, true);
        compare(f.adapter.value, "");
        compare(f.adapter.detail, "Plugged in");
    }

    function test_g815_laptop_is_measured_parts_only() {
        var f = _flow(g815, { cpuW: null, gpuW: 22.73 });
        compare(f.laptop.caption, "Laptop");
        compare(f.laptop.value, "23W");
        compare(f.laptop.detail, "GPU only");
    }

    function test_laptop_sums_cpu_and_gpu() {
        var f = _flow(g815, { cpuW: 6.4, gpuW: 22.6 });
        compare(f.laptop.detail, "CPU + GPU only");
        compare(f.laptop.value, "29W");
    }

    function test_laptop_with_no_parts_reads_nothing() {
        var f = _flow(g815, { cpuW: null, gpuW: null });
        compare(f.laptop.value, "");
        compare(f.laptop.detail, "No reading");
    }

    function test_g815_ports_from_ucsi() {
        var f = _flow(g815, { iphonePercent: 87.4 });
        compare(f.ports.length, 2);
        compare(f.poweringPorts, 2);
        compare(f.ports[0].name, "USB-C 1");
        compare(f.ports[0].label, "iPhone, 87%");
        compare(f.ports[0].detail, "Powering, 15W contract");
        compare(f.ports[0].wattsKind, "contract");
        compare(f.ports[1].label, "Device");
        compare(f.ports[1].watts, 15);
    }

    function test_ports_without_ucsi_claim_no_number() {
        var text = g815.split("@ucsi")[0];
        var f = _flow(text, {});
        compare(f.ports[0].powering, true);
        compare(f.ports[0].watts, null);
        compare(f.ports[0].detail, "Powering a device, PD");
    }

    function test_iphone_percent_only_on_iphone_port() {
        var f = _flow(g815, { iphonePercent: 50 });
        compare(f.ports[1].label, "Device");
    }

    function test_idle_port() {
        var f = _flow("@typec port0\npower_role=[source] sink\npower_operation_mode=usb", {});
        compare(f.ports[0].connected, false);
        compare(f.ports[0].powering, false);
        compare(f.ports[0].detail, "Nothing attached");
    }

    function test_port_measured_from_online_source_supply() {
        var text = [
            "@supply ucsi-source-psy-USBC000:001", "type=USB", "online=1", "voltage_now=9000000", "current_now=1500000",
            "@typec port0", "power_role=[source] sink", "partner=1"
        ].join("\n");
        var f = _flow(text, {});
        compare(f.ports[0].wattsKind, "measured");
        fuzzyCompare(f.ports[0].watts, 13.5, 0.001);
        compare(f.ports[0].detail, "Powering, 14W");
    }

    function test_source_supply_limit_is_not_a_measurement() {
        var f = _flow(g815.split("@ucsi")[0], {});
        compare(f.ports[0].wattsKind, "");
    }

    // battery directions

    function test_discharging_uses_battery_draw_as_system() {
        var f = _flow("@supply BAT0\ntype=Battery\nstatus=Discharging\ncapacity=60\npower_now=11200000\n@supply AC\ntype=Mains\nonline=0", { cpuW: 3 });
        compare(f.battery.state, "discharging");
        compare(f.links.battery, "out");
        compare(f.links.adapter, false);
        compare(f.laptop.detail, "System draw");
        compare(f.laptop.value, "11W");
        compare(f.adapter.detail, "Unplugged");
        compare(f.battery.detail, "Discharging 11W");
    }

    function test_charging_flows_into_battery() {
        var f = _flow("@supply BAT0\ntype=Battery\nstatus=Charging\ncapacity=40\npower_now=30000000\n@supply ADP0\ntype=Mains\nonline=1", {});
        compare(f.battery.state, "charging");
        compare(f.links.battery, "in");
        compare(f.battery.watts, 30);
        compare(f.battery.icon, "battery-charging");
    }

    function test_adapter_reports_watts_when_kernel_does() {
        var f = _flow("@supply ADP0\ntype=Mains\nonline=1\nvoltage_now=20000000\ncurrent_now=3250000\n@supply BAT0\ntype=Battery\nstatus=Charging\ncapacity=40", {});
        compare(f.adapter.value, "65W");
    }

    function test_current_and_voltage_give_battery_watts() {
        var f = _flow("@supply BAT0\ntype=Battery\nstatus=Discharging\ncapacity=40\nvoltage_now=12000000\ncurrent_now=1000000", {});
        compare(f.battery.watts, 12);
    }

    function test_usbc_charger_counts_as_adapter() {
        var f = _flow("@supply BAT0\ntype=Battery\nstatus=Charging\ncapacity=40\n@typec port0\npower_role=source [sink]\npartner=1", {});
        compare(f.adapter.online, true);
        compare(f.ports[0].supplying, true);
        compare(f.ports[0].detail, "Powering the laptop");
    }

    function test_device_scope_battery_is_ignored() {
        var f = _flow("@supply hidpp\ntype=Battery\nscope=Device\ncapacity=50", {});
        compare(f.battery.present, false);
        compare(f.available, false);
    }

    function test_nothing_at_all_is_unavailable() {
        var f = _flow("", {});
        compare(f.available, false);
        compare(f.ports.length, 0);
        compare(f.battery.present, false);
        compare(f.adapter.present, false);
    }

    function test_sample_matches_the_g815_reading() {
        var f = Flow.sampleFlow();
        compare(f.battery.state, "held");
        compare(f.poweringPorts, 2);
        compare(f.laptop.detail, "GPU only");
    }

    function test_collect_command_is_a_shell_script() {
        var argv = Flow.collectCommand();
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        verify(argv[2].indexOf("/run/formalshell/ucsi") >= 0);
    }
}
