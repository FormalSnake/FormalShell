.pragma library

// Where the power goes (adapter, laptop, battery, USB-C ports), built from
// one sysfs snapshot. No QML/Qt dependency: PowerPanel.qml runs
// collectCommand(), hands the text to buildFlow() with whatever it measured
// itself (RAPL, the dGPU, the iPhone bridge), and the Components/PowerFlow
// drawing reads the result. Everything the kernel does not report stays
// null, and the drawing prints a missing figure as absent.
//
// Units, per Documentation/ABI/testing/sysfs-class-power: power_now is
// microwatts, voltage_now microvolts, current_now microamps, capacity and
// charge_control_end_threshold whole percents.

var FIXED_SUPPLY_VOLTS = 5;

function collectCommand() {
    var supplyKeys = "type scope online status capacity power_now voltage_now current_now charge_control_end_threshold";
    var script = [
        "for d in /sys/class/power_supply/*; do",
        "[ -d \"$d\" ] || continue;",
        "echo \"@supply ${d##*/}\";",
        "for k in " + supplyKeys + "; do [ -r \"$d/$k\" ] && echo \"$k=$(cat \"$d/$k\" 2>/dev/null)\"; done;",
        "done;",
        "for d in /sys/class/typec/port[0-9]*; do",
        "case \"$d\" in *-partner) continue;; esac;",
        "[ -d \"$d\" ] || continue;",
        "echo \"@typec ${d##*/}\";",
        "for k in power_role power_operation_mode; do [ -r \"$d/$k\" ] && echo \"$k=$(cat \"$d/$k\" 2>/dev/null)\"; done;",
        "if [ -e \"$d-partner\" ]; then echo partner=1;",
        "for p in \"$d-partner\"/*/product; do [ -r \"$p\" ] && echo \"product=$(cat \"$p\" 2>/dev/null)\"; done; fi;",
        "done;",
        "echo @ucsi; cat /run/formalshell/ucsi 2>/dev/null; true"
    ].join(" ");
    return ["sh", "-c", script];
}

function _num(text) {
    if (text === undefined || text === null || String(text).trim() === "")
        return null;
    var n = Number(text);
    return isFinite(n) ? n : null;
}

function _micro(text) {
    var n = _num(text);
    return n === null ? null : n / 1000000;
}

// `@supply NAME`, `@typec portN` and `@ucsi` headers, `key=value` lines in
// the first two, `<connector> <0x hex>` lines in the last. A key the
// kernel does not expose is simply not in the output, so it reads null.
function parseSnapshot(text) {
    var out = { supplies: [], ports: [], ucsi: {} };
    var current = null;
    var section = "";
    var lines = String(text || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line === "")
            continue;

        if (line.charAt(0) === "@") {
            var parts = line.split(/\s+/);
            section = parts[0];
            if (section === "@supply") {
                current = { name: parts[1], type: "", scope: "", online: null, status: "", capacity: null,
                    powerW: null, voltageV: null, currentA: null, limit: null };
                out.supplies.push(current);
            } else if (section === "@typec") {
                current = { name: parts[1], index: parseInt(String(parts[1]).replace(/\D+/g, ""), 10), role: "",
                    mode: "", partner: false, product: "" };
                out.ports.push(current);
            }
            continue;
        }

        if (section === "@ucsi") {
            var m = line.match(/^(\d+)\s+((?:0x)?[0-9a-fA-F]+)$/);
            if (m)
                out.ucsi[m[1]] = decodeConnectorStatus(m[2]);
            continue;
        }

        var eq = line.indexOf("=");
        if (eq < 0 || !current)
            continue;
        var key = line.slice(0, eq);
        var value = line.slice(eq + 1).trim();

        if (section === "@supply") {
            if (key === "type") current.type = value;
            else if (key === "scope") current.scope = value;
            else if (key === "online") current.online = value === "" ? null : value !== "0";
            else if (key === "status") current.status = value;
            else if (key === "capacity") current.capacity = _num(value);
            else if (key === "power_now") current.powerW = _micro(value);
            else if (key === "voltage_now") current.voltageV = _micro(value);
            else if (key === "current_now") current.currentA = _micro(value);
            else if (key === "charge_control_end_threshold") current.limit = _num(value);
        } else if (section === "@typec") {
            if (key === "power_role") current.role = parseBracketed(value);
            else if (key === "power_operation_mode") current.mode = value;
            else if (key === "partner") current.partner = value === "1";
            else if (key === "product") current.product = value;
        }
    }
    return out;
}

// sysfs marks the selected entry of a choice attribute with brackets:
// "[source] sink" is a port currently sourcing.
function parseBracketed(text) {
    var m = String(text || "").match(/\[([^\]]+)\]/);
    return m ? m[1] : "";
}

var OPERATION_MODES = ["", "USB", "BC", "PD", "USB-C 1.5A", "USB-C 3A"];

// UCSI GET_CONNECTOR_STATUS (0x12 | connector << 16) response, the 128-bit
// value the debugfs `response` file prints as one hex string. Bits 16-18
// are the power operation mode, bit 19 connected, bit 20 the power
// direction (1 = this machine provides), bits 32-63 the request data
// object of the negotiated contract.
function decodeConnectorStatus(hex) {
    var digits = String(hex).replace(/^0x/i, "");
    if (!/^[0-9a-f]{1,32}$/i.test(digits))
        return null;
    while (digits.length < 32)
        digits = "0" + digits;
    var lo = parseInt(digits.slice(-8), 16);
    var rdo = parseInt(digits.slice(-16, -8), 16);

    var mode = (lo >>> 16) & 7;
    var position = (rdo >>> 28) & 0xf;
    // 10 mA units. Position 1 is always the 5 V vSafe5V object; any other
    // position needs the source capabilities to know its voltage, which
    // the kernel does not hand out, so no wattage is claimed for it.
    var opA = ((rdo >>> 10) & 0x3ff) * 0.01;
    var maxA = (rdo & 0x3ff) * 0.01;
    return {
        mode: OPERATION_MODES[mode] || "",
        connected: ((lo >>> 19) & 1) === 1,
        provider: ((lo >>> 20) & 1) === 1,
        contract: position === 0 ? null : {
            position: position,
            operatingA: opA,
            maxA: maxA,
            watts: position === 1 ? Math.round(FIXED_SUPPLY_VOLTS * maxA * 10) / 10 : null
        }
    };
}

function wattText(w) {
    if (w === null || w === undefined)
        return "";
    var abs = Math.abs(w);
    return (abs >= 10 ? String(Math.round(abs)) : abs.toFixed(1)) + "W";
}

function _sumKnown(parts) {
    var total = 0;
    var names = [];
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].w === null || parts[i].w === undefined)
            continue;
        total += parts[i].w;
        names.push(parts[i].name);
    }
    return names.length === 0 ? null : { watts: total, names: names };
}

// Watts a supply reports, from power_now or from voltage times current.
// A source port's current_now is a limit rather than a reading, so this is
// only asked of the mains adapter and of a port that says it is online.
function _supplyWatts(s) {
    if (s.powerW !== null && s.powerW > 0)
        return s.powerW;
    if (s.voltageV !== null && s.currentA !== null && s.voltageV > 0 && s.currentA > 0)
        return s.voltageV * s.currentA;
    return null;
}

function _isBattery(s) {
    return s.type === "Battery" && s.scope !== "Device";
}

function _isAdapter(s) {
    return !_isBattery(s) && s.type !== "" && s.name.indexOf("source") < 0 && s.scope !== "Device";
}

// A battery sitting at its charge limit reports "Not charging" (or "Full"
// on drivers that call the limit full) at a capacity within a percent of
// charge_control_end_threshold, with the adapter present.
function heldAtLimit(status, capacity, limit, adapterOnline) {
    if (!adapterOnline || capacity === null || limit === null || limit >= 100)
        return false;
    if (status !== "Not charging" && status !== "Full")
        return false;
    return capacity >= limit - 1;
}

function _battery(supply, adapterOnline) {
    if (!supply)
        return { present: false, state: "none", percent: null, watts: null, limit: null,
            icon: "battery", caption: "Battery", value: "", detail: "", link: "none" };

    var status = supply.status;
    var held = heldAtLimit(status, supply.capacity, supply.limit, adapterOnline);
    var state = held ? "held"
        : status === "Charging" ? "charging"
        : status === "Discharging" ? "discharging"
        : status === "Full" ? "full"
        : status === "Not charging" ? "idle"
        : "unknown";
    var watts = supply.powerW !== null && supply.powerW > 0 ? supply.powerW : _supplyWatts(supply);
    var flowing = state === "charging" || state === "discharging";

    var detail = state === "held" ? "Held at " + supply.limit + "%"
        : state === "charging" ? "Charging" + (watts !== null ? " " + wattText(watts) : "")
        : state === "discharging" ? "Discharging" + (watts !== null ? " " + wattText(watts) : "")
        : state === "full" ? "Full"
        : state === "idle" ? "Not charging"
        : "";

    return {
        present: true,
        state: state,
        percent: supply.capacity,
        watts: flowing ? watts : null,
        limit: supply.limit,
        icon: state === "charging" ? "battery-charging" : "battery",
        caption: "Battery",
        value: supply.capacity === null ? "" : Math.round(supply.capacity) + "%",
        detail: detail,
        link: state === "charging" ? "in" : state === "discharging" ? "out" : "none"
    };
}

function _portSupply(supplies, index) {
    for (var i = 0; i < supplies.length; i++) {
        var n = supplies[i].name;
        if (n.indexOf("source") >= 0 && parseInt(n.slice(n.lastIndexOf(":") + 1), 10) === index + 1)
            return supplies[i];
    }
    return null;
}

// The kernel numbers typec ports from 0 and UCSI connectors, and the
// ucsi-source-psy-...:00N supplies, from 1.
function _port(port, snapshot, extras) {
    var ucsi = snapshot.ucsi[String(port.index + 1)] || null;
    var supply = _portSupply(snapshot.supplies, port.index);
    var connected = ucsi ? ucsi.connected : port.partner;
    var provider = ucsi ? (ucsi.connected && ucsi.provider) : (port.partner && port.role === "source");
    var consumer = connected && !provider && (ucsi ? true : port.role === "sink");
    var mode = ucsi && ucsi.mode ? ucsi.mode : (port.mode === "usb_power_delivery" ? "PD" : port.mode);

    var watts = null;
    var kind = "";
    if (provider && supply && supply.online === true && supply.voltageV > 0 && supply.currentA > 0) {
        watts = supply.voltageV * supply.currentA;
        kind = "measured";
    } else if (provider && ucsi && ucsi.contract && ucsi.contract.watts !== null) {
        watts = ucsi.contract.watts;
        kind = "contract";
    }

    var product = port.product;
    var percent = product && /iphone/i.test(product) && extras.iphonePercent !== null && extras.iphonePercent !== undefined
        ? Math.round(extras.iphonePercent) : null;

    var detail = !connected ? "Nothing attached"
        : provider ? (watts !== null ? "Powering, " + wattText(watts) + (kind === "contract" ? " contract" : "") : "Powering a device")
        : consumer ? "Powering the laptop"
        : "Connected";
    if (connected && provider && mode && watts === null)
        detail += ", " + mode;

    return {
        name: "USB-C " + (port.index + 1),
        connected: connected,
        powering: provider,
        supplying: consumer,
        label: !connected ? "" : (product || "Device") + (percent !== null ? ", " + percent + "%" : ""),
        detail: detail,
        watts: watts,
        wattsKind: kind,
        mode: mode
    };
}

// extras: { cpuW, gpuW, iphonePercent }, each null when its source is
// unavailable. On battery the laptop node is the battery's own draw; on AC
// power_now is 0, so the node is the sum of the parts measured here and is
// captioned with exactly which parts those are.
function buildFlow(snapshot, extras) {
    extras = extras || {};
    var supplies = snapshot.supplies;
    var batterySupply = null;
    var adapterSupply = null;
    var adapterOnline = false;

    for (var i = 0; i < supplies.length; i++) {
        if (_isBattery(supplies[i]) && !batterySupply)
            batterySupply = supplies[i];
        else if (_isAdapter(supplies[i])) {
            if (!adapterSupply || supplies[i].online === true)
                adapterSupply = supplies[i];
            if (supplies[i].online === true)
                adapterOnline = true;
        }
    }

    var ports = snapshot.ports.map(function (p) { return _port(p, snapshot, extras); });
    var usbcCharger = ports.some(function (p) { return p.supplying; });
    adapterOnline = adapterOnline || usbcCharger;

    var battery = _battery(batterySupply, adapterOnline);
    var adapterWatts = adapterSupply && adapterSupply.online === true ? _supplyWatts(adapterSupply) : null;
    var adapterPresent = adapterSupply !== null || usbcCharger;

    var laptopWatts = null;
    var laptopDetail = "No reading";
    if (battery.state === "discharging" && battery.watts !== null) {
        laptopWatts = battery.watts;
        laptopDetail = "System draw";
    } else {
        var parts = _sumKnown([{ name: "CPU", w: extras.cpuW }, { name: "GPU", w: extras.gpuW }]);
        if (parts) {
            laptopWatts = parts.watts;
            laptopDetail = parts.names.join(" + ") + " only";
        }
    }

    var poweringPorts = ports.filter(function (p) { return p.powering; }).length;

    return {
        available: adapterPresent || battery.present || ports.length > 0,
        adapter: {
            present: adapterPresent,
            online: adapterOnline,
            icon: adapterOnline ? "plug-zap" : "plug",
            caption: "Adapter",
            value: !adapterPresent ? "" : adapterWatts !== null ? wattText(adapterWatts) : "",
            detail: !adapterPresent ? "" : adapterOnline ? (adapterWatts !== null ? "" : "Plugged in") : "Unplugged"
        },
        laptop: {
            icon: "laptop",
            caption: "Laptop",
            value: laptopWatts !== null ? wattText(laptopWatts) : "",
            detail: laptopDetail
        },
        battery: battery,
        links: {
            adapter: adapterOnline,
            battery: battery.link
        },
        ports: ports,
        poweringPorts: poweringPorts
    };
}

// The measured watts shown in the gallery come from this fixed snapshot,
// the g815 read over sysfs and UCSI on 2026-09-29 (AC, charge limit 80,
// both USB-C ports supplying a MacBook and an iPhone), never from a
// running machine. The iPhone's 87 percent is a stand-in for the bridge.
function sampleFlow() {
    var snapshot = parseSnapshot([
        "@supply ADP0", "type=Mains", "online=1",
        "@supply BAT0", "type=Battery", "status=Not charging", "capacity=80", "power_now=0",
        "voltage_now=16659000", "charge_control_end_threshold=80",
        "@supply ucsi-source-psy-USBC000:001", "type=USB", "online=0", "voltage_now=0", "current_now=3000000",
        "@supply ucsi-source-psy-USBC000:002", "type=USB", "online=0", "voltage_now=0", "current_now=3000000",
        "@typec port0", "power_role=[source] sink", "power_operation_mode=usb_power_delivery", "partner=1", "product=iPhone",
        "@typec port1", "power_role=[source] sink", "power_operation_mode=usb_power_delivery", "partner=1",
        "@ucsi", "1 0x00000000000000011784b12c403b0000", "2 0x00000000000000011504b12c801b0000"
    ].join("\n"));
    return buildFlow(snapshot, { cpuW: null, gpuW: 22.73, iphonePercent: 87 });
}
