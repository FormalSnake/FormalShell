#!/usr/bin/env python3
"""A BlueZ that is only scanning, for FormalShell's --bluez-rssi smoke leg.

Owns org.bluez on the bus it is pointed at and serves the same objects
crates/fs-bluez/tests/fake_bluez.rs does: one powered adapter, discovering
on a scan the shell did not start, one paired device and a handful of
strangers. Then it does what g815's BlueZ did at idle: a Device1
PropertiesChanged carrying only RSSI at --rate per minute, round robin over
every device, and a new stranger every 10 seconds.

Methods are not served; the shell must not call any of them while its panel
is shut, and a call shows up in the stub's own log as unhandled.
"""
import argparse
import random
import sys

from gi.repository import Gio, GLib

ADAPTER = "/org/bluez/hci0"


def device(address, alias, paired):
    return {
        "Address": GLib.Variant("s", address),
        "Name": GLib.Variant("s", alias),
        "Alias": GLib.Variant("s", alias),
        "Icon": GLib.Variant("s", "audio-headset" if paired else ""),
        "Paired": GLib.Variant("b", paired),
        "Bonded": GLib.Variant("b", paired),
        "Trusted": GLib.Variant("b", paired),
        "Connected": GLib.Variant("b", False),
        "Adapter": GLib.Variant("o", ADAPTER),
        "RSSI": GLib.Variant("n", -60),
    }


def path_of(address):
    return ADAPTER + "/dev_" + address.replace(":", "_")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--address", required=True, help="the bus to own org.bluez on")
    ap.add_argument("--rate", type=int, default=700, help="RSSI signals per minute")
    ap.add_argument("--count", required=True, help="file the signal count is written to")
    args = ap.parse_args()

    bus = Gio.DBusConnection.new_for_address_sync(
        args.address,
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
        None,
        None,
    )
    objects = {
        ADAPTER: {
            "org.bluez.Adapter1": {
                "Address": GLib.Variant("s", "00:11:22:33:44:55"),
                "Name": GLib.Variant("s", "rig"),
                "Alias": GLib.Variant("s", "rig"),
                "Powered": GLib.Variant("b", True),
                "PowerState": GLib.Variant("s", "on"),
                "Discovering": GLib.Variant("b", True),
                "Discoverable": GLib.Variant("b", False),
                "Pairable": GLib.Variant("b", True),
            }
        },
        path_of("AA:BB:CC:DD:EE:FF"): {"org.bluez.Device1": device("AA:BB:CC:DD:EE:FF", "Headphones", True)},
    }
    for i in range(6):
        a = "11:22:33:44:55:%02X" % i
        objects[path_of(a)] = {"org.bluez.Device1": device(a, "", False)}

    def managed():
        return GLib.Variant(
            "(a{oa{sa{sv}}})",
            ({p: {i: dict(props) for i, props in ifaces.items()} for p, ifaces in objects.items()},),
        )

    node = Gio.DBusNodeInfo.new_for_xml(
        """<node><interface name="org.freedesktop.DBus.ObjectManager">
        <method name="GetManagedObjects"><arg type="a{oa{sa{sv}}}" direction="out"/></method>
        <signal name="InterfacesAdded"><arg type="o"/><arg type="a{sa{sv}}"/></signal>
        <signal name="InterfacesRemoved"><arg type="o"/><arg type="as"/></signal>
        </interface></node>"""
    )

    def on_call(conn, sender, path, iface, method, params, invocation):
        if method == "GetManagedObjects":
            invocation.return_value(managed())
        else:
            print(f"bluez-stub: unhandled {iface}.{method} on {path}", file=sys.stderr, flush=True)
            invocation.return_dbus_error("org.bluez.Error.NotSupported", "stub")

    bus.register_object("/", node.interfaces[0], on_call, None, None)
    Gio.bus_own_name_on_connection(bus, "org.bluez", Gio.BusNameOwnerFlags.NONE, None, None)

    sent = [0]
    turn = [0]

    def rssi():
        paths = [p for p in objects if p != ADAPTER]
        p = paths[turn[0] % len(paths)]
        turn[0] += 1
        value = GLib.Variant("n", random.randint(-90, -40))
        objects[p]["org.bluez.Device1"]["RSSI"] = value
        bus.emit_signal(
            None,
            p,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", ("org.bluez.Device1", {"RSSI": value}, [])),
        )
        sent[0] += 1
        with open(args.count, "w") as f:
            f.write(f"{sent[0]}\n")
        return True

    strangers = [6]

    def stranger():
        a = "11:22:33:44:55:%02X" % strangers[0]
        strangers[0] += 1
        props = device(a, "", False)
        objects[path_of(a)] = {"org.bluez.Device1": props}
        bus.emit_signal(
            None,
            "/",
            "org.freedesktop.DBus.ObjectManager",
            "InterfacesAdded",
            GLib.Variant("(oa{sa{sv}})", (path_of(a), {"org.bluez.Device1": props})),
        )
        return True

    GLib.timeout_add(max(1, 60000 // args.rate), rssi)
    GLib.timeout_add_seconds(10, stranger)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
